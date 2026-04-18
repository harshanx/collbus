import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../core/theme.dart';

class ManageAnnouncements extends StatefulWidget {
  const ManageAnnouncements({super.key});

  @override
  State<ManageAnnouncements> createState() => _ManageAnnouncementsState();
}

class _ManageAnnouncementsState extends State<ManageAnnouncements> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  Future<void> _addAnnouncement() async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();

    if (title.isEmpty || message.isEmpty) return;

    await FirebaseFirestore.instance.collection('announcements').add({
      'title': title,
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _titleController.clear();
    _messageController.clear();
    // Hide keyboard
    if (mounted) FocusScope.of(context).unfocus();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement sent!'), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _deleteAnnouncement(String docId) async {
    await FirebaseFirestore.instance.collection('announcements').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Announcements')),
      body: Column(
        children: [
          // Add Announcement Form
          Container(
            margin: const EdgeInsets.all(Constants.paddingLg),
            padding: const EdgeInsets.all(Constants.paddingLg),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Constants.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    const Text(
                      'Push New Announcement',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Bus 1 Delayed',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'Explain the issue...',
                    prefixIcon: Icon(Icons.message_rounded),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _addAnnouncement,
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  label: const Text('Publish Announcement', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Constants.paddingLg),
            child: Row(
              children: [
                Text("Recent Activity", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                Expanded(child: Divider(indent: 12)),
              ],
            ),
          ),

          // List of Announcements
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('announcements')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No announcements history.', style: TextStyle(color: Colors.grey)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(Constants.paddingLg),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final timestamp = data['timestamp'] as Timestamp?;
                    
                    String formattedDate = 'Now';
                    if (timestamp != null) {
                      formattedDate = DateFormat('MMM d, h:mm a').format(timestamp.toDate());
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: const Icon(Icons.campaign_rounded, color: AppColors.primary),
                        ),
                        title: Text(data['title'] ?? 'Announcement', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(data['message'] ?? ''),
                            const SizedBox(height: 8),
                            Text(formattedDate, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                          onPressed: () => _deleteAnnouncement(doc.id),
                        ),
                      ),
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
