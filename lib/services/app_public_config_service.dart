import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:halaph/models/app_public_config.dart';
import 'package:halaph/utils/app_log.dart';

class AppPublicConfigService {
  static const Duration _readTimeout = Duration(seconds: 4);
  static AppPublicConfig _cachedConfig = const AppPublicConfig.defaults();
  static bool _hasLoadedConfig = false;
  static bool _hasResolvedLoadThisSession = false;
  static Future<AppPublicConfig>? _loadInFlight;
  static Completer<AppPublicConfig>? _watchFirstValueCompleter;
  static Future<AppPublicConfig>? _watchLoadFuture;
  static StreamController<AppPublicConfig>? _watchController;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _watchSubscription;
  static bool _loadedLoggedThisSession = false;
  static bool _timeoutLoggedThisSession = false;

  final FirebaseFirestore _firestore;

  AppPublicConfigService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static AppPublicConfig get cachedConfig => _cachedConfig;

  DocumentReference<Map<String, dynamic>> get _document => _firestore
      .collection(AppPublicConfig.collectionPath)
      .doc(AppPublicConfig.documentId);

  Stream<AppPublicConfig> watchPublicConfig() {
    final controller =
        _watchController ??= StreamController<AppPublicConfig>.broadcast();
    final firstWatchValue =
        _watchFirstValueCompleter ??= Completer<AppPublicConfig>();
    _watchLoadFuture ??= firstWatchValue.future.timeout(
      _readTimeout,
      onTimeout: () {
        _hasResolvedLoadThisSession = true;
        _logTimeout();
        return _cachedConfig;
      },
    );
    if (_hasLoadedConfig) {
      scheduleMicrotask(() => controller.add(_cachedConfig));
    }
    _watchSubscription ??= _document.snapshots().listen(
      (snapshot) {
        final config = AppPublicConfig.fromSnapshot(snapshot);
        _applyLoadedConfig(config);
        if (!firstWatchValue.isCompleted) {
          firstWatchValue.complete(config);
        }
        controller.add(config);
      },
      onError: (Object error) {
        _hasResolvedLoadThisSession = true;
        if (error is FirebaseException && error.code == 'permission-denied') {
          AppLog.throttledInfo(
            'public-config-watch-denied',
            'App public config watch permission-denied; using cached/default config.',
          );
        } else {
          AppLog.error('App public config watch failed: $error');
        }
        if (!firstWatchValue.isCompleted) {
          firstWatchValue.complete(_cachedConfig);
        }
        controller.add(_cachedConfig);
      },
    );
    return controller.stream;
  }

  Future<AppPublicConfig> loadPublicConfig({bool forceRefresh = false}) {
    if (!forceRefresh && _hasResolvedLoadThisSession) {
      return Future.value(_cachedConfig);
    }
    final inFlight = _loadInFlight;
    if (!forceRefresh && inFlight != null) return inFlight;

    final watchLoadFuture = _watchLoadFuture;
    if (!forceRefresh && watchLoadFuture != null) {
      _loadInFlight = watchLoadFuture;
      return watchLoadFuture;
    }

    final future = _fetchPublicConfig();
    _loadInFlight = future;
    return future;
  }

  Future<AppPublicConfig> _fetchPublicConfig() {
    final source =
        _document.get(const GetOptions(source: Source.server)).then((snapshot) {
      final config = AppPublicConfig.fromSnapshot(snapshot);
      _applyLoadedConfig(config);
      return config;
    });

    return source.timeout(
      _readTimeout,
      onTimeout: () {
        _hasResolvedLoadThisSession = true;
        _logTimeout();
        unawaited(
          source.catchError((Object error) {
            _logReadFailure(error);
            return _cachedConfig;
          }),
        );
        return _cachedConfig;
      },
    ).catchError((Object error) {
      _hasResolvedLoadThisSession = true;
      _logReadFailure(error);
      return _cachedConfig;
    });
  }

  void _applyLoadedConfig(AppPublicConfig config) {
    _cachedConfig = config;
    _hasLoadedConfig = true;
    _hasResolvedLoadThisSession = true;
    _logLoadedConfig(config);
  }

  void _logReadFailure(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        AppLog.throttledInfo(
          'public-config-denied',
          'App public config read denied; using cached/default config.',
        );
      } else {
        AppLog.error('App public config read failed: ${error.code}');
      }
      return;
    }
    AppLog.error('App public config read failed: $error');
  }

  void _logTimeout() {
    if (_timeoutLoggedThisSession) return;
    _timeoutLoggedThisSession = true;
    AppLog.info(
      'App public config read timed out; using cached/default config.',
    );
  }

  void _logLoadedConfig(AppPublicConfig config) {
    if (_loadedLoggedThisSession) return;
    _loadedLoggedThisSession = true;
    AppLog.info(
      'App public config loaded: '
      'maintenanceMode=${config.maintenanceMode}, '
      'adsEnabled=${config.adsEnabled}, '
      'sponsoredCardsEnabled=${config.sponsoredCardsEnabled}, '
      'fullscreenAdsEnabled=${config.fullscreenAdsEnabled}, '
      'featuredPlacesEnabled=${config.featuredPlacesEnabled}',
    );
  }
}
