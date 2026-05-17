import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/services/google_maps_service.dart';
import 'package:halaph/services/user_admin_locations_service.dart';
import 'package:halaph/utils/dev_mode.dart';
import 'package:halaph/utils/place_display_name_utils.dart';
import 'package:halaph/utils/app_log.dart';

class DestinationService {
  static const LatLng _defaultSearchLocation = LatLng(14.5995, 120.9842);
  static const Duration _locationSearchTimeout = Duration(seconds: 4);
  static const Duration _placesSearchTimeout = Duration(seconds: 10);
  static String get _googleApiKey => (dotenv.env['MAPS_API_KEY'] ?? '').trim();

  static LatLng? _cachedLocation;
  static DateTime? _locationCacheTime;
  static const _cacheValidity = Duration(minutes: 30);
  static const Duration _trendingCacheValidity = Duration(minutes: 5);
  static List<Destination>? _cachedTrendingDestinations;
  static DateTime? _trendingCacheTime;
  static Future<List<Destination>>? _trendingLoadInFlight;
  static bool _useTestLocation = false;
  static LatLng? _manualTestLocation;
  static final Map<String, String> _imageUrlCache = {};
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _cachedDestinationsCollection = 'cached_destinations';
  static const Duration _cachedDestinationWriteDebounce = Duration(seconds: 15);
  static final Map<String, String> _cachedDestinationSessionFingerprints = {};
  static final Map<String, DateTime> _cachedDestinationLastAttempts = {};
  static final Map<String, String> _cachedDestinationLastAttemptFingerprints =
      {};
  static final Set<String> _cachedDestinationUpsertsInFlight = {};

  // Popular malls in the Philippines with their coordinates
  static final List<Destination> _popularMalls = [
    Destination(
      id: 'sm_trinoma',
      name: 'TriNoma',
      description:
          'Major shopping mall in Quezon City with over 300 shops, restaurants, and a cinema.',
      location: 'EDSA corner North Avenue, Quezon City',
      coordinates: const LatLng(14.6536, 121.0334),
      imageUrl: '',
      category: DestinationCategory.malls,
      rating: 0.0,
      tags: ['shopping', 'dining', 'cinema', 'SM Supermalls'],
    ),
    Destination(
      id: 'sm_moa',
      name: 'SM Mall of Asia',
      description:
          'One of the largest malls in Asia with shopping, dining, entertainment, and an ice skating rink.',
      location: 'Seaside Blvd, Pasay City, Metro Manila',
      coordinates: const LatLng(14.5352, 120.9829),
      imageUrl: '',
      category: DestinationCategory.malls,
      rating: 4.6,
      tags: [
        'shopping',
        'dining',
        'entertainment',
        'SM Supermalls',
        'ice skating'
      ],
    ),
    Destination(
      id: 'sm_megamall',
      name: 'SM Megamall',
      description:
          'Large shopping mall in Ortigas Center with diverse retail stores and restaurants.',
      location: 'EDSA corner Julia Vargas Avenue, Mandaluyong City',
      coordinates: const LatLng(14.5842, 121.0564),
      imageUrl: '',
      category: DestinationCategory.malls,
      rating: 0.0,
      tags: ['shopping', 'dining', 'SM Supermalls'],
    ),
    Destination(
      id: 'ayala_glorietta',
      name: 'Ayala Malls Glorietta',
      description:
          'Upscale shopping mall complex in Makati with luxury brands and fine dining.',
      location: 'Ayala Center, Makati City',
      coordinates: const LatLng(14.5518, 121.0244),
      imageUrl: '',
      category: DestinationCategory.malls,
      rating: 4.6,
      tags: ['luxury shopping', 'fine dining', 'Ayala Malls'],
    ),
    Destination(
      id: 'robinsons_manila',
      name: 'Robinsons Place Manila',
      description:
          'Major shopping mall in Manila with a wide variety of retail and dining options.',
      location: 'Pedro Gil corner Adriatico Street, Manila',
      coordinates: const LatLng(14.5726, 120.9943),
      imageUrl: '',
      category: DestinationCategory.malls,
      rating: 4.4,
      tags: ['shopping', 'dining', 'Robinsons Malls'],
    ),
    Destination(
      id: 'sm_north',
      name: 'SM North EDSA',
      description:
          'One of the oldest and largest malls in the Philippines located in Quezon City.',
      location: 'EDSA, Quezon City, Metro Manila',
      coordinates: const LatLng(14.6554, 121.0289),
      imageUrl: '',
      category: DestinationCategory.malls,
      rating: 0.0,
      tags: ['shopping', 'dining', 'cinema', 'SM Supermalls'],
    ),
    Destination(
      id: 'greenbelt',
      name: 'Greenbelt Mall',
      description:
          'Premium shopping and dining destination in Makati with landscaped gardens.',
      location: 'Ayala Center, Makati City',
      coordinates: const LatLng(14.5500, 121.0255),
      imageUrl: '',
      category: DestinationCategory.malls,
      rating: 4.7,
      tags: ['luxury shopping', 'fine dining', 'Ayala Malls', 'gardens'],
    ),
    Destination(
      id: 'sm_aura',
      name: 'SM Aura Premier',
      description:
          'Upscale shopping mall in Taguig with high-end brands and dining options.',
      location:
          '26th Street corner McKinley Parkway, Bonifacio Global City, Taguig',
      coordinates: const LatLng(14.5493, 121.0505),
      imageUrl: '',
      category: DestinationCategory.malls,
      rating: 4.6,
      tags: ['luxury shopping', 'dining', 'SM Supermalls', 'BGC'],
    ),
  ];

