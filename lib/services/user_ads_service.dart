import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:halaph/models/sponsored_ad.dart';
import 'package:halaph/utils/app_log.dart';

class UserAdsService {
  static const Duration _readTimeout = Duration(seconds: 4);
  static const Duration _cacheTtl = Duration(minutes: 5);
  static List<SponsoredAd>? _cachedSponsoredCards;
  static DateTime? _sponsoredCardsCachedAt;
  static Future<List<SponsoredAd>>? _sponsoredCardsLoadInFlight;
  static Future<List<SponsoredAd>>? _sponsoredCardsReadInFlight;
  static Completer<List<SponsoredAd>>? _sponsoredCardsFirstValueCompleter;
  static Future<List<SponsoredAd>>? _sponsoredCardsWatchFuture;
  static StreamController<List<SponsoredAd>>? _sponsoredCardsController;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _sponsoredCardsSubscription;

  final FirebaseFirestore _firestore;

  UserAdsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(SponsoredAd.collectionPath);

  Stream<List<SponsoredAd>> watchSponsoredCards() {
    final controller = _sponsoredCardsController ??=
        StreamController<List<SponsoredAd>>.broadcast();
    final firstWatchValue =
        _sponsoredCardsFirstValueCompleter ??= Completer<List<SponsoredAd>>();
    _sponsoredCardsWatchFuture ??= firstWatchValue.future.timeout(
      _readTimeout,
      onTimeout: () => _fallbackSponsoredCards(logTimeout: true),
    );
    final cached = _freshSponsoredCards;
    if (cached != null) {
      scheduleMicrotask(() => controller.add(cached));
    }
    _sponsoredCardsSubscription ??= _collection.snapshots().listen(
      (snapshot) {
        final ads = _filterAndSortSponsoredAds(snapshot.docs);
        _cacheSponsoredCards(ads);
        if (!firstWatchValue.isCompleted) {
          firstWatchValue.complete(ads);
        }
        controller.add(ads);
      },
      onError: (Object error) {
        if (error is FirebaseException && error.code == 'permission-denied') {
          AppLog.throttledInfo(
            'sponsored-watch-denied',
            'Sponsored ads permission-denied; hiding cards.',
          );
        } else {
          AppLog.error('Sponsored ads watch failed: $error');
        }
        final fallback = _fallbackSponsoredCards();
        if (!firstWatchValue.isCompleted) {
          firstWatchValue.complete(fallback);
        }
        controller.add(fallback);
      },
    );
    return controller.stream;
  }

  List<SponsoredAd> _filterAndSortSponsoredAds(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return _filterAndSortAds(docs, SponsoredAd.sponsoredCardPlacement);
  }

  List<SponsoredAd> _filterAndSortFullscreenAds(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return _filterAndSortAds(docs, SponsoredAd.fullscreenPlacement);
  }

