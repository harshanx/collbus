import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../core/constants.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  Future<void> _deleteLog(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Log?'),
        content: const Text('This will permanently remove this trip record from history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(c, true), 
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('trip_history').doc(docId).delete();
    }
  }

  Future<void> _clearAllCompleted() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Clear Completed Logs?'),
        content: const Text('This will delete all "Completed" trips from the history. "Running" trips will be kept. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(c, true), 
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final snapshot = await FirebaseFirestore.instance
          .collection('trip_history')
          .where('status', isEqualTo: 'Completed')
          .get();
      
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      // Also handle documents without explicit 'status' but have 'endTime'
      final legacySnapshot = await FirebaseFirestore.instance
          .collection('trip_history')
          .get();
          
      for (var doc in legacySnapshot.docs) {
        final data = doc.data();
        if (data['status'] == null && data['endTime'] != null) {
          batch.delete(doc.reference);
        }
      }

      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completed history cleared successfully.'), backgroundColor: AppColors.success),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip History & Logs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: _clearAllCompleted,
            icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.error),
            tooltip: 'Clear Completed Logs',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('trip_history')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('No trip logs found.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          // 1. Filter and Separate Active/Completed
          // FIXED: Strictly filter to show ONLY running and completed states as requested
          final List<DocumentSnapshot> activeTrips = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'];
            final isRunning = data['endTime'] == null;
            return status == 'Running' || (status == null && isRunning);
          }).toList();

          final List<DocumentSnapshot> completedTrips = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'];
            final isRunning = data['endTime'] == null;
            return status == 'Completed' || (status == null && !isRunning);
          }).toList();

          final List<Map<String, dynamic>> items = [];
          if (activeTrips.isNotEmpty) {
            items.add({'type': 'header', 'label': 'Active Trips'});
            items.addAll(activeTrips.map((doc) => {'type': 'trip', 'data': doc.data(), 'id': doc.id}));
          }
          if (completedTrips.isNotEmpty) {
            items.add({'type': 'header', 'label': 'Completed Logs'});
            items.addAll(completedTrips.map((doc) => {'type': 'trip', 'data': doc.data(), 'id': doc.id}));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(Constants.paddingLg),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item['type'] == 'header') {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    item['label'].toString().toUpperCase(),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1.5),
                  ),
                );
              }
              
              final data = item['data'] as Map<String, dynamic>;
              final String docId = item['id'];
              
              final busNumber = data['busNumber'] ?? 'N/A';
              final driverEmail = data['driverEmail'] ?? 'N/A';
              final routeName = data['routeName'] ?? 'N/A';
              
              final startObj = data['startTime'];
              final endObj = data['endTime'];
              
              DateTime? startTime;
              DateTime? endTime;
              if (startObj is Timestamp) startTime = startObj.toDate();
              if (endObj is Timestamp) endTime = endObj.toDate();

              final dateFormat = DateFormat('MMM dd, yyyy');
              final timeFormat = DateFormat('hh:mm a');
              
              final dateStr = startTime != null ? dateFormat.format(startTime) : 'Unknown Date';
              final startStr = startTime != null ? timeFormat.format(startTime) : '--:--';
              final endStr = endTime != null ? timeFormat.format(endTime) : (startTime != null ? 'Running...' : '--:--');
              
              String durationStr = 'In Progress';
              bool isRunning = false;
              
              if (startTime != null && endTime != null) {
                final int minutes = data['duration'] ?? endTime.difference(startTime).inMinutes;
                if (minutes >= 60) {
                  final int hrs = minutes ~/ 60;
                  final int mins = minutes % 60;
                  durationStr = '${hrs} hr ${mins} min';
                } else {
                  durationStr = '${minutes} min';
                }
              } else if (startTime != null && endTime == null) {
                isRunning = true;
                durationStr = 'Trip Running';
              }

              return Card(
                elevation: 4,
                shadowColor: Colors.black.withOpacity(0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isRunning ? AppColors.success.withOpacity(0.1) : AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.directions_bus_rounded, 
                              color: isRunning ? AppColors.success : AppColors.primary, 
                              size: 24
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(busNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                Text(routeName, style: TextStyle(color: AppColors.primary.withOpacity(0.7), fontSize: 13)),
                              ],
                            ),
                          ),
                          // FIXED: Individual delete button for manual cleanup
                          IconButton(
                            onPressed: () => _deleteLog(docId),
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                            tooltip: 'Delete Log',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(child: Text(driverEmail, style: const TextStyle(color: Colors.grey, fontSize: 14))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isRunning ? AppColors.success.withOpacity(0.1) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isRunning ? 'LIVE' : dateStr, 
                              style: TextStyle(
                                color: isRunning ? AppColors.success : Colors.grey.shade700, 
                                fontSize: 11, 
                                fontWeight: FontWeight.bold
                              )
                            ),
                          )
                        ],
                      ),
                      const Divider(height: 32),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isRunning ? AppColors.success.withOpacity(0.05) : AppColors.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('START', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(height: 6),
                                Text(startStr, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 15)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isRunning ? AppColors.success : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [if(!isRunning) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]
                              ),
                              child: Text(
                                durationStr, 
                                style: TextStyle(
                                  fontSize: 12, 
                                  color: isRunning ? Colors.white : AppColors.primary, 
                                  fontWeight: FontWeight.bold
                                )
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('END', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                const SizedBox(height: 6),
                                Text(
                                  endStr, 
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    color: isRunning ? AppColors.success : AppColors.error, 
                                    fontSize: 15
                                  )
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
