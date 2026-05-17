import 'dart:math' as math;

import 'package:flutter/material.dart';

class AdminPageScaffold extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final double maxWidth;

  const AdminPageScaffold({
    super.key,
    required this.children,
    this.padding,
    this.maxWidth = 1320,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final horizontalPadding = viewportWidth < 600
            ? 16.0
            : viewportWidth < 900
                ? 20.0
                : 28.0;
        final resolvedPadding = padding ??
            EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 28);
        final safeMaxWidth = math.max(
          0.0,
          math.min(maxWidth, viewportWidth - resolvedPadding.horizontal),
        );

        return ListView(
          padding: resolvedPadding,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: safeMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class AdminSectionHeader extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final List<Widget> actions;

  const AdminSectionHeader({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AdminDataCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;
          final heading = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (stacked || actions.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(spacing: 10, runSpacing: 10, children: actions),
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 20),
              Wrap(spacing: 10, runSpacing: 10, children: actions),
            ],
          );
        },
      ),
    );
  }
}

class AdminMetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final bool emphasized;
  final bool restricted;

  const AdminMetricCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.emphasized = false,
    this.restricted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = restricted ? scheme.error : scheme.primary;
    return AdminDataCard(
      padding: const EdgeInsets.all(20),
      backgroundColor: emphasized ? accent.withValues(alpha: 0.06) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const Spacer(),
              if (restricted)
                AdminStatusBadge(
                  label: 'Restricted',
                  icon: Icons.lock_outline_rounded,
                  tone: AdminStatusTone.danger,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: scheme.onSurface,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class AdminDataCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  const AdminDataCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: backgroundColor,
      child: Padding(padding: padding, child: child),
    );
  }
}

class AdminActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool tonal;

  const AdminActionButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.tonal = false,
  });

  @override
  Widget build(BuildContext context) {
    return tonal
        ? FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          )
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
  }
}

enum AdminStatusTone { neutral, info, success, warning, danger }

class AdminStatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final AdminStatusTone tone;

  const AdminStatusBadge({
    super.key,
    required this.label,
    required this.icon,
    this.tone = AdminStatusTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      AdminStatusTone.success => (
          const Color(0xFFDCFCE7),
          const Color(0xFF166534),
        ),
      AdminStatusTone.warning => (
          const Color(0xFFFEF3C7),
          const Color(0xFF92400E),
        ),
      AdminStatusTone.danger => (
          const Color(0xFFFEE2E2),
          const Color(0xFFB91C1C),
        ),
      AdminStatusTone.info => (
          const Color(0xFFDBEAFE),
          const Color(0xFF1D4ED8),
        ),
      AdminStatusTone.neutral => (
          scheme.surfaceContainerLow,
          scheme.onSurfaceVariant,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AdminDataCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}

class AdminErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const AdminErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AdminDataCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.error_outline_rounded, color: scheme.error),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminLoadingState extends StatelessWidget {
  final String label;

  const AdminLoadingState({super.key, this.label = 'Loading data...'});

  @override
  Widget build(BuildContext context) {
    return AdminDataCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label),
        ],
      ),
    );
  }
}

class AdminReadOnlyNotice extends StatelessWidget {
  final String title;
  final String message;

  const AdminReadOnlyNotice({
    super.key,
    this.title = 'Read-only access',
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AdminDataCard(
      padding: const EdgeInsets.all(18),
      backgroundColor: scheme.primary.withValues(alpha: 0.04),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.visibility_rounded, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminResponsiveTable extends StatelessWidget {
  final Widget desktop;
  final Widget mobile;
  final double breakpoint;

  const AdminResponsiveTable({
    super.key,
    required this.desktop,
    required this.mobile,
    this.breakpoint = 980,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) return mobile;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: desktop,
            ),
          ),
        );
      },
    );
  }
}

class AdminResponsiveFormRow extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  final double spacing;

  const AdminResponsiveFormRow({
    super.key,
    required this.children,
    this.breakpoint = 520,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}

double adminDialogWidth(BuildContext context, double maxWidth) {
  final viewportWidth = MediaQuery.sizeOf(context).width;
  return math.max(0, math.min(maxWidth, viewportWidth - 80));
}