  List<SponsoredAd> _filterAndSortAds(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String placement,
  ) {
    final now = DateTime.now();
    final ads = <SponsoredAd>[];

    for (final doc in docs) {
      try {
        final ad = SponsoredAd.fromSnapshot(doc);
        final skipReason = _skipReason(ad, placement, now);
        if (skipReason == null) {
          ads.add(ad);
        } else {
          AppLog.throttledInfo(
            'sponsored-card-skip-${doc.id}-$skipReason',
            'Skipping admin ad ${doc.id}: $skipReason',
          );
        }
      } catch (error) {
        AppLog.error('Skipping admin ad ${doc.id}: invalid data: $error');
      }
    }

    ads.sort((a, b) {
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    AppLog.throttledInfo(
      'sponsored-ads-loaded-$placement',
      'Sponsored ads loaded for $placement: ${ads.length}',
    );
    return ads;
  }

  String? _skipReason(SponsoredAd ad, String placement, DateTime now) {
    if (!ad.isActive) {
      return 'inactive or status is not active';
    }
    if (!ad.matchesPlacement(placement)) {
      return 'placement "${ad.placement}" does not match $placement';
    }
    final starts = ad.startsAt;
    if (starts != null && starts.isAfter(now)) {
      return 'startsAt is in the future';
    }
    final ends = ad.endsAt;
    if (ends != null && ends.isBefore(now)) {
      return 'endsAt is in the past';
    }
    return null;
  }

  Future<List<SponsoredAd>> loadFullscreenAds() async {
    try {
      AppLog.throttledInfo(
        'fullscreen-ads-query',
        'Fullscreen ads query started',
      );
      final snapshot = await _collection
          .get(const GetOptions(source: Source.server))
          .timeout(_readTimeout);
      final ads = _filterAndSortFullscreenAds(snapshot.docs);
      AppLog.throttledInfo(
        'fullscreen-ads-loaded',
        'Fullscreen ads loaded: ${ads.length}',
      );
      return ads;
    } on TimeoutException {
      AppLog.throttledInfo(
        'fullscreen-ads-timeout',
        'Fullscreen ads read timed out; hiding ads.',
      );
      return const [];
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        AppLog.throttledInfo(
          'fullscreen-ads-denied',
          'Fullscreen ads permission-denied; hiding ads.',
        );
      } else {
        AppLog.error('Fullscreen ads read failed: ${error.code}');
      }
      return const [];
    } on FormatException catch (error) {
      AppLog.error('Fullscreen ads data invalid; hiding ads: $error');
      return const [];
    } catch (error) {
      AppLog.error('Fullscreen ads read failed: $error');
      return const [];
    }
  }

  Future<List<SponsoredAd>> loadSponsoredCards({
    bool forceRefresh = false,
  }) {
    final cached = _freshSponsoredCards;
    if (!forceRefresh && cached != null) {
      return Future.value(cached);
    }
    final readInFlight = _sponsoredCardsReadInFlight;
    if (!forceRefresh && readInFlight != null) {
      return _sponsoredCardsLoadInFlight ??
          Future.value(_fallbackSponsoredCards());
    }
    final inFlight = _sponsoredCardsLoadInFlight;
    if (!forceRefresh && inFlight != null) return inFlight;

    final watchFuture = _sponsoredCardsWatchFuture;
    if (!forceRefresh && watchFuture != null) {
      return watchFuture;
    }

    final future = _fetchSponsoredCards();
    _sponsoredCardsLoadInFlight = future;
    return future;
  }

  Future<List<SponsoredAd>> _fetchSponsoredCards() {
    AppLog.throttledInfo(
      'sponsored-cards-query',
      'Sponsored cards query started',
      interval: _cacheTtl,
    );
    final source = _collection
        .get(const GetOptions(source: Source.server))
        .then((snapshot) {
      final ads = _filterAndSortSponsoredAds(snapshot.docs);
      _cacheSponsoredCards(ads);
      return ads;
    });
    _sponsoredCardsReadInFlight = source;
    unawaited(
      source
          .then<void>(
        (_) {},
        onError: (_) {},
      )
          .whenComplete(() {
        if (identical(_sponsoredCardsReadInFlight, source)) {
          _sponsoredCardsReadInFlight = null;
          _sponsoredCardsLoadInFlight = null;
        }
      }),
    );

    return source.timeout(
      _readTimeout,
      onTimeout: () {
        final fallback = _fallbackSponsoredCards(logTimeout: true);
        unawaited(
          source.catchError((Object error) {
            _logSponsoredCardsReadFailure(error);
            return fallback;
          }),
        );
        return fallback;
      },
    ).catchError((Object error) {
      _logSponsoredCardsReadFailure(error);
      return _fallbackSponsoredCards();
    });
  }

  List<SponsoredAd>? get _freshSponsoredCards {
    final cachedAt = _sponsoredCardsCachedAt;
    final cached = _cachedSponsoredCards;
    if (cachedAt == null || cached == null) return null;
    if (DateTime.now().difference(cachedAt) > _cacheTtl) return null;
    return cached;
  }

  void _cacheSponsoredCards(List<SponsoredAd> ads) {
    _cachedSponsoredCards = List<SponsoredAd>.unmodifiable(ads);
    _sponsoredCardsCachedAt = DateTime.now();
  }

  List<SponsoredAd> _fallbackSponsoredCards({bool logTimeout = false}) {
    if (logTimeout) {
      AppLog.throttledInfo(
        'sponsored-cards-timeout',
        'Sponsored cards read timed out; showing cached cards if available.',
        interval: _cacheTtl,
      );
    }
    final fallback = _cachedSponsoredCards ?? const <SponsoredAd>[];
    _cacheSponsoredCards(fallback);
    return _cachedSponsoredCards!;
  }

  void _logSponsoredCardsReadFailure(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        AppLog.throttledInfo(
          'sponsored-cards-denied',
          'Sponsored cards permission-denied; hiding cards.',
          interval: _cacheTtl,
        );
      } else {
        AppLog.error('Sponsored cards read failed: ${error.code}');
      }
      return;
    }
    if (error is FormatException) {
      AppLog.error('Sponsored cards data invalid; hiding cards: $error');
      return;
    }
    AppLog.error('Sponsored cards read failed: $error');
  }
}
