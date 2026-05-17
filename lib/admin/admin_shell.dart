import 'package:flutter/material.dart';

import 'admin_routes.dart';
import 'models/admin_user.dart';
import 'models/admin_user_role.dart';
import 'screens/admin_ads_screen.dart';
import 'screens/admin_app_settings_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/admin_featured_places_screen.dart';
import 'screens/admin_locations_screen.dart';
import 'screens/admin_route_reports_screen.dart';
import 'screens/admin_terminal_routes_screen.dart';
import 'screens/admin_users_screen.dart';
import 'services/admin_auth_service.dart';
import 'widgets/admin_guard.dart';
import 'widgets/admin_nav_item.dart';
import 'widgets/admin_ui.dart';

class AdminShell extends StatefulWidget {
  final AdminUser adminUser;
  final AdminAuthService authService;

  const AdminShell({
    super.key,
    required this.adminUser,
    required this.authService,
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  static const _sidebarWidth = 292.0;
  static const _minimumWideContentWidth = 900.0;

  AdminRouteId _selectedRoute = AdminRouteId.dashboard;

  AdminRouteConfig get _route => AdminRoutes.byId(_selectedRoute);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            constraints.maxWidth >= _sidebarWidth + _minimumWideContentWidth;
        final content = Row(
          children: [
            if (isWide) _buildSidebar(context),
            Expanded(child: _buildMainContent(context)),
          ],
        );

        return Scaffold(
          appBar: isWide ? null : _buildAppBar(context),
          drawer: isWide
              ? null
              : Drawer(
                  backgroundColor: const Color(0xFF0B1220),
                  child: _buildNavigation(context),
                ),
          body: SafeArea(child: content),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      toolbarHeight: 72,
      title: Text(_route.title),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: AdminStatusBadge(
              label: widget.adminUser.role.label,
              icon: Icons.verified_user_rounded,
              tone: AdminStatusTone.info,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: widget.authService.signOut,
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: _sidebarWidth,
      decoration: const BoxDecoration(
        color: Color(0xFF0B1220),
      ),
      child: _buildNavigation(context),
    );
  }

  Widget _buildNavigation(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.route_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HalaPH Admin',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                    ),
                    Text(
                      'Operations console',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.62),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.adminUser.displayName.isEmpty
                            ? widget.adminUser.email
                            : widget.adminUser.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.adminUser.role.label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 18),
            children: [
              for (final route in AdminRoutes.routes)
                AdminNavItem(
                  icon: route.icon,
                  label: route.title,
                  selected: route.id == _selectedRoute,
                  locked: !_canAccess(route.minimumRole),
                  onTap: () {
                    setState(() => _selectedRoute = route.id);
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            ),
            onPressed: widget.authService.signOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _route.title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Signed in as ${widget.adminUser.email}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              AdminStatusBadge(
                label: widget.adminUser.role.label,
                icon: Icons.verified_user_rounded,
                tone: AdminStatusTone.info,
              ),
            ],
          ),
        ),
        Expanded(
          child: AdminGuard(
            adminUser: widget.adminUser,
            minimumRole: _route.minimumRole,
            child: _buildPage(),
          ),
        ),
      ],
    );
  }

  Widget _buildPage() {
    return switch (_selectedRoute) {
      AdminRouteId.dashboard => const AdminDashboardScreen(),
      AdminRouteId.locations =>
        AdminLocationsScreen(currentAdmin: widget.adminUser),
      AdminRouteId.terminalRoutes => const AdminTerminalRoutesScreen(),
      AdminRouteId.routeReports => const AdminRouteReportsScreen(),
      AdminRouteId.advertisements =>
        AdminAdsScreen(currentAdmin: widget.adminUser),
      AdminRouteId.featuredPlaces =>
        AdminFeaturedPlacesScreen(currentAdmin: widget.adminUser),
      AdminRouteId.appSettings =>
        AdminAppSettingsScreen(currentAdmin: widget.adminUser),
      AdminRouteId.adminUsers =>
        AdminUsersScreen(currentAdmin: widget.adminUser),
    };
  }

  bool _canAccess(AdminUserRole minimumRole) {
    return switch (minimumRole) {
      AdminUserRole.owner => widget.adminUser.role == AdminUserRole.owner,
      AdminUserRole.headAdmin => widget.adminUser.role == AdminUserRole.owner ||
          widget.adminUser.role == AdminUserRole.headAdmin,
      AdminUserRole.admin => true,
    };
  }
}