  static String? get placesProviderError => null;

  static Future<LatLng> getCurrentLocation() async {
    try {
      if (_useTestLocation && _manualTestLocation != null) {
        return _manualTestLocation!;
      }
      final cachedAt = _locationCacheTime;
      if (_cachedLocation != null &&
          cachedAt != null &&
          DateTime.now().difference(cachedAt) < _cacheValidity) {
        return _cachedLocation!;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return _defaultSearchLocation;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return _defaultSearchLocation;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return _defaultSearchLocation;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      ).timeout(const Duration(seconds: 10));

      _cachedLocation = LatLng(position.latitude, position.longitude);
      _locationCacheTime = DateTime.now();
      return _cachedLocation!;
    } catch (_) {
      return _cachedLocation ?? _defaultSearchLocation;
    }
  }

  static void setTestLocation(double lat, double lng) {
    _useTestLocation = true;
    _manualTestLocation = LatLng(lat, lng);
    debugPrint('Test location set: $lat, $lng');
  }

  static void clearTestLocation() {
    _useTestLocation = false;
    _manualTestLocation = null;
    _cachedLocation = null;
    _locationCacheTime = null;
    debugPrint('Test location cleared');
  }

  static Future<List<Destination>> searchDestinations(String? query) async {
    final trimmed = query?.trim() ?? '';
    final queryLower = trimmed.toLowerCase();
    final hasTypedQuery = trimmed.isNotEmpty;
    final location = await _getSearchLocation();
    final adminLocations =
        await UserAdminLocationsService.getActiveLocations(query: trimmed);

    // Typed searches should come from Google Places, not hardcoded fallback data.
    // Keep hardcoded malls only for empty/default discovery.
    final List<Destination> allDestinations =
        hasTypedQuery && DevModeService.allowPaidGoogleApis
            ? <Destination>[]
            : [..._popularMalls];
    allDestinations.addAll(adminLocations);

    final isMallQuery = queryLower.contains('mall') ||
        queryLower.contains('shopping') ||
        queryLower.contains('sm ') ||
        queryLower.contains('ayala') ||
        queryLower.contains('robinsons') ||
        queryLower.contains('trinoma') ||
        queryLower.contains('megamall') ||
        queryLower.contains('glorietta') ||
        queryLower.contains('greenbelt') ||
        queryLower.contains('aura');

    if (!DevModeService.allowPaidGoogleApis) {
      final localDestinations = hasTypedQuery
          ? allDestinations.where((destination) {
              final searchable = [
                destination.name,
                destination.location,
                destination.description,
                destination.tags.join(' '),
              ].join(' ').toLowerCase();
              return searchable.contains(queryLower);
            }).toList()
          : allDestinations;

      return _rankAndLimit(localDestinations, location, limit: 5);
    }

    try {
      final googleResults = await _searchPlaces(
        query: hasTypedQuery ? trimmed : 'tourist attractions in Manila',
        location: location,
        limit: 5,
      ).timeout(_placesSearchTimeout, onTimeout: () => <Destination>[]);

      allDestinations.addAll(googleResults);
    } catch (e) {
      debugPrint('Google search error: $e');
    }

    if (isMallQuery) {
      allDestinations.sort((a, b) {
        if (a.category == DestinationCategory.malls &&
            b.category != DestinationCategory.malls) {
          return -1;
        }
        if (a.category != DestinationCategory.malls &&
            b.category == DestinationCategory.malls) {
          return 1;
        }
        return 0;
      });
    }

    final ranked = _rankAndLimit(allDestinations, location, limit: 5);
    return _hydrateMissingImages(ranked, location, maxHydration: 5);
  }

  static Future<List<Destination>> getTrendingDestinations({
    bool forceRefresh = false,
  }) {
    final cached = _freshTrendingDestinations;
    if (!forceRefresh && cached != null) {
      return Future.value(cached);
    }
    final inFlight = _trendingLoadInFlight;
    if (!forceRefresh && inFlight != null) return inFlight;

    final future = _fetchTrendingDestinations();
    _trendingLoadInFlight = future;
    return future.whenComplete(() {
      if (identical(_trendingLoadInFlight, future)) {
        _trendingLoadInFlight = null;
      }
    });
  }

