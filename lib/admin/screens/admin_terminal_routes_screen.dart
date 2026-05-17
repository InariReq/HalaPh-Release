import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/admin_terminal_route.dart';
import '../services/admin_terminal_route_service.dart';
import '../widgets/admin_ui.dart';
import 'admin_terminal_route_form_screen.dart';

class AdminTerminalRoutesScreen extends StatefulWidget {
  const AdminTerminalRoutesScreen({super.key});

  @override
  State<AdminTerminalRoutesScreen> createState() =>
      _AdminTerminalRoutesScreenState();
}

class _AdminTerminalRoutesScreenState extends State<AdminTerminalRoutesScreen> {
  final _service = AdminTerminalRouteService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminTerminalRoute>>(
      stream: _service.streamAll(),
      builder: (context, snapshot) {
        final routes = snapshot.data ?? const <AdminTerminalRoute>[];
        return AdminPageScaffold(
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting)
              const AdminLoadingState(label: 'Loading terminal routes...')
            else if (snapshot.hasError)
              AdminErrorState(
                title: 'Terminal routes unavailable',
                message: snapshot.error is FirebaseException &&
                        (snapshot.error as FirebaseException).code ==
                            'permission-denied'
                    ? 'Firestore rules do not allow this admin to read terminal routes yet.'
                    : 'Terminal routes could not be loaded. Try again later.',
              )
            else if (routes.isEmpty)
              const AdminEmptyState(
                icon: Icons.route_rounded,
                title: 'No terminal routes yet',
                message:
                    'Create the first verified terminal route to start building the reference set.',
              )
            else
              _TerminalRoutesList(
                routes: routes,
                onEdit: _openEditScreen,
                onDelete: _deleteRoute,
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return AdminSectionHeader(
      icon: Icons.route_rounded,
      eyebrow: 'Transit',
      title: 'Terminal routes',
      description:
          'Maintain verified terminal and bus-route references for future user-facing route features.',
      actions: [
        AdminActionButton(
          onPressed: _openAddScreen,
          icon: Icons.add_rounded,
          label: 'Add terminal route',
        ),
      ],
    );
  }

  Future<void> _openAddScreen() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => const AdminTerminalRouteFormScreen(),
      ),
    );
  }

  Future<void> _openEditScreen(AdminTerminalRoute route) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => AdminTerminalRouteFormScreen(existing: route),
      ),
    );
  }

  Future<void> _deleteRoute(AdminTerminalRoute route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteConfirmDialog(
        title: 'Delete Terminal Route',
        itemName: '${route.terminalName} → ${route.destination}',
        description:
            'Delete permanently removes this terminal-route admin record.',
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteRoute(route.id);
      if (mounted) _showSnack('Terminal route deleted.');
    } on FirebaseException catch (error) {
      if (mounted) {
        _showSnack(error.code == 'permission-denied'
            ? 'Delete blocked by Firestore rules.'
            : 'Could not delete terminal route.');
      }
    } catch (_) {
      if (mounted) _showSnack('Could not delete terminal route.');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TerminalRoutesList extends StatelessWidget {
  final List<AdminTerminalRoute> routes;
  final ValueChanged<AdminTerminalRoute> onEdit;
  final ValueChanged<AdminTerminalRoute> onDelete;

  const _TerminalRoutesList({
    required this.routes,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AdminResponsiveTable(
      breakpoint: 1000,
      mobile: Column(
        children: [
          for (final route in routes)
            _TerminalRouteCard(
              route: route,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
        ],
      ),
      desktop: DataTable(
        columns: const [
          DataColumn(label: Text('Terminal')),
          DataColumn(label: Text('Destination')),
          DataColumn(label: Text('City')),
          DataColumn(label: Text('Operator')),
          DataColumn(label: Text('Source')),
          DataColumn(label: Text('Confidence')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final route in routes)
            DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 280,
                    child: _TerminalTextSummary(route: route),
                  ),
                ),
                DataCell(Text(route.destination)),
                DataCell(Text(route.city)),
                DataCell(Text(
                  route.operatorName.isEmpty ? '—' : route.operatorName,
                )),
                DataCell(_SourceBadge(sourceType: route.sourceType)),
                DataCell(Text(_labelize(route.confidenceLevel))),
                DataCell(_StatusBadge(status: route.status)),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: () => onEdit(route),
                        icon: const Icon(Icons.edit_rounded),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => onDelete(route),
                        icon: const Icon(Icons.delete_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TerminalRouteCard extends StatelessWidget {
  final AdminTerminalRoute route;
  final ValueChanged<AdminTerminalRoute> onEdit;
  final ValueChanged<AdminTerminalRoute> onDelete;

  const _TerminalRouteCard({
    required this.route,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _TerminalTextSummary(route: route)),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => onEdit(route),
                  icon: const Icon(Icons.edit_rounded),
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () => onDelete(route),
                  icon: const Icon(Icons.delete_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(icon: Icons.location_city_rounded, label: route.city),
                _InfoChip(
                  icon: Icons.business_rounded,
                  label: route.operatorName.isEmpty
                      ? 'Operator unset'
                      : route.operatorName,
                ),
                _SourceBadge(sourceType: route.sourceType),
                _InfoChip(
                  icon: Icons.fact_check_rounded,
                  label: _labelize(route.confidenceLevel),
                ),
                _StatusBadge(status: route.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalTextSummary extends StatelessWidget {
  final AdminTerminalRoute route;

  const _TerminalTextSummary({required this.route});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          route.terminalName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'To ${route.destination}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final (label, icon) = switch (normalized) {
      'active' => ('Active', Icons.check_circle_rounded),
      'needs_review' => ('Needs review', Icons.rate_review_rounded),
      _ => ('Inactive', Icons.block_rounded),
    };

    return AdminStatusBadge(
      label: label,
      icon: icon,
      tone: switch (normalized) {
        'active' => AdminStatusTone.success,
        'needs_review' => AdminStatusTone.warning,
        _ => AdminStatusTone.neutral,
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String sourceType;

  const _SourceBadge({required this.sourceType});

  @override
  Widget build(BuildContext context) {
    final normalized = sourceType.trim().toLowerCase();
    return AdminStatusBadge(
      label: _labelize(sourceType),
      icon: switch (normalized) {
        'official' => Icons.verified_rounded,
        'operator' => Icons.business_rounded,
        'user' => Icons.person_rounded,
        'estimated' => Icons.analytics_rounded,
        _ => Icons.source_rounded,
      },
      tone: switch (normalized) {
        'official' => AdminStatusTone.success,
        'estimated' => AdminStatusTone.warning,
        _ => AdminStatusTone.info,
      },
    );
  }
}

class _DeleteConfirmDialog extends StatefulWidget {
  final String title;
  final String itemName;
  final String description;

  const _DeleteConfirmDialog({
    required this.title,
    required this.itemName,
    required this.description,
  });

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _controller.text.trim() == 'DELETE';
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: adminDialogWidth(context, 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.itemName,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(widget.description),
            const SizedBox(height: 12),
            const Text('Type DELETE to confirm.'),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Confirmation'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canDelete ? () => Navigator.pop(context, true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

String _labelize(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return '—';
  return normalized
      .split('_')
      .map((part) => part.isEmpty
          ? part
          : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}
