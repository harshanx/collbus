import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../auth/login_screen.dart'; 
import '../services/google_maps_service.dart';
import '../widgets/menu_dialogs.dart';
import '../services/notification_service.dart';
import 'live_tracking.dart'; 
import 'package:intl/intl.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  late GoogleMapController _mapController;
  StreamSubscription? _busSubscription;
  StreamSubscription? _announcementSub;
  Timestamp? _lastAnnouncementTimestamp;
  BitmapDescriptor? _busIcon;
  
  int _lastSeenAnnouncementCount = 0;
  bool _hasCheckedUnread = false;

  final Map<String, Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  DocumentSnapshot? _selectedBus;

  static const _initialCameraPosition = CameraPosition(
    target: LatLng(10.8505, 76.2711),
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();
    _lastAnnouncementTimestamp = Timestamp.now();
    _loadSeenAnnouncementCount();
    _loadBusIcon();
    _listenToBusUpdates();
    _listenToAnnouncements();
  }

  Future<void> _loadSeenAnnouncementCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastSeenAnnouncementCount = prefs.getInt('last_seen_announcements') ?? 0;
    });
  }

  Future<void> _loadBusIcon() async {
    final icon = await GoogleMapsService.getMarkerIcon(Icons.directions_bus_rounded, AppColors.primary, size: 100);
    if (mounted) {
      setState(() {
        _busIcon = icon;
      });
    }
  }

  // Refresh function for pull-to-refresh
  Future<void> _refreshBuses() async {
    try {
      // Force refresh by clearing markers and letting stream rebuild
      setState(() {
        _markers.clear();
        _polylines.clear();
      });
      
      // Show feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refreshing bus data...')),
      );
      
      // The stream will automatically update with fresh data
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to refresh: ${e.toString()}')),
      );
    }
  }

  @override
  void dispose() {
    _busSubscription?.cancel();
    _announcementSub?.cancel();
    super.dispose();
  }

  void _listenToAnnouncements() {
    _announcementSub = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        final timestamp = data['timestamp'] as Timestamp?;

        // Ignore old announcements
        if (timestamp != null && _lastAnnouncementTimestamp != null &&
            timestamp.compareTo(_lastAnnouncementTimestamp!) > 0) {
          
          _lastAnnouncementTimestamp = timestamp;
          
          NotificationService.showNotification(
            id: doc.id.hashCode,
            title: data['title'] ?? 'New Announcement',
            body: data['message'] ?? 'Tap to view details',
          );
          
          if (mounted) {
            // Check if we should show the full popup immediately
            _showAnnouncementsDialog();
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['title'] ?? 'New Announcement'),
                action: SnackBarAction(label: 'View', onPressed: _showAnnouncementsDialog),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    });
  }

  // =========================
  // LOGOUT FUNCTION
  // =========================
  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showAnnouncementsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                   const Padding(
                     padding: EdgeInsets.all(16),
                     child: Text('Announcements', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary)),
                   ),
                   const Divider(height: 1),
                   Expanded(
                     child: StreamBuilder<QuerySnapshot>(
                       stream: FirebaseFirestore.instance.collection('announcements').orderBy('timestamp', descending: true).snapshots(),
                       builder: (context, snapshot) {
                         if (snapshot.hasError) return Center(child: Text('Error loading announcements', style: TextStyle(color: AppColors.error)));
                         if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                         if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No announcements', style: TextStyle(color: Colors.grey)));
                         return ListView.builder(
                           controller: scrollController,
                           itemCount: snapshot.data!.docs.length,
                           itemBuilder: (context, index) {
                             final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                             final timestamp = data['timestamp'] as Timestamp?;
                             final dateStr = timestamp != null ? DateFormat('MMM d, h:mm a').format(timestamp.toDate()) : 'Now';
                             return ListTile(
                               contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                               leading: const CircleAvatar(backgroundColor: Color(0x330A2463), child: Icon(Icons.campaign_rounded, color: AppColors.primary)),
                               title: Text(data['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                               subtitle: Column(
                                 crossAxisAlignment: CrossAxisAlignment.start,
                                 children: [
                                   const SizedBox(height: 4),
                                   Text(data['message'] ?? ''),
                                   const SizedBox(height: 4),
                                   Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                 ],
                               ),
                               isThreeLine: true,
                             );
                           },
                         );
                       },
                     ),
                   )
                ]
              )
            );
          }
        );
      }
    );
  }

  void _showUnreadPopup(int unreadCount) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.campaign_rounded, color: AppColors.primary, size: 28),
              const SizedBox(width: 10),
              const Text('New Announcements'),
            ],
          ),
          content: Text('You have $unreadCount new unread announcement(s) from the Admin!'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Dismiss', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                final snapshot = await FirebaseFirestore.instance.collection('announcements').get();
                final total = snapshot.docs.length;
                await prefs.setInt('last_seen_announcements', total);
                setState(() => _lastSeenAnnouncementCount = total);
                _showAnnouncementsDialog();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('View Now', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }
    );
  }

  final Map<String, List<LatLng>> _polylineCache = {};

  void _listenToBusUpdates() {
    _busSubscription = FirebaseFirestore.instance
        .collection('buses')
        .snapshots()
        .listen((snapshot) async {
      if (!mounted) return;

      final Set<Marker> newMarkers = {};
      final Set<Polyline> newPolylines = {};

      for (var doc in snapshot.docs) {
        final busId = doc.id;
        final busData = doc.data() as Map<String, dynamic>;

        if (busData['location'] != null && busData['location'] is GeoPoint) {
          final GeoPoint location = busData['location'];
          final latLng = LatLng(location.latitude, location.longitude);

          newMarkers.add(Marker(
            markerId: MarkerId(busId),
            position: latLng,
            icon: _busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(title: busData['busNumber'] ?? 'Bus'),
            onTap: () => _onBusSelected(doc),
          ));

          // Fetch and show route polyline for this bus
          final String? routeId = busData['currentRouteId'];
          if (routeId != null && routeId.isNotEmpty) {
            if (_polylineCache.containsKey(routeId)) {
              newPolylines.add(Polyline(
                polylineId: PolylineId(routeId),
                points: _polylineCache[routeId]!,
                color: AppColors.primary.withAlpha(150),
                width: 3,
              ));
            } else {
              // Fetch route and generate polyline (optimistic background task)
              _fetchAndCacheRoute(routeId);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _markers.clear();
          for (var m in newMarkers) {
            _markers[m.markerId.value] = m;
          }
          _polylines.clear();
          _polylines.addAll(newPolylines);
        });
      }
    });
  }

  Future<void> _fetchAndCacheRoute(String routeId) async {
    final routeDoc = await FirebaseFirestore.instance.collection('routes').doc(routeId).get();
    if (!routeDoc.exists) return;

    final data = routeDoc.data() as Map<String, dynamic>;
    final start = data['startpoint'] as Map?;
    final end = data['endpoint'] as Map?;
    final List<dynamic> stops = data['stops'] ?? [];

    if (start == null || end == null) return;

    List<LatLng> waypoints = [LatLng(start['lat'], start['lng'])];
    for (var stop in stops) {
      if (stop is Map && stop['lat'] != null && stop['lat'] != 0) {
        waypoints.add(LatLng(stop['lat'], stop['lng']));
      }
    }
    waypoints.add(LatLng(end['lat'], end['lng']));

    final path = await GoogleMapsService.getRoutePolyline(waypoints);
    if (path.isNotEmpty) {
      _polylineCache[routeId] = path;
      if (mounted) setState(() {}); // Trigger rebuild to show the new polyline
    }
  }

  Future<void> _onBusSelected(DocumentSnapshot bus) async {
    final busData = bus.data() as Map<String, dynamic>;
    if (busData['location'] == null) return;
    
    final geoPoint = busData['location'] as GeoPoint;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LiveTracking(
          busId: bus.id,
          initialLocation: LatLng(geoPoint.latitude, geoPoint.longitude),
          initialBusNumber: busData['busNumber'] ?? 'Bus',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Bus Tracking'),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('announcements').snapshots(),
            builder: (context, snapshot) {
              int totalCount = snapshot.data?.docs.length ?? 0;
              int unreadCount = totalCount - _lastSeenAnnouncementCount;
              if (unreadCount < 0) unreadCount = 0;

              // Trigger popup ONLY on first load if unread
              // PostFrameCallback is required to build a Dialog during build phase
              if (!_hasCheckedUnread && unreadCount > 0 && snapshot.hasData) {
                _hasCheckedUnread = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showUnreadPopup(unreadCount);
                });
              } else if (snapshot.hasData) {
                _hasCheckedUnread = true;
              }

              return IconButton(
                icon: Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text(unreadCount.toString()),
                  child: const Icon(Icons.campaign_rounded),
                ),
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('last_seen_announcements', totalCount);
                  setState(() {
                    _lastSeenAnnouncementCount = totalCount;
                  });
                  _showAnnouncementsDialog();
                },
                tooltip: 'Announcements',
              );
            }
          ),
          PopupMenuButton<String>(
            elevation: 10,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'logout') {
                MenuDialogs.showLogoutConfirmation(context, () {
                  _logout();
                });
              } else if (value == 'terms') {
                MenuDialogs.showTerms(context);
              } else if (value == 'about') {
                MenuDialogs.showAbout(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded, color: AppColors.primary),
                  title: Text('About'),
                  contentPadding: EdgeInsets.zero,
                  horizontalTitleGap: 0,
                ),
              ),
              const PopupMenuItem(
                value: 'terms',
                child: ListTile(
                  leading: Icon(Icons.description_outlined, color: Colors.blue),
                  title: Text('Terms'),
                  contentPadding: EdgeInsets.zero,
                  horizontalTitleGap: 0,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded, color: AppColors.error),
                  title: Text('Logout', style: TextStyle(color: AppColors.error)),
                  contentPadding: EdgeInsets.zero,
                  horizontalTitleGap: 0,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: (controller) => _mapController = controller,
            markers: _markers.values.toSet(),
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),

          // Draggable Bus List Panel
          DraggableScrollableSheet(
            initialChildSize: 0.25,
            minChildSize: 0.15,
            maxChildSize: 0.5,
            builder:
                (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(Constants.radiusXl),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      color: Colors.black.withAlpha(20),
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('buses')
                            .orderBy('busNumber')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Padding(
                                 padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                 child: Text(
                                   'Failed to load buses. Please log out and log back in.\n\nError: ${snapshot.error}', 
                                   textAlign: TextAlign.center,
                                   style: const TextStyle(color: AppColors.error)
                                 ),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          return RefreshIndicator(
                            onRefresh: _refreshBuses,
                            child: ListView.builder(
                              controller: scrollController,
                              itemCount: snapshot.data!.docs.length,
                              itemBuilder: (context, index) {
                                final bus = snapshot.data!.docs[index];
                                final busData = bus.data() as Map<String, dynamic>;
                                final String? currentRouteId = busData['currentRouteId'];
                                final bool isLive = busData['location'] != null && 
                                                   currentRouteId != null && 
                                                   currentRouteId.isNotEmpty;

                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isLive ? AppColors.surface : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(Constants.radiusLg),
                                    border: Border.all(
                                      color: isLive ? AppColors.primary.withAlpha(40) : Colors.grey.shade300,
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isLive ? AppColors.primary.withAlpha(20) : Colors.black.withAlpha(10),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isLive ? AppColors.primary.withAlpha(20) : Colors.grey.shade200,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.directions_bus,
                                        color: isLive ? AppColors.primary : Colors.grey,
                                        size: 24,
                                      ),
                                    ),
                                    title: Text(
                                      busData['busNumber'] ?? 'Unknown Bus',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isLive ? AppColors.textPrimary : Colors.grey.shade600,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (currentRouteId != null) ...[
                                          FutureBuilder<DocumentSnapshot>(
                                            future: FirebaseFirestore.instance
                                                .collection('routes')
                                                .doc(currentRouteId)
                                                .get(),
                                            builder: (context, routeSnapshot) {
                                              final routeName = routeSnapshot.data?['name'] ?? 'Unknown Route';
                                              return Text(
                                                'Route: $routeName',
                                                style: TextStyle(
                                                  color: isLive ? AppColors.textSecondary : Colors.grey.shade500,
                                                  fontSize: 12,
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                        if (busData['direction'] != null)
                                          Text(
                                            'Direction: ${busData['direction']}',
                                            style: TextStyle(
                                              color: isLive ? AppColors.textSecondary : Colors.grey.shade500,
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: isLive
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.circle,
                                                color: AppColors.success,
                                                size: 12,
                                              ),
                                              const SizedBox(width: 6),
                                              const Text(
                                                "Live",
                                                style: TextStyle(
                                                    color: AppColors.success),
                                              ),
                                            ],
                                          )
                                        : const Text(
                                            "Not Running",
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                    onTap: isLive ? () => _onBusSelected(bus) : null,
                                    enabled: isLive,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BusRouteSubtitle extends StatelessWidget {
  final String? routeId;
  const _BusRouteSubtitle({this.routeId});

  @override
  Widget build(BuildContext context) {
    if (routeId == null || routeId!.isEmpty) {
      return const Text('No route assigned', style: TextStyle(color: Colors.grey, fontSize: 13));
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('routes').doc(routeId).get(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Error loading route', style: TextStyle(color: AppColors.error, fontSize: 13));
        if (!snapshot.hasData) return const Text('Loading route...', style: TextStyle(fontSize: 12));
        if (!snapshot.data!.exists) return const Text('Route not found', style: TextStyle(color: Colors.grey, fontSize: 13));
        
        final data = snapshot.data!.data() as Map<String, dynamic>;
        return Text(data['name'] ?? 'Unnamed Route', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500));
      },
    );
  }
}