  static Future<List<Destination>> _fetchTrendingDestinations() async {
    try {
      // Start with popular malls
      final adminLocations =
          await UserAdminLocationsService.getActiveLocations();
      final List<Destination> trending = [...adminLocations, ..._popularMalls];

      final location = await _getSearchLocation();

      if (!DevModeService.allowPaidGoogleApis) {
        return _cacheTrending(_rankAndLimit(trending, location, limit: 5));
      }

      final places = await _discoverPlaces(location);
      trending.addAll(places);

      final ranked = _rankAndLimit(trending, location, limit: 5);
      return _cacheTrending(
        await _hydrateMissingImages(ranked, location, maxHydration: 5),
      );
    } catch (e) {
      debugPrint('Error fetching trending destinations: $e');
      return _cachedTrendingDestinations ??
          _popularMalls; // Fallback to saved or local data.
    }
  }

  static List<Destination>? get _freshTrendingDestinations {
    final cached = _cachedTrendingDestinations;
    final cachedAt = _trendingCacheTime;
    if (cached == null || cachedAt == null) return null;
    if (DateTime.now().difference(cachedAt) > _trendingCacheValidity) {
      return null;
    }
    return cached;
  }

  static List<Destination> _cacheTrending(List<Destination> destinations) {
    _cachedTrendingDestinations = List<Destination>.unmodifiable(destinations);
    _trendingCacheTime = DateTime.now();
    return _cachedTrendingDestinations!;
  }

  static Future<List<Destination>> searchRealPlaces({
    required String query,
    LatLng? location,
    DestinationCategory? category,
  }) async {
    final searchLocation = location ?? await _getSearchLocation();
    final adminLocations = await UserAdminLocationsService.getActiveLocations(
      query: query,
      category: category,
    );

    if (!DevModeService.allowPaidGoogleApis) {
      final localDestinations =
          [...adminLocations, ..._popularMalls].where((destination) {
        final searchable = [
          destination.name,
          destination.location,
          destination.description,
          destination.tags.join(' '),
        ].join(' ').toLowerCase();
        return searchable.contains(query.toLowerCase());
      }).where((destination) {
        return category == null || destination.category == category;
      }).toList();

      return _rankAndLimit(localDestinations, searchLocation, limit: 5);
    }

    final searchQuery = _queryFor(query, category);
    final places = await _searchPlaces(
      query: searchQuery,
      location: searchLocation,
      limit: 5,
    );
    final filtered = category == null
        ? places
        : places.where((place) => place.category == category).toList();
    return _rankAndLimit(
      [...adminLocations, ...filtered],
      searchLocation,
      limit: 5,
    );
  }

  static Future<void> cacheDestinationForAdminFeature(
    Destination destination, {
    String source = 'app_search',
  }) async {
    await _upsertCachedDestination(destination, source: source);
  }

  static Future<List<String>> getAutocompleteSuggestions(
    String input, {
    LatLng? location,
  }) async {
    try {
      final trimmed = input.trim();
      if (trimmed.length < 2) return [];
      final searchLocation = location ?? await _getSearchLocation();
      final places = await _searchPlaces(
        query: trimmed,
        location: searchLocation,
        limit: 5,
      );
      final labels = <String>[];
      final seen = <String>{};
      for (final place in places) {
        final label = place.location.trim().isEmpty
            ? place.name
            : '${place.name}, ${place.location}';
        if (seen.add(label.toLowerCase())) {
          labels.add(label);
        }
      }
      return labels.take(5).toList(growable: false);
    } catch (e) {
      debugPrint('Error getting autocomplete: $e');
      return <String>[];
    }
  }

  static List<Destination> deduplicateDestinationsById(List<Destination> list) {
    final out = <Destination>[];

    for (final destination in list) {
      final duplicateIndex = out.indexWhere(
        (existing) => _areDuplicateDestinations(existing, destination),
      );

      if (duplicateIndex == -1) {
        out.add(destination);
        continue;
      }

      final existing = out[duplicateIndex];
      if (_imagePriority(destination.imageUrl) >
          _imagePriority(existing.imageUrl)) {
        out[duplicateIndex] = destination;
      }
    }

    return out;
  }

  static bool _areDuplicateDestinations(
    Destination a,
    Destination b,
  ) {
    if (a.id.trim().isNotEmpty && a.id == b.id) return true;

    final aName = _normalizeDestinationName(a.name);
    final bName = _normalizeDestinationName(b.name);

    if (aName.isNotEmpty && bName.isNotEmpty) {
      if (aName == bName) return true;
      if (_nameSimilarity(aName, bName) >= 0.72 && _areCoordinatesClose(a, b)) {
        return true;
      }
    }

    return _areCoordinatesClose(a, b) && a.category == b.category;
  }

