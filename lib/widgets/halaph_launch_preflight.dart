import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/plan_notification_service.dart';
import 'hala_mobile_ui.dart';

class HalaPhLaunchPreflight extends StatefulWidget {
  final VoidCallback onStart;
  final bool visualOnly;
  final String? debugLabel;

  const HalaPhLaunchPreflight({
    super.key,
    required this.onStart,
    this.visualOnly = false,
    this.debugLabel,
  });

  @override
  State<HalaPhLaunchPreflight> createState() => _HalaPhLaunchPreflightState();
}

class _HalaPhLaunchPreflightState extends State<HalaPhLaunchPreflight>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _routeController;
  late final Animation<double> _logoScale;
  late final Animation<double> _contentFade;
  late final Animation<Offset> _contentSlide;

  bool _animationComplete = false;
  bool _checksComplete = false;
  bool _accountChecked = false;
  bool _notificationsReady = false;
  bool _locationReady = false;
  bool _checksFinalized = false;
  bool _startTriggered = false;
  bool _readyLogged = false;

  String _notificationMessage = 'Plans and reminders ready.';
  String _locationMessage = 'Route tools ready.';
  String _accountMessage = 'Your commute workspace is ready.';
  late final Stopwatch _preflightStopwatch;

  bool get _canStart => _animationComplete && _checksComplete;

  @override
  void initState() {
    super.initState();
    _preflightStopwatch = Stopwatch()..start();
    debugPrint('Preflight: started');

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _routeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _logoScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.86, end: 1.06)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 58,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.06, end: 1)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 42,
      ),
    ]).animate(_introController);

    _contentFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.24, 1, curve: Curves.easeOut),
      ),
    );
    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.24, 1, curve: Curves.easeOutCubic),
      ),
    );

    _introController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _animationComplete = true);
        _logReadyForContinueIfReady();
      }
    });

    unawaited(_introController.forward());
    if (widget.visualOnly) {
      debugPrint('Preflight: visual-only checks skipped');
      setState(() {
        _checksComplete = true;
        _checksFinalized = true;
        _accountChecked = true;
        _notificationsReady = true;
        _locationReady = true;
        _notificationMessage = 'Notifications available after Start';
        _locationMessage = 'Location available when needed';
        _accountMessage = 'Account routing starts after Start';
      });
    } else {
      unawaited(_runChecks());
    }
  }

  Future<void> _runChecks() async {
    var timedOut = false;
    await Future.wait<void>([
      _checkNotifications(),
      _checkLocation(),
      _checkAccountSession(),
    ]).timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        if (!mounted) return <void>[];
        timedOut = true;
        debugPrint('Preflight: timed out, continuing');
        setState(() {
          _checksFinalized = true;
          if (_notificationMessage == 'Checking notifications') {
            _notificationMessage = 'Notifications checked';
          }
          if (_locationMessage == 'Checking location') {
            _locationMessage = 'Location checked';
          }
          _accountMessage = 'Account session checked';
          _accountChecked = true;
        });
        return <void>[];
      },
    );

    if (!mounted) return;
    setState(() {
      _checksFinalized = true;
      _checksComplete = true;
      _accountChecked = true;
      if (_notificationMessage == 'Checking notifications') {
        _notificationMessage = 'Notifications checked';
      }
      if (_locationMessage == 'Checking location') {
        _locationMessage = 'Location checked';
      }
      _accountMessage = 'Account session checked';
    });
    if (timedOut) {
      debugPrint('Preflight: completed after timeout fallback');
    }
    debugPrint(
      'Preflight: completed in ${_preflightStopwatch.elapsedMilliseconds} ms',
    );
    _logReadyForContinueIfReady();
  }

  Future<void> _checkNotifications() async {
    try {
      final remindersEnabled =
          await PlanNotificationService.arePlanRemindersEnabled()
              .timeout(const Duration(milliseconds: 500));
      if (!mounted || _checksFinalized) return;
      setState(() {
        _notificationsReady = remindersEnabled;
        _notificationMessage = remindersEnabled
            ? 'Notifications checked'
            : 'Notifications not enabled. You can turn them on later.';
      });
      debugPrint('Preflight: notification check done');
    } catch (_) {
      if (!mounted || _checksFinalized) return;
      setState(() {
        _notificationsReady = false;
        _notificationMessage =
            'Notifications will be requested when reminders are enabled.';
      });
      debugPrint('Preflight: notification check done');
    }
  }

  Future<void> _checkLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(milliseconds: 500));
      final permission = await Geolocator.checkPermission()
          .timeout(const Duration(milliseconds: 500));
      final ready = serviceEnabled &&
          (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse);

      if (!mounted || _checksFinalized) return;
      setState(() {
        _locationReady = ready;
        _locationMessage = ready
            ? 'Location checked'
            : 'Location not enabled. You can continue and allow it later.';
      });
      debugPrint('Preflight: location check done');
    } catch (_) {
      if (!mounted || _checksFinalized) return;
      setState(() {
        _locationReady = false;
        _locationMessage = 'Location will be requested when needed.';
      });
      debugPrint('Preflight: location check done');
    }
  }

  Future<void> _checkAccountSession() async {
    try {
      firebase_auth.FirebaseAuth.instance.currentUser;
    } catch (_) {
      // AuthWrapper owns the real auth flow after Start.
    }

    if (!mounted || _checksFinalized) return;
    setState(() {
      _accountChecked = true;
      _accountMessage = 'Account session checked';
    });
    debugPrint('Preflight: auth check done');
  }

  void _logReadyForContinueIfReady() {
    if (!_canStart || _readyLogged || _startTriggered) return;
    _readyLogged = true;
    if (widget.visualOnly) {
      debugPrint('AppStartup: Android visual-only start button ready');
    } else {
      debugPrint('Preflight: ready for continue');
    }
  }

  void _completeStart() {
    if (_startTriggered) return;
    _startTriggered = true;
    debugPrint('Preflight: continue tapped');
    _introController.stop();
    _routeController.stop();
    debugPrint('Preflight: animation stopped before route');
    debugPrint('Preflight: routing to login or app shell');
    widget.onStart();
  }

  @override
  void dispose() {
    _introController.dispose();
    _routeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_introController, _routeController]),
          builder: (context, child) {
            final introProgress = _safeUnit(_introController.value);
            final routeProgress = _safeModuloUnit(_routeController.value);

            return Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LaunchRouteBoard(
                        introProgress: introProgress,
                        routeProgress: routeProgress,
                        logoScale: _logoScale,
                        colorScheme: colorScheme,
                      ),
                      const SizedBox(height: 18),
                      FadeTransition(
                        opacity: _contentFade,
                        child: SlideTransition(
                          position: _contentSlide,
                          child: Column(
                            children: [
                              Text(
                                'Your commute workspace is ready',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: colorScheme.onSurface,
                                  letterSpacing: -0.45,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _TaglinePill(colorScheme: colorScheme),
                              const SizedBox(height: 12),
                              Text(
                                'Plan with confidence before you leave.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                              if (widget.visualOnly &&
                                  widget.debugLabel != null) ...[
                                const SizedBox(height: 12),
                                _DebugLabel(
                                  label: widget.debugLabel!,
                                  colorScheme: colorScheme,
                                ),
                              ],
                              const SizedBox(height: 22),
                              _StatusPanel(
                                colorScheme: colorScheme,
                                children: [
                                  _StatusRow(
                                    icon: _animationComplete
                                        ? Icons.check_circle_rounded
                                        : Icons.route_rounded,
                                    iconColor: colorScheme.primary,
                                    label: _animationComplete
                                        ? 'Route guide ready'
                                        : 'Preparing route guide',
                                  ),
                                  _StatusRow(
                                    icon: _notificationsReady
                                        ? Icons.check_circle_rounded
                                        : Icons.info_rounded,
                                    iconColor: _notificationsReady
                                        ? colorScheme.primary
                                        : colorScheme.tertiary,
                                    label: _notificationMessage,
                                  ),
                                  _StatusRow(
                                    icon: _locationReady
                                        ? Icons.check_circle_rounded
                                        : Icons.info_rounded,
                                    iconColor: _locationReady
                                        ? colorScheme.primary
                                        : colorScheme.tertiary,
                                    label: _locationMessage,
                                  ),
                                  _StatusRow(
                                    icon: _accountChecked
                                        ? Icons.check_circle_rounded
                                        : Icons.hourglass_top_rounded,
                                    iconColor: colorScheme.primary,
                                    label: _accountMessage,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                switchInCurve: Curves.easeOutCubic,
                                transitionBuilder: (child, animation) {
                                  final offset = Tween<Offset>(
                                    begin: const Offset(0, 0.14),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  );
                                  final scale = Tween<double>(
                                    begin: 0.96,
                                    end: 1,
                                  ).animate(animation);
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: offset,
                                      child: ScaleTransition(
                                        scale: scale,
                                        child: child,
                                      ),
                                    ),
                                  );
                                },
                                child: _canStart
                                    ? SizedBox(
                                        key: const ValueKey('start-ready'),
                                        width: double.infinity,
                                        child: HalaPrimaryButton(
                                          onPressed: _completeStart,
                                          icon: Icons.arrow_forward_rounded,
                                          child: const Text('Start commute'),
                                        ),
                                      )
                                    : _PreparingPill(
                                        key: const ValueKey('start-waiting'),
                                        colorScheme: colorScheme,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LogoCard extends StatelessWidget {
  final ColorScheme colorScheme;
  final double size;

  const _LogoCard({
    required this.colorScheme,
    this.size = 110,
  });

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.25;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.11),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: Image.asset(
          'assets/icons/app_icon.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.explore_rounded,
              color: colorScheme.primary,
              size: size * 0.52,
            );
          },
        ),
      ),
    );
  }
}

class _TaglinePill extends StatelessWidget {
  final ColorScheme colorScheme;

  const _TaglinePill({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        'Where Every Trip Meets Its Line',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.35,
              height: 1.2,
            ),
      ),
    );
  }
}

