import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';

import 'admin/admin_app.dart';
import 'models/destination.dart';
import 'services/simple_plan_service.dart';
import 'services/auth_service.dart';
import 'services/firebase_app_service.dart';
import 'services/theme_mode_service.dart';
import 'services/app_tutorial_service.dart';
import 'screens/home_screen.dart';
import 'screens/favorites_screen.dart';

import 'screens/explore_screen.dart';

import 'screens/create_plan_screen.dart';

import 'screens/plan_details_screen.dart';

import 'screens/explore_details_screen.dart';

import 'screens/my_plans_screen.dart';

import 'screens/profile_screen.dart';
import 'screens/trip_history_screen.dart';

import 'screens/map_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/share_plan_screen.dart';
import 'screens/route_options_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/add_place_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/app_tutorial_screen.dart';
import 'screens/terminal_routes_screen.dart';
import 'widgets/halaph_launch_preflight.dart';
import 'widgets/halaph_logo_loading.dart';
import 'package:halaph/models/app_public_config.dart';
import 'package:halaph/services/app_public_config_service.dart';

bool _androidLaunchScreenAccepted = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadEnvSafe();
  // Allow time for env to be ready
  await Future.delayed(const Duration(milliseconds: 100));
  await FirebaseAppService.initialize().timeout(
    const Duration(seconds: 4),
    onTimeout: () {
      debugPrint('Startup: Firebase initialization timed out; continuing.');
      return false;
    },
  );
  await ThemeModeService.initialize().timeout(
    const Duration(milliseconds: 900),
    onTimeout: () {
      debugPrint(
          'Startup: theme initialization timed out; using default theme.');
    },
  );
  debugPrint(
      'Startup: notification initialization deferred until reminders use.');

  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('Flutter widget error: ${details.exceptionAsString()}');
    return Directionality(
      textDirection: TextDirection.ltr,
      child: _HalaPhErrorPanel(
        message: kReleaseMode
            ? 'Something went wrong, but HalaPH is still running.'
            : details.exceptionAsString(),
      ),
    );
  };

  runApp(kIsWeb ? const AdminApp() : const HalaPhApp());
}

