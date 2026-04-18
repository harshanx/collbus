import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import 'manage_routes.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'trip_history.dart';
import '../widgets/menu_dialogs.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Constants.paddingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// ===== Header =====
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  const Spacer(),
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
                          title: Text('About CollBus'),
                          contentPadding: EdgeInsets.zero,
                          horizontalTitleGap: 0,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'terms',
                        child: ListTile(
                          leading: Icon(Icons.description_outlined, color: Colors.blue),
                          title: Text('Terms & Privacy'),
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
                ],
              ),

              const SizedBox(height: 10),

              Center(
                child: Text(
                  'Admin Dashboard',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),

              const SizedBox(height: 24),

              /// ===== Welcome Card =====
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Constants.paddingLg),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primaryDark,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      BorderRadius.circular(Constants.radiusLg),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.admin_panel_settings_rounded,
                        color: Colors.white, size: 36),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, Admin 👋',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Manage buses and drivers efficiently',
                            style: TextStyle(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _buildAnalyticsRow(),

              const SizedBox(height: 32),

              Text(
                'Management',
                style: Theme.of(context).textTheme.titleLarge,
              ),

              const SizedBox(height: 20),

              /// ===== Dashboard Grid =====
              Row(
                children: [
                  Expanded(
                    child: _DashboardCard(
                      icon: Icons.directions_bus_rounded,
                      title: 'Manage Buses',
                      subtitle: 'Add, edit or remove buses',
                      onTap: () {
                        Navigator.pushNamed(
                            context, '/manage_buses');
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DashboardCard(
                      icon: Icons.people_rounded,
                      title: 'Manage Drivers',
                      subtitle: 'Add or remove driver accounts',
                      onTap: () {
                        Navigator.pushNamed(
                            context, '/manage_drivers');
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _DashboardCard(
                      icon: Icons.alt_route_rounded,
                      title: 'Manage Routes',
                      subtitle: 'Create routes, assign drivers & buses',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ManageRoutes(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DashboardCard(
                      icon: Icons.campaign_rounded,
                      title: 'Announcements',
                      subtitle: 'Push alerts to students',
                      onTap: () {
                        Navigator.pushNamed(context, '/manage_announcements');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                   Expanded(
                    child: _DashboardCard(
                      icon: Icons.history_rounded,
                      title: 'Trip History',
                      subtitle: 'View driver log reports',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TripHistoryScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Spacer(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsRow() {
    return Row(
      children: [
        _buildStatCard('Total Buses', FirebaseFirestore.instance.collection('buses').snapshots(), Colors.blue),
        const SizedBox(width: 12),
        _buildStatCard('Total Drivers', FirebaseFirestore.instance.collection('drivers').snapshots(), Colors.orange),
        const SizedBox(width: 12),
        _buildStatCard('Total Routes', FirebaseFirestore.instance.collection('routes').snapshots(), Colors.green),
      ],
    );
  }

  Widget _buildStatCard(String title, Stream<QuerySnapshot> stream, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 24, width: 24, 
                    child: CircularProgressIndicator(strokeWidth: 2)
                  );
                }
                final count = snapshot.data?.docs.length ?? 0;
                return Text(
                  count.toString(),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color),
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(Constants.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(Constants.paddingLg),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius:
                BorderRadius.circular(Constants.radiusLg),
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withAlpha(10),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, // prevents crash
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(30),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: AppColors.primary, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style:
                    Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style:
                    Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.bottomRight,
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
