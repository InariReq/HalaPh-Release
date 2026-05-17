import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/admin_route_correction_report.dart';
import '../services/admin_route_correction_report_service.dart';
import '../widgets/admin_ui.dart';

class AdminRouteReportsScreen extends StatefulWidget {
  const AdminRouteReportsScreen({super.key});

  @override
  State<AdminRouteReportsScreen> createState() =>
      _AdminRouteReportsScreenState();
}

class _AdminRouteReportsScreenState extends State<AdminRouteReportsScreen> {
  final _service = AdminRouteCorrectionReportService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AdminRouteCorrectionReport>>(
      stream: _service.streamAll(),
      builder: (context, snapshot) {
        final reports = snapshot.data ?? const <AdminRouteCorrectionReport>[];
        return AdminPageScaffold(
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            _QueueSummary(reportCount: reports.length),
            const SizedBox(height: 16),
            if (snapshot.connectionState == ConnectionState.waiting)
              const AdminLoadingState(label: 'Loading route reports...')
            else if (snapshot.hasError)
              AdminErrorState(
                title: 'Route reports unavailable',
                message: snapshot.error is FirebaseException &&
                        (snapshot.error as FirebaseException).code ==
                            'permission-denied'
                    ? 'Firestore rules do not allow this admin to read route reports yet.'
                    : 'Route reports could not be loaded. Try again later.',
                onRetry: () => setState(() {}),
              )
            else if (reports.isEmpty)
              const AdminEmptyState(
                icon: Icons.inbox_rounded,
                title: 'Inbox clear',
                message:
                    'No user-submitted correction reports are waiting right now.',
              )
            else
              _RouteReportsList(
                reports: reports,
                onOpen: _openDetailDialog,
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return const AdminSectionHeader(
      icon: Icons.fact_check_rounded,
      eyebrow: 'Inbox',
      title: 'Route reports',
      description:
          'Read-only inbox for user-submitted terminal route correction reports.',
    );
  }

  Future<void> _openDetailDialog(
    AdminRouteCorrectionReport report,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _RouteReportDetailDialog(report: report),
    );
  }
}

class _QueueSummary extends StatelessWidget {
  final int reportCount;

  const _QueueSummary({required this.reportCount});

  @override
  Widget build(BuildContext context) {
    return AdminDataCard(
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          AdminStatusBadge(
            label: '$reportCount open',
            icon: Icons.inbox_rounded,
            tone: reportCount == 0
                ? AdminStatusTone.success
                : AdminStatusTone.warning,
          ),
          Text(
            'Newest reports arrive first. Open each item to inspect the submitted correction details.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _RouteReportsList extends StatelessWidget {
  final List<AdminRouteCorrectionReport> reports;
  final ValueChanged<AdminRouteCorrectionReport> onOpen;

  const _RouteReportsList({
    required this.reports,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return AdminResponsiveTable(
      breakpoint: 1000,
      mobile: Column(
        children: [
          for (final report in reports)
            _RouteReportCard(
              report: report,
              onOpen: onOpen,
            ),
        ],
      ),
      desktop: DataTable(
        columns: const [
          DataColumn(label: Text('Route')),
          DataColumn(label: Text('Terminal')),
          DataColumn(label: Text('Destination')),
          DataColumn(label: Text('Correction note')),
          DataColumn(label: Text('Submitted by')),
          DataColumn(label: Text('Submitted at')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final report in reports)
            DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 220,
                    child: Text(
                      _routeLabel(report),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(report.terminalName)),
                DataCell(Text(report.destination)),
                DataCell(
                  SizedBox(
                    width: 320,
                    child: Text(
                      report.correctionNote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(_submittedByLabel(report))),
                DataCell(Text(_formatSubmittedAt(report.submittedAt))),
                DataCell(
                  IconButton(
                    tooltip: 'View report',
                    onPressed: () => onOpen(report),
                    icon: const Icon(Icons.visibility_rounded),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RouteReportCard extends StatelessWidget {
  final AdminRouteCorrectionReport report;
  final ValueChanged<AdminRouteCorrectionReport> onOpen;

  const _RouteReportCard({
    required this.report,
    required this.onOpen,
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
                Expanded(
                  child: Text(
                    _routeLabel(report),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'View report',
                  onPressed: () => onOpen(report),
                  icon: const Icon(Icons.visibility_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              report.correctionNote,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.place_rounded,
                  label: report.terminalName,
                ),
                _InfoChip(
                  icon: Icons.flag_rounded,
                  label: report.destination,
                ),
                _InfoChip(
                  icon: Icons.person_rounded,
                  label: _submittedByLabel(report),
                ),
                _InfoChip(
                  icon: Icons.schedule_rounded,
                  label: _formatSubmittedAt(report.submittedAt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteReportDetailDialog extends StatelessWidget {
  final AdminRouteCorrectionReport report;

  const _RouteReportDetailDialog({required this.report});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Correction Report'),
      content: SizedBox(
        width: adminDialogWidth(context, 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Route', value: _routeLabel(report)),
              _DetailRow(
                  label: 'Route ID', value: _valueOrDash(report.routeId)),
              _DetailRow(
                label: 'Terminal',
                value: _valueOrDash(report.terminalName),
              ),
              _DetailRow(
                label: 'Destination',
                value: _valueOrDash(report.destination),
              ),
              _DetailRow(
                label: 'Submitted by',
                value: _submittedByLabel(report),
              ),
              _DetailRow(
                label: 'Submitted at',
                value: _formatSubmittedAt(report.submittedAt),
              ),
              const SizedBox(height: 16),
              Text(
                'Correction note',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SelectableText(_valueOrDash(report.correctionNote)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

String _routeLabel(AdminRouteCorrectionReport report) {
  return _valueOrDash(report.routeName);
}

String _submittedByLabel(AdminRouteCorrectionReport report) {
  return _valueOrDash(report.submittedByUid);
}

String _valueOrDash(String value) {
  return value.trim().isEmpty ? '—' : value.trim();
}

String _formatSubmittedAt(DateTime? value) {
  if (value == null) return 'Pending timestamp';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}-$month-$day $hour:$minute';
}