Future<void> _loadEnvSafe() async {
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('main: .env loaded, keys: ${dotenv.env.keys.toList()}');
  } catch (e) {
    debugPrint('main: Failed to load .env: $e');
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _launchAccepted = false;
  bool _checkingGuideMode = false;
  bool _showGuideMode = false;
  bool _guideModeShownThisSession = false;
  bool _guideModeStartupEvaluated = false;
  bool _guideModeStartupInFlight = false;
  bool _guideModeStartupScheduled = false;
  bool _isLoggedIn = false;
  bool _loading = true;
  String? _sessionUid;
  AppPublicConfigService? _publicConfigService;
  AppPublicConfig _publicConfig = const AppPublicConfig.defaults();
  StreamSubscription<firebase_auth.User?>? _authSubscription;
  StreamSubscription<AppPublicConfig>? _publicConfigSubscription;
  bool _publicConfigWatchStarted = false;

  bool get _isAndroidStartup =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    AppTutorialService.guideReplayRequests
        .addListener(_handleGuideReplayRequest);
    if (_isAndroidStartup) {
      if (!_androidLaunchScreenAccepted) {
        debugPrint('AppStartup: Android launch screen shown');
        debugPrint('AppStartup: Android startup checks skipped');
        return;
      }
      _launchAccepted = true;
    }
    _startAuthListener();
    _checkLogin();
  }

  Future<void> _startAuthListener() async {
    final firebaseReady = await FirebaseAppService.initialize().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint('AuthWrapper: Firebase listener setup timed out.');
        return false;
      },
    );

    if (!firebaseReady) {
      _showLoggedOutAccounts('auth timeout, showing accounts');
      return;
    }
    if (!mounted) return;
    _startPublicConfigWatch();

    _authSubscription =
        firebase_auth.FirebaseAuth.instance.userChanges().listen((user) {
      if (!mounted) return;

      if (user == null) {
        _showLoggedOutAccounts('unauthenticated, showing accounts');
        return;
      }

      final nextUid = user.uid;
      final sessionChanged = _sessionUid != nextUid;
      debugPrint('AppStartup: authenticated, showing home');
      setState(() {
        _isLoggedIn = true;
        _sessionUid = nextUid;
        _loading = false;
        if (sessionChanged) {
          _guideModeStartupEvaluated = false;
          _guideModeStartupInFlight = false;
          _guideModeStartupScheduled = false;
          _checkingGuideMode = false;
          if (!_showGuideMode) {
            _guideModeShownThisSession = false;
          }
        }
      });
    });
  }

  Future<void> _checkLogin() async {
    final auth = AuthService();
    final user = await auth.getCurrentUser().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint('AuthWrapper: auth session check timed out.');
        return null;
      },
    );

    if (user == null) {
      _showLoggedOutAccounts('auth timeout, showing accounts');
      return;
    }

    unawaited(SimplePlanService.initialize().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint('AuthWrapper: plan initialization timed out; continuing.');
      },
    ));

    _startPublicConfigWatch();

    if (mounted) {
      debugPrint('AppStartup: authenticated, showing home');
      setState(() {
        _isLoggedIn = true;
        _sessionUid = _safeCurrentFirebaseUid();
        _loading = false;
        _checkingGuideMode = false;
        _guideModeStartupEvaluated = false;
        _guideModeStartupInFlight = false;
        _guideModeStartupScheduled = false;
      });
    }
  }

  void _showLoggedOutAccounts(String reason) {
    if (!mounted) return;
    debugPrint('AppStartup: $reason');
    setState(() {
      _isLoggedIn = false;
      _sessionUid = null;
      _loading = false;
      _checkingGuideMode = false;
      _showGuideMode = false;
      _guideModeStartupInFlight = false;
      _guideModeStartupEvaluated = false;
      _guideModeStartupScheduled = false;
      _guideModeShownThisSession = false;
    });
  }

  void _onLoginSuccess() {
    unawaited(SimplePlanService.initialize());
    _startPublicConfigWatch();
    setState(() {
      _isLoggedIn = true;
      _sessionUid = _safeCurrentFirebaseUid();
      _guideModeStartupEvaluated = false;
      _guideModeStartupInFlight = false;
      _guideModeStartupScheduled = false;
      _checkingGuideMode = false;
    });
  }

  void _onLaunchStart() {
    setState(() {
      _launchAccepted = true;
    });
  }

  void _onAndroidLaunchStart() {
    debugPrint('AppStartup: Android start tapped');
    _androidLaunchScreenAccepted = true;

    firebase_auth.User? currentUser;
    try {
      if (FirebaseAppService.isInitialized) {
        currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
      }
    } catch (error) {
      debugPrint('AppStartup: Android auth session unavailable: $error');
    }

    if (currentUser == null) {
      debugPrint('AppStartup: Android routing to login');
      setState(() {
        _launchAccepted = true;
        _isLoggedIn = false;
        _sessionUid = null;
        _loading = false;
        _checkingGuideMode = false;
        _showGuideMode = false;
        _guideModeStartupInFlight = false;
        _guideModeStartupEvaluated = false;
        _guideModeStartupScheduled = false;
        _guideModeShownThisSession = false;
      });
      unawaited(_startAuthListener());
      return;
    }

    debugPrint('AppStartup: Android routing to app shell');
    setState(() {
      _launchAccepted = true;
      _isLoggedIn = true;
      _sessionUid = currentUser?.uid;
      _loading = false;
      _checkingGuideMode = false;
      _guideModeStartupEvaluated = false;
      _guideModeStartupInFlight = false;
      _guideModeStartupScheduled = false;
    });
    unawaited(SimplePlanService.initialize().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint('AuthWrapper: plan initialization timed out; continuing.');
      },
    ));
    _startPublicConfigWatch();
    unawaited(_startAuthListener());
  }

  void _startPublicConfigWatch() {
    if (_publicConfigWatchStarted || !FirebaseAppService.isInitialized) return;

    final publicConfigService =
        _publicConfigService ??= AppPublicConfigService();

    _publicConfigWatchStarted = true;
    _publicConfigSubscription?.cancel();
    _publicConfigSubscription =
        publicConfigService.watchPublicConfig().listen((config) {
      if (!mounted) return;

      setState(() {
        _publicConfig = config;
        if (config.maintenanceMode) {
          _showGuideMode = false;
          _checkingGuideMode = false;
          _guideModeStartupScheduled = false;
          _guideModeStartupInFlight = false;
          _guideModeStartupEvaluated = true;
        }
      });
    });

    unawaited(publicConfigService.loadPublicConfig().then((config) {
      if (!mounted) return;
      setState(() {
        _publicConfig = config;
      });
    }).catchError((error) {
      debugPrint('Maintenance config preload failed: $error');
    }));
  }

  Future<void> _signOutFromMaintenance() async {
    try {
      await firebase_auth.FirebaseAuth.instance.signOut();
    } catch (error) {
      debugPrint('Maintenance sign out failed: $error');
    }
    _showLoggedOutAccounts('signed out from maintenance');
  }

  String? _safeCurrentFirebaseUid() {
    if (!FirebaseAppService.isInitialized) return null;
    try {
      return firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    } catch (error) {
      debugPrint('AuthWrapper: current Firebase UID unavailable: $error');
      return null;
    }
  }

  void _continueAfterTutorial(String reason) {
    debugPrint('Guide Mode closed: $reason');
    setState(() {
      _showGuideMode = false;
      _guideModeShownThisSession = true;
      _guideModeStartupEvaluated = true;
      _guideModeStartupInFlight = false;
      _guideModeStartupScheduled = false;
      _checkingGuideMode = false;
    });
  }

  void _scheduleGuideModeStartupEvaluation() {
    if (!_launchAccepted ||
        _loading ||
        !_isLoggedIn ||
        _guideModeStartupEvaluated ||
        _guideModeStartupInFlight ||
        _guideModeStartupScheduled ||
        _guideModeShownThisSession ||
        _showGuideMode) {
      return;
    }
    _guideModeStartupScheduled = true;
    debugPrint('Guide Mode startup: scheduled after launch');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 220), () {
        if (!mounted) return;
        _guideModeStartupScheduled = false;
        if (!_launchAccepted ||
            _loading ||
            !_isLoggedIn ||
            _guideModeStartupEvaluated ||
            _guideModeStartupInFlight ||
            _guideModeShownThisSession ||
            _showGuideMode) {
          return;
        }
        unawaited(_evaluateGuideModeStartup());
      }));
    });
  }

  Future<void> _evaluateGuideModeStartup() async {
    if (_guideModeStartupInFlight) return;

    if (!_launchAccepted) {
      _logGuideModeDecisionSkip('launch not accepted');
      return;
    }
    if (!_isLoggedIn) {
      _logGuideModeDecisionSkip('user is logged out');
      return;
    }
    if (_guideModeShownThisSession) {
      _logGuideModeDecisionSkip('already shown this session');
      _guideModeStartupEvaluated = true;
      return;
    }

    setState(() {
      _guideModeStartupInFlight = true;
      _checkingGuideMode = true;
    });

    var enabledEveryStart = false;
    var completed = false;
    var failed = false;
    try {
      final results = await Future.wait([
        AppTutorialService.isGuideModeEnabledOnStart(),
        AppTutorialService.isTutorialCompleted(),
      ]).timeout(const Duration(seconds: 2));
      enabledEveryStart = results[0];
      completed = results[1];
    } catch (error) {
      debugPrint('Guide Mode startup: skipped because settings failed: $error');
      failed = true;
    }

    if (!mounted) return;

    debugPrint(
      'Guide Mode decision: loggedIn=$_isLoggedIn, loading=$_loading, '
      'showEveryStart=$enabledEveryStart, completed=$completed, '
      'shownThisSession=$_guideModeShownThisSession, forceReplay=false',
    );

    if (failed) {
      debugPrint('Guide Mode decision: skipped because settings failed');
      setState(() {
        _checkingGuideMode = false;
        _guideModeStartupInFlight = false;
        _guideModeStartupScheduled = false;
        _guideModeStartupEvaluated = true;
      });
      return;
    }

    if (!enabledEveryStart) {
      debugPrint('Guide Mode decision: skipped because every start is off');
      setState(() {
        _checkingGuideMode = false;
        _guideModeStartupInFlight = false;
        _guideModeStartupScheduled = false;
        _guideModeStartupEvaluated = true;
      });
      return;
    }

    debugPrint('Guide Mode decision: showing because every start is on');
    setState(() {
      _checkingGuideMode = false;
      _guideModeStartupInFlight = false;
      _guideModeStartupScheduled = false;
      _guideModeStartupEvaluated = true;
      _showGuideMode = true;
    });
  }

  void _handleGuideReplayRequest() {
    if (!mounted) return;
    debugPrint('Guide Mode replay: received by app shell');

    if (_showGuideMode) {
      debugPrint('Guide Mode replay: ignored because guide is already showing');
      return;
    }

    if (!_isLoggedIn) {
      debugPrint('Guide Mode replay: ignored because user is logged out');
      return;
    }

    setState(() {
      _showGuideMode = true;
      _guideModeShownThisSession = true;
      _guideModeStartupEvaluated = true;
      _guideModeStartupInFlight = false;
      _guideModeStartupScheduled = false;
    });
  }

  void _logGuideModeDecisionSkip(String reason) {
    debugPrint(
      'Guide Mode decision: loggedIn=$_isLoggedIn, loading=$_loading, '
      'showEveryStart=unknown, completed=unknown, '
      'shownThisSession=$_guideModeShownThisSession, forceReplay=false',
    );
    debugPrint('Guide Mode decision: skipped because $reason');
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _publicConfigSubscription?.cancel();
    AppTutorialService.guideReplayRequests
        .removeListener(_handleGuideReplayRequest);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAndroidStartup) {
      debugPrint(
        'AppStartup: AuthWrapper build Android launchAccepted=$_launchAccepted',
      );
    }

    if (!_launchAccepted) {
      if (_isAndroidStartup) {
        debugPrint('AppStartup: Android launch screen rendered');
        return HalaPhLaunchPreflight(
          visualOnly: true,
          debugLabel: 'Android launch screen v3',
          onStart: _onAndroidLaunchStart,
        );
      }

      return HalaPhLaunchPreflight(
        onStart: _onLaunchStart,
      );
    }

    if (_checkingGuideMode) {
      return const HalaPhLogoLoading(
        label: 'Preparing HalaPH...',
        fullScreen: true,
      );
    }

    if (_loading) {
      return const HalaPhLogoLoading(
        label: 'Preparing HalaPH...',
        fullScreen: true,
      );
    }
    if (!_isLoggedIn) {
      return AccountsScreen(onLoginSuccess: _onLoginSuccess);
    }

    if (_publicConfig.maintenanceMode) {
      return _MaintenanceModeScreen(
        config: _publicConfig,
        onSignOut: _signOutFromMaintenance,
      );
    }

    _scheduleGuideModeStartupEvaluation();
    return MainNavigation(
      key: ValueKey(_sessionUid ?? 'signed-in'),
      showGuideMode: _showGuideMode,
      onGuideModeFinished: () => _continueAfterTutorial('finish'),
      onGuideModeSkipped: () => _continueAfterTutorial('skip'),
    );
  }
}