class _LaunchRouteBoard extends StatelessWidget {
  final double introProgress;
  final double routeProgress;
  final Animation<double> logoScale;
  final ColorScheme colorScheme;

  const _LaunchRouteBoard({
    required this.introProgress,
    required this.routeProgress,
    required this.logoScale,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeIntroProgress = _safeUnit(introProgress);
    final safeRouteProgress = _safeModuloUnit(routeProgress);
    final routeDraw = _phase(safeIntroProgress, 0.20, 0.72);
    final pinsIn = _phase(safeIntroProgress, 0.08, 0.36);
    final chipsIn = _phase(safeIntroProgress, 0.48, 0.86);

    return HalaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ScaleTransition(
                scale: logoScale,
                child: _LogoCard(colorScheme: colorScheme, size: 60),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HalaPH',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Where Every Trip Meets Its Line',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              _BoardBadge(
                colorScheme: colorScheme,
                progress: routeDraw,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 145,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _RouteBoardPainter(
                          drawProgress: routeDraw,
                          pulseProgress: safeRouteProgress,
                          primary: colorScheme.primary,
                          secondary: colorScheme.secondary,
                          surface: colorScheme.surface,
                          lineBase: colorScheme.secondaryContainer,
                        ),
                      ),
                    ),
                    _BoardPin(
                      left: size.width * 0.05,
                      top: size.height * 0.63,
                      progress: pinsIn,
                      icon: Icons.location_on_rounded,
                      label: 'Origin',
                      color: colorScheme.primary,
                    ),
                    _BoardPin(
                      left: size.width * 0.73,
                      top: size.height * 0.08,
                      progress: _phase(safeIntroProgress, 0.18, 0.42),
                      icon: Icons.flag_rounded,
                      label: 'Destination',
                      color: colorScheme.tertiary,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: chipsIn,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                HalaStatusChip(
                  icon: Icons.alt_route_rounded,
                  label: 'Route tools',
                  color: colorScheme.primary,
                ),
                HalaStatusChip(
                  icon: Icons.event_available_rounded,
                  label: 'Plans',
                  color: colorScheme.secondary,
                ),
                HalaStatusChip(
                  icon: Icons.notifications_active_rounded,
                  label: 'Reminders',
                  color: colorScheme.tertiary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardBadge extends StatelessWidget {
  final ColorScheme colorScheme;
  final double progress;

  const _BoardBadge({
    required this.colorScheme,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final ready = progress >= 0.98;
    final accent = colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: 0.25),
        ),
      ),
      child: Icon(
        ready ? Icons.check_rounded : Icons.route_rounded,
        size: 18,
        color: accent,
      ),
    );
  }
}

class _BoardPin extends StatelessWidget {
  final double left;
  final double top;
  final double progress;
  final IconData icon;
  final String label;
  final Color color;

  const _BoardPin({
    required this.left,
    required this.top,
    required this.progress,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final clamped = _safeUnit(progress);
    return Positioned(
      left: left,
      top: top - (1 - clamped) * 8,
      child: Opacity(
        opacity: clamped,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 17),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteBoardPainter extends CustomPainter {
  final double drawProgress;
  final double pulseProgress;
  final Color primary;
  final Color secondary;
  final Color surface;
  final Color lineBase;

  const _RouteBoardPainter({
    required this.drawProgress,
    required this.pulseProgress,
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.lineBase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final safeDrawProgress = _safeUnit(drawProgress);
    final safePulseProgress = _safeModuloUnit(pulseProgress);
    final panel = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(22),
    );
    canvas.drawRRect(
      panel,
      Paint()..color = surface.withValues(alpha: 0.62),
    );

    final gridPaint = Paint()
      ..color = lineBase.withValues(alpha: 0.32)
      ..strokeWidth = 1;
    for (var x = size.width * 0.12; x < size.width; x += size.width * 0.18) {
      canvas.drawLine(Offset(x, 10), Offset(x, size.height - 10), gridPaint);
    }
    for (var y = size.height * 0.18; y < size.height; y += size.height * 0.24) {
      canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), gridPaint);
    }

    final route = Path()
      ..moveTo(size.width * 0.15, size.height * 0.74)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.42,
        size.width * 0.40,
        size.height * 0.86,
        size.width * 0.53,
        size.height * 0.55,
      )
      ..cubicTo(
        size.width * 0.64,
        size.height * 0.30,
        size.width * 0.73,
        size.height * 0.28,
        size.width * 0.86,
        size.height * 0.20,
      );

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(route.shift(const Offset(0, 8)), shadowPaint);

    final basePaint = Paint()
      ..color = lineBase
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(route, basePaint);

    final metric = route.computeMetrics().first;
    final activeLength = metric.length * safeDrawProgress;
    final activePath = metric.extractPath(0, activeLength);
    final activePaint = Paint()
      ..shader = LinearGradient(colors: [primary, secondary]).createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(activePath, activePaint);

    final waypoints = const [0.0, 0.30, 0.55, 0.76, 1.0];
    for (var i = 0; i < waypoints.length; i++) {
      final tangent = metric.getTangentForOffset(metric.length * waypoints[i]);
      if (tangent == null) continue;
      final localPulse = _safeUnit(
          (math.sin((safePulseProgress * 2 * math.pi) - i * 1.05) + 1) / 2);
      final reached = safeDrawProgress >= waypoints[i] || i == 0;
      final dotPaint = Paint()
        ..color = reached ? primary : surface.withValues(alpha: 0.95)
        ..style = PaintingStyle.fill;
      final ringPaint = Paint()
        ..color = reached
            ? primary.withValues(alpha: 0.18 + localPulse * 0.14)
            : lineBase
        ..style = PaintingStyle.fill;
      canvas.drawCircle(tangent.position, 13 + localPulse * 3, ringPaint);
      canvas.drawCircle(tangent.position, 7, dotPaint);
      canvas.drawCircle(
        tangent.position,
        7,
        Paint()
          ..color = reached ? Colors.white : lineBase
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final markerProgress = safeDrawProgress < 0.98
        ? safeDrawProgress.clamp(0.06, 0.94).toDouble()
        : _safeModuloUnit(0.08 + safePulseProgress * 0.84);
    final vehicleTangent =
        metric.getTangentForOffset(metric.length * markerProgress);
    if (vehicleTangent != null) {
      _drawVehicle(canvas, vehicleTangent.position, vehicleTangent.angle);
    }
  }

  void _drawVehicle(Canvas canvas, Offset center, double angle) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 34, height: 20),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      body.shift(const Offset(0, 2)),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );
    canvas.drawRRect(body, Paint()..color = secondary);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-15, -11, 30, 6),
        const Radius.circular(4),
      ),
      Paint()..color = primary,
    );
    canvas.drawRect(
      const Rect.fromLTWH(-10, -6, 7, 5),
      Paint()..color = Colors.white.withValues(alpha: 0.82),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, -6, 7, 5),
      Paint()..color = Colors.white.withValues(alpha: 0.82),
    );
    canvas.drawRect(
      const Rect.fromLTWH(9, -6, 5, 5),
      Paint()..color = Colors.white.withValues(alpha: 0.82),
    );
    canvas.drawCircle(
        const Offset(-10, 9), 2.7, Paint()..color = Colors.black87);
    canvas.drawCircle(
        const Offset(10, 9), 2.7, Paint()..color = Colors.black87);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RouteBoardPainter oldDelegate) {
    return oldDelegate.drawProgress != drawProgress ||
        oldDelegate.pulseProgress != pulseProgress ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.surface != surface ||
        oldDelegate.lineBase != lineBase;
  }
}

double _phase(double value, double start, double end) {
  final safeValue = _safeUnit(value);
  if (safeValue <= start) return 0;
  if (safeValue >= end) return 1;
  final t = _safeUnit((safeValue - start) / (end - start));
  return Curves.easeOutCubic.transform(t);
}

double _safeUnit(double value) {
  if (value.isNaN || value.isInfinite) return 0;
  return value.clamp(0.0, 1.0).toDouble();
}

double _safeModuloUnit(double value) {
  if (value.isNaN || value.isInfinite) return 0;
  final normalized = value % 1.0;
  return _safeUnit(normalized < 0 ? normalized + 1.0 : normalized);
}

class _StatusPanel extends StatelessWidget {
  final ColorScheme colorScheme;
  final List<Widget> children;

  const _StatusPanel({
    required this.colorScheme,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return HalaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'READINESS CHECK',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.75,
                ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _DebugLabel extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;

  const _DebugLabel({
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _StatusRow({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Icon(
            icon,
            key: ValueKey('${icon.codePoint}-$label'),
            color: iconColor,
            size: 22,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _PreparingPill extends StatelessWidget {
  final ColorScheme colorScheme;

  const _PreparingPill({
    super.key,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Preparing route guide...',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
