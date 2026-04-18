class Constants {
  static const String appName = 'CollBus';
  static const String googleMapsApiKey = 'AIzaSyDVeKzFzZkFOXznHmn4FksNE-ToinyPttk';

  // Set your backend URL. For local backend: use http://10.0.2.2:3000/api (Android)
  // or http://localhost:3000/api (web). See STEPS_TO_RUN.md for help.
  static const String baseUrl = 'http://localhost:3000/api';
  static const int gpsUpdateInterval = 5;
  static const double mapZoom = 14.0;

  static const String studentRole = 'student';
  static const String driverRole = 'driver';
  static const String adminRole = 'admin';

  // Design tokens
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 24.0;
  static const double paddingSm = 8.0;
  static const double paddingMd = 16.0;
  static const double paddingLg = 24.0;
}
