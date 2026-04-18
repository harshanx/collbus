import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';

class ManageDrivers extends StatefulWidget {
  const ManageDrivers({super.key});

  @override
  State<ManageDrivers> createState() => _ManageDriversState();
}

class _ManageDriversState extends State<ManageDrivers> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ─── Show Create Driver Dialog ────────────────────────────────────────────
  void _showCreateDriverDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
              // Drag handle
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
              const SizedBox(height: 20),
              Text('Create Driver Account',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'You can assign a bus & route from Manage Routes.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Driver Name',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Driver Email',
                  prefixIcon: Icon(Icons.email_rounded),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_rounded),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  final email = emailController.text.trim();
                  final password = passwordController.text.trim();

                  if (name.isEmpty || email.isEmpty || password.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill all fields')),
                    );
                    return;
                  }
                  Navigator.pop(context);
                  await _createDriver(name, email, password);
                },
                child: const Text('Create Driver'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Create Driver (Firebase Auth + Firestore) ────────────────────────────
  Future<void> _createDriver(
      String name, String email, String password) async {
    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final uid = credential.user!.uid;

      await _firestore.collection('drivers').doc(uid).set({
        'name': name,
        'email': email,
        'isAssigned': false,
        'currentRouteId': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver created successfully')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unexpected error: $e')),
        );
      }
    }
  }

  // ─── Delete Driver ────────────────────────────────────────────────────────
  Future<void> _deleteDriver(
      String driverId, Map<String, dynamic> driverData) async {
    final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Delete Driver'),
            content: const Text(
                'This will remove the driver from the database. If assigned to a route, they will be unassigned automatically.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.error),
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      final routeId = (driverData['currentRouteId'] ?? '') as String;
      if (routeId.isNotEmpty) {
        try {
          // 1. Get route to find bus
          final routeDoc = await _firestore.collection('routes').doc(routeId).get();
          if (routeDoc.exists) {
            final busId = (routeDoc.data()?['busid'] ?? '') as String;
            if (busId.isNotEmpty) {
              // 2. Clear bus location
              await _firestore.collection('buses').doc(busId).update({
                'location': FieldValue.delete(),
              });
            }
          }
          
          // 3. Unassign driver from route
          await _firestore.collection('routes').doc(routeId).update({
            'driverid': '',
          });
        } catch (e) {
          debugPrint('Error cleaning up route/bus on driver deletion: $e');
        }
      }

      await _firestore.collection('drivers').doc(driverId).delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting driver: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Drivers'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDriverDialog,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Driver'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('drivers').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _EmptyState(onAdd: _showCreateDriverDialog);
          }

          final drivers = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                Constants.paddingLg, Constants.paddingLg,
                Constants.paddingLg, 100),
            itemCount: drivers.length,
            itemBuilder: (context, index) {
              final driver = drivers[index];
              final data = driver.data() as Map<String, dynamic>;
              final isAssigned = data['isAssigned'] == true;
              final routeId = (data['currentRouteId'] ?? '') as String;

              return _DriverCard(
                name: data['name'] ?? '',
                email: data['email'] ?? 'N/A',
                isAssigned: isAssigned,
                routeId: routeId,
                firestore: _firestore,
                onDelete: () => _deleteDriver(driver.id, data),
              );
            },
          );
        },
      ),
    );
  }
}

// ─── Driver Card ──────────────────────────────────────────────────────────────
class _DriverCard extends StatelessWidget {
  final String name;
  final String email;
  final bool isAssigned;
  final String routeId;
  final FirebaseFirestore firestore;
  final VoidCallback onDelete;

  const _DriverCard({
    required this.name,
    required this.email,
    required this.isAssigned,
    required this.routeId,
    required this.firestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(Constants.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded,
                color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : email,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(email,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textMuted)),
                ],
                const SizedBox(height: 6),
                _RouteStatusBadge(
                  isAssigned: isAssigned,
                  routeId: routeId,
                  firestore: firestore,
                ),
              ],
            ),
          ),

          // Delete
          IconButton(
            icon:
                const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ─── Route Status Badge ───────────────────────────────────────────────────────
class _RouteStatusBadge extends StatelessWidget {
  final bool isAssigned;
  final String routeId;
  final FirebaseFirestore firestore;

  const _RouteStatusBadge({
    required this.isAssigned,
    required this.routeId,
    required this.firestore,
  });

  @override
  Widget build(BuildContext context) {
    if (!isAssigned || routeId.isEmpty) {
      return Row(
        children: [
          Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                  color: AppColors.textMuted, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('Unassigned',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textMuted)),
        ],
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: firestore.collection('routes').doc(routeId).snapshots(),
      builder: (context, snap) {
        String label = 'Assigned';
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          label = 'Route: ${data['name'] ?? 'Unknown'}';
        }
        return Row(
          children: [
            Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.success)),
          ],
        );
      },
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Constants.paddingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_rounded,
                  size: 56, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text('No Drivers Yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to add your first driver.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Add Driver'),
            ),
          ],
        ),
      ),
    );
  }
}