  static bool _areCoordinatesClose(Destination a, Destination b) {
    final aCoords = a.coordinates;
    final bCoords = b.coordinates;
    if (aCoords == null || bCoords == null) return false;

    return calculateDistance(aCoords, bCoords) <= 0.15;
  }

  static double _nameSimilarity(String a, String b) {
    final aWords = a.split(' ').where((word) => word.isNotEmpty).toSet();
    final bWords = b.split(' ').where((word) => word.isNotEmpty).toSet();

    if (aWords.isEmpty || bWords.isEmpty) return 0;

    final shared = aWords.intersection(bWords).length;
    final total = aWords.union(bWords).length;

    return shared / total;
  }

  static double calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371;
    final lat1Rad = point1.latitude * (pi / 180);
    final lat2Rad = point2.latitude * (pi / 180);
    final deltaLatRad = (point2.latitude - point1.latitude) * (pi / 180);
    final deltaLngRad = (point2.longitude - point1.longitude) * (pi / 180);

    final a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) *
            cos(lat2Rad) *
            sin(deltaLngRad / 2) *
            sin(deltaLngRad / 2);
    final c = 2 * asin(sqrt(a).clamp(0.0, 1.0));
    return earthRadius * c;
  }

  static bool isInvalidLocation(LatLng location) {
    return location.latitude == 0 && location.longitude == 0;
  }

  static String getCategoryName(DestinationCategory category) {
    return switch (category) {
      DestinationCategory.park => 'Parks',
      DestinationCategory.landmark => 'Landmarks',
      DestinationCategory.food => 'Food',
      DestinationCategory.activities => 'Activities',
      DestinationCategory.museum => 'Museums',
      DestinationCategory.malls => 'Malls',
    };
  }

  static Future<List<Destination>> _discoverPlaces(LatLng location) async {
    final isRealLocation = !isInvalidLocation(location);
    final searchLocation = isRealLocation ? location : _defaultSearchLocation;
    final results = <Destination>[];

    // Query for each category to ensure all types appear
    final categoryQueries = [
      'tourist attractions landmarks',
      'restaurants cafes food',
      'parks gardens',
      'museums galleries',
      'shopping malls',
      'activities entertainment',
    ];

    for (final query in categoryQueries) {
      try {
        final places = await _searchPlaces(
          query: query,
          location: searchLocation,
          limit: 5,
        ).timeout(_placesSearchTimeout, onTimeout: () => const <Destination>[]);
        results.addAll(places);
      } catch (e) {
        debugPrint('Error discovering places for query "$query": $e');
      }
    }

    return results;
  }

  static Future<List<Destination>> _searchPlaces({
    required String query,
    required LatLng location,
    required int limit,
  }) async {
    if (!DevModeService.allowPaidGoogleApis) {
      debugPrint('Google Places skipped by dev cost guard: $query');
      return <Destination>[];
    }

    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json',
      ).replace(queryParameters: {
        'query': query,
        'location': '${location.latitude},${location.longitude}',
        'radius': '3000',
        'key': _googleApiKey,
      });

      final response = await http.get(uri).timeout(_placesSearchTimeout,
          onTimeout: () => throw TimeoutException(''));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final results = data['results'] as List;
          final destinations = results
              .map((item) => _convertGooglePlaceToDestination(item, null))
              .whereType<Destination>()
              .toList();
          _cacheDestinationsBestEffort(destinations, source: 'google');
          return destinations;
        }
      }
    } catch (e) {
      debugPrint('Google Places search error: $e');
    }
    return <Destination>[];
  }

  static List<Destination> _rankAndLimit(
    List<Destination> places,
    LatLng origin, {
    required int limit,
  }) {
    final cleanedPlaces = deduplicateDestinationsById(places);
    final bestByKey = <String, Destination>{};

    for (final place in cleanedPlaces) {
      final key = _destinationDedupeKey(place);
      final existing = bestByKey[key];

      if (existing == null ||
          _shouldPreferDestination(place, existing, origin)) {
        bestByKey[key] = place;
      }
    }

    final deduped = bestByKey.values.toList()
      ..sort(
        (a, b) =>
            _trendingScore(b, origin).compareTo(_trendingScore(a, origin)),
      );

    return deduped.take(limit).toList(growable: false);
  }

  static String _destinationDedupeKey(Destination destination) {
    final normalizedName = _normalizeDestinationName(destination.name);
    if (normalizedName.isNotEmpty) {
      return '${destination.category.name}|$normalizedName';
    }

    final coordinates = destination.coordinates;
    if (coordinates != null) {
      final latBucket = (coordinates.latitude * 1000).round();
      final lngBucket = (coordinates.longitude * 1000).round();
      return '${destination.category.name}|$latBucket,$lngBucket';
    }

    return '${destination.category.name}|${destination.id.toLowerCase()}';
  }

  static String _normalizeDestinationName(String value) {
    final words = value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .where(
          (word) => !{
            'city',
            'mall',
            'malls',
            'shopping',
            'center',
            'centre',
            'the',
            'of',
          }.contains(word),
        )
        .toList();

    return words.join(' ');
  }

  static bool _shouldPreferDestination(
    Destination candidate,
    Destination existing,
    LatLng origin,
  ) {
    final candidateImagePriority = _imagePriority(candidate.imageUrl);
    final existingImagePriority = _imagePriority(existing.imageUrl);

    if (candidateImagePriority != existingImagePriority) {
      return candidateImagePriority > existingImagePriority;
    }

    return _trendingScore(candidate, origin) > _trendingScore(existing, origin);
  }

  static int _imagePriority(String imageUrl) {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) return 0;
    if (trimmed
        .startsWith('https://maps.googleapis.com/maps/api/place/photo')) {
      return 3;
    }
    if (trimmed.startsWith('http')) return 1;
    return 0;
  }

  static double _trendingScore(Destination destination, LatLng origin) {
    final reviews = destination.tags.contains('popular') ? 500.0 : 50.0;
    final distance = destination.coordinates == null
        ? 12.0
        : calculateDistance(origin, destination.coordinates!);
    final categoryBoost = switch (destination.category) {
      DestinationCategory.malls => 12.0,
      DestinationCategory.food => 12.0,
      DestinationCategory.park => 10.0,
      DestinationCategory.activities => 6.0,
      DestinationCategory.museum => 4.0,
      DestinationCategory.landmark => 4.0,
    };
    return destination.rating * 20.0 +
        log(reviews + 1) * 8.0 +
        categoryBoost -
        distance.clamp(0.0, 50.0);
  }

  static Future<LatLng> _getSearchLocation() async {
    try {
      final location = await getCurrentLocation().timeout(
        _locationSearchTimeout,
        onTimeout: () {
          debugPrint('Location fetch timed out, using default search location');
          return _cachedLocation ?? _defaultSearchLocation;
        },
      );
      if (isInvalidLocation(location)) {
        debugPrint('Invalid location detected, using default search location');
        return _cachedLocation ?? _defaultSearchLocation;
      }
      return location;
    } catch (e) {
      debugPrint('Error getting search location: $e');
      return _cachedLocation ?? _defaultSearchLocation;
    }
  }

  static Future<List<Destination>> _hydrateMissingImages(
    List<Destination> destinations,
    LatLng location, {
    required int maxHydration,
  }) async {
    if (!DevModeService.allowPaidGoogleApis) {
      return destinations;
    }

    final hydrated = <Destination>[];
    var requestsUsed = 0;

    for (final destination in destinations) {
      if (destination.imageUrl.trim().isNotEmpty) {
        hydrated.add(destination);
        continue;
      }

      final cacheKey = _normalizeDestinationName(destination.name);
      final cachedUrl = _imageUrlCache[cacheKey];
      if (cachedUrl != null && cachedUrl.isNotEmpty) {
        hydrated.add(_copyDestinationWithImage(destination, cachedUrl));
        continue;
      }

      if (requestsUsed >= maxHydration) {
        hydrated.add(destination);
        continue;
      }

      requestsUsed++;
      final imageUrl = await _findGooglePhotoForDestination(
        destination,
        location,
      );

      if (imageUrl != null && imageUrl.isNotEmpty) {
        _imageUrlCache[cacheKey] = imageUrl;
        hydrated.add(_copyDestinationWithImage(destination, imageUrl));
      } else {
        hydrated.add(destination);
      }
    }

    return hydrated;
  }

  static Future<String?> _findGooglePhotoForDestination(
    Destination destination,
    LatLng location,
  ) async {
    final query = destination.location.trim().isEmpty
        ? destination.name
        : '${destination.name} ${destination.location}';

    final matches = await _searchPlaces(
      query: query,
      location: destination.coordinates ?? location,
      limit: 5,
    );

    for (final match in matches) {
      if (match.imageUrl.trim().isEmpty) continue;

      final namesAreClose = _nameSimilarity(
            _normalizeDestinationName(destination.name),
            _normalizeDestinationName(match.name),
          ) >=
          0.45;

      final locationsAreClose = _areCoordinatesClose(destination, match);

      if (namesAreClose || locationsAreClose) {
        return match.imageUrl;
      }
    }

    return null;
  }

  static Destination _copyDestinationWithImage(
    Destination destination,
    String imageUrl,
  ) {
    return Destination(
      id: destination.id,
      name: destination.name,
      description: destination.description,
      location: destination.location,
      coordinates: destination.coordinates,
      imageUrl: imageUrl,
      category: destination.category,
      rating: destination.rating,
      tags: destination.tags,
    );
  }

  static String _queryFor(String query, DestinationCategory? category) {
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (category == null) return 'tourist attractions';
    return switch (category) {
      DestinationCategory.food => 'restaurants cafes',
      DestinationCategory.park => 'parks',
      DestinationCategory.museum => 'museums',
      DestinationCategory.malls => 'shopping malls',
      DestinationCategory.activities => 'activities entertainment',
      DestinationCategory.landmark => 'tourist attractions landmarks',
    };
  }

  static Destination? _convertGooglePlaceToDestination(
    Map<String, dynamic> item,
    String? placeId,
  ) {
    final id = placeId ??
        item['place_id'] ??
        'google_${DateTime.now().millisecondsSinceEpoch}';
    final name = item['name'] as String? ?? 'Unknown Place';
    final formattedAddress =
        item['formatted_address'] as String? ?? 'Philippines';
    final geometry = item['geometry'] as Map<String, dynamic>?;
    final location = geometry?['location'] as Map<String, dynamic>?;
    final lat = (location?['lat'] as num?)?.toDouble();
    final lng = (location?['lng'] as num?)?.toDouble();
    final rating = (item['rating'] as num?)?.toDouble() ?? 4.0;

    DestinationCategory category = DestinationCategory.landmark;
    final types = item['types'] as List?;
    if (types != null) {
      final typesStr = types.join(' ').toLowerCase();
      if (typesStr.contains('restaurant') ||
          typesStr.contains('food') ||
          typesStr.contains('cafe')) {
        category = DestinationCategory.food;
      } else if (typesStr.contains('park') || typesStr.contains('garden')) {
        category = DestinationCategory.park;
      } else if (typesStr.contains('museum') || typesStr.contains('gallery')) {
        category = DestinationCategory.museum;
      } else if (typesStr.contains('shopping') ||
          typesStr.contains('mall') ||
          typesStr.contains('store')) {
        category = DestinationCategory.malls;
      } else if (typesStr.contains('tourist') ||
          typesStr.contains('attraction') ||
          typesStr.contains('landmark')) {
        category = DestinationCategory.landmark;
      }
    }

    final photoReference = _firstGooglePhotoReference(item);
    final imageUrl = photoReference == null
        ? ''
        : GoogleMapsService.buildPhotoUrl(photoReference);
    if (photoReference == null) {
      AppLog.throttledInfo(
        'destination-google-photo-missing',
        'Google photo unavailable for some destinations in this result set.',
      );
    }

    return Destination(
      id: id,
      name: name,
      description: formattedAddress,
      location: formattedAddress,
      coordinates: (lat != null && lng != null) ? LatLng(lat, lng) : null,
      imageUrl: imageUrl,
      category: category,
      rating: rating,
      tags: [
        'google',
        'googlePlaceId:$id',
        'placeId:$id',
        if (photoReference != null) 'googlePhotoReference:$photoReference',
        if (photoReference != null) 'photoReference:$photoReference',
        ...?types?.cast<String>(),
      ],
    );
  }

  static void _cacheDestinationsBestEffort(
    List<Destination> destinations, {
    required String source,
  }) {
    for (final destination in destinations) {
      unawaited(_upsertCachedDestination(destination, source: source));
    }
  }

  static Future<void> _upsertCachedDestination(
    Destination destination, {
    required String source,
  }) async {
    final name = destination.name.trim();
    final coordinates = destination.coordinates;
    if (name.isEmpty || coordinates == null) {
      AppLog.throttledInfo(
        'cached-destination-missing-fields',
        'Cached destination upsert skipped: missing name or coordinates',
      );
      return;
    }

    try {
      final googlePlaceId = _tagValue(destination.tags, 'googlePlaceId:') ??
          _tagValue(destination.tags, 'placeId:') ??
          (destination.id.startsWith('google_') ? '' : destination.id).trim();
      final effectiveSource = googlePlaceId.isNotEmpty ||
              destination.tags.any((tag) => tag.toLowerCase() == 'google')
          ? 'google'
          : source;
      final cacheKey = _cachedDestinationSessionKey(
        destination,
        googlePlaceId,
        coordinates,
      );
      final photoReference =
          _tagValue(destination.tags, 'googlePhotoReference:') ??
              _tagValue(destination.tags, 'photoReference:') ??
              '';
      final imageUrl = _bestDestinationImage(destination, photoReference);
      final displayName = PlaceDisplayNameUtils.cleanGoogleDisplayName(name);
      if (displayName.isNotEmpty && displayName != name) {
        debugPrint(
            'Cached destination display name cleaned: $name -> $displayName');
      }
      debugPrint('Featured place original name preserved: $name');

      final incomingFingerprint = _cachedDestinationFingerprint(
        destination: destination,
        name: name,
        displayName: displayName,
        effectiveSource: effectiveSource,
        googlePlaceId: googlePlaceId,
        photoReference: photoReference,
        imageUrl: imageUrl,
      );
      if (_cachedDestinationSessionFingerprints[cacheKey] ==
          incomingFingerprint) {
        AppLog.throttledInfo(
          'cached-destination-unchanged',
          'Cached destination upsert skipped: unchanged this session',
        );
        return;
      }
      if (_cachedDestinationUpsertsInFlight.contains(cacheKey)) {
        AppLog.throttledInfo(
          'cached-destination-inflight',
          'Cached destination upsert skipped: already in flight',
        );
        return;
      }
      final lastAttempt = _cachedDestinationLastAttempts[cacheKey];
      final now = DateTime.now();
      if (lastAttempt != null &&
          _cachedDestinationLastAttemptFingerprints[cacheKey] ==
              incomingFingerprint &&
          now.difference(lastAttempt) < _cachedDestinationWriteDebounce) {
        AppLog.throttledInfo(
          'cached-destination-debounced',
          'Cached destination upsert skipped: debounced',
        );
        return;
      }
      _cachedDestinationLastAttempts[cacheKey] = now;
      _cachedDestinationLastAttemptFingerprints[cacheKey] = incomingFingerprint;
      _cachedDestinationUpsertsInFlight.add(cacheKey);

      final existing = await _findCachedDestination(
        googlePlaceId: googlePlaceId,
        name: name,
        coordinates: coordinates,
      );
      final existingData = existing?.data() ?? const <String, dynamic>{};
      final existingImage = _firstHttpString(existingData, const [
        'imageUrl',
        'googlePhotoUrl',
        'photoUrl',
        'photoURL',
        'thumbnailUrl',
        'thumbnail',
        'coverImageUrl',
        'bannerImage',
      ]);
      final savedImage = imageUrl.isNotEmpty ? imageUrl : existingImage;
      if (imageUrl.isEmpty && existingImage.isNotEmpty) {
        debugPrint('Cached destination image preserved');
      } else if (imageUrl.isNotEmpty) {
        debugPrint('Cached destination image saved from field: imageUrl');
      }

      final writeData = <String, dynamic>{
        'id': destination.id,
        'name': name,
        'title': name,
        'displayName': displayName.isEmpty ? name : displayName,
        'originalName': name,
        if (effectiveSource == 'google') 'googleName': name,
        'rawName': name,
        'description': _preferNonBlank(
          destination.description,
          existingData['description'],
        ),
        'address':
            _preferNonBlank(destination.location, existingData['address']),
        'location': _preferNonBlank(
          destination.location,
          existingData['location'],
        ),
        'city': _preferNonBlank(destination.location, existingData['city']),
        'category': _preferNonBlank(
          destination.category.name,
          existingData['category'],
        ),
        'latitude': coordinates.latitude,
        'longitude': coordinates.longitude,
        'imageUrl': savedImage,
        if (savedImage.isNotEmpty) 'googlePhotoUrl': savedImage,
        if (photoReference.isNotEmpty) 'googlePhotoReference': photoReference,
        if (photoReference.isNotEmpty) 'photoReference': photoReference,
        if (googlePlaceId.isNotEmpty) 'googlePlaceId': googlePlaceId,
        if (googlePlaceId.isNotEmpty) 'placeId': googlePlaceId,
        'source': effectiveSource,
        'rating': destination.rating,
        'tags': destination.tags,
      };
      if (existing != null &&
          !_cachedDestinationRequiredFieldsChanged(existingData, writeData)) {
        _cachedDestinationSessionFingerprints[cacheKey] = incomingFingerprint;
        AppLog.throttledInfo(
          'cached-destination-no-field-changes',
          'Cached destination upsert skipped: no field changes',
        );
        return;
      }

      final doc = existing?.reference ??
          _firestore
              .collection(_cachedDestinationsCollection)
              .doc(_cachedDestinationDocId(destination, googlePlaceId));
      await doc.set({
        ...writeData,
        'updatedAt': FieldValue.serverTimestamp(),
        if (existing == null) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _cachedDestinationSessionFingerprints[cacheKey] = incomingFingerprint;
      debugPrint(
        'Cached destination upserted: ${googlePlaceId.isEmpty ? name : googlePlaceId}',
      );
    } catch (error) {
      debugPrint('Cached destination upsert failed: $error');
    } finally {
      final googlePlaceId = _tagValue(destination.tags, 'googlePlaceId:') ??
          _tagValue(destination.tags, 'placeId:') ??
          (destination.id.startsWith('google_') ? '' : destination.id).trim();
      if (destination.coordinates != null) {
        _cachedDestinationUpsertsInFlight.remove(
          _cachedDestinationSessionKey(
            destination,
            googlePlaceId,
            destination.coordinates!,
          ),
        );
      }
    }
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?>
      _findCachedDestination({
    required String googlePlaceId,
    required String name,
    required LatLng coordinates,
  }) async {
    final collection = _firestore.collection(_cachedDestinationsCollection);
    if (googlePlaceId.isNotEmpty) {
      for (final field in const ['googlePlaceId', 'placeId']) {
        final snapshot = await collection
            .where(field, isEqualTo: googlePlaceId)
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) return snapshot.docs.first;
      }
    }

    final normalizedName = _normalizeDestinationName(name);
    final coordinateBucket = _coordinateBucket(coordinates);
    final snapshot = await collection.limit(250).get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final docName = _normalizeDestinationName(data['name'] ?? data['title']);
      if (normalizedName.isNotEmpty && docName == normalizedName) return doc;

      final latitude = _readDouble(data['latitude'] ?? data['lat']);
      final longitude = _readDouble(data['longitude'] ?? data['lng']);
      if (latitude != null &&
          longitude != null &&
          _coordinateBucket(LatLng(latitude, longitude)) == coordinateBucket) {
        return doc;
      }
    }
    return null;
  }

  static String _cachedDestinationDocId(
    Destination destination,
    String googlePlaceId,
  ) {
    final raw = googlePlaceId.isNotEmpty
        ? 'google_$googlePlaceId'
        : '${_normalizeDestinationName(destination.name)}_${_coordinateBucket(destination.coordinates!)}';
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  }

  static String _cachedDestinationSessionKey(
    Destination destination,
    String googlePlaceId,
    LatLng coordinates,
  ) {
    if (googlePlaceId.isNotEmpty) return 'google:$googlePlaceId';
    return 'local:${_normalizeDestinationName(destination.name)}:${_coordinateBucket(coordinates)}';
  }

  static String _cachedDestinationFingerprint({
    required Destination destination,
    required String name,
    required String displayName,
    required String effectiveSource,
    required String googlePlaceId,
    required String photoReference,
    required String imageUrl,
  }) {
    final coordinates = destination.coordinates!;
    return [
      destination.id,
      name,
      displayName.isEmpty ? name : displayName,
      destination.description.trim(),
      destination.location.trim(),
      destination.category.name,
      coordinates.latitude.toStringAsFixed(6),
      coordinates.longitude.toStringAsFixed(6),
      imageUrl,
      photoReference,
      googlePlaceId,
      effectiveSource,
      destination.rating.toStringAsFixed(3),
      destination.tags.join('\u001f'),
    ].join('\u001e');
  }

  static bool _cachedDestinationRequiredFieldsChanged(
    Map<String, dynamic> existingData,
    Map<String, dynamic> writeData,
  ) {
    for (final entry in writeData.entries) {
      final existingValue = existingData[entry.key];
      final nextValue = entry.value;
      if (existingValue is List && nextValue is List) {
        if (!listEquals(existingValue, nextValue)) return true;
        continue;
      }
      if (existingValue is num && nextValue is num) {
        if (existingValue.toDouble() != nextValue.toDouble()) return true;
        continue;
      }
      if (existingValue != nextValue) return true;
    }
    return false;
  }

  static String _bestDestinationImage(
    Destination destination,
    String photoReference,
  ) {
    final imageUrl = destination.imageUrl.trim();
    if (imageUrl.startsWith('http')) return imageUrl;
    if (photoReference.isEmpty) return '';
    final googlePhotoUrl = GoogleMapsService.buildPhotoUrl(photoReference);
    if (googlePhotoUrl.isNotEmpty) {
      debugPrint(
          'Cached destination image saved from field: googlePhotoReference');
    }
    return googlePhotoUrl;
  }

  static String? _firstGooglePhotoReference(Map<String, dynamic> item) {
    for (final field in const ['googlePhotoReference', 'photoReference']) {
      final value = item[field];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }

    final photos = item['photos'];
    if (photos is List && photos.isNotEmpty) {
      final first = photos.first;
      if (first is Map) {
        final value = first['photo_reference'] ?? first['photoReference'];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return null;
  }

  static String? _tagValue(List<String> tags, String prefix) {
    final normalizedPrefix = prefix.toLowerCase();
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.toLowerCase().startsWith(normalizedPrefix)) {
        final value = trimmed.substring(prefix.length).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static String _firstHttpString(
    Map<String, dynamic> data,
    List<String> fields,
  ) {
    for (final field in fields) {
      final value = data[field];
      if (value is String && value.trim().startsWith('http')) {
        return value.trim();
      }
    }
    return '';
  }

  static String _preferNonBlank(String candidate, Object? existing) {
    final trimmed = candidate.trim();
    if (trimmed.isNotEmpty) return trimmed;
    if (existing is String && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    return '';
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return null;
  }

  static String _coordinateBucket(LatLng coordinates) {
    return '${(coordinates.latitude * 10000).round()},${(coordinates.longitude * 10000).round()}';
  }
}

class TimeoutException implements Exception {
  final String message;
  const TimeoutException(this.message);
}
