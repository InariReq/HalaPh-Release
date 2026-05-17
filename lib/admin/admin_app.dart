import 'package:flutter/material.dart';

import 'admin_shell.dart';
import 'admin_theme.dart';
import 'screens/admin_login_screen.dart';
import 'services/admin_auth_service.dart';
import 'widgets/admin_ui.dart';

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HalaPH Admin',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.light(),
      home: const _AdminAuthGate(),
    );
  }
}

class _AdminAuthGate extends StatefulWidget {
  const _AdminAuthGate();

  @override
  State<_AdminAuthGate> createState() => _AdminAuthGateState();
}

class _AdminAuthGateState extends State<_AdminAuthGate> {
  final _authService = AdminAuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminAuthState>(
      stream: _authService.watchAdminState(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AdminLoadingScreen();
        }

        final state = snapshot.data;
        if (state == null || state.firebaseUser == null) {
          return AdminLoginScreen(authService: _authService);
        }

        if (state.error == 'access-denied' || state.adminUser == null) {
          return _AccessProblemScreen(
            title: 'Access denied',
            message:
                'This Firebase account is not registered as a HalaPH admin.',
            authService: _authService,
          );
        }

        if (!state.adminUser!.isActive) {
          return _AccessProblemScreen(
            title: 'Access disabled',
            message: 'This admin account has been disabled by an owner.',
            authService: _authService,
          );
        }

        return AdminShell(
          adminUser: state.adminUser!,
          authService: _authService,
        );
      },
    );
  }
}

class _AdminLoadingScreen extends StatelessWidget {
  const _AdminLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: AdminLoadingState(label: 'Checking admin access...'),
        ),
      ),
    );
  }
}

class _AccessProblemScreen extends StatelessWidget {
  final String title;
  final String message;
  final AdminAuthService authService;

  const _AccessProblemScreen({
    required this.title,
    required this.message,
    required this.authService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AdminPageScaffold(
          maxWidth: 720,
          children: [
            AdminSectionHeader(
              icon: Icons.admin_panel_settings_rounded,
              eyebrow: 'Admin access',
              title: title,
              description: message,
              actions: [
                AdminActionButton(
                  onPressed: authService.signOut,
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _FirstOwnerSetupNote(),
          ],
        ),
      ),
    );
  }
}

class _FirstOwnerSetupNote extends StatelessWidget {
  const _FirstOwnerSetupNote();

  @override
  Widget build(BuildContext context) {
    return AdminDataCard(
      backgroundColor:
          Theme.of(context).colorScheme.primary.withValues(alpha: 0.04),
      child: Text(
        'First owner setup: create admin_users/{uid} manually in Firestore '
        'for jeraldforschool@gmail.com with displayName '
        '"Cheong, C Jerald Jia Le D.", role owner, isActive true, and '
        'createdBy/updatedBy manual_setup. Firestore rules must enforce '
        'admin-only access before production.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