class _MaintenanceModeScreen extends StatelessWidget {
  final AppPublicConfig config;
  final Future<void> Function() onSignOut;

  const _MaintenanceModeScreen({
    required this.config,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasAnnouncement = config.hasAnnouncement;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.construction_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'HalaPH is under maintenance',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    hasAnnouncement
                        ? _maintenanceMessage()
                        : 'We are updating the app right now. Please check again later.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_rounded,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Route search, plans, Guide Mode, and ads are paused while maintenance mode is active.',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onSignOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This screen updates automatically when maintenance mode is turned off.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _maintenanceMessage() {
    final title = config.announcementTitle.trim();
    final body = config.announcementBody.trim();

    if (title.isNotEmpty && body.isNotEmpty) {
      return '$title\n\n$body';
    }
    if (body.isNotEmpty) return body;
    return title;
  }
}

final GoRouter _router = GoRouter(
  errorBuilder: (context, state) {
    debugPrint('GoRouter error: ${state.error}');
    return const _HalaPhErrorScreen();
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AuthWrapper()),
    GoRoute(
      path: '/explore-details',
      builder: (context, state) {
        final destination = _decodeDestinationQuery(
          state.uri.queryParameters['destination'],
        );
        return ExploreDetailsScreen(
          destinationId: state.uri.queryParameters['destinationId'] ??
              destination?.id ??
              '',
          source: state.uri.queryParameters['source'],
          destination: destination,
        );
      },
    ),
    GoRoute(
      path: '/plan-details',
      builder: (context, state) {
        final planId = state.uri.queryParameters['planId'];
        return PlanDetailsScreen(planId: planId);
      },
    ),
    GoRoute(path: '/view', builder: (context, state) => const MapScreen()),
    GoRoute(
      path: '/create-plan',
      builder: (context, state) => const CreatePlanScreen(),
    ),
    GoRoute(
      path: '/my-plans',
      builder: (context, state) => const MyPlansScreen(),
    ),
    GoRoute(
      path: '/favorites',
      builder: (context, state) => const FavoritesScreen(),
    ),
    GoRoute(
      path: '/trip-history',
      builder: (context, state) => const TripHistoryScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/accounts',
      builder: (context, state) =>
          AccountsScreen(onLoginSuccess: () => context.go('/')),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) =>
          AccountsScreen(onLoginSuccess: () => context.go('/')),
    ),
    GoRoute(
      path: '/share-plan',
      builder: (context, state) =>
          SharePlanScreen(planId: state.uri.queryParameters['planId'] ?? ''),
    ),
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/add-place',
      builder: (context, state) => const AddPlaceScreen(),
    ),
    GoRoute(
      path: '/friends',
      builder: (context, state) => const FriendsScreen(),
    ),
    GoRoute(
      path: '/terminal-routes',
      builder: (context, state) => const TerminalRoutesScreen(),
    ),
    GoRoute(
      path: '/route-options',
      builder: (context, state) {
        final destination = _decodeDestinationQuery(
          state.uri.queryParameters['destination'],
        );
        return RouteOptionsScreen(
          destinationId: state.uri.queryParameters['destinationId'] ??
              destination?.id ??
              '',
          destinationName: state.uri.queryParameters['destinationName'] ??
              destination?.name ??
              'Destination',
          source: state.uri.queryParameters['source'],
          destination: destination,
        );
      },
    ),
  ],
);

