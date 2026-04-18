import 'dart:async';
//import '../driver/start_trip.dart'; // ensure startTripLogic updates this stream


class LocationStreamService {
  // Singleton stream for driver location
  static final LocationStreamService _instance = LocationStreamService._internal();
  factory LocationStreamService() => _instance;
  LocationStreamService._internal();

  final StreamController<DriverLocation> _locationController =
      StreamController<DriverLocation>.broadcast();

  Stream<DriverLocation> get locationStream => _locationController.stream;

  void updateLocation(String driverId, double lat, double lng) {
    _locationController.add(DriverLocation(driverId, lat, lng));
  }
}

// Driver location model
class DriverLocation {
  final String driverId;
  final double latitude;
  final double longitude;

  DriverLocation(this.driverId, this.latitude, this.longitude);
}
