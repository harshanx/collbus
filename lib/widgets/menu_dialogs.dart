import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/constants.dart';

class MenuDialogs {
  static Future<void> showLogoutConfirmation(BuildContext context, VoidCallback onConfirm) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.logout_rounded, color: AppColors.error),
            SizedBox(width: 12),
            Text('Confirm Logout'),
          ],
        ),
        content: const Text('Are you sure you want to sign out of CollBus?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  static void showTerms(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Terms & Privacy'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Welcome to CollBus.', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('1. Usage: This app is strictly for college transportation management.'),
              SizedBox(height: 8),
              Text('2. Privacy: We collect location data only during active trips for bus tracking.'),
              SizedBox(height: 8),
              Text('3. Safety: Respect the drivers and follow college guidelines.'),
              SizedBox(height: 16),
              Text('By using this app, you agree to our internal safety policies.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static void showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'CollBus',
      applicationVersion: '1.0.0+1',
      applicationIcon: Image.asset('assets/icon.png', width: 50, height: 50),
      applicationLegalese: '© 2026 Collagen Transportation System.\nDesigned with Advanced AI.',
      children: [
        const SizedBox(height: 20),
        const Text('CollBus simplifies campus commutes by providing real-time tracking, student announcements, and driver management in one unified platform.'),
      ],
    );
  }
}
