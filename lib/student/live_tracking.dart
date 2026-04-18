import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/theme.dart';
import '../services/google_maps_service.dart';
import '../services/notification_service.dart';
import 'package:geolocator/geolocator.dart';

class LiveTracking extends StatefulWidget {
  final String busId; 
  final LatLng initialLocation;
  final String initialBusNumber;

  const LiveTracking({
    super.key, 
    required this.busId,
    required this.initialLocation,
    required this.initialBusNumber,
  });

  @override
  State<LiveTracking> createState() => _LiveTrackingState();
}

class _LiveTrackingState extends State<LiveTracking> {
  late GoogleMapController mapController;
  late LatLng busLocation;
  LatLng? startLocation;
  LatLng? endLocation;
  List<Map<String, dynamic>> _stops = [];
  List<LatLng> _polylinePoints = [];
  BitmapDescriptor? _busIcon;
  BitmapDescriptor? _stopIcon;
  late String busNumber;
  String routeName = 'Loading route...';
  String startPoint = '';
  String endPoint = '';
  String eta = 'Calculating...';
  bool mapReady = false;
  bool _isPanelExpanded = false;
  String? _endStopEta;
  Timer? _etaTimer;
  String? _notifiedStopName;
  bool _hasNotifiedArrival = false;
  bool _isTrackingBus = true;
  String? _currentRouteId;
  DateTime? _lastEtaUpdate;
  Map<String, dynamic>? _cachedRouteData; 
  String? _lastDirection;
  DateTime? _lastUpdateTime; // Track last update time
  bool _isRefreshing = false; // Track refresh state 
  bool _isNavMode = false; // toggle for 3D navigation perspective
  double _lastHeading = 0.0; // tracks bus heading for 3D view

