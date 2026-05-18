import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_tutorial_service.dart';

class AppTutorialScreen extends StatefulWidget {
  final bool launchedFromSettings;
  final VoidCallback onFinish;
  final VoidCallback onSkip;
  final ValueChanged<int>? onStepChanged;

  const AppTutorialScreen({
    super.key,
    required this.launchedFromSettings,
    required this.onFinish,
    required this.onSkip,
    this.onStepChanged,
  });

  @override
  State<AppTutorialScreen> createState() => _AppTutorialScreenState();
}

class _AppTutorialScreenState extends State<AppTutorialScreen> {
  static const _steps = <_GuideStep>[
    _GuideStep(
      title: 'Home',
      body:
          'See your commute dashboard, Up Next, and the quickest path into trip planning.',
      icon: Icons.home_rounded,
      tabLabel: 'Home',
    ),
    _GuideStep(
      title: 'Explore',
      body:
          'Search destinations, browse categories, and move from discovery into route planning.',
      icon: Icons.explore_rounded,
      tabLabel: 'Explore',
    ),
    _GuideStep(
      title: 'Terminals',
      body:
          'Browse verified terminal routes, review confidence cues, and report corrections when needed.',
      icon: Icons.departure_board_rounded,
      tabLabel: 'Terminals',
    ),
    _GuideStep(
      title: 'Plans',
      body:
          'Create plans, review shared trips, revisit history, and keep reminders close.',
      icon: Icons.calendar_month_rounded,
      tabLabel: 'Plans',
    ),
    _GuideStep(
      title: 'Profile',
      body:
          'Open Friends, Saved Places, Trip History, Settings, and Guide Mode from one hub.',
      icon: Icons.person_rounded,
      tabLabel: 'Profile',
    ),
  ];

  int _index = 0;
  bool _closing = false;

  bool get _isFirst => _index == 0;
  bool get _isLast => _index == _steps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyStepChanged());
  }

  void _notifyStepChanged() {
    if (!mounted) return;
    widget.onStepChanged?.call(_index);
  }

  Future<void> _close({required bool skipped, required String reason}) async {
    if (_closing) return;
    debugPrint('Guide Mode closed: $reason');
    setState(() => _closing = true);
    await AppTutorialService.setTutorialCompleted(true);
    if (!mounted) return;
    if (skipped) {
      widget.onSkip();
    } else {
      widget.onFinish();
    }
  }

  void _next() {
    if (_closing) return;
    if (_isLast) {
      unawaited(_close(skipped: false, reason: 'finish'));
      return;
    }
    setState(() => _index += 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyStepChanged());
  }

  void _back() {
    if (_closing || _isFirst) return;
    setState(() => _index -= 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyStepChanged());
  }

  Future<void> _handleSystemBack() async {
    if (_closing) return;
    if (!_isFirst) {
      _back();
      return;
    }
    await _close(skipped: true, reason: 'back');
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_index];
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_handleSystemBack());
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary.withValues(alpha: 0.08),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.10),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: 460,
                          maxHeight: constraints.maxHeight * 0.82,
                        ),
                        child: Semantics(
                          container: true,
                          liveRegion: true,
                          label:
                              'Guide step ${_index + 1} of ${_steps.length}: ${step.title}',
                          child: _GuideCard(
                            step: step,
                            stepIndex: _index,
                            totalSteps: _steps.length,
                            launchedFromSettings: widget.launchedFromSettings,
                            isFirst: _isFirst,
                            isLast: _isLast,
                            isBusy: _closing,
                            onSkip: () => unawaited(
                              _close(skipped: true, reason: 'skip'),
                            ),
                            onBack: _back,
                            onNext: _next,
                            onFinish: () => unawaited(
                              _close(skipped: false, reason: 'finish'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideStep {
  final String title;
  final String body;
  final IconData icon;
  final String tabLabel;

  const _GuideStep({
    required this.title,
    required this.body,
    required this.icon,
    required this.tabLabel,
  });
}

class _GuideCard extends StatelessWidget {
  final _GuideStep step;
  final int stepIndex;
  final int totalSteps;
  final bool launchedFromSettings;
  final bool isFirst;
  final bool isLast;
  final bool isBusy;
  final VoidCallback onSkip;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  const _GuideCard({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.launchedFromSettings,
    required this.isFirst,
    required this.isLast,
    required this.isBusy,
    required this.onSkip,
    required this.onBack,
    required this.onNext,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardColor = colorScheme.surfaceContainerLow;
    final borderColor = colorScheme.outlineVariant;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(step.icon, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${stepIndex + 1} of $totalSteps',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          step.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: isBusy ? null : onSkip,
                    child: const Text('Skip'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (stepIndex + 1) / totalSteps,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  step.tabLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                step.body,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (launchedFromSettings) ...[
                const SizedBox(height: 12),
                Text(
                  'You can replay this guide anytime from Settings.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isFirst || isBusy ? null : onBack,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isBusy ? null : (isLast ? onFinish : onNext),
                      icon: Icon(
                        isLast
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                        size: 18,
                      ),
                      label: Text(isLast ? 'Finish' : 'Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
