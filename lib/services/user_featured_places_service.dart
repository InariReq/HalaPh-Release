import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/services/google_maps_service.dart';
import 'package:halaph/utils/app_log.dart';
import 'package:halaph/utils/place_display_name_utils.dart';

class UserFeaturedPlacesService {
  static const Duration _timeout = Duration(seconds: 4);
  static const _featuredCollection = 'admin_featured_places';
  static const _adminLocationsCollection = 'admin_locations';
  static const _destinationCollections = <String>[
    'destinations',
    'places',
    'locations',
    'cached_destinations',
  ];
  static const _referenceFields = <String>[
    'destinationId',
    'placeId',
    'locationId',
    'targetId',
  ];
  static const Duration _cacheTtl = Duration(minutes: 5);
  static List<Destination>? _cachedActivePlaces;
  static DateTime? _cachedAt;
  static Future<List<Destination>>? _loadInFlight;

  static Future<List<Destination>> getActiveFeaturedPlaces({
    DestinationCategory? category,
    String query = '',
    bool forceRefresh = false,
  }) async {
    final allPlaces = await _loadActiveFeaturedPlaces(
      forceRefresh: forceRefresh,
    );
    return _filterDestinations(allPlaces, category: category, query: query);
  }

  static Future<List<Destination>> _loadActiveFeaturedPlaces({
    required bool forceRefresh,
  }) {
    final cached = _freshCache;
    if (!forceRefresh && cached != null) {
      return Future.value(cached);
    }
    final inFlight = _loadInFlight;
    if (!forceRefresh && inFlight != null) return inFlight;

    final future = _fetchActiveFeaturedPlaces();
    _loadInFlight = future;
    return future.whenComplete(() {
      if (identical(_loadInFlight, future)) {
        _loadInFlight = null;
      }
    });
  }

