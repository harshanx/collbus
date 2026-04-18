import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // ADDED: Map support
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/google_maps_service.dart'; // ADDED: Helper service
import '../core/theme.dart';
import '../core/constants.dart';
// FIXED: Removed unused imports (api_service, notification_service)
import '../widgets/menu_dialogs.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<DocumentSnapshot>? _driverSub;
  StreamSubscription<DocumentSnapshot>? _routeSub;
  StreamSubscription<DocumentSnapshot>? _busSub;

  DocumentSnapshot? _routeDoc;
  DocumentSnapshot? _busDoc;

  bool _isTripActive = false;
  bool _isLoading = true;
  String _errorMessage = '';
  DateTime? _tripStartTime;
  double _currentSpeed = 0.0; // speed in km/h
  String? _lastPublishedDirection; // tracks last direction pushed to Firestore

  // New variables for ETA calculation
  Position? _currentPosition;
  List<Map<String, dynamic>> _stopsWithETA = [];
  // NEW FEATURE: Map and Tracking states
  GoogleMapController? _mapController;
  List<LatLng> _fullRouteCoords = [];
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  Set<Marker> _stopMarkers = {}; // stores static pins for stops along the route
  int _lastSplitIndex = 0;
  Timer? _etaTimer;
  String? _currentTripDocId; // tracks the current trip record in Firestore
  bool _isNavMode = false; // toggle for 3D navigation perspective
  BitmapDescriptor? _busIcon; // custom bus marker icon
  StreamSubscription<Position>? _globalPositionSub; // tracks driver even when trip is inactive

  @override
  void initState() {
    super.initState();
    _loadBusIcon();
    _setupListeners();
    _startGlobalLocationListener(); // start tracking driver position immediately for the map UI
  }

  Future<void> _loadBusIcon() async {
    final icon = await GoogleMapsService.getBusMarkerWithNumber('', size: 50);
    if (mounted) setState(() { _busIcon = icon; });
  }

  void _startGlobalLocationListener() async {
    if (!await _requestLocationPermission()) return;
    
    _globalPositionSub?.cancel();
    _globalPositionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)
    ).listen((pos) {
      if (!mounted) return;
      
      // Update local position for map UI focus
      if (_currentPosition == null) {
        // Initial fly-to driver location
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
      }
      
      setState(() { _currentPosition = pos; });
      _updatePolylineSlicing(); // Refresh the bus marker on the map
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _globalPositionSub?.cancel();
    _driverSub?.cancel();
    _routeSub?.cancel();
    _busSub?.cancel();
    _etaTimer?.cancel();
    super.dispose();
  }

  // ─── Real-time Listeners ──────────────────────────────────────────────────
  void _setupListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() { _errorMessage = 'Not logged in'; _isLoading = false; });
      return;
    }

    setState(() { _isLoading = true; });

    // 1. Listen to Driver doc
    _driverSub?.cancel();
    _driverSub = FirebaseFirestore.instance
        .collection('drivers')
        .doc(user.uid)
        .snapshots()
        .listen((driverSnap) {
      if (!driverSnap.exists) {
        setState(() { _errorMessage = 'Driver account not found.'; _isLoading = false; });
        _stopSharingLocally();
        return;
      }

      final routeId = (driverSnap.data()?['currentRouteId'] ?? '') as String;
      if (routeId.isEmpty) {
        setState(() { 
          _errorMessage = 'No route assigned.'; 
          _isLoading = false; 
          _routeDoc = null;
          _busDoc = null;
        });
        _stopSharingLocally();
        return;
      }

      // 2. Listen to Route doc
      _listenToRoute(routeId);
    }, onError: (e) {
      setState(() { _errorMessage = 'Error: $e'; _isLoading = false; });
    });
  }

  void _listenToRoute(String routeId) {
    _routeSub?.cancel();
    _routeSub = FirebaseFirestore.instance
        .collection('routes')
        .doc(routeId)
        .snapshots()
        .listen((routeSnap) async {
      if (!routeSnap.exists) {
        _errorMessage = 'Assigned route was deleted.';
        _stopSharingLocally();
        _snack('Your assigned route was deleted by Admin.');
        setState(() { _routeDoc = null; _busDoc = null; _isLoading = false; });
        return;
      }

      final busId = (routeSnap.data()?['busid'] ?? '') as String;
      if (busId.isEmpty) {
        _stopSharingLocally();
        setState(() { 
          _routeDoc = routeSnap; 
          _busDoc = null; 
          _errorMessage = 'No bus assigned to this route.';
          _isLoading = false; 
        });
        return;
      }

      // 3. Listen to Bus doc
      _busSub?.cancel();
      _busSub = FirebaseFirestore.instance
          .collection('buses')
          .doc(busId)
          .snapshots()
          .listen((busSnap) {
        if (!mounted) return;
        final prevRouteId = (_routeDoc?.data() as Map<String, dynamic>?)?['id'];
        final newRouteId = routeSnap.id;
        setState(() {
          _routeDoc = routeSnap;
          _busDoc = busSnap.exists ? busSnap : null;
          // FIXED: Re-fetch polyline whenever route changes, not just when empty
          if (_routeDoc != null && (prevRouteId != newRouteId || _fullRouteCoords.isEmpty)) {
            _fullRouteCoords = []; // reset to force reload
            _fetchRoutePolyline();
          }
          _isTripActive = routeSnap.data()?['isTripActive'] == true;
          _errorMessage = busSnap.exists ? '' : 'Assigned bus not found.';
          _isLoading = false;
        });
      }, onError: (e) {
        if (mounted) setState(() { _errorMessage = 'Error listening to bus: $e'; _isLoading = false; });
      });
    });
  }

  void _stopSharingLocally() async {
    if (_isTripActive) {
      _positionSub?.cancel();
      _positionSub = null;
      _etaTimer?.cancel(); // Cancel ETA timer
      if (mounted) setState(() { _isTripActive = false; });
      debugPrint('Location sharing stopped locally.');

      // Also attempt to clear from Firestore if possible
      if (_busDoc != null) {
        try {
          await FirebaseFirestore.instance
              .collection('buses')
              .doc(_busDoc!.id)
              .update({'location': FieldValue.delete()});
          debugPrint('Bus location cleared from Firestore.');
        } catch (e) {
          debugPrint('Error clearing location from Firestore: $e');
        }
      }
    }
  }

  // Helper fetch for manual refresh
  Future<void> _fetchAssignment() async {
    _setupListeners();
  }

  /// Automatically re-evaluates bus direction on every GPS update.
  /// Enhanced multi-factor analysis for robust direction detection
  void _autoUpdateDirection(double lat, double lng) {
    if (_routeDoc == null || _busDoc == null) return;
    final rData = _routeDoc!.data() as Map<String, dynamic>?;
    if (rData == null) return;

    final start = rData['startpoint'] as Map?;
    final end   = rData['endpoint']   as Map?;
    if (start == null || end == null) return;

    final distToStart = Geolocator.distanceBetween(
      lat, lng,
      (start['lat'] ?? 0).toDouble(), (start['lng'] ?? 0).toDouble(),
    );
    final distToEnd = Geolocator.distanceBetween(
      lat, lng,
      (end['lat'] ?? 0).toDouble(), (end['lng'] ?? 0).toDouble(),
    );

    final now = DateTime.now();
    String detectedDirection;
    
    // Multi-factor analysis for real-time updates
    final maxDistance = math.max(distToStart, distToEnd);
    final distanceRatio = distToStart / (distToEnd + 0.1);
    
    // Factor 1: Time-based (Morning = TO COLLEGE, Evening = FROM COLLEGE)
    final timeBasedDirection = now.hour >= 14 ? 'FROM_COLLEGE' : 'TO_COLLEGE';
    
    // Factor 2: Distance-based with confidence levels
    String distanceBasedDirection = 'TO_COLLEGE';
    if (distanceRatio > 2.0) {
      distanceBasedDirection = 'FROM_COLLEGE'; // High confidence
    } else if (distanceRatio < 0.5) {
      distanceBasedDirection = 'TO_COLLEGE'; // High confidence
    }
    
    // Factor 3: Proximity detection
    String proximityDirection = 'TO_COLLEGE';
    if (distToEnd < 300) { // Very close to endpoint
      proximityDirection = 'FROM_COLLEGE';
    } else if (distToStart < 300) { // Very close to start
      proximityDirection = 'TO_COLLEGE';
    }
    
    // Smart decision making based on context
    if (maxDistance > 50000) { // Very far from route
      detectedDirection = timeBasedDirection;
    } else if (now.hour >= 12 && now.hour <= 16) { // Peak hours (12-4 PM)
      // Prioritize time during peak hours
      detectedDirection = timeBasedDirection;
    } else if (distanceRatio > 3.0 || distanceRatio < 0.33) { // Very strong distance signal
      detectedDirection = distanceBasedDirection;
    } else if (distToEnd < 500 || distToStart < 500) { // Very close to endpoints
      detectedDirection = proximityDirection;
    } else {
      // Balanced approach
      detectedDirection = timeBasedDirection;
    }

    // Only write to Firestore if direction actually changed (avoid spamming writes)
    if (detectedDirection != _lastPublishedDirection) {
      _lastPublishedDirection = detectedDirection;
      FirebaseFirestore.instance
          .collection('buses')
          .doc(_busDoc!.id)
          .update({'direction': detectedDirection});
      debugPrint('Auto-direction updated → $detectedDirection (Time: ${now.hour}:00, Ratio: ${distanceRatio.toStringAsFixed(2)}, Start: ${(distToStart/1000).round()}km, End: ${(distToEnd/1000).round()}km)');
    }
  }

  Future<bool> _requestLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _snack('Please enable location services.');
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        _snack('Location permission denied.');
        return false;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      _snack('Location permission permanently denied.');
      return false;
    }
    return true;
  }

  // Helper function to auto-detect direction (used by _startTrip)
  String _autoDetectDirection(Position pos, Map? start, Map? end) {
    String direction = 'forward';
    final now = DateTime.now();
    
    if (start != null && end != null) {
      final distToStart = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        (start['lat'] ?? 0).toDouble(), (start['lng'] ?? 0).toDouble()
      );
      final distToEnd = Geolocator.distanceBetween(
        pos.latitude, pos.longitude,
        (end['lat'] ?? 0).toDouble(), (end['lng'] ?? 0).toDouble()
      );
      
      // Smart direction detection with multiple factors
      final maxDistance = math.max(distToStart, distToEnd);
      final distanceRatio = distToStart / (distToEnd + 0.1); // Avoid division by zero
      
      // Factor 1: Time of day (Morning = TO COLLEGE, Evening = FROM COLLEGE)
      final timeBasedDirection = now.hour >= 14 ? 'FROM_COLLEGE' : 'TO_COLLEGE';
      
      // Factor 2: Distance ratio (how much closer to one endpoint)
      final distanceBasedDirection = distanceRatio > 1.2 ? 'FROM_COLLEGE' : 'TO_COLLEGE';
      
      // Factor 3: Proximity threshold (very close to an endpoint)
      String proximityBasedDirection = 'TO_COLLEGE';
      if (distToEnd < 500) { // Within 500m of endpoint
        proximityBasedDirection = 'FROM_COLLEGE';
      } else if (distToStart < 500) { // Within 500m of start
        proximityBasedDirection = 'TO_COLLEGE';
      }
      
      // Decision logic with confidence scoring
      if (maxDistance > 50000) { // Very far from route (>50km)
        // Use time-based logic with high confidence
        direction = timeBasedDirection;
      } else if (now.hour >= 14 || now.hour < 6) { // Evening/early morning
        // Weight time more heavily
        if (distanceRatio > 1.5) {
          direction = 'FROM_COLLEGE';
        } else if (distanceRatio < 0.7) {
          direction = 'TO_COLLEGE';
        } else {
          direction = timeBasedDirection;
        }
      } else { // Normal hours
        // Balance time and distance
        if (distToEnd < 1000 || distToStart < 1000) { // Very close to either endpoint
          direction = proximityBasedDirection;
        } else if (distanceRatio > 2.0 || distanceRatio < 0.5) { // Strong distance signal
          direction = distanceBasedDirection;
        } else {
          direction = timeBasedDirection;
        }
      }
      
      debugPrint('Direction detection: $direction (Time: ${now.hour}:00, Ratio: ${distanceRatio.toStringAsFixed(2)}, Dist to start: ${(distToStart/1000).round()}km, to end: ${(distToEnd/1000).round()}km)');
    }
    
    return direction;
  }

  // ─── Start Trip ───────────────────────────────────────────────────────────
  void _startTrip() async {
    if (_routeDoc == null || _busDoc == null) return;
    if (!await _requestLocationPermission()) return;

    // 1. Mark trip as active on route
    await FirebaseFirestore.instance
        .collection('routes')
        .doc(_routeDoc!.id)
        .update({'isTripActive': true});
        
    _tripStartTime = DateTime.now();

    // 2. Write initial location and detect direction immediately
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final busRef = FirebaseFirestore.instance.collection('buses').doc(_busDoc!.id);
      
      // Auto-detect direction
      final rData = _routeDoc!.data() as Map<String, dynamic>;
      final start = rData['startpoint'] as Map?;
      final end = rData['endpoint'] as Map?;
      
      String direction = _autoDetectDirection(pos, start, end);
      
      await busRef.update({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'direction': direction,
      });
      // Store initial position for immediate ETA calculation
      _currentPosition = pos;
    } catch (e) {
      debugPrint('Error writing initial location: $e');
    }

    // 3. Start streaming updates with high responsiveness
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0, // FIXED: Trigger on every change
      intervalDuration: const Duration(milliseconds: 500), // FIXED: 500ms update rate instead of default lag
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: "Bus tracking is active in the background",
        notificationTitle: "CollBus Tracking",
        enableWakeLock: true,
      ),
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (pos) {
        if (!mounted) return;
        setState(() {
          _currentSpeed = pos.speed * 3.6; // Convert m/s to km/h
        });

        if (_busDoc != null) {
          final busRef = FirebaseFirestore.instance.collection('buses').doc(_busDoc!.id);
          busRef.update({
            'location': GeoPoint(pos.latitude, pos.longitude),
            'speed': pos.speed, // m/s
            'heading': pos.heading, // degrees
            'timestamp': FieldValue.serverTimestamp(),
          });

          // Store current position for ETA calculation
          _currentPosition = pos;

          // Auto-detect and update direction on every GPS tick
          _autoUpdateDirection(pos.latitude, pos.longitude);
          _updatePolylineSlicing(); // ADDED: Refresh map visuals
        }
      },
      onError: (e) {
        _snack('Location sharing interrupted.');
        _stopSharingLocally();
      },
    );

    // 4. Create Trip History record at START
    try {
      final user = FirebaseAuth.instance.currentUser;
      final rData = _routeDoc!.data() as Map<String, dynamic>?;
      final bData = _busDoc!.data() as Map<String, dynamic>?;

      final tripRef = await FirebaseFirestore.instance.collection('trip_history').add({
        'busId': _busDoc?.id, // ADDED: ID for persistent tracking
        'routeId': _routeDoc?.id, // ADDED: ID for persistent tracking
        'busNumber': bData?['busNumber'] ?? 'Unknown',
        'driverEmail': user?.email ?? 'Unknown',
        'routeName': rData?['name'] ?? 'Unknown',
        'startTime': FieldValue.serverTimestamp(),
        'endTime': null, 
        'status': 'Running', // ADDED: Initial status 
        'createdAt': FieldValue.serverTimestamp(),
      });
      _currentTripDocId = tripRef.id;
    } catch (e) {
      debugPrint('Failed to initialize trip history: $e');
    }

    // Start ETA calculation timer
    _startETATimer();
    _calculateETAs(); // FIXED: Initial calculation immediately on start
  }

  void _toggleDirection() async {
    if (_busDoc == null) return;
    final busData = _busDoc!.data() as Map<String, dynamic>?;
    final currentDir = busData?['direction'] ?? 'TO_COLLEGE';
    final newDir = (currentDir == 'TO_COLLEGE') ? 'FROM_COLLEGE' : 'TO_COLLEGE';
    
    await FirebaseFirestore.instance
        .collection('buses')
        .doc(_busDoc!.id)
        .update({'direction': newDir});
        
    _snack('Direction: ${newDir == 'FROM_COLLEGE' ? 'From College' : 'To College'}');
  }

  // ─── End Trip ─────────────────────────────────────────────────────────────
  void _endTrip() async {
    _stopSharingLocally();

    // FIXED: Clear route status and bus location in a single batch to avoid duplicate writes
    if (_routeDoc != null && _routeDoc!.exists) {
      await FirebaseFirestore.instance
          .collection('routes')
          .doc(_routeDoc!.id)
          .update({'isTripActive': false});
    }

    if (_busDoc != null && _busDoc!.exists) {
      // FIXED: Single update — clears location, direction, speed in one write
      await FirebaseFirestore.instance
          .collection('buses')
          .doc(_busDoc!.id)
          .update({
            'location': FieldValue.delete(),
            'direction': FieldValue.delete(),
            'speed': FieldValue.delete(),
            'heading': FieldValue.delete(),
          });
    }

    // FIXED: Trip History — only save if duration >= 10 minutes
    if (_currentTripDocId != null) {
      try {
        final endTime = DateTime.now();
        final startTime = _tripStartTime ?? endTime;
        final durationInMinutes = endTime.difference(startTime).inMinutes;

        if (durationInMinutes >= 10) {
          // Valid trip → save as Completed
          await FirebaseFirestore.instance
              .collection('trip_history')
              .doc(_currentTripDocId)
              .update({
            'endTime': FieldValue.serverTimestamp(),
            'duration': durationInMinutes,
            'status': 'Completed',
          });
          debugPrint('Trip saved. Duration: $durationInMinutes mins.');
        } else {
          // Too short → discard the running record
          await FirebaseFirestore.instance
              .collection('trip_history')
              .doc(_currentTripDocId)
              .delete();
          debugPrint('Trip discarded (< 10 mins).');
        }
      } catch (e) {
        debugPrint('Failed to finalize trip history: $e');
      }
      _currentTripDocId = null;
    }
    _tripStartTime = null;

    // FIXED: Reset map visuals after trip ends
    if (mounted) {
      setState(() {
        _polylines = {};
        _markers = {};
        _fullRouteCoords = [];
        _lastSplitIndex = 0;
      });
    }
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Calculate ETAs for all stops based on current position and direction
  void _calculateETAs() {
    if (_currentPosition == null || _routeDoc == null) return;
    
    final routeData = _routeDoc!.data() as Map<String, dynamic>?;
    if (routeData == null) return;
    
    final stops = routeData['stops'] as List? ?? [];
    final direction = (_busDoc?.data() as Map<String, dynamic>?)?['direction'] ?? 'TO_COLLEGE';
    final isToCollege = direction == 'TO_COLLEGE' || direction == 'forward';
    
    // Find current position in route
    int currentStopIndex = -1;
    double minDistance = double.infinity;
    
    for (int i = 0; i < stops.length; i++) {
      final stop = stops[i];
      if (stop is Map && stop['lat'] != null) {
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          stop['lat'].toDouble(),
          stop['lng'].toDouble(),
        );
        if (distance < minDistance) {
          minDistance = distance;
          currentStopIndex = i;
        }
      }
    }
    
    // Order stops based on direction
    List<Map<String, dynamic>> orderedStops = [];
    
    if (isToCollege) {
      // TO COLLEGE trip (Forward): Travel from start of original array to end (0 -> N)
      for (int i = 0; i < stops.length; i++) {
        final stop = stops[i] is Map ? Map<String, dynamic>.from(stops[i]) : {'name': stops[i].toString()};
        
        // Status logic for original (TO COLLEGE) travel:
        if (i == currentStopIndex) {
          stop['status'] = 'current';
        } else if (i < currentStopIndex) {
          stop['status'] = 'passed';
        } else {
          stop['status'] = 'upcoming';
        }
        orderedStops.add(stop);
      }
    } else {
      // FROM COLLEGE trip (Return): Travel from end of original array to start (N -> 0)
      for (int i = stops.length - 1; i >= 0; i--) {
        final stop = stops[i] is Map ? Map<String, dynamic>.from(stops[i]) : {'name': stops[i].toString()};
        
        // Status logic for reversed (FROM COLLEGE) travel:
        if (i == currentStopIndex) {
          stop['status'] = 'current';
        } else if (i > currentStopIndex) {
          stop['status'] = 'passed';
        } else {
          stop['status'] = 'upcoming';
        }
        orderedStops.add(stop);
      }
    }
    
    // Calculate ETAs for ordered stops
    final List<Map<String, dynamic>> stopsWithETA = [];
    
    for (int i = 0; i < orderedStops.length; i++) {
      final stop = orderedStops[i];
      
      String eta = '';
      String stopStatus = '';
      
      if (i == 0 && minDistance < 50) {
        eta = 'Now';
        stopStatus = 'current';
      } else if (i > 0) {
        // Calculate cumulative distance from current position
        final distance = _calculateCumulativeDistance(orderedStops, i);
        
        // Calculate ETA based on current speed
        final speedKmh = _currentSpeed > 0 ? _currentSpeed : 30.0; // Default to 30 km/h if not moving
        final speedMs = speedKmh / 3.6; // Convert km/h to m/s
        final timeSeconds = distance / speedMs;
        
        if (timeSeconds < 60) {
          eta = '${timeSeconds.round()}s';
        } else if (timeSeconds < 3600) {
          eta = '${(timeSeconds / 60).round()}m';
        } else {
          eta = '${(timeSeconds / 3600).round()}h ${(timeSeconds % 3600 / 60).round()}m';
        }
        
        // Set status for college trips
        if (!isToCollege) {
          if (stop['isLastStop'] == true) {
            stopStatus = 'last'; // This is the stop nearest to college
          } else if (i == 0) {
            stopStatus = 'next'; // This is the nearest stop to current position
          } else {
            stopStatus = 'upcoming';
          }
        }
      }
      
      stopsWithETA.add({
        ...stop,
        'eta': eta,
        'distance': i == 0 ? minDistance.round() : (i > 0 ? _calculateCumulativeDistance(orderedStops, i) : 0).round(),
        'status': stopStatus,
      });
    }
    
    if (mounted) {
      setState(() {
        _stopsWithETA = stopsWithETA;
      });
    }
  }

  // Start ETA calculation timer
  void _startETATimer() {
    _etaTimer?.cancel();
    _etaTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _calculateETAs();
    });
  }

  // Helper functions for stop display
  IconData _getStopIcon(String? status) {
    switch (status) {
      case 'current':
        return Icons.my_location_rounded;
      case 'next':
        return Icons.play_circle_fill_rounded;
      case 'last':
        return Icons.flag_rounded;
      case 'passed':
        return Icons.check_circle_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  Color _getStopIconColor(String? status) {
    switch (status) {
      case 'current':
        return AppColors.success;
      case 'next':
        return AppColors.primary;
      case 'last':
        return AppColors.error;
      case 'passed':
        return Colors.grey;
      default:
        return AppColors.primary;
    }
  }

  Color _getETAColor(String? status) {
    switch (status) {
      case 'current':
        return AppColors.success;
      case 'next':
        return AppColors.primary;
      case 'last':
        return AppColors.error;
      case 'passed':
        return Colors.grey;
      default:
        return AppColors.success.withOpacity(0.1);
    }
  }

  TextStyle _getStopTextStyle(String? status) {
    switch (status) {
      case 'passed':
        return const TextStyle(fontSize: 14, color: Colors.grey, decoration: TextDecoration.lineThrough);
      default:
        return const TextStyle(fontSize: 14);
    }
  }

  // Helper function to calculate cumulative distance
  double _calculateCumulativeDistance(List<Map<String, dynamic>> orderedStops, int targetIndex) {
    double totalDistance = 0;
    Position lastPos = _currentPosition!;
    
    for (int i = 0; i < targetIndex; i++) {
      final prevStop = orderedStops[i];
      // FIXED: prevStop is already Map<String,dynamic>, removed redundant type check
      if (prevStop['lat'] != null) {
        final distance = Geolocator.distanceBetween(
          lastPos.latitude,
          lastPos.longitude,
          prevStop['lat'].toDouble(),
          prevStop['lng'].toDouble(),
        );
        totalDistance += distance;
        lastPos = Position(
          latitude: prevStop['lat'].toDouble(),
          longitude: prevStop['lng'].toDouble(),
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );
      }
    }
    
    return totalDistance;
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchAssignment,
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            elevation: 10,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'logout') {
                MenuDialogs.showLogoutConfirmation(context, () {
                  Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
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
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(Constants.paddingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSpeedometer(),
              const SizedBox(height: 24),
              // NEW FEATURE: Interactive Driver Map
              _buildMapView(),
              _buildInfoCard(),
              const SizedBox(height: 24),
              if (_errorMessage.isEmpty) ...[
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Constants.radiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || _isTripActive ? null : _startTrip,
                    icon: const Icon(Icons.play_circle_fill_rounded, size: 28, color: Colors.white),
                    label: const Text('START TRIP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Constants.radiusLg)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _isTripActive ? _endTrip : null,
                  icon: const Icon(Icons.stop_circle_rounded, size: 28),
                  label: const Text('END TRIP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    side: const BorderSide(color: AppColors.error, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Constants.radiusLg)),
                  ),
                ),
                if (_isTripActive) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _toggleDirection,
                    icon: const Icon(Icons.swap_calls_rounded),
                    label: const Text('CHANGE DIRECTION'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Info Card ────────────────────────────────────────────────────────────
  Widget _buildInfoCard() {
    final routeData = _routeDoc?.data() as Map<String, dynamic>?;
    final busData = _busDoc?.data() as Map<String, dynamic>?;

    final routeName = routeData?['name'] ?? '—';
    final busNumber = busData?['busNumber'] ?? '—';
    final startName = (routeData?['startpoint'] as Map?)?['name'] ?? '';
    final endName = (routeData?['endpoint'] as Map?)?['name'] ?? '';

    return Container(
      padding: const EdgeInsets.all(Constants.paddingLg),
      decoration: BoxDecoration(
        gradient: _isTripActive
            ? LinearGradient(colors: [AppColors.success.withAlpha(40), AppColors.success.withAlpha(10)])
            : LinearGradient(colors: [AppColors.surfaceDark, Colors.grey.shade100]),
        borderRadius: BorderRadius.circular(Constants.radiusLg),
        border: Border.all(
          color: _isTripActive ? AppColors.success.withAlpha(100) : Colors.grey.shade200,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: _isTripActive ? AppColors.success.withAlpha(30) : Colors.black.withAlpha(10),
            blurRadius: 16, offset: const Offset(0, 8),
          )
        ],
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Column(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.accent, size: 40),
                    const SizedBox(height: 12),
                    Text(_errorMessage, textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _fetchAssignment,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    )
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Route name
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.alt_route_rounded, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(routeName, style: Theme.of(context).textTheme.headlineSmall)),
                    ]),
                    const SizedBox(height: 16),
                    // Bus number
                    _InfoRow(icon: Icons.directions_bus_rounded, label: 'Bus', value: busNumber),
                    if (startName.isNotEmpty || endName.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      // Start → End
                      Row(children: [
                        const Icon(Icons.radio_button_checked, color: AppColors.success, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(startName, style: Theme.of(context).textTheme.bodyMedium)),
                        const Icon(Icons.arrow_forward_rounded, color: AppColors.textMuted, size: 18),
                        const SizedBox(width: 8),
                        const Icon(Icons.location_on, color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(endName, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.right)),
                      ]),
                    ],
                    const Divider(height: 24),
                    // FIXED: Status Badge UI
                    Row(children: [
                      Icon(
                        _isTripActive ? Icons.radio_button_checked_rounded : Icons.check_circle_rounded,
                        color: _isTripActive ? AppColors.accent : AppColors.success, size: 20
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isTripActive ? 'Trip: Running' : 'Status: Ready',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: _isTripActive ? AppColors.accent : AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // ADDED: Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (_isTripActive ? AppColors.accent : AppColors.success).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _isTripActive ? 'RUNNING' : 'COMPLETED',
                          style: TextStyle(
                            color: _isTripActive ? AppColors.accent : AppColors.success, 
                            fontSize: 10, 
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_isTripActive) ...[
                          // FIXED: Direction Indicator updates now
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  (busData?['direction'] == 'FROM_COLLEGE' || busData?['direction'] == 'return') 
                                      ? Icons.logout_rounded : Icons.login_rounded,
                                  size: 14, color: AppColors.primary
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  // FIXED: Correctly mapping direction to UI text
                                  (busData?['direction'] == 'FROM_COLLEGE' || busData?['direction'] == 'return') ? 'From College' : 'To College',
                                  style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ]),
                    
                    // FIXED: Route Stops Listing (Fallback to static data if no active trip ETA)
                    const Divider(height: 32),
                    Text('Route Stops', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    ...(() {
                      // Use ETA-enhanced stops if available, otherwise fallback to static stops from the route doc
                      final List<dynamic> rawStops = routeData?['stops'] as List? ?? [];
                      // FIXED: Always prioritize _stopsWithETA if available, even before trip starts
                      final List<dynamic> stopsToShow = (_stopsWithETA.isNotEmpty)
                          ? _stopsWithETA
                          : rawStops.map((s) => s is Map ? Map<String, dynamic>.from(s) : {'name': s.toString()}).toList();

                      if (stopsToShow.isEmpty) return [const Text('No stops defined for this route.')];
                      
                      return stopsToShow.map((stop) {
                        final name = stop['name'] ?? 'Unknown Stop';
                        final eta = stop['eta'] ?? '';
                        final status = stop['status'] ?? 'upcoming';
                        final distance = stop['distance'] ?? 0;
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                _getStopIcon(stop['status']),
                                size: 16, 
                                color: _getStopIconColor(stop['status']),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(name, style: _getStopTextStyle(stop['status']))),
                              if (eta.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getETAColor(stop['status']),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    eta,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ),
                              ],
                              if (distance > 0) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '${distance}m',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList();
                    })(),
                  ],
                ),
    );
  }

  // ENHANCED: Smooth Animated Speedometer with dynamic colors
  Widget _buildSpeedometer() {
    // Dynamic color based on thresholds (0-30: Green, 30-60: Orange, 60+: Red)
    final Color speedColor = _currentSpeed > 60 
        ? AppColors.error 
        : (_currentSpeed > 30 ? AppColors.accent : AppColors.success);

    return Container(
      padding: const EdgeInsets.all(Constants.paddingLg),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(Constants.radiusLg),
        boxShadow: [
          BoxShadow(
            color: speedColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('CURRENT SPEED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1.5)),
          const SizedBox(height: 16),
          // ADDED: Smooth animation for speed value
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0, end: _currentSpeed),
            builder: (context, value, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 48, 
                      fontWeight: FontWeight.bold, 
                      color: speedColor, // ENHANCED: Dynamic color
                      fontFamily: 'monospace'
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('km/h', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          // ADDED: Smoothly animating progress bar
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0, end: (_currentSpeed / 80).clamp(0.0, 1.0)),
            builder: (context, value, child) {
              return LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.grey.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(speedColor),
                minHeight: 8,
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── NEW FEATURE: Map Visualization Methods ─────────────────────────────────
  
  Future<void> _fetchRoutePolyline() async {
    if (_routeDoc == null) return;
    try {
      final data = _routeDoc!.data() as Map<String, dynamic>;
      final start = data['startpoint'] as Map?;
      final end = data['endpoint'] as Map?;
      final stops = data['stops'] as List? ?? [];

      List<LatLng> waypoints = [];
      Set<Marker> tempMarkers = {};

      if (start != null && start['lat'] != null) {
        waypoints.add(LatLng(start['lat'], start['lng']));
        tempMarkers.add(Marker(
            markerId: const MarkerId('start'),
            position: LatLng(start['lat'], start['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: start['name'] ?? 'Start Point'),
        ));
      }
      
      for (int i = 0; i < stops.length; i++) {
        final s = stops[i];
        if (s is Map && s['lat'] != null) {
          waypoints.add(LatLng(s['lat'], s['lng']));
          tempMarkers.add(Marker(
            markerId: MarkerId('stop_$i'),
            position: LatLng(s['lat'], s['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(title: s['name'] ?? 'Stop ${i + 1}'),
          ));
        }
      }
      
      if (end != null && end['lat'] != null) {
        waypoints.add(LatLng(end['lat'], end['lng']));
        tempMarkers.add(Marker(
            markerId: const MarkerId('end'),
            position: LatLng(end['lat'], end['lng']),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: end['name'] ?? 'Final Destination'),
        ));
      }

      // FIXED: Reverse waypoints if we are on a return trip (FROM COLLEGE)
      final direction = (_busDoc?.data() as Map<String, dynamic>?)?['direction'] ?? 'TO_COLLEGE';
      if (direction == 'FROM_COLLEGE' || direction == 'return') {
        waypoints = waypoints.reversed.toList();
      }

      final poly = await GoogleMapsService.getRoutePolyline(waypoints);
      if (!mounted) return;
      setState(() {
        _fullRouteCoords = poly;
        _stopMarkers = tempMarkers;
      });
      _updatePolylineSlicing();
    } catch (e) {
      debugPrint('Error fetching map polyline: $e');
    }
  }

  void _zoomToFitRoute() {
    if (_fullRouteCoords.isEmpty || _mapController == null) {
      _snack('No route coords to view.');
      return;
    }
    
    double minLat = _fullRouteCoords.first.latitude;
    double maxLat = _fullRouteCoords.first.latitude;
    double minLng = _fullRouteCoords.first.longitude;
    double maxLng = _fullRouteCoords.first.longitude;

    for (final p in _fullRouteCoords) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  void _updatePolylineSlicing() {
    if (_fullRouteCoords.isEmpty) {
      if (_currentPosition != null) {
        setState(() {
          _markers = {
            Marker(
              markerId: const MarkerId('bus'),
              position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              icon: _busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              rotation: _currentPosition!.heading,
              flat: true,
              anchor: const Offset(0.5, 0.5),
              zIndex: 10,
            ),
          };
        });
      }
      return;
    }

    // 2. Pre-trip view or Trip not active: Show full route in primary color
    if (!_isTripActive || _currentPosition == null) {
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('upcoming'),
            points: _fullRouteCoords,
            color: AppColors.primary,
            width: 7,
            startCap: Cap.roundCap, endCap: Cap.roundCap,
            jointType: JointType.round,
          ),
        };
        _markers = {
          ..._stopMarkers,
          if (_currentPosition != null)
            Marker(
              markerId: const MarkerId('bus'),
              position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              icon: _busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              rotation: _currentPosition!.heading,
              flat: true,
              anchor: const Offset(0.5, 0.5),
              zIndex: 100,
            ),
        };
      });
      return;
    }

    // 3. Active Trip tracking: Slice the polyline
    double minDist = double.infinity;
    int nearestIndex = _lastSplitIndex;

    int searchStart = (_lastSplitIndex - 50).clamp(0, _fullRouteCoords.length - 1);
    int searchEnd = (_lastSplitIndex + 100).clamp(0, _fullRouteCoords.length - 1);
    
    // Safety jump for first run or large distance
    if (_lastSplitIndex >= _fullRouteCoords.length || 
        Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, 
        _fullRouteCoords[_lastSplitIndex.clamp(0, _fullRouteCoords.length-1)].latitude, 
        _fullRouteCoords[_lastSplitIndex.clamp(0, _fullRouteCoords.length-1)].longitude) > 1000) {
      searchStart = 0;
      searchEnd = _fullRouteCoords.length - 1;
    }

    for (int i = searchStart; i <= searchEnd; i++) {
        final d = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, 
            _fullRouteCoords[i].latitude, _fullRouteCoords[i].longitude);
        if (d < minDist) {
          minDist = d;
          nearestIndex = i;
        }
    }
    _lastSplitIndex = nearestIndex;

    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('passed'),
          points: _fullRouteCoords.sublist(0, nearestIndex + 1),
          color: Colors.grey.withOpacity(0.7),
          width: 5,
        ),
        Polyline(
          polylineId: const PolylineId('upcoming'),
          points: _fullRouteCoords.sublist(nearestIndex),
          color: AppColors.primary,
          width: 7,
          startCap: Cap.roundCap, endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      };

      _markers = {
        ..._stopMarkers,
        Marker(
          markerId: const MarkerId('bus'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: _busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          rotation: _currentPosition!.heading,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          zIndex: 100, // ensure bus is always on top
        ),
      };
    });

    if (_mapController != null) {
      if (_isNavMode && _currentPosition != null) {
        _mapController!.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            bearing: _currentPosition!.heading,
            tilt: 60.0,
            zoom: 17.5,
          )
        ));
      } else if (_currentPosition != null && _isTripActive) {
        // Only auto-follow if trip is active or in nav mode
        _mapController!.animateCamera(CameraUpdate.newLatLng(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        ));
      }
    }
  }

  Widget _buildMapView() {
    if (_routeDoc == null) return const SizedBox.shrink();
    
    return Container(
      height: 300,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Constants.radiusLg),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition != null 
                  ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                  : const LatLng(10.787222, 76.216389),
              zoom: 15,
            ),
            onMapCreated: (ctrl) => _mapController = ctrl,
            polylines: _polylines,
            markers: _markers,
            myLocationEnabled: false, 
            compassEnabled: true,
            mapToolbarEnabled: false,
          ),
          Positioned(
            top: 12, right: 12,
            child: Column(
              children: [
                GestureDetector(
                  onTap: _zoomToFitRoute,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                    child: const Icon(Icons.alt_route_rounded, color: AppColors.primary, size: 24),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    if (_currentPosition != null) {
                      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 17));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                    child: const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 24),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 12, left: 12,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isNavMode = !_isNavMode;
                });
                _updatePolylineSlicing(); // Force camera update immediately
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _isNavMode ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4)],
                ),
                child: Row(
                  children: [
                    Icon(
                      _isNavMode ? Icons.explore : Icons.navigation_rounded, 
                      color: _isNavMode ? Colors.white : AppColors.primary, 
                      size: 16
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isNavMode ? '3D NAV MODE' : '2D MAP VIEW', 
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold, 
                        color: _isNavMode ? Colors.white : AppColors.primary, 
                        letterSpacing: 0.5
                      )
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: AppColors.primary, size: 20),
      const SizedBox(width: 10),
      Text('$label: ', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      Text(value, style: Theme.of(context).textTheme.bodyMedium),
    ]);
  }
}
