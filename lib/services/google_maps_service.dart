import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:halaph/models/destination.dart';
import 'package:halaph/utils/dev_mode.dart';
import 'package:halaph/utils/app_log.dart';

class GooglePlacesSearchResult {
  final List<Destination> destinations;
  final String? failure;
  final String? photoFailure;

  const GooglePlacesSearchResult({
    required this.destinations,
    this.failure,
    this.photoFailure,
  });

  bool get isUnavailable => failure != null;
}

class GoogleMapsService {
  static final Map<String, String> _photoUrlCache = {};
  static String get _googleApiKey => (dotenv.env['MAPS_API_KEY'] ?? '').trim();

  // Determine if Google Maps API key is actually configured in the environment.
  // If missing, API calls will gracefully fail and UI can show an estimated state.
  static bool get isConfigured =>
      DevModeService.allowPaidGoogleApis && _googleApiKey.isNotEmpty;

  static String buildPhotoUrl(String photoReference, {int maxWidth = 1200}) {
    final reference = photoReference.trim();
    if (reference.isEmpty || !isConfigured) return '';
    final cacheKey = '$maxWidth:$reference';
    final cachedUrl = _photoUrlCache[cacheKey];
    if (cachedUrl != null) return cachedUrl;
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/photo',
    ).replace(queryParameters: {
      'maxwidth': '$maxWidth',
      'photoreference': reference,
      'key': _googleApiKey,
    });
    final url = uri.toString();
    _photoUrlCache[cacheKey] = url;
    return url;
  }

  /// Get directions using Google Directions API.
  /// Costs: ~$5 per 1,000 requests.
  static Future<Map<String, dynamic>?> getDirections({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    String profile = 'walking',
  }) async {
    if (!isConfigured) {
      debugPrint('Google Maps API key not configured');
      return null;
    }

    try {
      final mode = _mapProfileToMode(profile);
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json',
      ).replace(queryParameters: {
        'origin': '$startLat,$startLon',
        'destination': '$endLat,$endLon',
        'mode': mode,
        'key': _googleApiKey,
      });

      debugPrint('🌍 Google Directions: Getting $mode directions (billable)');
      // ApiUsageTracker.logPlaceSearch('directions_$mode');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final routes = data['routes'] as List;
          if (routes.isNotEmpty) {
            final route = routes.first;
            final leg = (route['legs'] as List).first;
            return {
              'distance': (leg['distance']['value'] as num).toDouble(),
              'duration': (leg['duration']['value'] as num).toDouble(),
              'polyline': route['overview_polyline']['points'],
              'steps': leg['steps'],
            };
          }
        }
      }
    } catch (e) {
      debugPrint('Google Directions error: $e');
    }
    return null;
  }

  /// Get multiple Google Directions route alternatives.
  /// Used only when comparing public transit options.
  static Future<List<Map<String, dynamic>>> getDirectionAlternatives({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    String profile = 'walking',
  }) async {
    if (!isConfigured) {
      debugPrint('Google Maps API key not configured');
      return const <Map<String, dynamic>>[];
    }

    try {
      final mode = _mapProfileToMode(profile);
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json',
      ).replace(queryParameters: {
        'origin': '$startLat,$startLon',
        'destination': '$endLat,$endLon',
        'mode': mode,
        'alternatives': 'true',
        'key': _googleApiKey,
      });

      debugPrint(
        '🌍 Google Directions: Getting $mode route alternatives (billable)',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final routes = data['routes'] as List;
          final results = <Map<String, dynamic>>[];

          for (final route in routes) {
            if (route is! Map) continue;

            final legs = route['legs'];
            if (legs is! List || legs.isEmpty) continue;

            final leg = legs.first;
            if (leg is! Map) continue;

            final distance = leg['distance'];
            final duration = leg['duration'];
            final overviewPolyline = route['overview_polyline'];

            if (distance is! Map ||
                duration is! Map ||
                overviewPolyline is! Map) {
              continue;
            }

            final distanceValue = distance['value'];
            final durationValue = duration['value'];
            final polyline = overviewPolyline['points'];

            if (distanceValue is! num ||
                durationValue is! num ||
                polyline is! String) {
              continue;
            }

            results.add({
              'distance': distanceValue.toDouble(),
              'duration': durationValue.toDouble(),
              'polyline': polyline,
              'steps': leg['steps'],
            });
          }

          return results;
        }
      }
    } catch (e) {
      debugPrint('Google Directions alternatives error: $e');
    }

    return const <Map<String, dynamic>>[];
  }

  /// Geocode an address to LatLng using Google Geocoding API.
  /// Costs: ~$5 per 1,000 requests.
  static Future<LatLng?> geocodeAddress(String address) async {
    if (!isConfigured) {
      debugPrint('Google Maps API key not configured');
      return null;
    }

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json',
      ).replace(queryParameters: {
        'address': address,
        'key': _googleApiKey,
      });

      debugPrint('🌍 Google Geocoding: "$address" (billable)');
      // ApiUsageTracker.logPlaceSearch('geocode');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final results = data['results'] as List;
          if (results.isNotEmpty) {
            final location = results.first['geometry']['location'];
            return LatLng(location['lat'], location['lng']);
          }
        }
      }
    } catch (e) {
      debugPrint('Google Geocoding error: $e');
    }
    return null;
  }

  /// Search places using Google Places Text Search API.
  /// Costs: $17 per 1,000 requests.
  static Future<List<Destination>> searchPlacesNearby({
    required LatLng location,
    required String query,
    int radius = 3000,
    int limit = 5,
  }) async {
    final result = await searchPlacesNearbyDetailed(
      location: location,
      query: query,
      radius: radius,
      limit: limit,
    );
    return result.destinations;
  }

  static Future<GooglePlacesSearchResult> searchPlacesNearbyDetailed({
    required LatLng location,
    required String query,
    int radius = 3000,
    int limit = 5,
  }) async {
    if (!isConfigured) {
      return const GooglePlacesSearchResult(
        destinations: <Destination>[],
        failure: 'Google API unavailable',
      );
    }
    try {
      final params = {
        'query': query,
        'location': '${location.latitude},${location.longitude}',
        'radius': '$radius',
        'key': _googleApiKey,
      };

      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/textsearch/json',
      ).replace(queryParameters: params);

      debugPrint('🌍 Google Places: Searching "$query" (billable)');
      // ApiUsageTracker.logPlaceSearch(query);

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String? ?? 'UNKNOWN';
        if (status == 'OK') {
          final results = data['results'] as List;
          final limitedResults =
              results.take(limit).whereType<Map<String, dynamic>>().toList();
          final destinations = <Destination>[];
          var missingPhotoCount = 0;

          for (final item in limitedResults) {
            final destination = _convertToDestination(item);
            if (destination == null) continue;
            destinations.add(destination);
            final hasImage = destination.imageUrl.trim().isNotEmpty;
            final hasReference = destination.tags.any(
              (tag) => tag.toLowerCase().startsWith('googlephotoreference:'),
            );
            if (!hasImage && !hasReference) missingPhotoCount += 1;
          }

          return GooglePlacesSearchResult(
            destinations: destinations,
            photoFailure: missingPhotoCount == 0
                ? null
                : 'Google photo unavailable: no photo reference returned for $missingPhotoCount result(s).',
          );
        }
        final message = data['error_message'] as String? ?? status;
        return GooglePlacesSearchResult(
          destinations: const <Destination>[],
          failure: status == 'REQUEST_DENIED'
              ? 'API key/request denied: $message'
              : 'Google search failed: $message',
        );
      }
      return GooglePlacesSearchResult(
        destinations: const <Destination>[],
        failure: 'Google search failed: HTTP ${response.statusCode}',
      );
    } catch (e) {
      debugPrint('Google Places search error: $e');
      return GooglePlacesSearchResult(
        destinations: const <Destination>[],
        failure: 'Google search failed: $e',
      );
    }
  }

  static String _mapProfileToMode(String profile) {
    switch (profile) {
      case 'driving':
        return 'driving';
      case 'bicycling':
        return 'bicycling';
      case 'transit':
        return 'transit';
      case 'walking':
      default:
        return 'walking';
    }
  }

  static Destination? _convertToDestination(Map<String, dynamic> item) {
    try {
      final placeId = item['place_id'] as String? ?? '';
      final name = item['name'] as String? ?? 'Unknown';
      final geometry = item['geometry'] as Map<String, dynamic>?;
      final loc = geometry?['location'] as Map<String, dynamic>?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      final photoReference = _firstPhotoReference(item);
      final imageUrl =
          photoReference == null ? '' : buildPhotoUrl(photoReference);
      if (photoReference == null) {
        AppLog.throttledInfo(
          'google-photo-missing',
          'Google photo unavailable for some places in this result set.',
        );
      }

      return Destination(
        id: placeId,
        name: name,
        description: 'A great place to visit.',
        location: item['formatted_address'] as String? ?? '',
        imageUrl: imageUrl,
        coordinates: LatLng(lat, lng),
        category: _mapTypeToCategory(item['types'] as List? ?? []),
        rating: (item['rating'] as num?)?.toDouble() ?? 4.0,
        tags: [
          'google',
          if (photoReference != null) 'googlePhotoReference:$photoReference',
          if (photoReference != null) 'photoReference:$photoReference',
        ],
      );
    } catch (_) {
      return null;
    }
  }

  static DestinationCategory _mapTypeToCategory(List types) {
    for (final type in types) {
      final t = type.toString().toLowerCase();
      if (t.contains('restaurant') || t.contains('cafe')) {
        return DestinationCategory.food;
      } else if (t.contains('park')) {
        return DestinationCategory.park;
      } else if (t.contains('museum')) {
        return DestinationCategory.museum;
      } else if (t.contains('shop') ||
          t.contains('mall') ||
          t.contains('market')) {
        return DestinationCategory.malls;
      } else if (t.contains('tourist') || t.contains('attraction')) {
        return DestinationCategory.landmark;
      }
    }
    return DestinationCategory.activities;
  }

  static String? _firstPhotoReference(Map<String, dynamic> item) {
    final photos = item['photos'];
    if (photos is! List || photos.isEmpty) return null;
    final first = photos.first;
    if (first is! Map) return null;
    final reference = first['photo_reference'] ?? first['photoReference'];
    if (reference is String && reference.trim().isNotEmpty) {
      return reference.trim();
    }
    return null;
  }
}
