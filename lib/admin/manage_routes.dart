import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../widgets/places_search_field.dart';
import 'manage_stops.dart';

class ManageRoutes extends StatefulWidget {
  const ManageRoutes({super.key});

  @override
  State<ManageRoutes> createState() => _ManageRoutesState();
}

class _ManageRoutesState extends State<ManageRoutes> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Form controllers
  final _routeNameController = TextEditingController();
  final _startPointController = TextEditingController();
  final _endPointController = TextEditingController();

  String? _selectedBusId;
  String? _selectedDriverId;
  String? _oldBusId;
  String? _oldDriverId;

  double _startLat = 0;
  double _startLng = 0;
  double _endLat = 0;
  double _endLng = 0;

  void _resetForm() {
    final now = DateTime.now();
    final isAfternoon = now.hour >= 14; // After 2:00 PM

    _routeNameController.clear();
    _selectedBusId = null;
    _selectedDriverId = null;
    _oldBusId = null;
    _oldDriverId = null;

    if (isAfternoon) {
      _startPointController.text = 'GEC Palakkad';
      _startLat = 10.8505;
      _startLng = 76.2711;
      _endPointController.clear();
      _endLat = 0;
      _endLng = 0;
    } else {
      _startPointController.clear();
      _startLat = 0;
      _startLng = 0;
      _endPointController.text = 'GEC Palakkad';
      _endLat = 10.8505;
      _endLng = 76.2711;
    }
  }

  Future<void> _reverseRouteStops(String routeId) async {
    final doc = await _firestore.collection('routes').doc(routeId).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final stops = data['stops'] as List? ?? [];
      final start = data['startpoint'];
      final end = data['endpoint'];
      
      await _firestore.collection('routes').doc(routeId).update({
        'stops': stops.reversed.toList(),
        'startpoint': end,
        'endpoint': start,
      });
    }
  }

  // ─── Save Route (create or update) ───────────────────────────────────────
  Future<void> _saveRoute({String? routeId}) async {
    final name = _routeNameController.text.trim();
    if (name.isEmpty) return;

    if (_startLat == 0 || _endLat == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select real places for both Start and End points from the suggestions.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final startName = _startPointController.text.trim();
    final endName = _endPointController.text.trim();

    final data = {
      'name': name,
      'busid': _selectedBusId ?? '',
      'driverid': _selectedDriverId ?? '',
      'startpoint': {'lat': _startLat, 'lng': _startLng, 'name': startName},
      'endpoint': {'lat': _endLat, 'lng': _endLng, 'name': endName},
      'isAssigned': _selectedBusId != null && _selectedBusId!.isNotEmpty,
      'isTripActive': false,
    };

    if (routeId == null) {
      data['createdAt'] = FieldValue.serverTimestamp() as Object;
      final ref = await _firestore.collection('routes').add(data);
      await _handleAssignments(newRouteId: ref.id);
    } else {
      await _firestore.collection('routes').doc(routeId).update(data);
      await _handleAssignments(newRouteId: routeId);
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _handleAssignments({required String newRouteId}) async {
    // Unassign old bus if changed
    if (_oldBusId != null && _oldBusId!.isNotEmpty && _oldBusId != _selectedBusId) {
      await _firestore.collection('buses').doc(_oldBusId).update({
        'isAssigned': false,
        'currentRouteId': '',
        'location': FieldValue.delete(), // Clear ghost markers
      });
    }
    // Assign new bus
    if (_selectedBusId != null && _selectedBusId!.isNotEmpty && _oldBusId != _selectedBusId) {
      await _firestore.collection('buses').doc(_selectedBusId).update({
        'isAssigned': true,
        'currentRouteId': newRouteId,
      });
    }

    // Unassign old driver if changed
    if (_oldDriverId != null && _oldDriverId!.isNotEmpty && _oldDriverId != _selectedDriverId) {
      await _firestore.collection('drivers').doc(_oldDriverId).update({
        'isAssigned': false,
        'currentRouteId': '',
      });
    }
    // Assign new driver
    if (_selectedDriverId != null && _selectedDriverId!.isNotEmpty && _oldDriverId != _selectedDriverId) {
      await _firestore.collection('drivers').doc(_selectedDriverId).update({
        'isAssigned': true,
        'currentRouteId': newRouteId,
      });
    }
  }

  // ─── Delete Route ─────────────────────────────────────────────────────────
  Future<void> _deleteRoute(DocumentSnapshot route) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Route'),
        content: Text('Delete "${route['name']}"? The linked bus and driver will be unassigned.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final data = route.data() as Map<String, dynamic>;
      final busid = (data['busid'] ?? '') as String;
      final driverid = (data['driverid'] ?? '') as String;

      // 1. Unassign Bus
      if (busid.isNotEmpty) {
        try {
          await _firestore.collection('buses').doc(busid).update({
            'isAssigned': false, 
            'currentRouteId': '',
            'location': FieldValue.delete(), // Clear ghost markers
          });
        } catch (e) {
          debugPrint('Error unassigning bus: $e');
        }
      }

      // 2. Unassign Driver
      if (driverid.isNotEmpty) {
        try {
          await _firestore.collection('drivers').doc(driverid).update({'isAssigned': false, 'currentRouteId': ''});
        } catch (e) {
          debugPrint('Error unassigning driver: $e');
        }
      }

      // 3. Delete Route
      await _firestore.collection('routes').doc(route.id).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting route: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // ─── Open Bottom Sheet ────────────────────────────────────────────────────
  void _openRouteSheet({DocumentSnapshot? existing}) {
    if (existing != null) {
      final data = existing.data() as Map<String, dynamic>;
      _routeNameController.text = data['name'] ?? '';
      _startPointController.text = (data['startpoint'] as Map?)?['name'] ?? '';
      _endPointController.text = (data['endpoint'] as Map?)?['name'] ?? '';
      _startLat = ((data['startpoint'] as Map?)?['lat'] ?? 0).toDouble();
      _startLng = ((data['startpoint'] as Map?)?['lng'] ?? 0).toDouble();
      _endLat = ((data['endpoint'] as Map?)?['lat'] ?? 0).toDouble();
      _endLng = ((data['endpoint'] as Map?)?['lng'] ?? 0).toDouble();
      _selectedBusId = (data['busid'] ?? '').isEmpty ? null : data['busid'];
      _selectedDriverId = (data['driverid'] ?? '').isEmpty ? null : data['driverid'];
      _oldBusId = _selectedBusId;
      _oldDriverId = _selectedDriverId;
    } else {
      _resetForm();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => Container(
            decoration: const BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.textMuted, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Constants.paddingLg),
                  child: Row(
                    children: [
                      Text(existing == null ? 'Create Route' : 'Edit Route',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(Constants.paddingLg),
                    children: [

                      // ─ Route Name
                      TextField(
                        controller: _routeNameController,
                        decoration: const InputDecoration(
                          labelText: 'Route Name',
                          hintText: 'e.g. Campus – City Center',
                          prefixIcon: Icon(Icons.alt_route_rounded),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ─ Start & End Points
                      Text('Route Points', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),

                      // Start Point
                      Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                            child: const Icon(Icons.radio_button_checked, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: PlacesSearchField(
                              controller: _startPointController,
                              label: 'Start Point',
                              hint: 'e.g. College Main Gate',
                              icon: Icons.radio_button_checked,
                              onPlaceSelected: (name, lat, lng) {
                                if (lat != 0) {
                                  setSheetState(() {
                                    _startLat = lat;
                                    _startLng = lng;
                                  });
                                } else {
                                  _startLat = 0;
                                  _startLng = 0;
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Connector line with Swap Button
                      Row(
                        children: [
                          const SizedBox(width: 17),
                          Column(
                            children: List.generate(3, (_) => Container(
                              width: 2, height: 8,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.textMuted.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            )),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () {
                              setSheetState(() {
                                final tempAddr = _startPointController.text;
                                _startPointController.text = _endPointController.text;
                                _endPointController.text = tempAddr;

                                final tempLat = _startLat;
                                final tempLng = _startLng;
                                _startLat = _endLat;
                                _startLng = _endLng;
                                _endLat = tempLat;
                                _endLng = tempLng;
                              });

                              if (existing != null) {
                                _reverseRouteStops(existing.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Points swapped and stops reversed!')),
                                );
                              }
                            },
                            icon: const Icon(Icons.swap_vert_rounded, color: AppColors.primary),
                            tooltip: 'Swap Directions',
                          ),
                        ],
                      ),

                      // End Point
                      Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                            child: const Icon(Icons.location_on, color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: PlacesSearchField(
                              controller: _endPointController,
                              label: 'End Point',
                              hint: 'e.g. City Bus Stand',
                              icon: Icons.location_on,
                              onPlaceSelected: (name, lat, lng) {
                                if (lat != 0) {
                                  setSheetState(() {
                                    _endLat = lat;
                                    _endLng = lng;
                                  });
                                } else {
                                  _endLat = 0;
                                  _endLng = 0;
                                }
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // ─ Bus Dropdown
                      Text('Assign Bus', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore.collection('buses').snapshots(),
                        builder: (context, snap) {
                          if (!snap.hasData) return const LinearProgressIndicator();
                          final available = snap.data!.docs.where((b) {
                            final d = b.data() as Map;
                            return d['isAssigned'] != true || b.id == _selectedBusId;
                          }).toList();
                          return _StyledDropdown<String?>(
                            value: _selectedBusId,
                            hint: 'Select a bus',
                            items: [
                              const DropdownMenuItem(value: null, child: Text('None')),
                              ...available.map((b) => DropdownMenuItem(
                                value: b.id,
                                child: Text((b.data() as Map)['busNumber'] ?? b.id),
                              )),
                            ],
                            onChanged: (v) => setSheetState(() => _selectedBusId = v),
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // ─ Driver Dropdown
                      Text('Assign Driver', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore.collection('drivers').snapshots(),
                        builder: (context, snap) {
                          if (!snap.hasData) return const LinearProgressIndicator();
                          final available = snap.data!.docs.where((d) {
                            final data = d.data() as Map;
                            return data['isAssigned'] != true || d.id == _selectedDriverId;
                          }).toList();
                          return _StyledDropdown<String?>(
                            value: _selectedDriverId,
                            hint: 'Select a driver',
                            items: [
                              const DropdownMenuItem(value: null, child: Text('None')),
                              ...available.map((d) {
                                final data = d.data() as Map;
                                final label = (data['name']?.toString().isNotEmpty == true)
                                    ? data['name']
                                    : data['email'] ?? d.id;
                                return DropdownMenuItem(value: d.id, child: Text(label));
                              }),
                            ],
                            onChanged: (v) => setSheetState(() => _selectedDriverId = v),
                          );
                        },
                      ),

                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _saveRoute(routeId: existing?.id),
                          child: Text(existing == null ? 'Create Route' : 'Save Changes'),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Manage Routes'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openRouteSheet(),
        icon: const Icon(Icons.add_road_rounded),
        label: const Text('New Route'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('routes').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return _EmptyState(onAdd: () => _openRouteSheet());
          }
          final routes = snap.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                Constants.paddingLg, Constants.paddingLg, Constants.paddingLg, 100),
            itemCount: routes.length,
            itemBuilder: (context, index) => _RouteCard(
              route: routes[index],
              onEdit: () => _openRouteSheet(existing: routes[index]),
              onDelete: () => _deleteRoute(routes[index]),
              firestore: _firestore,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _routeNameController.dispose();
    _startPointController.dispose();
    _endPointController.dispose();
    super.dispose();
  }
}

// ─── Styled Dropdown ─────────────────────────────────────────────────────────
class _StyledDropdown<T> extends StatelessWidget {
  final T value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _StyledDropdown({required this.value, required this.hint, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          hint: Text(hint),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── Route Card ───────────────────────────────────────────────────────────────
class _RouteCard extends StatelessWidget {
  final DocumentSnapshot route;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final FirebaseFirestore firestore;

  const _RouteCard({required this.route, required this.onEdit, required this.onDelete, required this.firestore});

  @override
  Widget build(BuildContext context) {
    final data = route.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unnamed Route';
    final busid = (data['busid'] ?? '') as String;
    final driverid = (data['driverid'] ?? '') as String;
    final isTripActive = data['isTripActive'] == true;
    final startName = (data['startpoint'] as Map?)?['name'] ?? '';
    final endName = (data['endpoint'] as Map?)?['name'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(Constants.radiusLg),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.alt_route_rounded, color: AppColors.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: isTripActive ? AppColors.success : AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isTripActive ? 'Trip Active' : 'Inactive',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isTripActive ? AppColors.success : AppColors.textMuted,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.edit_rounded, color: AppColors.primary), onPressed: onEdit),
                IconButton(icon: const Icon(Icons.delete_rounded, color: AppColors.error), onPressed: onDelete),
              ],
            ),
          ),

          // Start → End
          if (startName.isNotEmpty || endName.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.radio_button_checked, color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(startName.isNotEmpty ? startName : '—',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary)),
                  ),
                  const Icon(Icons.arrow_forward_rounded, color: AppColors.textMuted, size: 18),
                  const SizedBox(width: 8),
                  const Icon(Icons.location_on, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(endName.isNotEmpty ? endName : '—',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
                        textAlign: TextAlign.right),
                  ),
                ],
              ),
            ),
          ],

          // Bus & Driver Badges
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _AssignmentBadge(
                  icon: Icons.directions_bus_rounded,
                  docId: busid,
                  collection: 'buses',
                  fieldName: 'busNumber',
                  emptyLabel: 'No Bus',
                  color: busid.isEmpty ? AppColors.textMuted : AppColors.accent,
                  firestore: firestore,
                ),
                const SizedBox(width: 8),
                _AssignmentBadge(
                  icon: Icons.person_rounded,
                  docId: driverid,
                  collection: 'drivers',
                  fieldName: 'name',
                  secondaryField: 'email',
                  emptyLabel: 'No Driver',
                  color: driverid.isEmpty ? AppColors.textMuted : AppColors.success,
                  firestore: firestore,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    final rData = route.data() as Map<String, dynamic>;
                    final start = rData['startpoint'] as Map?;
                    final end = rData['endpoint'] as Map?;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManageStopsScreen(
                          routeId: route.id,
                          routeName: name,
                          startLat: (start?['lat'] ?? 0.0).toDouble(),
                          startLng: (start?['lng'] ?? 0.0).toDouble(),
                          endLat: (end?['lat'] ?? 0.0).toDouble(),
                          endLng: (end?['lng'] ?? 0.0).toDouble(),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_location_alt_rounded, size: 20),
                  label: const Text('Stops'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Assignment Badge ─────────────────────────────────────────────────────────
class _AssignmentBadge extends StatelessWidget {
  final IconData icon;
  final String docId;
  final String collection;
  final String fieldName;
  final String? secondaryField;
  final String emptyLabel;
  final Color color;
  final FirebaseFirestore firestore;

  const _AssignmentBadge({
    required this.icon, required this.docId, required this.collection,
    required this.fieldName, this.secondaryField, required this.emptyLabel,
    required this.color, required this.firestore,
  });

  Widget _chip(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    if (docId.isEmpty) return _chip(context, emptyLabel);
    return StreamBuilder<DocumentSnapshot>(
      stream: firestore.collection(collection).doc(docId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return _chip(context, '…');
        if (!snap.data!.exists) return _chip(context, 'Unknown');
        final data = snap.data!.data() as Map<String, dynamic>;
        final text = data[fieldName]?.toString().isNotEmpty == true
            ? data[fieldName]!
            : (secondaryField != null ? data[secondaryField] : null) ?? '—';
        return _chip(context, text.toString());
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
        padding: EdgeInsets.all(Constants.paddingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), shape: BoxShape.circle),
              child: const Icon(Icons.alt_route_rounded, size: 56, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text('No Routes Yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Tap the button below to create your first route.',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('Create Route'),
            ),
          ],
        ),
      ),
    );
  }
}