  static Future<List<Destination>> _fetchActiveFeaturedPlaces() async {
    try {
      AppLog.throttledInfo(
        'featured-places-query',
        'Featured places query started',
      );
      final now = DateTime.now();
      final candidates = <_FeaturedDestination>[];

      final featuredDocs = await _readCollection(_featuredCollection);
      for (final doc in featuredDocs) {
        final candidate = await _featuredCollectionCandidate(doc, now);
        if (candidate != null) {
          candidates.add(candidate);
        }
      }

      final existingDestinationCandidates =
          await _loadExistingFeaturedDestinations(now);
      candidates.addAll(existingDestinationCandidates);

      final adminLocationCandidates =
          await _loadExistingFeaturedAdminLocations(now);
      candidates.addAll(adminLocationCandidates);

      final merged = _mergeAndSort(candidates);
      final destinations = merged
          .map((candidate) => candidate.destination)
          .toList(growable: false);
      _cachedActivePlaces = destinations;
      _cachedAt = DateTime.now();
      AppLog.throttledInfo(
        'featured-places-loaded',
        'Featured places loaded: ${destinations.length}',
      );
      return destinations;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        AppLog.throttledInfo(
          'featured-places-denied',
          'Featured places permission-denied; showing saved data if available.',
        );
        return _cachedActivePlaces ?? const <Destination>[];
      }
      AppLog.error('Featured places read failed: ${error.code}');
      return _cachedActivePlaces ?? const <Destination>[];
    } catch (error) {
      AppLog.error('Featured places read failed: $error');
      return _cachedActivePlaces ?? const <Destination>[];
    }
  }

  static List<Destination>? get _freshCache {
    final cached = _cachedActivePlaces;
    final cachedAt = _cachedAt;
    if (cached == null || cachedAt == null) return null;
    if (DateTime.now().difference(cachedAt) > _cacheTtl) return null;
    return cached;
  }

  static List<Destination> _filterDestinations(
    List<Destination> destinations, {
    required DestinationCategory? category,
    required String query,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    return destinations.where((destination) {
      if (category != null && destination.category != category) return false;
      if (normalizedQuery.isEmpty) return true;
      final searchable = [
        destination.name,
        destination.location,
        destination.description,
        destination.tags.join(' '),
      ].join(' ').toLowerCase();
      return searchable.contains(normalizedQuery);
    }).toList(growable: false);
  }

  static Future<_FeaturedDestination?> _featuredCollectionCandidate(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    DateTime now,
  ) async {
    final data = doc.data();
    final skipReason = _skipReason(data, now, requiresFeatureFlag: false);
    if (skipReason != null) {
      AppLog.throttledInfo(
        'featured-skip-${doc.id}-$skipReason',
        'Skipping featured place ${doc.id}: $skipReason',
      );
      return null;
    }

    final priority = _readPriority(data);
    final sourceCollection = _stringValue(data['sourceCollection']);
    final sourceId = _stringValue(data['sourceId'] ?? data['targetId']);
    if (sourceCollection.isNotEmpty && sourceId.isNotEmpty) {
      final resolved = await _resolveReferencedDestinationFromCollection(
        sourceCollection,
        sourceId,
        now,
        featuredData: data,
      );
      if (resolved != null) {
        return _FeaturedDestination(
          destination: _markFeatured(
            _applyFeaturedDisplayName(resolved.destination, data),
            priority,
          ),
          priority: priority,
          sourceId: '$sourceCollection/$sourceId',
        );
      }
      AppLog.throttledInfo(
        'featured-reference-not-found',
        'Some featured place references could not be resolved.',
      );
    }

    final referenceId = _readReferenceId(data);
    if (referenceId != null) {
      final resolved = await _resolveReferencedDestination(referenceId, now);
      if (resolved != null) {
        return _FeaturedDestination(
          destination: _markFeatured(resolved.destination, priority),
          priority: priority,
          sourceId: doc.id,
        );
      }
      AppLog.throttledInfo(
        'featured-reference-not-found',
        'Some featured place references could not be resolved.',
      );
    }

    final destination = _toDestination(
      id: 'admin-featured-${doc.id}',
      data: data,
      sourceLabel: 'Admin Featured',
    );
    if (destination == null) {
      AppLog.throttledInfo(
        'featured-invalid-shape',
        'Some featured places are missing required fields.',
      );
      return null;
    }

    return _FeaturedDestination(
      destination: _markFeatured(destination, priority),
      priority: priority,
      sourceId: doc.id,
    );
  }

  static Future<List<_FeaturedDestination>> _loadExistingFeaturedDestinations(
      DateTime now) async {
    final candidates = <_FeaturedDestination>[];

    for (final collectionPath in _destinationCollections) {
      final docs = await _readFeaturedDocs(collectionPath);
      for (final doc in docs) {
        final data = doc.data();
        final skipReason = _skipReason(
          data,
          now,
          allowMissingActive: true,
        );
        if (skipReason != null) {
          continue;
        }

        final priority = _readPriority(data);
        final destination = _toDestination(
          id: doc.id,
          data: data,
          sourceLabel: 'Featured Destination',
        );
        if (destination == null) {
          debugPrint(
            'Featured place skipped invalid: ${doc.id} missing name, location, or category',
          );
          continue;
        }

        candidates.add(
          _FeaturedDestination(
            destination: _markFeatured(destination, priority),
            priority: priority,
            sourceId: doc.id,
          ),
        );
      }
    }

    return candidates;
  }

  static Future<List<_FeaturedDestination>> _loadExistingFeaturedAdminLocations(
      DateTime now) async {
    final docs = await _readFeaturedDocs(_adminLocationsCollection);
    final candidates = <_FeaturedDestination>[];

    for (final doc in docs) {
      final data = doc.data();
      final skipReason = _skipReason(data, now);
      if (skipReason != null) {
        continue;
      }

      final priority = _readPriority(data);
      final destination = _toDestination(
        id: 'admin-location-${doc.id}',
        data: data,
        sourceLabel: 'Admin Featured',
      );
      if (destination == null) {
        debugPrint(
          'Featured place skipped invalid: ${doc.id} missing name, location, or category',
        );
        continue;
      }

      candidates.add(
        _FeaturedDestination(
          destination: _markFeatured(destination, priority),
          priority: priority,
          sourceId: doc.id,
        ),
      );
    }

    return candidates;
  }

  static Future<_FeaturedDestination?> _resolveReferencedDestination(
    String referenceId,
    DateTime now,
  ) async {
    for (final collectionPath in <String>[
      _adminLocationsCollection,
      ..._destinationCollections,
    ]) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(collectionPath)
            .doc(referenceId)
            .get(const GetOptions(source: Source.server))
            .timeout(_timeout);
        if (!doc.exists) continue;

        final data = doc.data() ?? const <String, dynamic>{};
        final skipReason = _skipReason(
          data,
          now,
          requiresFeatureFlag: false,
          allowMissingActive: true,
        );
        if (skipReason != null) {
          return null;
        }

        final isAdminLocation = collectionPath == _adminLocationsCollection;
        final priority = _readPriority(data);
        final destination = _toDestination(
          id: isAdminLocation ? 'admin-location-${doc.id}' : doc.id,
          data: data,
          sourceLabel:
              isAdminLocation ? 'Admin Featured' : 'Featured Destination',
        );
        if (destination == null) return null;

        return _FeaturedDestination(
          destination: destination,
          priority: priority,
          sourceId: referenceId,
        );
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          debugPrint(
            'Featured places permission-denied resolving $collectionPath/$referenceId: ${error.message}',
          );
        } else {
          debugPrint(
            'Featured place reference read failed $collectionPath/$referenceId: ${error.code}',
          );
        }
      } catch (error) {
        debugPrint(
          'Featured place reference read failed $collectionPath/$referenceId: $error',
        );
      }
    }

    return null;
  }

  static Future<_FeaturedDestination?>
      _resolveReferencedDestinationFromCollection(
          String collectionPath, String referenceId, DateTime now,
          {Map<String, dynamic> featuredData =
              const <String, dynamic>{}}) async {
    if (collectionPath != _adminLocationsCollection &&
        !_destinationCollections.contains(collectionPath)) {
      AppLog.throttledInfo(
        'featured-unsupported-source',
        'Some featured places use an unsupported source collection.',
      );
      return null;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(referenceId)
          .get(const GetOptions(source: Source.server))
          .timeout(_timeout);
      if (!doc.exists) return null;

      final data = doc.data() ?? const <String, dynamic>{};
      final skipReason = _skipReason(
        data,
        now,
        requiresFeatureFlag: false,
        allowMissingActive: true,
      );
      if (skipReason != null) {
        return null;
      }

      final isAdminLocation = collectionPath == _adminLocationsCollection;
      final priority = _readPriority(data);
      final destination = _toDestination(
        id: isAdminLocation ? 'admin-location-${doc.id}' : doc.id,
        data: {
          ...data,
          ..._displayNameFields(featuredData),
          'sourceCollection': collectionPath,
          'sourceId': doc.id,
        },
        sourceLabel:
            isAdminLocation ? 'Admin Featured' : 'Featured Destination',
      );
      if (destination == null) return null;

      return _FeaturedDestination(
        destination: destination,
        priority: priority,
        sourceId: '$collectionPath/$referenceId',
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        debugPrint(
          'Featured places permission-denied resolving $collectionPath/$referenceId: ${error.message}',
        );
      } else {
        debugPrint(
          'Featured place reference read failed $collectionPath/$referenceId: ${error.code}',
        );
      }
    } catch (error) {
      debugPrint(
        'Featured place reference read failed $collectionPath/$referenceId: $error',
      );
    }

    return null;
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _readFeaturedDocs(String collectionPath) async {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

    for (final field in const ['isFeatured', 'featured']) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection(collectionPath)
            .where(field, isEqualTo: true)
            .get(const GetOptions(source: Source.server))
            .timeout(_timeout);
        for (final doc in snapshot.docs) {
          byId[doc.id] = doc;
        }
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          debugPrint(
            'Featured places permission-denied reading $collectionPath.$field: ${error.message}',
          );
        } else {
          debugPrint(
            'Featured places query failed $collectionPath.$field: ${error.code}',
          );
        }
      } catch (error) {
        debugPrint(
            'Featured places query failed $collectionPath.$field: $error');
      }
    }

    return byId.values.toList(growable: false);
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _readCollection(String collectionPath) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(collectionPath)
          .get(const GetOptions(source: Source.server))
          .timeout(_timeout);
      return snapshot.docs;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        debugPrint(
          'Featured places permission-denied reading $collectionPath: ${error.message}',
        );
      } else {
        debugPrint(
            'Featured places query failed $collectionPath: ${error.code}');
      }
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    } catch (error) {
      debugPrint('Featured places query failed $collectionPath: $error');
      return const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    }
  }

  static List<_FeaturedDestination> _mergeAndSort(
    List<_FeaturedDestination> candidates,
  ) {
    final sorted = [...candidates]..sort((a, b) {
        final priorityCompare = a.priority.compareTo(b.priority);
        if (priorityCompare != 0) return priorityCompare;
        return a.destination.name
            .toLowerCase()
            .compareTo(b.destination.name.toLowerCase());
      });
    final merged = <_FeaturedDestination>[];
    final seen = <String>{};

    for (final candidate in sorted) {
      final keys = _dedupeKeys(candidate.destination);
      final duplicate = keys.any(seen.contains);
      if (duplicate) {
        continue;
      }

      seen.addAll(keys);
      merged.add(candidate);
    }

    return merged;
  }

  static Destination? _toDestination({
    required String id,
    required Map<String, dynamic> data,
    required String sourceLabel,
  }) {
    final sourceCollection = _stringValue(data['sourceCollection']);
    final source = _stringValue(data['source']).toLowerCase();
    final cleanRawName =
        sourceCollection == 'cached_destinations' || source == 'google';
    final name = PlaceDisplayNameUtils.resolveDisplayName(
      data,
      cleanRawName: cleanRawName,
    );
    final city = _stringValue(
      data['city'] ??
          data['location'] ??
          data['address'] ??
          data['formattedAddress'],
    );
    final province = _stringValue(data['province']);
    final categoryLabel = _stringValue(data['category'] ?? data['type']);
    final description = _stringValue(data['description']);
    final imageUrl = _resolveImageUrl(data, name);
    final googlePlaceId =
        _stringValue(data['googlePlaceId'] ?? data['placeId']);
    final sourceId = _stringValue(
      data['sourceId'] ??
          data['destinationId'] ??
          data['locationId'] ??
          data['targetId'],
    );
    final priority = _readPriority(data);
    final originalName = PlaceDisplayNameUtils.originalName(data);

    if (name.isEmpty || city.isEmpty || categoryLabel.isEmpty) {
      return null;
    }

    final locationLabel = province.isEmpty ? city : '$city, $province';
    final coordinates = _readCoordinates(data);

    return Destination(
      id: id,
      name: name,
      description: description.isEmpty ? locationLabel : description,
      location: locationLabel,
      coordinates: coordinates,
      imageUrl: imageUrl,
      category: _mapCategory(categoryLabel),
      rating: _readRating(data['rating']),
      tags: [
        'Featured',
        sourceLabel,
        categoryLabel,
        city,
        province,
        if (googlePlaceId.isNotEmpty) 'googlePlaceId:$googlePlaceId',
        if (googlePlaceId.isNotEmpty) 'placeId:$googlePlaceId',
        if (sourceId.isNotEmpty) 'sourceId:$sourceId',
        if (sourceCollection.isNotEmpty) 'sourceCollection:$sourceCollection',
        if (sourceCollection.isNotEmpty && sourceId.isNotEmpty)
          'sourceRef:$sourceCollection/$sourceId',
        if (originalName.isNotEmpty) 'originalName:$originalName',
        'priority:$priority',
      ].where((tag) => tag.trim().isNotEmpty).toList(growable: false),
    );
  }

  static Destination _applyFeaturedDisplayName(
    Destination destination,
    Map<String, dynamic> featuredData,
  ) {
    final displayName = _firstDisplayName(featuredData);
    if (displayName.isEmpty || displayName == destination.name) {
      return destination;
    }
    return Destination(
      id: destination.id,
      name: displayName,
      description: destination.description,
      location: destination.location,
      coordinates: destination.coordinates,
      imageUrl: destination.imageUrl,
      category: destination.category,
      rating: destination.rating,
      tags: destination.tags,
    );
  }

  static Map<String, dynamic> _displayNameFields(Map<String, dynamic> data) {
    return {
      for (final field in const [
        'displayNameOverride',
        'adminDisplayName',
        'displayName',
        'originalName',
        'googleName',
        'rawName',
      ])
        if (_stringValue(data[field]).isNotEmpty)
          field: _stringValue(data[field]),
    };
  }

  static String _firstDisplayName(Map<String, dynamic> data) {
    for (final field in const [
      'displayNameOverride',
      'adminDisplayName',
      'displayName',
    ]) {
      final value = _stringValue(data[field]);
      if (value.isNotEmpty) {
        if (field == 'displayNameOverride') {}
        return value;
      }
    }
    return '';
  }

  static Destination _markFeatured(Destination destination, int priority) {
    final tags = <String>{
      ...destination.tags,
      'Featured',
      'Admin Featured',
      'priority:$priority',
    }.where((tag) => tag.trim().isNotEmpty).toList(growable: false);

    return Destination(
      id: destination.id,
      name: destination.name,
      description: destination.description,
      location: destination.location,
      coordinates: destination.coordinates,
      imageUrl: destination.imageUrl,
      category: destination.category,
      rating: destination.rating,
      tags: tags,
    );
  }

  static String? _skipReason(
    Map<String, dynamic> data,
    DateTime now, {
    bool requiresFeatureFlag = true,
    bool allowMissingActive = false,
  }) {
    if (requiresFeatureFlag && !_isFeatured(data)) {
      return 'missing featured flag';
    }

    if (!_isActive(data, allowMissing: allowMissingActive)) {
      return 'inactive or status is not active';
    }

    final startsAt =
        _timestampToDate(data['startsAt'] ?? data['featuredStartsAt']);
    if (startsAt != null && startsAt.isAfter(now)) {
      return 'startsAt is in the future';
    }

    final endsAt = _timestampToDate(data['endsAt'] ?? data['featuredEndsAt']);
    if (endsAt != null && endsAt.isBefore(now)) {
      return 'endsAt is in the past';
    }

    return null;
  }

  static bool _isFeatured(Map<String, dynamic> data) {
    return data['isFeatured'] == true || data['featured'] == true;
  }

  static bool _isActive(
    Map<String, dynamic> data, {
    bool allowMissing = false,
  }) {
    final isActive = data['isActive'];
    if (isActive is bool) return isActive;

    final active = data['active'];
    if (active is bool) return active;

    final status = data['status'];
    if (status is String) {
      final normalized = status.trim().toLowerCase();
      if (normalized == 'active' ||
          normalized == 'enabled' ||
          normalized == 'live' ||
          normalized == 'published') {
        return true;
      }
      if (normalized == 'inactive' ||
          normalized == 'disabled' ||
          normalized == 'draft' ||
          normalized == 'expired') {
        return false;
      }
    }

    return allowMissing;
  }

  static int _readPriority(Map<String, dynamic> data) {
    final featuredPriority = data['featuredPriority'];
    if (featuredPriority is int) return featuredPriority;
    if (featuredPriority is num) return featuredPriority.round();

    final priority = data['priority'];
    if (priority is int) return priority;
    if (priority is num) return priority.round();

    return 999;
  }

  static double _readRating(Object? value) {
    if (value is num && value > 0 && value <= 5) return value.toDouble();
    return 0.0;
  }

  static String? _readReferenceId(Map<String, dynamic> data) {
    for (final field in _referenceFields) {
      final value = data[field];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static String _stringValue(Object? value) {
    if (value is! String) return '';
    return value.trim();
  }

  static DateTime? _timestampToDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static LatLng? _readCoordinates(Map<String, dynamic> data) {
    final latitude = _readDouble(data['latitude'] ?? data['lat']);
    final longitude = _readDouble(data['longitude'] ?? data['lng']);
    if (latitude != null && longitude != null) {
      return LatLng(latitude, longitude);
    }

    final coordinates = data['coordinates'];
    if (coordinates is GeoPoint) {
      return LatLng(coordinates.latitude, coordinates.longitude);
    }
    if (coordinates is Map) {
      final lat = _readDouble(coordinates['latitude'] ?? coordinates['lat']);
      final lng = _readDouble(coordinates['longitude'] ?? coordinates['lng']);
      if (lat != null && lng != null) return LatLng(lat, lng);
    }

    return null;
  }

  static double? _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return null;
  }

  static String _resolveImageUrl(Map<String, dynamic> data, String name) {
    for (final entry in <String, Object?>{
      'imageUrl': data['imageUrl'],
      'image': data['image'],
      'image_url': data['image_url'],
      'photoUrl': data['photoUrl'],
      'photoURL': data['photoURL'],
      'thumbnailUrl': data['thumbnailUrl'],
      'thumbnail': data['thumbnail'],
      'coverImageUrl': data['coverImageUrl'],
      'bannerImage': data['bannerImage'],
      'googlePhotoUrl': data['googlePhotoUrl'],
    }.entries) {
      final value = entry.value;
      if (value is String && value.trim().startsWith('http')) {
        return value.trim();
      }
    }

    final reference = _readPhotoReference(data);
    if (reference.isNotEmpty) {
      final imageUrl = GoogleMapsService.buildPhotoUrl(reference);
      if (imageUrl.isNotEmpty) {
        return imageUrl;
      }
    }

    AppLog.throttledInfo(
      'featured-image-missing',
      'Some featured places do not have an image.',
    );
    return '';
  }

  static String _readPhotoReference(Map<String, dynamic> data) {
    for (final field in const [
      'googlePhotoReference',
      'photoReference',
      'photo_reference',
      'google_photo_reference',
    ]) {
      final value = data[field];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }

    final photos = data['photos'];
    if (photos is List && photos.isNotEmpty) {
      final first = photos.first;
      if (first is Map) {
        final value = first['photoReference'] ?? first['photo_reference'];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return '';
  }

  static Set<String> _dedupeKeys(Destination destination) {
    final keys = <String>{};
    final id = destination.id.trim().toLowerCase();
    if (id.isNotEmpty) {
      keys.add('id:$id');
      keys.add('id:${id.replaceFirst('admin-location-', '')}');
      keys.add('id:${id.replaceFirst('admin-featured-', '')}');
    }

    for (final tag in destination.tags) {
      final normalizedTag = tag.trim().toLowerCase();
      if (normalizedTag.startsWith('googleplaceid:')) {
        final value = normalizedTag.replaceFirst('googleplaceid:', '').trim();
        if (value.isNotEmpty) keys.add('google:$value');
      }
      if (normalizedTag.startsWith('placeid:')) {
        final value = normalizedTag.replaceFirst('placeid:', '').trim();
        if (value.isNotEmpty) keys.add('place:$value');
      }
      if (normalizedTag.startsWith('sourceid:')) {
        final value = normalizedTag.replaceFirst('sourceid:', '').trim();
        if (value.isNotEmpty) keys.add('source:$value');
      }
      if (normalizedTag.startsWith('sourceref:')) {
        final value = normalizedTag.replaceFirst('sourceref:', '').trim();
        if (value.isNotEmpty) keys.add('source-ref:$value');
      }
    }

    final normalizedName = _normalizeName(destination.name);
    if (normalizedName.isNotEmpty) keys.add('name:$normalizedName');

    final coordinates = destination.coordinates;
    if (coordinates != null) {
      final latBucket = (coordinates.latitude * 10000).round();
      final lngBucket = (coordinates.longitude * 10000).round();
      keys.add('coords:$latBucket,$lngBucket');
    }

    return keys;
  }

  static String _normalizeName(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .join(' ');
  }

  static DestinationCategory _mapCategory(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'malls' || 'mall' => DestinationCategory.malls,
      'food' || 'restaurant' || 'cafe' => DestinationCategory.food,
      'park' || 'parks' => DestinationCategory.park,
      'museum' || 'museums' => DestinationCategory.museum,
      'activity' || 'activities' => DestinationCategory.activities,
      'landmark' ||
      'destination' ||
      'tourist spot' ||
      'other' =>
        DestinationCategory.landmark,
      _ => DestinationCategory.landmark,
    };
  }
}

class _FeaturedDestination {
  final Destination destination;
  final int priority;
  final String sourceId;

  const _FeaturedDestination({
    required this.destination,
    required this.priority,
    required this.sourceId,
  });
}