class _HalaPhErrorScreen extends StatelessWidget {
  const _HalaPhErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HalaPH')),
      body: _HalaPhErrorPanel(
        message: 'This page could not be opened.',
        onGoHome: () => context.go('/'),
      ),
    );
  }
}

class _HalaPhErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback? onGoHome;

  const _HalaPhErrorPanel({
    required this.message,
    this.onGoHome,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 56,
                  color: Colors.orange[700],
                ),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: kReleaseMode ? 3 : 6,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (onGoHome != null) ...[
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: onGoHome,
                    child: const Text('Go Home'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Destination? _decodeDestinationQuery(String? encoded) {
  if (encoded == null || encoded.isEmpty) return null;
  try {
    final dynamic decoded = jsonDecode(encoded);
    if (decoded is Map<String, dynamic>) {
      return Destination.fromJson(decoded);
    }
    if (decoded is Map) {
      return Destination.fromJson(Map<String, dynamic>.from(decoded));
    }
  } catch (_) {
    return null;
  }
  return null;
}

const Color _halaNavy = Color(0xFF123A66);
const Color _halaNavyAccent = Color(0xFF14518F);
const Color _halaDeepNavy = Color(0xFF06162F);
const Color _halaSoftNavy = Color(0xFFE6F0FF);
const Color _halaBurgundy = Color(0xFF8F123D);
const Color _halaBurgundyAccent = Color(0xFFA91446);
const Color _halaDeepBurgundy = Color(0xFF2F0715);
const Color _halaSoftBurgundy = Color(0xFFFDE8EF);
const Color _halaCreamBackground = Color(0xFFFFF8F5);
const Color _halaNeutralBackground = Color(0xFFF8FAFC);

class MainNavigation extends StatefulWidget {
  final bool showGuideMode;
  final VoidCallback? onGuideModeFinished;
  final VoidCallback? onGuideModeSkipped;

  const MainNavigation({
    super.key,
    this.showGuideMode = false,
    this.onGuideModeFinished,
    this.onGuideModeSkipped,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  bool _terminalsTabInitialized = false;
  final _homeNavKey = GlobalKey();
  final _exploreNavKey = GlobalKey();
  final _terminalsNavKey = GlobalKey();
  final _plansNavKey = GlobalKey();
  final _profileNavKey = GlobalKey();

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 2) {
        _terminalsTabInitialized = true;
      }
    });
  }

  void _onGuideStepChanged(int stepIndex) {
    final targetIndex = switch (stepIndex) {
      0 => 0,
      1 => 0,
      2 => 1,
      3 => 2,
      4 => 3,
      5 => 4,
      6 => 0,
      _ => _currentIndex,
    };
    final shouldInitializeTerminals = targetIndex == 2;
    if (targetIndex == _currentIndex &&
        (!shouldInitializeTerminals || _terminalsTabInitialized)) {
      return;
    }
    setState(() {
      _currentIndex = targetIndex;
      if (shouldInitializeTerminals) {
        _terminalsTabInitialized = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navBackground =
        isDark ? const Color(0xFF111827) : Colors.white.withValues(alpha: 0.96);
    final navBorder =
        isDark ? const Color(0xFF263244) : const Color(0xFFE3ECF8);

    return Stack(
      children: [
        Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: [
              const HomeScreen(),
              const ExploreScreen(),
              _terminalsTabInitialized
                  ? const TerminalRoutesScreen()
                  : const SizedBox.shrink(),
              const MyPlansScreen(),
              const ProfileScreen(),
            ],
          ),
          bottomNavigationBar: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            decoration: BoxDecoration(
              color: navBackground,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: navBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildNavItem(Icons.home_rounded, 'Home', 0, _homeNavKey),
                    _buildNavItem(
                      Icons.explore_rounded,
                      'Explore',
                      1,
                      _exploreNavKey,
                    ),
                    _buildNavItem(
                      Icons.departure_board_rounded,
                      'Terminals',
                      2,
                      _terminalsNavKey,
                    ),
                    _buildNavItem(
                      Icons.calendar_month_rounded,
                      'Plans',
                      3,
                      _plansNavKey,
                    ),
                    _buildNavItem(
                      Icons.person_rounded,
                      'Profile',
                      4,
                      _profileNavKey,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.showGuideMode)
          Positioned.fill(
            child: AppTutorialScreen(
              launchedFromSettings: false,
              onStepChanged: _onGuideStepChanged,
              onFinish: widget.onGuideModeFinished ?? () {},
              onSkip: widget.onGuideModeSkipped ?? () {},
            ),
          ),
      ],
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index, GlobalKey key) {
    final isActive = _currentIndex == index;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final activeColor = colorScheme.primary;
    final inactiveColor = colorScheme.onSurfaceVariant;
    final activeBackground = isDark
        ? colorScheme.primaryContainer.withValues(alpha: 0.34)
        : colorScheme.primaryContainer.withValues(alpha: 0.70);

    return Expanded(
      child: KeyedSubtree(
        key: key,
        child: GestureDetector(
          onTap: () => _onTabChanged(index),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? activeBackground : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: isActive ? 1.08 : 1,
                  child: Icon(
                    icon,
                    size: 23,
                    color: isActive ? activeColor : inactiveColor,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1,
                    color: isActive ? activeColor : inactiveColor,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData _buildHalaTheme(
  Brightness brightness, {
  required BrandColorMode brandColorMode,
}) {
  final isDark = brightness == Brightness.dark;
  final resolvedBrandMode = brandColorMode == BrandColorMode.burgundy
      ? BrandColorMode.burgundy
      : BrandColorMode.navy;
  final isBurgundyMode = resolvedBrandMode == BrandColorMode.burgundy;
  final primary = isBurgundyMode ? _halaBurgundy : _halaNavy;
  final primaryAccent = isBurgundyMode ? _halaBurgundyAccent : _halaNavyAccent;
  final deepPrimary = isBurgundyMode ? _halaDeepBurgundy : _halaDeepNavy;
  final primaryTint = isBurgundyMode ? _halaSoftBurgundy : _halaSoftNavy;
  final supporting = isBurgundyMode ? _halaNavy : _halaBurgundyAccent;
  final supportingTint = isBurgundyMode ? _halaSoftNavy : _halaSoftBurgundy;
  final deepSupporting = isBurgundyMode ? _halaDeepNavy : _halaDeepBurgundy;

  final baseScheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
  );
  final colorScheme = baseScheme.copyWith(
    primary: isDark ? _lighten(primary, 0.36) : primary,
    onPrimary: Colors.white,
    primaryContainer: isDark ? _darken(primary, 0.44) : primaryTint,
    onPrimaryContainer: isDark ? primaryTint : deepPrimary,
    secondary: isDark ? _lighten(supporting, 0.32) : supporting,
    onSecondary: Colors.white,
    secondaryContainer: isDark ? _darken(supporting, 0.38) : supportingTint,
    onSecondaryContainer: isDark ? supportingTint : deepSupporting,
    tertiary: isDark ? _lighten(primaryAccent, 0.28) : primaryAccent,
    onTertiary: Colors.white,
    tertiaryContainer:
        isDark ? _darken(primaryAccent, 0.42) : _lighten(primaryAccent, 0.88),
    onTertiaryContainer: isDark ? primaryTint : deepPrimary,
    surface: isDark ? const Color(0xFF101827) : Colors.white,
    onSurface: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF071426),
    surfaceContainerLowest: isDark ? const Color(0xFF07101F) : Colors.white,
    surfaceContainerLow:
        isDark ? const Color(0xFF0E1726) : const Color(0xFFFFFCFB),
    surfaceContainer: isDark ? const Color(0xFF111C2D) : Colors.white,
    surfaceContainerHigh:
        isDark ? const Color(0xFF172338) : const Color(0xFFF8FAFC),
    surfaceContainerHighest:
        isDark ? const Color(0xFF1E2C44) : const Color(0xFFF1F5F9),
    outline: isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
    outlineVariant: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
  );

  final scaffoldBackground = isDark
      ? const Color(0xFF0B1120)
      : (isBurgundyMode ? _halaCreamBackground : _halaNeutralBackground);
  final surfaceColor = colorScheme.surface;
  final textColor = colorScheme.onSurface;
  final mutedTextColor =
      isDark ? const Color(0xFFCBD5E1) : const Color(0xFF52657F);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackground,
    fontFamily: 'Roboto',
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.8,
      ),
      headlineMedium: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
      ),
      titleLarge: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      titleMedium: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      bodyLarge: TextStyle(
        color: textColor,
        height: 1.35,
        letterSpacing: -0.1,
      ),
      bodyMedium: TextStyle(
        color: isDark ? const Color(0xFFE5E7EB) : const Color(0xFF071426),
        height: 1.35,
        letterSpacing: -0.05,
      ),
      labelLarge: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.1,
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scaffoldBackground,
      foregroundColor: textColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: textColor,
        fontSize: 20,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.4,
      ),
    ),
    cardTheme: CardThemeData(
      color: surfaceColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      circularTrackColor: colorScheme.primaryContainer.withValues(alpha: 0.52),
      linearTrackColor: colorScheme.primaryContainer.withValues(alpha: 0.52),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.45)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: surfaceColor,
      selectedItemColor: colorScheme.primary,
      unselectedItemColor: colorScheme.onSurfaceVariant,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.42),
      selectedColor: colorScheme.primaryContainer,
      secondarySelectedColor: colorScheme.secondaryContainer,
      side: BorderSide(color: colorScheme.outlineVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      labelStyle: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
      secondaryLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.1,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
      iconColor: colorScheme.primary,
      prefixIconColor: colorScheme.primary,
      suffixIconColor: mutedTextColor,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colorScheme.primary;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primaryContainer;
        }
        return null;
      }),
    ),
  );
}

