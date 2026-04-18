import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// Helper service used if you want to trigger trip logic from outside DriverHome.
/// DriverHome handles the trip logic directly; this service mirrors it for external use.
class StartTripService {
  static final StartTripService _instance = StartTripService._internal();
  factory StartTripService() => _instance;
  StartTripService._internal();

  StreamSubscription<Position>? _posSub;
  String? _busId;
  String? _routeId;

  /// Fetch route and bus from driver's currentRouteId, then start streaming location.
  Future<void> startTrip({required String driverUid}) async {
    // 1. Read driver doc
    final driverDoc = await FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverUid)
        .get();

    final routeId = (driverDoc.data()?['currentRouteId'] ?? '') as String;
    if (routeId.isEmpty) throw Exception('No route assigned to driver.');

    // 2. Read route doc → get busid
    final routeDoc = await FirebaseFirestore.instance
        .collection('routes')
        .doc(routeId)
        .get();

    final busId = (routeDoc.data()?['busid'] ?? '') as String;
    if (busId.isEmpty) throw Exception('No bus assigned to route.');

    _routeId = routeId;
    _busId = busId;

    // 3. Mark route as active
    await FirebaseFirestore.instance
        .collection('routes')
        .doc(routeId)
        .update({'isTripActive': true});

    // 4. Stream location every ~10 metres
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((pos) async {
      if (_busId != null) {
        await FirebaseFirestore.instance
            .collection('buses')
            .doc(_busId)
            .update({'location': GeoPoint(pos.latitude, pos.longitude)});
      }
    });
  }

  /// Stop streaming and clear Firestore location.
  Future<void> stopTrip() async {
    await _posSub?.cancel();
    _posSub = null;

    if (_routeId != null) {
      await FirebaseFirestore.instance
          .collection('routes')
          .doc(_routeId)
          .update({'isTripActive': false});
    }
    if (_busId != null) {
      await FirebaseFirestore.instance
          .collection('buses')
          .doc(_busId)
          .update({'location': FieldValue.delete()});
    }

    _busId = null;
    _routeId = null;
  }
}
