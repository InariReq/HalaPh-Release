import 'package:flutter/material.dart';

import '../models/admin_user.dart';
import '../models/admin_user_role.dart';
import 'admin_ui.dart';

class AdminGuard extends StatelessWidget {
  final AdminUser adminUser;
  final AdminUserRole minimumRole;
  final Widget child;

  const AdminGuard({
    super.key,
    required this.adminUser,
    required this.minimumRole,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final allowed = switch (minimumRole) {
      AdminUserRole.owner => adminUser.role == AdminUserRole.owner,
      AdminUserRole.headAdmin => adminUser.role == AdminUserRole.owner ||
          adminUser.role == AdminUserRole.headAdmin,
      AdminUserRole.admin => true,
    };
    if (allowed) return child;
    return const _LockedAdminState();
  }
}

class _LockedAdminState extends StatelessWidget {
  const _LockedAdminState();

  @override
  Widget build(BuildContext context) {
    return const AdminPageScaffold(
      children: [
        AdminEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Access restricted',
          message: 'Your admin role does not allow access to this page.',
        ),
      ],
    );
  }
}
