import 'package:flutter/material.dart';

import '../services/admin_dashboard_service.dart';
import '../widgets/admin_ui.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminDashboardService _dashboardService = AdminDashboardService();

  late Future<AdminDashboardStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _dashboardService.loadStats();
  }

  void _refreshStats() {
    setState(() {
      _statsFuture = _dashboardService.loadStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminDashboardStats>(
      future: _statsFuture,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final error = snapshot.hasError;

        return AdminPageScaffold(
          children: [
            AdminSectionHeader(
              icon: Icons.dashboard_rounded,
              eyebrow: 'Command center',
              title: 'Operations overview',
              description: loading
                  ? 'Loading live Firestore metrics...'
                  : error
                      ? 'Some dashboard metrics could not be loaded.'
                      : 'A live pulse across users, routes, content, and admin access.',
              actions: [
                AdminActionButton(
                  onPressed: loading ? null : _refreshStats,
                  icon: Icons.refresh_rounded,
                  label: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (error) ...[
              AdminErrorState(
                title: 'Dashboard metrics unavailable',
                message:
                    'The dashboard could not complete the stats request. Try refreshing, then check Firestore rules if the issue continues.',
                onRetry: _refreshStats,
              ),
              const SizedBox(height: 16),
            ],
            _DashboardGroupLabel(
              title: 'Audience and network',
              subtitle: 'User-facing activity signals.',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1080
                    ? 4
                    : constraints.maxWidth >= 720
                        ? 2
                        : 1;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: columns == 1 ? 2.2 : 1.35,
                  children: [
                    _statCard(
                      stats: stats,
                      keyName: 'userbase',
                      icon: Icons.people_alt_rounded,
                      title: 'Userbase',
                    ),
                    _statCard(
                      stats: stats,
                      keyName: 'sharedPlans',
                      icon: Icons.route_rounded,
                      title: 'Shared Plans',
                    ),
                    _statCard(
                      stats: stats,
                      keyName: 'publicProfiles',
                      icon: Icons.badge_rounded,
                      title: 'Public Profiles',
                    ),
                    _statCard(
                      stats: stats,
                      keyName: 'friendCodes',
                      icon: Icons.qr_code_2_rounded,
                      title: 'Friend Codes',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _DashboardGroupLabel(
              title: 'Content and operations',
              subtitle: 'Admin-managed surfaces and staff controls.',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1080
                    ? 4
                    : constraints.maxWidth >= 720
                        ? 2
                        : 1;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: columns == 1 ? 2.2 : 1.35,
                  children: [
                    _statCard(
                      stats: stats,
                      keyName: 'locations',
                      icon: Icons.place_rounded,
                      title: 'Locations',
                    ),
                    _statCard(
                      stats: stats,
                      keyName: 'featuredPlaces',
                      icon: Icons.star_rounded,
                      title: 'Featured Places',
                    ),
                    _statCard(
                      stats: stats,
                      keyName: 'terminalRoutes',
                      icon: Icons.route_rounded,
                      title: 'Terminal Routes',
                    ),
                    _statCard(
                      stats: stats,
                      keyName: 'routeReports',
                      icon: Icons.fact_check_rounded,
                      title: 'Route Reports',
                    ),
                    _statCard(
                      stats: stats,
                      keyName: 'ads',
                      icon: Icons.campaign_rounded,
                      title: 'Ads',
                    ),
                    _statCard(
                      stats: stats,
                      keyName: 'adminUsers',
                      icon: Icons.admin_panel_settings_rounded,
                      title: 'Admin Users',
                    ),
                    _statCard(
                      stats: stats,
                      keyName: 'activeAdmins',
                      icon: Icons.verified_user_rounded,
                      title: 'Active Admins',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            AdminDataCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdminStatusBadge(
                    label: 'Protected',
                    icon: Icons.security_rounded,
                    tone: AdminStatusTone.info,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Dashboard reads are protected by Firestore rules. Restricted cards mean the UI is ready, but the matching collection read rule has not been opened yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            if (stats != null) ...[
              const SizedBox(height: 12),
              Text(
                'Last updated: ${_formatLoadedAt(stats.loadedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _statCard({
    required AdminDashboardStats? stats,
    required String keyName,
    required IconData icon,
    required String title,
  }) {
    final metric = stats?.metric(keyName);
    return AdminMetricCard(
      icon: icon,
      title: title,
      value: metric?.value ?? 'Loading',
      subtitle: metric?.subtitle ?? 'Fetching latest count...',
      restricted: metric?.restricted ?? false,
      emphasized: keyName == 'userbase',
    );
  }

  String _formatLoadedAt(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _DashboardGroupLabel extends StatelessWidget {
  final String title;
  final String subtitle;

  const _DashboardGroupLabel({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
