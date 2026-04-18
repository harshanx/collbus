import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';

class ManageBuses extends StatefulWidget {
  const ManageBuses({super.key});

  @override
  State<ManageBuses> createState() => _ManageBusesState();
}

class _ManageBusesState extends State<ManageBuses> {
  // Get a reference to the buses collection
  final CollectionReference _busesCollection = FirebaseFirestore.instance.collection('buses');

  // Re-usable method to show the add/edit dialog
  void _showAddEditBusDialog({DocumentSnapshot? bus}) {
    final isEditing = bus != null;
    final busData = isEditing ? bus.data() as Map<String, dynamic> : null;
    final busNumberController = TextEditingController(text: isEditing ? (busData!['busNumber'] ?? '') : '');
    final serialNumberController = TextEditingController(text: isEditing ? (busData!['serialNumber'] ?? '') : '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(Constants.paddingLg),
          decoration: const BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isEditing ? 'Edit Bus' : 'Add Bus',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: busNumberController,
                decoration: const InputDecoration(
                  labelText: 'Bus Number',
                  hintText: 'e.g. KL-10-AB-1234',
                  prefixIcon: Icon(Icons.directions_bus_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: serialNumberController,
                decoration: const InputDecoration(
                  labelText: 'Serial Number',
                  hintText: 'e.g. SN-987654321',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        final busNumber = busNumberController.text.trim();
                        final serialNumber = serialNumberController.text.trim();
                        if (busNumber.isEmpty || serialNumber.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter bus number and serial number'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        if (isEditing) {
                          await _busesCollection.doc(bus.id).update({
                            'busNumber': busNumber,
                            'serialNumber': serialNumber,
                          });
                        } else {
                          await _busesCollection.add({
                            'busNumber': busNumber,
                            'serialNumber': serialNumber,
                            'isAssigned': false,
                            'currentRouteId': '',
                            'createdAt': FieldValue.serverTimestamp(),
                            'stops': [],
                          });
                        }

                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      child: Text(isEditing ? 'Save' : 'Add Bus'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Method to delete a bus
  Future<void> _deleteBus(String busId) async {
    final busDoc = await _busesCollection.doc(busId).get();
    if (!busDoc.exists) return;
    
    final busData = busDoc.data() as Map<String, dynamic>;
    final routeId = (busData['currentRouteId'] ?? '') as String;

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete this bus? If assigned to a route, it will be unassigned.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;

    if (confirm) {
      try {
        // 1. Unassign from Route
        if (routeId.isNotEmpty) {
          await FirebaseFirestore.instance.collection('routes').doc(routeId).update({
            'busid': '',
          });
        }
        
        // 2. Delete Bus
        await _busesCollection.doc(busId).delete();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bus deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting bus: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Buses'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Constants.paddingLg),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showAddEditBusDialog(),
                icon: const Icon(Icons.add_rounded, size: 22),
                label: const Text('Add Bus'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _busesCollection.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text('Firebase Error:\n\n${snapshot.error}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.directions_bus_outlined, size: 64, color: AppColors.textMuted),
                        const SizedBox(height: 16),
                        Text(
                          'No buses yet',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap Add Bus to get started',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                }

                final buses = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: Constants.paddingLg),
                  itemCount: buses.length,
                  itemBuilder: (context, index) {
                    final bus = buses[index];
                    final busData = bus.data() as Map<String, dynamic>;

                    return _BusCard(
                      busId: bus.id,
                      busNumber: busData['busNumber'] ?? 'N/A',
                      serialNumber: busData['serialNumber'] ?? 'N/A',
                      onEdit: () => _showAddEditBusDialog(bus: bus),
                      onDelete: () => _deleteBus(bus.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BusCard extends StatelessWidget {
  final String busId;
  final String busNumber;
  final String serialNumber;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BusCard({
    required this.busId,
    required this.busNumber,
    required this.serialNumber,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(Constants.radiusMd),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_bus_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(busNumber, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text('S/N: $serialNumber', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                color: AppColors.primary,
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                color: AppColors.error,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
