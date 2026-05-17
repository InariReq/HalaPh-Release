import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:halaph/models/app_public_config.dart';
import 'package:halaph/utils/app_log.dart';

class AppPublicConfigService {
  static const Duration _readTimeout = Duration(seconds: 4);
  static AppPublicConfig _cachedConfig = const AppPublicConfig.defaults();
  static bool _hasLoadedConfig = false;
  static Future<AppPublicConfig>? _loadInFlight;
  static StreamController<AppPublicConfig>? _watchController;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _watchSubscription;

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
    if (_hasLoadedConfig) {
      scheduleMicrotask(() => controller.add(_cachedConfig));
    }
    _watchSubscription ??= _document.snapshots().listen(
      (snapshot) {
        final config = AppPublicConfig.fromSnapshot(snapshot);
        _cachedConfig = config;
        _hasLoadedConfig = true;
        _logLoadedConfig(config);
        controller.add(config);
      },
      onError: (Object error) {
        if (error is FirebaseException && error.code == 'permission-denied') {
          AppLog.throttledInfo(
            'public-config-watch-denied',
            'App public config watch permission-denied; using cached/default config.',
          );
        } else {
          AppLog.error('App public config watch failed: $error');
        }
        controller.add(_cachedConfig);
      },
    );
    return controller.stream;
  }

  Future<AppPublicConfig> loadPublicConfig({bool forceRefresh = false}) {
    if (!forceRefresh && _hasLoadedConfig) {
      return Future.value(_cachedConfig);
    }
    final inFlight = _loadInFlight;
    if (!forceRefresh && inFlight != null) return inFlight;

    final future = _fetchPublicConfig();
    _loadInFlight = future;
    return future.whenComplete(() {
      if (identical(_loadInFlight, future)) {
        _loadInFlight = null;
      }
    });
  }

  Future<AppPublicConfig> _fetchPublicConfig() async {
    try {
      final snapshot = await _document
          .get(const GetOptions(source: Source.server))
          .timeout(_readTimeout);
      final config = AppPublicConfig.fromSnapshot(snapshot);
      _cachedConfig = config;
      _hasLoadedConfig = true;
      _logLoadedConfig(config);
      return config;
    } on TimeoutException {
      AppLog.throttledInfo(
        'public-config-timeout',
        'App public config read timed out; using cached/default config.',
      );
      return _cachedConfig;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        AppLog.throttledInfo(
          'public-config-denied',
          'App public config read denied; using cached/default config.',
        );
      } else {
        AppLog.error('App public config read failed: ${error.code}');
      }
      return _cachedConfig;
    } catch (error) {
      AppLog.error('App public config read failed: $error');
      return _cachedConfig;
    }
  }

  void _logLoadedConfig(AppPublicConfig config) {
    AppLog.throttledInfo(
      'public-config-loaded',
      'App public config loaded: '
          'maintenanceMode=${config.maintenanceMode}, '
          'adsEnabled=${config.adsEnabled}, '
          'sponsoredCardsEnabled=${config.sponsoredCardsEnabled}, '
          'fullscreenAdsEnabled=${config.fullscreenAdsEnabled}, '
          'featuredPlacesEnabled=${config.featuredPlacesEnabled}',
    );
  }
}
