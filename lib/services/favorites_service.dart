import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:halaph/models/destination.dart';
import 'package:halaph/services/firebase_app_service.dart';
import 'package:halaph/services/favorites_notifier.dart';
import 'package:halaph/services/friend_service.dart';
import 'package:halaph/services/remote_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  // ignore: unused_field
  static const _key = 'favorite_destinations';
  static const _localIdsKeyPrefix = 'favorite_destinations_ids';
  static const _localPlacesKeyPrefix = 'favorite_destinations_places';
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;
  FavoritesService._internal();

  String? _cachedUserId;
  List<String>? _cachedIds;
  Map<String, Destination>? _cachedDestinations;
  Future<List<String>>? _loadInFlight;
  String? _loadInFlightScope;

  Future<List<String>> getFavorites({bool forceRefresh = false}) async {
    final userId = await _currentUserId();
    final cacheScope = _cacheScope(userId);

    if (!forceRefresh && _cachedUserId == cacheScope && _cachedIds != null) {
      return List<String>.from(_cachedIds!);
    }
    if (!forceRefresh &&
        _loadInFlightScope == cacheScope &&
        _loadInFlight != null) {
      return _loadInFlight!;
    }

    final future = _loadFavoritesForScope(userId, cacheScope);
    _loadInFlight = future;
    _loadInFlightScope = cacheScope;
    return future.whenComplete(() {
      if (identical(_loadInFlight, future)) {
        _loadInFlight = null;
        _loadInFlightScope = null;
      }
    });
  }

  Future<List<String>> _loadFavoritesForScope(
    String? userId,
    String cacheScope,
  ) async {
    if (userId == null) {
      return _loadLocalFavorites(scope: _localScope(null));
    }

    final payload = await RemoteSyncService.instance.loadNamespace('favorites');
    if (payload == null) {
      return _loadLocalFavorites(scope: _localScope(userId));
    }

    final ids = payload['ids'] is List
        ? List<String>.from(payload['ids'])
        : const <String>[];
    _cachedUserId = cacheScope;
    _cachedIds = <String>{...ids}.toList();
    _cachedDestinations = _parseDestinations(payload['places']);
    unawaited(
      _saveLocalFavorites(
        _cachedIds!,
        destinations: _cachedDestinations,
        scope: _localScope(userId),
      ),
    );
    unawaited(
      FriendService()
          .publishFavoritePlaces(_orderedCachedDestinations())
          .catchError((_) {}),
    );
    return List<String>.from(_cachedIds!);
  }

  Future<List<Destination>> getFavoriteDestinations({
    bool forceRefresh = false,
  }) async {
    final ids = await getFavorites(forceRefresh: forceRefresh);
    final byId = _cachedDestinations ?? const <String, Destination>{};
    return ids
        .map((id) => byId[id])
        .whereType<Destination>()
        .toList(growable: false);
  }

  Future<void> setFavorites(
    List<String> ids, {
    Map<String, Destination>? destinations,
  }) async {
    final deduped = <String>{...ids}.toList();
    final sourceDestinations = destinations ?? _cachedDestinations ?? {};
    final savedDestinations = <String, Destination>{
      for (final id in deduped)
        if (sourceDestinations[id] != null) id: sourceDestinations[id]!,
    };

    final saved = await _persistFavorites(deduped, savedDestinations);
    if (!saved) {
      throw StateError('Could not save favorites');
    }
  }

  Future<bool> addFavorite(Destination destination) async {
    final favoriteId = destination.id.trim();
    if (favoriteId.isEmpty) return false;

    final ids = await getFavorites();
    final destinations = Map<String, Destination>.from(
      _cachedDestinations ?? const <String, Destination>{},
    );

    if (!ids.contains(favoriteId)) {
      ids.add(favoriteId);
    }
    destinations[favoriteId] = destination;

    return _persistFavorites(ids, destinations);
  }

  Future<bool> removeFavorite(String id) async {
    final favoriteId = id.trim();
    if (favoriteId.isEmpty) return false;

    final ids = await getFavorites();
    if (!ids.contains(favoriteId)) return true;

    final nextIds = ids.where((item) => item != favoriteId).toList();
    final nextDestinations = Map<String, Destination>.from(
      _cachedDestinations ?? const <String, Destination>{},
    )..remove(favoriteId);
    return _persistFavorites(nextIds, nextDestinations);
  }

  Future<bool> toggleFavorite(Destination destination) async {
    final ids = await getFavorites();
    if (ids.contains(destination.id)) {
      final removed = await removeFavorite(destination.id);
      if (!removed) {
        throw StateError('Could not remove favorite ${destination.id}');
      }
      return false;
    }

    final added = await addFavorite(destination);
    if (!added) {
      throw StateError('Could not add favorite ${destination.id}');
    }
    return true;
  }

  Future<bool> toggleFavoriteDestination(Destination destination) {
    return toggleFavorite(destination);
  }

  Future<bool> isFavorite(String id) async {
    final ids = await getFavorites();
    return ids.contains(id);
  }

  void clearCache() {
    _cachedUserId = null;
    _cachedIds = null;
    _cachedDestinations = null;
    _loadInFlight = null;
    _loadInFlightScope = null;
  }

  Future<bool> _persistFavorites(
    List<String> ids,
    Map<String, Destination> destinations,
  ) async {
    final userId = await _currentUserId();
    final cacheScope = _cacheScope(userId);
    final deduped = <String>{...ids}.toList();
    final savedDestinations = <String, Destination>{
      for (final id in deduped)
        if (destinations[id] != null) id: destinations[id]!,
    };
    if (_favoritesMatchCurrentCache(
      cacheScope,
      deduped,
      savedDestinations,
    )) {
      return true;
    }

    if (userId != null) {
      final savedRemotely = await RemoteSyncService.instance.saveNamespace(
        'favorites',
        {
          'ids': deduped,
          'places': savedDestinations.values
              .map((destination) => destination.toJson())
              .toList(),
        },
      );
      if (!savedRemotely) return false;
    }

    final savedLocally = await _saveLocalFavoritesWithResult(
      deduped,
      destinations: savedDestinations,
      scope: _localScope(userId),
    );
    if (!savedLocally && userId == null) return false;

    _cachedUserId = cacheScope;
    _cachedIds = deduped;
    _cachedDestinations = savedDestinations;

    if (userId != null) {
      unawaited(
        FriendService()
            .publishFavoritePlaces(_orderedCachedDestinations())
            .catchError((_) {}),
      );
    }

    FavoritesNotifier().notifyFavoritesChanged();
    return true;
  }

  Future<List<String>> _loadLocalFavorites({required String scope}) async {
    List<String> ids = const <String>[];
    String? placesJson;

    try {
      final localStore = SharedPreferencesAsync();
      ids = await localStore.getStringList(_localIdsKey(scope)) ??
          const <String>[];
      placesJson = await localStore.getString(_localPlacesKey(scope));
    } catch (_) {
      // SharedPreferences is unavailable in some test environments.
    }

    _cachedUserId = _cacheScopeForLocal(scope);
    _cachedIds = <String>{...ids}.toList();
    _cachedDestinations = _parseLocalDestinations(placesJson);
    return List<String>.from(_cachedIds!);
  }

  bool _favoritesMatchCurrentCache(
    String cacheScope,
    List<String> ids,
    Map<String, Destination> destinations,
  ) {
    if (_cachedUserId != cacheScope || _cachedIds == null) return false;
    if (_cachedIds!.length != ids.length) return false;
    for (var index = 0; index < ids.length; index++) {
      if (_cachedIds![index] != ids[index]) return false;
    }
    final cachedDestinations =
        _cachedDestinations ?? const <String, Destination>{};
    if (cachedDestinations.length != destinations.length) return false;
    for (final entry in destinations.entries) {
      final cached = cachedDestinations[entry.key];
      if (cached == null ||
          jsonEncode(cached.toJson()) != jsonEncode(entry.value.toJson())) {
        return false;
      }
    }
    return true;
  }

  Future<void> _saveLocalFavorites(
    List<String> ids, {
    required Map<String, Destination>? destinations,
    required String scope,
  }) async {
    await _saveLocalFavoritesWithResult(
      ids,
      destinations: destinations,
      scope: scope,
    );
  }

  Future<bool> _saveLocalFavoritesWithResult(
    List<String> ids, {
    required Map<String, Destination>? destinations,
    required String scope,
  }) async {
    final deduped = <String>{...ids}.toList();
    final places = (destinations ?? const <String, Destination>{})
        .values
        .map((destination) => destination.toJson())
        .toList();

    try {
      final localStore = SharedPreferencesAsync();
      await localStore.setStringList(_localIdsKey(scope), deduped);
      await localStore.setString(_localPlacesKey(scope), jsonEncode(places));
      return true;
    } catch (_) {
      // SharedPreferences is unavailable in some test environments.
      return false;
    }
  }

  Map<String, Destination> _parseLocalDestinations(String? placesJson) {
    if (placesJson == null || placesJson.isEmpty) {
      return <String, Destination>{};
    }

    try {
      final decoded = jsonDecode(placesJson);
      return _parseDestinations(decoded);
    } catch (_) {
      return <String, Destination>{};
    }
  }

  String _cacheScope(String? userId) {
    return userId == null
        ? _cacheScopeForLocal(_localScope(null))
        : 'remote:$userId';
  }

  String _cacheScopeForLocal(String scope) {
    return 'local:$scope';
  }

  String _localScope(String? userId) {
    return userId == null ? 'guest' : 'user_$userId';
  }

  String _localIdsKey(String scope) {
    return '${_localIdsKeyPrefix}_$scope';
  }

  String _localPlacesKey(String scope) {
    return '${_localPlacesKeyPrefix}_$scope';
  }

  Future<String?> _currentUserId() async {
    if (!await FirebaseAppService.initialize()) return null;
    return firebase_auth.FirebaseAuth.instance.currentUser?.uid;
  }

  List<Destination> _orderedCachedDestinations() {
    final ids = _cachedIds ?? const <String>[];
    final byId = _cachedDestinations ?? const <String, Destination>{};
    return ids
        .map((id) => byId[id])
        .whereType<Destination>()
        .toList(growable: false);
  }

  Map<String, Destination> _parseDestinations(Object? rawPlaces) {
    if (rawPlaces is! List) return <String, Destination>{};
    final places = <String, Destination>{};
    for (final rawPlace in rawPlaces) {
      if (rawPlace is! Map) continue;
      try {
        final destination = Destination.fromJson(
          Map<String, dynamic>.from(rawPlace),
        );
        places[destination.id] = destination;
      } catch (_) {}
    }
    return places;
  }
}
