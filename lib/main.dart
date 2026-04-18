import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'auth/splash_screen.dart';
import 'auth/login_screen.dart';
import 'student/student_home.dart';
//import 'student/live_tracking.dart';
import 'driver/driver_home.dart';
import 'admin/admin_home.dart';
import 'admin/manage_buses.dart';
import 'admin/manage_drivers.dart';
import 'admin/manage_routes.dart';
import 'admin/manage_announcements.dart';
import 'auth/student_signup_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Initialize Firebase
  await NotificationService.initialize();
  runApp(const CollBusApp());
}

class CollBusApp extends StatelessWidget {
  const CollBusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CollBus',
      theme: appTheme,
      debugShowCheckedModeBanner: false,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/student_signup': (context) => const StudentSignupScreen(),
        '/student_home': (context) => const StudentHome(),
        //'/live_tracking': (context) => const LiveTracking(),
        '/driver_home': (context) => const DriverHome(),
        '/admin_home': (context) => const AdminHome(),
        '/manage_buses': (context) => const ManageBuses(),
        '/manage_drivers': (context) => const ManageDrivers(),
        '/manage_routes': (context) => const ManageRoutes(),
        '/manage_announcements': (context) => const ManageAnnouncements(),
      },
    );
  }
}