Color _lighten(Color color, double amount) {
  return Color.lerp(color, Colors.white, amount)!;
}

Color _darken(Color color, double amount) {
  return Color.lerp(color, Colors.black, amount)!;
}

class HalaPhApp extends StatefulWidget {
  const HalaPhApp({super.key});

  @override
  State<HalaPhApp> createState() => _HalaPhAppState();
}

class _HalaPhAppState extends State<HalaPhApp> {
  bool get _showAndroidLaunchScreen =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      !_androidLaunchScreenAccepted;

  void _onAndroidVisualLaunchStart() {
    debugPrint('AppStartup: Android start tapped');
    _androidLaunchScreenAccepted = true;

    firebase_auth.User? currentUser;
    try {
      if (FirebaseAppService.isInitialized) {
        currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
      }
    } catch (error) {
      debugPrint('AppStartup: Android auth session unavailable: $error');
    }

    if (currentUser == null) {
      debugPrint('AppStartup: Android routing to login');
    } else {
      debugPrint('AppStartup: Android routing to app shell');
    }

    setState(() {});
    debugPrint('AppStartup: Android router enabled after Start');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _router.go('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeModeService.themeMode,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<BrandColorMode>(
          valueListenable: ThemeModeService.brandColorMode,
          builder: (context, brandColorMode, _) {
            final lightTheme = _buildHalaTheme(
              Brightness.light,
              brandColorMode: brandColorMode,
            );
            final darkTheme = _buildHalaTheme(
              Brightness.dark,
              brandColorMode: brandColorMode,
            );

            if (_showAndroidLaunchScreen) {
              debugPrint('AppStartup: Android hard launch gate active');
              debugPrint('AppStartup: Android launch screen v3 rendered');
              return MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'HalaPH - Discover Philippines',
                theme: lightTheme,
                darkTheme: darkTheme,
                themeMode: themeMode,
                home: HalaPhLaunchPreflight(
                  visualOnly: true,
                  debugLabel: 'Android launch screen v3',
                  onStart: _onAndroidVisualLaunchStart,
                ),
              );
            }

            return MaterialApp.router(
              debugShowCheckedModeBanner: false,
              title: 'HalaPH - Discover Philippines',
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: themeMode,
              routerDelegate: _router.routerDelegate,
              routeInformationParser: _router.routeInformationParser,
              routeInformationProvider: _router.routeInformationProvider,
            );
          },
        );
      },
    );
  }
}