  void _focusOnBus() {
    setState(() => _isTrackingBus = true);
    if (mapReady) {
      if (_isNavMode) {
        mapController.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(
            target: busLocation,
            bearing: _lastHeading,
            tilt: 60.0,
            zoom: 17.5,
          )
        ));
      } else {
        mapController.animateCamera(CameraUpdate.newLatLngZoom(busLocation, 16));
      }
    }
  }

  void _fitEntireRoute() {
    setState(() => _isTrackingBus = false);
    if (!mapReady || _polylinePoints.isEmpty) return;
    
    double minLat = _polylinePoints[0].latitude;
    double maxLat = _polylinePoints[0].latitude;
    double minLng = _polylinePoints[0].longitude;
    double maxLng = _polylinePoints[0].longitude;

    for (var point in _polylinePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    mapController.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
        100.0, 
      ),
    );
  }

  void _setNotificationForStop(String stopName) {
    setState(() {
      if (_notifiedStopName == stopName) {
        _notifiedStopName = null;
      } else {
        _notifiedStopName = stopName;
        _hasNotifiedArrival = false;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_notifiedStopName != null ? 'Notification set for $stopName' : 'Notification cancelled'),
    ));
  }

  // Manual refresh function
  Future<void> _refreshData() async {
    if (_isRefreshing) return;
    
    setState(() {
      _isRefreshing = true;
    });
    
    try {
      // Force update ETA calculation
      final busDoc = await FirebaseFirestore.instance.collection('buses').doc(widget.busId).get();
      if (busDoc.exists) {
        await _updateETA(busDoc.data() as Map<String, dynamic>);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data refreshed successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to refresh: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    busLocation = widget.initialLocation;
    busNumber = widget.initialBusNumber;
    _refreshBusIcon();

    FirebaseFirestore.instance
        .collection('buses')
        .doc(widget.busId)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return;

      if (data['location'] != null) {
        GeoPoint loc = data['location'];
        final newLoc = LatLng(loc.latitude, loc.longitude);
        final String newBusNumber = data['busNumber'] ?? 'Bus';

        if (newBusNumber != busNumber) {
           busNumber = newBusNumber;
           _refreshBusIcon();
        }
        
        if (mounted) {
          setState(() {
            busLocation = newLoc;
            _lastHeading = (data['heading'] ?? 0.0).toDouble();
          });
        }

        _updateETA(data);

        if (mapReady && _isTrackingBus) {
          _focusOnBus();
        }
      }
      // Update route info whenever route changes
      final routeId = data['currentRouteId'] as String?;
      final currentDirection = data['direction'] as String? ?? 'forward';

      if (routeId != null && routeId.isNotEmpty) {
        // 1. Fetch route data if the route itself changed or is new
        if (routeId != _currentRouteId) {
          _currentRouteId = routeId;
          final routeDoc = await FirebaseFirestore.instance.collection('routes').doc(routeId).get();
          if (routeDoc.exists && mounted) {
            _cachedRouteData = routeDoc.data() as Map<String, dynamic>;
            _lastDirection = null; // force re-apply UI for new route
          }
        }

        // 2. FORCE APPLY: Check direction and refresh stops accordingly
        if (_cachedRouteData != null && (currentDirection != _lastDirection || _stops.isEmpty)) {
          _applyDirectionAndStops(_cachedRouteData!, currentDirection);
        }
      }
    });

    _etaTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      FirebaseFirestore.instance.collection('buses').doc(widget.busId).get().then((doc) {
        if (doc.exists) _updateETA(doc.data() as Map<String, dynamic>);
      });
    });
  }

  void _applyDirectionAndStops(Map<String, dynamic> rData, String direction) {
    if (!mounted) return;
    
    // Mapping: 
    // FROM_COLLEGE (Original Order: Start -> End)
    // TO_COLLEGE (Reversed Order: End -> Start)
    final bool isToCollege = direction == 'TO_COLLEGE' || direction == 'forward'; 
    final bool isFromCollege = direction == 'FROM_COLLEGE' || direction == 'return';

    // NOTE: Based on user feedback, the previous logic was inverted.
    // We want: 
    // FROM_COLLEGE -> Original [A, B, C, D, E]
    // TO_COLLEGE   -> Reversed [E, D, C, B, A]

    final start = rData['startpoint'] as Map?;
    final end = rData['endpoint'] as Map?;
    final List<dynamic> stopsRaw = List.from(rData['stops'] as List? ?? []);

    setState(() {
      _lastDirection = direction; // ADDED: track direction for badge
      routeName = rData['name'] ?? 'Route';
      List<Map<String, dynamic>> processedStops = [];
      
      if (isToCollege) {
        // TO COLLEGE trip: Use ORIGINAL [Home -> College] list order
        startPoint = start?['name'] ?? 'Start';
        endPoint = end?['name'] ?? 'College';
        startLocation = start != null ? LatLng((start['lat'] ?? 0).toDouble(), (start['lng'] ?? 0).toDouble()) : null;
        endLocation = end != null ? LatLng((end['lat'] ?? 0).toDouble(), (end['lng'] ?? 0).toDouble()) : null;
        processedStops = stopsRaw.map((s) => Map<String, dynamic>.from(s is Map ? s : {'name': s.toString()})).toList();
      } else {
        // FROM COLLEGE trip (Return): Use REVERSED [College -> Home] list order
        startPoint = end?['name'] ?? 'College';
        endPoint = start?['name'] ?? 'Destination';
        startLocation = end != null ? LatLng((end['lat'] ?? 0).toDouble(), (end['lng'] ?? 0).toDouble()) : null;
        endLocation = start != null ? LatLng((start['lat'] ?? 0).toDouble(), (start['lng'] ?? 0).toDouble()) : null;
        processedStops = stopsRaw.reversed.map((s) => Map<String, dynamic>.from(s is Map ? s : {'name': s.toString()})).toList();
      }

      _stops = [];
      if (startLocation != null) {
        _stops.add({'name': startPoint, 'lat': startLocation!.latitude, 'lng': startLocation!.longitude});
      }
      _stops.addAll(processedStops);
      if (endLocation != null) {
        _stops.add({'name': endPoint, 'lat': endLocation!.latitude, 'lng': endLocation!.longitude});
      }
      _lastDirection = direction; // FIXED: Update state inside setState for UI rebuild
    });

    _updatePolyline(); 
  }


  Future<void> _refreshBusIcon() async {
    final bus = await GoogleMapsService.getBusMarkerWithNumber(busNumber);
    final stop = await GoogleMapsService.getMarkerIcon(Icons.location_on_rounded, AppColors.accent, size: 25); // Absolute minimum size
    if (mounted) {
      setState(() {
        _busIcon = bus;
        _stopIcon = stop;
      });
    }
  }

  Future<void> _updatePolyline() async {
    List<LatLng> pts = [];
    for (var stop in _stops) {
      if (stop['lat'] != null && stop['lat'] != 0) {
        pts.add(LatLng(stop['lat'], stop['lng']));
      }
    }
    if (pts.length < 2) return;
    
    // Automatic route optimization: Uses OSRM to follow actual roads
    final points = await GoogleMapsService.getRoutePolyline(pts);
    if (mounted && points.isNotEmpty) {
      setState(() { _polylinePoints = points; });
    } else if (mounted) {
      // Fallback to direct points if OSRM fails
      setState(() { _polylinePoints = pts; });
    }
  }

  Future<void> _updateETA(Map<String, dynamic> busData) async {
    if (_lastEtaUpdate != null && DateTime.now().difference(_lastEtaUpdate!).inSeconds < 5) return;
    _lastEtaUpdate = DateTime.now();

    final GeoPoint? busLocPoint = busData['location'] as GeoPoint?;
    if (busLocPoint == null || _stops.isEmpty) return;

    final currentPos = LatLng(busLocPoint.latitude, busLocPoint.longitude);
    final double? currentSpeed = busData['speed']?.toDouble();
    final bool isReturn = _lastDirection == 'return';

    // Find the nearest stop to determine which stops are passed vs upcoming
    int nearestIdx = -1;
    double minDistance = double.infinity;
    for (int i = 0; i < _stops.length; i++) {
        if (_stops[i]['lat'] != null && _stops[i]['lat'] != 0) {
          double d = Geolocator.distanceBetween(currentPos.latitude, currentPos.longitude, _stops[i]['lat'], _stops[i]['lng']);
          if (d < minDistance) { 
            minDistance = d; 
            nearestIdx = i; 
          }
        }
    }

    // Calculate ETAs for ALL stops in order
    final List<LatLng> allStopPoints = [];
    for (int i = 0; i < _stops.length; i++) {
      if (_stops[i]['lat'] != null && _stops[i]['lat'] != 0) {
        allStopPoints.add(LatLng(_stops[i]['lat'], _stops[i]['lng']));
      }
    }
    
    if (allStopPoints.isEmpty) return;

    final results = GoogleMapsService.calculateCumulativeETAs(currentPos, allStopPoints, speedInMpS: currentSpeed);

    // Assign ETAs to ALL stops and determine their status
    for (int i = 0; i < _stops.length; i++) {
      if (_stops[i]['lat'] != null && _stops[i]['lat'] != 0) {
        // Assign ETA to this stop
        if (i < results.length) {
          _stops[i]['eta'] = results[i];
        }

        // Robust ordering: Since _stops is already travel-ordered (reversed if return), 
        // the nearest stop is the logical "Current/Next" target.
        double distanceToStop = Geolocator.distanceBetween(currentPos.latitude, currentPos.longitude, _stops[i]['lat'], _stops[i]['lng']);
        if (distanceToStop < 100) {
          _stops[i]['isPassed'] = false;
          _stops[i]['isNext'] = true;
          _stops[i]['isAtStop'] = true; // High-confidence "At Stop" state
        } else {
          _stops[i]['isPassed'] = i < nearestIdx;
          _stops[i]['isNext'] = i == nearestIdx;
        }
      }
    }

    // Find the next stop for display
    String nextStopMsg = 'In Transit';
    String? nextStopId;
    
    // First check if there's a stop marked as "next"
    for (var stop in _stops) {
      if (stop['isNext'] == true) {
        nextStopMsg = 'Next: ${stop['name']}${stop['eta'] != null ? ' at ${stop['eta']}' : ''}';
        nextStopId = stop['name'];
        break;
      }
    }
    
    // If no explicit next stop, find the first upcoming stop with ETA
    if (nextStopId == null) {
      for (var stop in _stops) {
        if (stop['eta'] != null && stop['isPassed'] != true) {
          nextStopMsg = 'Next: ${stop['name']} at ${stop['eta']}';
          nextStopId = stop['name'];
          break;
        }
      }
    }
    
    if (mounted) {
      setState(() {
        eta = nextStopMsg;
        _endStopEta = (endLocation != null && results.isNotEmpty) ? results.last : null;
        _lastUpdateTime = DateTime.now(); // Update last refresh time
      });
    }

    if (_notifiedStopName != null && !_hasNotifiedArrival) {
      LatLng? target;
      if (_notifiedStopName == endPoint) target = endLocation;
      else {
        for (var s in _stops) { if (s['name'] == _notifiedStopName) target = LatLng(s['lat'], s['lng']); }
      }
      if (target != null && Geolocator.distanceBetween(currentPos.latitude, currentPos.longitude, target.latitude, target.longitude) < 2000) { // 2 km notification radius
          _hasNotifiedArrival = true;
          NotificationService.showNotification(id: 888, title: 'Bus Arriving!', body: '$busNumber is near $_notifiedStopName');
      }
    }
  }

  @override
  void dispose() { _etaTimer?.cancel(); super.dispose(); }

  // Format time for display
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    Set<Marker> markers = {
      Marker(
        markerId: MarkerId(widget.busId),
        position: busLocation,
        icon: _busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        zIndex: 10,
      ),
    };

    for (int i = 0 ; i < _stops.length; i++) {
      final s = _stops[i];
      if (s['lat'] != null && (s['lat'] ?? 0) != 0) {
        markers.add(Marker(
          markerId: MarkerId('stop_$i'),
          position: LatLng(s['lat'], s['lng']),
          infoWindow: InfoWindow(title: i == 0 ? 'Start: ${s['name']}' : (i == _stops.length - 1 ? 'End: ${s['name']}' : 'Stop: ${s['name']}')),
          icon: _stopIcon ?? (i == 0 || i == _stops.length - 1 ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)),
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: _isRefreshing 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.refresh),
            onPressed: _refreshData,
            tooltip: 'Refresh data',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: busLocation, zoom: 14),
            markers: markers,
            polylines: {
              Polyline(
                polylineId: const PolylineId('r'), 
                points: _polylinePoints, 
                color: AppColors.primary, 
                width: 7,
                jointType: JointType.round,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
              )
            },
            onMapCreated: (c) { mapController = c; mapReady = true; if (_isTrackingBus) _focusOnBus(); },
            onCameraMoveStarted: () { if (_isTrackingBus) setState(() => _isTrackingBus = false); },
          ),
          
          // Floating Controls
          Positioned(right: 16, top: 16, child: Column(children: [
            FloatingActionButton.small(heroTag: 'f', backgroundColor: _isTrackingBus ? AppColors.primary : Colors.white, foregroundColor: _isTrackingBus ? Colors.white : AppColors.primary, onPressed: _focusOnBus, child: const Icon(Icons.my_location)),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'nav', 
              backgroundColor: _isNavMode ? AppColors.primary : Colors.white, 
              foregroundColor: _isNavMode ? Colors.white : AppColors.primary, 
              onPressed: () {
                setState(() => _isNavMode = !_isNavMode);
                if (_isNavMode) _focusOnBus();
              }, 
              child: Icon(_isNavMode ? Icons.explore : Icons.navigation_rounded)
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: 'r', backgroundColor: Colors.white, foregroundColor: AppColors.primary, onPressed: _fitEntireRoute, child: const Icon(Icons.map_outlined)),
          ])),

          // Info Panel
          Positioned(left: 16, right: 16, bottom: 24, child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Color(0x1A4F46E5), shape: BoxShape.circle), child: const Icon(Icons.directions_bus, color: AppColors.primary, size: 24)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(busNumber, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(routeName, style: TextStyle(fontSize: 12, color: AppColors.primary.withOpacity(0.7)), overflow: TextOverflow.ellipsis),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), 
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        (_lastDirection == 'FROM_COLLEGE' || _lastDirection == 'return') 
                            ? Icons.logout_rounded : Icons.login_rounded,
                        size: 10, color: AppColors.success
                      ),
                      const SizedBox(width: 4),
                      Text(
                        // FIXED: Re-mapping direction to fixed labels
                        (_lastDirection == 'FROM_COLLEGE' || _lastDirection == 'return') ? 'FROM COLLEGE' : 'TO COLLEGE', 
                        style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold)
                      ),
                    ],
                  )),
              ]),
              const Divider(height: 32),
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.05), borderRadius: BorderRadius.circular(12)), child: Row(children: [
                const Icon(Icons.timer_outlined, color: AppColors.primary, size: 20), const SizedBox(width: 12), Expanded(child: Text(eta, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)))
              ])),
              const SizedBox(height: 8),
              // Last updated timestamp
              if (_lastUpdateTime != null) 
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.update, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        'Updated ${_formatTime(_lastUpdateTime!)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => setState(() => _isPanelExpanded = !_isPanelExpanded),
                child: Row(children: [
                  const Icon(Icons.location_on_outlined, color: AppColors.textMuted, size: 18), const SizedBox(width: 8),
                  Expanded(child: Text('$startPoint → $endPoint', style: const TextStyle(color: AppColors.textMuted, fontSize: 13), overflow: TextOverflow.ellipsis)),
                  Icon(_isPanelExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textMuted),
                ]),
              ),
              if (_isPanelExpanded) ...[
                const Divider(height: 24),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _stops.length,
                    itemBuilder: (context, idx) {
                      final s = _stops[idx];
                      final isPassed = s['isPassed'] == true;
                      final isNext = s['isNext'] == true;
                      return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
                        Icon(isPassed ? Icons.check_circle_outline : (isNext ? Icons.play_circle_fill : Icons.location_on), size: 16, color: isPassed ? Colors.grey : (isNext ? AppColors.primary : AppColors.accent)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(s['name'] ?? '', style: TextStyle(fontSize: 13, color: isPassed ? Colors.grey : AppColors.textPrimary, decoration: isPassed ? TextDecoration.lineThrough : null))),
                        if (s['eta'] != null) Text(s['eta'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => _setNotificationForStop(s['name']),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              _notifiedStopName == s['name'] ? Icons.notifications_active : Icons.notifications_none,
                              size: 18,
                              color: _notifiedStopName == s['name'] ? AppColors.primary : Colors.grey,
                            ),
                          ),
                        ),
                      ]));
                    },
                  ),
                )
              ]
            ]),
          ))
        ],
      ),
    );
  }
}
