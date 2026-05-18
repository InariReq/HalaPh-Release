import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:halaph/models/verified_route.dart';
import 'package:halaph/services/budget_routing_service.dart';
import 'package:halaph/services/fare_service.dart';
import 'package:halaph/services/google_maps_service.dart';
import 'package:halaph/services/verified_route_service.dart';

class RouteFareEstimateResult {
  final double totalFare;
  final List<String> fareBreakdown;
  final String routeName;
  final bool isVerified;
  final bool isAvailable;

  const RouteFareEstimateResult({
    required this.totalFare,
    required this.fareBreakdown,
    required this.routeName,
    required this.isVerified,
    required this.isAvailable,
  });

  const RouteFareEstimateResult.unavailable()
      : totalFare = 0,
        fareBreakdown = const [],
        routeName = 'No available route',
        isVerified = false,
        isAvailable = false;
}

class RouteFareEstimatorService {
  static const double _stationAccessRideThresholdKm = 0.80;
  static const int _maxFareEstimateCacheEntries = 80;

  static final Map<String, RouteFareEstimateResult> _fareEstimateCache =
      <String, RouteFareEstimateResult>{};

  static Future<RouteFareEstimateResult> estimateBestRouteFare({
    required LatLng origin,
    required LatLng destination,
    PassengerType type = PassengerType.regular,
  }) async {
    if (BudgetRoutingService.isInvalidLocation(origin) ||
        BudgetRoutingService.isInvalidLocation(destination)) {
      return const RouteFareEstimateResult.unavailable();
    }

    final cacheKey = _fareEstimateCacheKey(
      origin: origin,
      destination: destination,
      type: type,
    );
    final cachedEstimate = _fareEstimateCache[cacheKey];

    if (cachedEstimate != null) {
      debugPrint('Route fare estimator cache hit: $cacheKey');
      return cachedEstimate;
    }

    debugPrint('Route fare estimator billable Directions call: $cacheKey');

    final liveEstimate = await _estimateFromLiveTransit(
      origin: origin,
      destination: destination,
      type: type,
    );

    if (liveEstimate != null && liveEstimate.isAvailable) {
      _rememberFareEstimate(cacheKey, liveEstimate);
      return liveEstimate;
    }

    final historicalEstimate = await _estimateFromHistoricalRoutes(
      origin: origin,
      destination: destination,
      type: type,
    );

    if (historicalEstimate != null && historicalEstimate.isAvailable) {
      _rememberFareEstimate(cacheKey, historicalEstimate);
      return historicalEstimate;
    }

    const unavailable = RouteFareEstimateResult.unavailable();
    _rememberFareEstimate(cacheKey, unavailable);
    return unavailable;
  }

  static RouteFareEstimateResult? cachedBestRouteFare({
    required LatLng origin,
    required LatLng destination,
    PassengerType type = PassengerType.regular,
  }) {
    if (BudgetRoutingService.isInvalidLocation(origin) ||
        BudgetRoutingService.isInvalidLocation(destination)) {
      return null;
    }

    return _fareEstimateCache[_fareEstimateCacheKey(
        origin: origin, destination: destination, type: type)];
  }

  static String _fareEstimateCacheKey({
    required LatLng origin,
    required LatLng destination,
    required PassengerType type,
  }) {
    return '${type.name}:'
        '${origin.latitude.toStringAsFixed(5)},'
        '${origin.longitude.toStringAsFixed(5)}->'
        '${destination.latitude.toStringAsFixed(5)},'
        '${destination.longitude.toStringAsFixed(5)}';
  }

  static void _rememberFareEstimate(
    String key,
    RouteFareEstimateResult estimate,
  ) {
    if (_fareEstimateCache.length >= _maxFareEstimateCacheEntries &&
        !_fareEstimateCache.containsKey(key)) {
      _fareEstimateCache.remove(_fareEstimateCache.keys.first);
    }

    _fareEstimateCache[key] = estimate;
  }

  static Future<RouteFareEstimateResult?> _estimateFromLiveTransit({
    required LatLng origin,
    required LatLng destination,
    required PassengerType type,
  }) async {
    final candidates = await GoogleMapsService.getDirectionAlternatives(
      startLat: origin.latitude,
      startLon: origin.longitude,
      endLat: destination.latitude,
      endLon: destination.longitude,
      profile: 'transit',
    );

    Map<String, dynamic>? best;
    var bestScore = double.infinity;

    for (final candidate in candidates) {
      final steps =
          (candidate['steps'] as List?)?.cast<Map<String, dynamic>>() ??
              <Map<String, dynamic>>[];

      if (steps.isEmpty) continue;
      if (!_hasLiveTransitStep(steps)) continue;
      if (_liveStepsUseUnsupportedPaidTransit(steps)) continue;

      final sequence = _liveModeSequence(steps);
      if (sequence.isEmpty) continue;

      final estimate = _estimateFareForLiveSteps(steps, type: type);
      final fare = estimate.totalFare;
      final duration = _durationMinutesForDirections(candidate);
      final walkKm = _walkDistanceKmForLiveSteps(steps);
      final totalKm = _totalDistanceKmForLiveSteps(steps);
      final transfers = sequence.length > 1 ? sequence.length - 1 : 0;
      final includesTrain = sequence.contains(TravelMode.train);

      var score = 0.0;
      score += fare * 1.4;
      score += duration * 0.65;
      score += walkKm * 18.0;
      score += transfers * 8.0;

      if (includesTrain && totalKm >= 8) {
        score -= 18.0;
      }

      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    if (best == null) return null;

    final steps = (best['steps'] as List).cast<Map<String, dynamic>>();
    final estimate = _estimateFareForLiveSteps(steps, type: type);
    final routeName = _displayNameForLiveSteps(steps);

    return RouteFareEstimateResult(
      totalFare: estimate.totalFare,
      fareBreakdown: estimate.displayLines,
      routeName: routeName,
      isVerified: true,
      isAvailable: true,
    );
  }

  static Future<RouteFareEstimateResult?> _estimateFromHistoricalRoutes({
    required LatLng origin,
    required LatLng destination,
    required PassengerType type,
  }) async {
    final modes = <TravelMode>[
      TravelMode.jeepney,
      TravelMode.bus,
      TravelMode.train,
      TravelMode.fx,
    ];

    RouteFareEstimateResult? best;
    var bestScore = double.infinity;

    for (final mode in modes) {
      final exactWalkMeters = _gtfsMatchRadiusForMode(mode);
      final destinationWalkMeters = _gtfsNearbyDestinationRadiusForMode(mode);

      final matches = await VerifiedRouteService.findHistoricalRouteMatches(
        mode: mode,
        origin: origin,
        destination: destination,
        limit: 1,
        maxWalkMeters: exactWalkMeters,
        destinationMaxWalkMeters: destinationWalkMeters,
      );

      if (matches.isEmpty) continue;

      final match = matches.first;
      final estimate = _estimateFareForHistoricalRoute(
        selectedMode: mode,
        match: match,
        type: type,
      );

      final routeName = _displayNameForHistoricalMatch(mode, match);
      final score = estimate.totalFare +
          (match.transferCount * 12.0) +
          ((match.walkToBoardMeters + match.walkFromAlightMeters) / 1000.0 * 8);

      if (score < bestScore) {
        bestScore = score;
        best = RouteFareEstimateResult(
          totalFare: estimate.totalFare,
          fareBreakdown: estimate.displayLines,
          routeName: routeName,
          isVerified: true,
          isAvailable: true,
        );
      }
    }

    return best;
  }

  static double _gtfsMatchRadiusForMode(TravelMode mode) {
    switch (mode) {
      case TravelMode.train:
        return 1800;
      case TravelMode.bus:
        return 1200;
      case TravelMode.jeepney:
      case TravelMode.fx:
        return 900;
      case TravelMode.walking:
        return 0;
    }
  }

  static double _gtfsNearbyDestinationRadiusForMode(TravelMode mode) {
    switch (mode) {
      case TravelMode.train:
        return 2500;
      case TravelMode.bus:
        return 1800;
      case TravelMode.jeepney:
      case TravelMode.fx:
        return 1400;
      case TravelMode.walking:
        return 0;
    }
  }

  static bool _isRoadTransitMode(TravelMode mode) {
    return mode == TravelMode.jeepney ||
        mode == TravelMode.bus ||
        mode == TravelMode.fx;
  }

  static TravelMode? _inferRoadModeFromLegText(HistoricalRouteLeg leg) {
    final text = [
      leg.signboard,
      leg.via,
      leg.boardStopName,
      leg.alightStopName,
    ].join(' ').toLowerCase();

    if (RegExp(r'\b(fx|uv|van)\b').hasMatch(text)) {
      return TravelMode.fx;
    }

    if (RegExp(r'\b(jeepney|jeep)\b').hasMatch(text)) {
      return TravelMode.jeepney;
    }

    if (RegExp(r'\b(bus|busway|carousel|p2p)\b').hasMatch(text)) {
      return TravelMode.bus;
    }

    return null;
  }

  static TravelMode _effectiveRideModeForLeg(
    TravelMode selectedMode,
    HistoricalRouteLeg leg,
  ) {
    if (leg.mode == TravelMode.train) return TravelMode.train;
    if (leg.mode == TravelMode.walking) return TravelMode.walking;

    final inferredMode = _inferRoadModeFromLegText(leg);
    if (inferredMode != null) return inferredMode;

    if (_isRoadTransitMode(selectedMode) && _isRoadTransitMode(leg.mode)) {
      return selectedMode;
    }

    return leg.mode;
  }

  static List<HistoricalRouteLeg> _historicalFareLegs(
    HistoricalRouteMatch match,
  ) {
    if (match.legs.isNotEmpty) return match.legs;

    return [
      HistoricalRouteLeg(
        route: match.route,
        mode: match.route.mode,
        signboard: match.signboard,
        via: match.via,
        boardStopName: match.boardStopName,
        boardStopLat: match.boardStopLat,
        boardStopLon: match.boardStopLon,
        alightStopName: match.alightStopName,
        alightStopLat: match.alightStopLat,
        alightStopLon: match.alightStopLon,
        walkToBoardMeters: match.walkToBoardMeters,
        rideDistanceMeters: match.rideDistanceMeters,
        stopCount: match.stopCount,
      ),
    ];
  }

  static MultiSegmentFareEstimate _estimateFareForHistoricalRoute({
    required TravelMode selectedMode,
    required HistoricalRouteMatch match,
    required PassengerType type,
  }) {
    final legs = _historicalFareLegs(match);
    final segments = <FareSegment>[];

    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      final effectiveMode = _effectiveRideModeForLeg(selectedMode, leg);

      segments.add(_accessSegmentForLeg(leg, type, isFirstLeg: i == 0));

      segments.add(
        FareSegment(
          label: _rideFareLabelForMode(effectiveMode),
          mode: effectiveMode,
          distanceKm: leg.rideDistanceKm,
          fare: FareService.estimateFare(
            effectiveMode,
            leg.rideDistanceKm,
            type: type,
          ),
        ),
      );
    }

    segments.add(_finalAccessSegmentForMatch(match, type));

    return MultiSegmentFareEstimate(segments: segments);
  }

  static FareSegment _accessSegmentForLeg(
    HistoricalRouteLeg leg,
    PassengerType type, {
    required bool isFirstLeg,
  }) {
    final distanceKm = leg.walkToBoardMeters / 1000.0;
    final isTrain = leg.mode == TravelMode.train;
    final needsLocalRide =
        isTrain && distanceKm > _stationAccessRideThresholdKm;

    if (needsLocalRide) {
      return FareSegment(
        label: isFirstLeg
            ? 'Estimated local jeepney ride to MRT/LRT station'
            : 'Estimated local jeepney ride to connecting station',
        mode: TravelMode.jeepney,
        distanceKm: distanceKm,
        fare: FareService.estimateFare(
          TravelMode.jeepney,
          distanceKm,
          type: type,
        ),
      );
    }

    return FareSegment(
      label: isTrain
          ? (isFirstLeg
              ? 'Walk to MRT/LRT station'
              : 'Walk to connecting station')
          : (isFirstLeg ? 'Walk to first boarding point' : 'Transfer walk'),
      mode: TravelMode.walking,
      distanceKm: distanceKm,
      fare: 0,
    );
  }

  static FareSegment _finalAccessSegmentForMatch(
    HistoricalRouteMatch match,
    PassengerType type,
  ) {
    final distanceKm = match.walkFromAlightMeters / 1000.0;
    final legs = _historicalFareLegs(match);
    final isTrain = legs.isNotEmpty && legs.last.mode == TravelMode.train;
    final needsLocalRide =
        isTrain && distanceKm > _stationAccessRideThresholdKm;

    if (needsLocalRide) {
      return FareSegment(
        label: 'Estimated local jeepney ride from MRT/LRT station',
        mode: TravelMode.jeepney,
        distanceKm: distanceKm,
        fare: FareService.estimateFare(
          TravelMode.jeepney,
          distanceKm,
          type: type,
        ),
      );
    }

    return FareSegment(
      label: isTrain ? 'Walk from MRT/LRT station' : 'Walk from final drop-off',
      mode: TravelMode.walking,
      distanceKm: distanceKm,
      fare: 0,
    );
  }

  static String _displayNameForHistoricalMatch(
    TravelMode selectedMode,
    HistoricalRouteMatch match,
  ) {
    final legs = _historicalFareLegs(match);
    if (legs.isEmpty) return _vehicleTitleForMode(selectedMode);

    final sequence = <TravelMode>[];

    for (final leg in legs) {
      final needsLocalRideToStation = leg.mode == TravelMode.train &&
          leg.walkToBoardMeters / 1000.0 > _stationAccessRideThresholdKm;
      if (needsLocalRideToStation) {
        sequence.add(TravelMode.jeepney);
      }
      sequence.add(_effectiveRideModeForLeg(selectedMode, leg));
    }

    final lastLeg = legs.last;
    final needsLocalRideFromStation = lastLeg.mode == TravelMode.train &&
        match.walkFromAlightMeters / 1000.0 > _stationAccessRideThresholdKm;
    if (needsLocalRideFromStation) {
      sequence.add(TravelMode.jeepney);
    }

    return _modeSequenceTitle(sequence);
  }

  static TravelMode _travelModeForLiveStep(Map<String, dynamic> step) {
    final travelMode = (step['travel_mode'] ?? '').toString().toUpperCase();

    if (travelMode == 'WALKING') return TravelMode.walking;
    if (travelMode != 'TRANSIT') return TravelMode.walking;

    final transitDetails = step['transit_details'];
    if (transitDetails is! Map) return TravelMode.walking;

    final line = transitDetails['line'];
    if (line is! Map) return TravelMode.walking;

    final vehicle = line['vehicle'];
    final vehicleType =
        vehicle is Map ? (vehicle['type'] ?? '').toString().toUpperCase() : '';
    final vehicleName =
        vehicle is Map ? (vehicle['name'] ?? '').toString().toUpperCase() : '';

    final lineText = [
      line['name'],
      line['short_name'],
      line['agency'],
      vehicleType,
      vehicleName,
    ].whereType<Object>().join(' ').toUpperCase();

    if (lineText.contains('MRT') ||
        lineText.contains('LRT') ||
        lineText.contains('PNR') ||
        lineText.contains('TRAIN') ||
        lineText.contains('RAIL') ||
        lineText.contains('SUBWAY') ||
        lineText.contains('TRAM') ||
        lineText.contains('METRO')) {
      return TravelMode.train;
    }

    if (lineText.contains('FX') ||
        lineText.contains('UV') ||
        lineText.contains('VAN')) {
      return TravelMode.fx;
    }

    if (lineText.contains('JEEP')) return TravelMode.jeepney;

    return TravelMode.bus;
  }

  static double _distanceKmForLiveStep(Map<String, dynamic> step) {
    final distance = step['distance'];

    if (distance is Map) {
      final value = distance['value'];
      if (value is num) return value.toDouble() / 1000.0;

      final text = (distance['text'] ?? '').toString().toLowerCase();

      final km = RegExp(r'([\d.]+)\s*km').firstMatch(text);
      if (km != null) return double.tryParse(km.group(1) ?? '') ?? 0.0;

      final meters = RegExp(r'([\d.]+)\s*m').firstMatch(text);
      if (meters != null) {
        return (double.tryParse(meters.group(1) ?? '') ?? 0.0) / 1000.0;
      }
    }

    return 0;
  }

  static bool _hasLiveTransitStep(List<Map<String, dynamic>> steps) {
    return steps.any((step) {
      final travelMode = (step['travel_mode'] ?? '').toString().toUpperCase();
      return travelMode == 'TRANSIT' && step['transit_details'] is Map;
    });
  }

  static bool _liveStepUsesUnsupportedPaidTransit(Map<String, dynamic> step) {
    final travelMode = (step['travel_mode'] ?? '').toString().toUpperCase();

    if (travelMode == 'WALKING') return false;
    if (travelMode != 'TRANSIT') return false;

    final transitDetails = step['transit_details'];
    if (transitDetails is! Map) return true;

    final line = transitDetails['line'];
    if (line is! Map) return true;

    final vehicle = line['vehicle'];
    final vehicleType =
        vehicle is Map ? (vehicle['type'] ?? '').toString().toUpperCase() : '';
    final vehicleName =
        vehicle is Map ? (vehicle['name'] ?? '').toString().toUpperCase() : '';

    final lineText = [
      line['name'],
      line['short_name'],
      line['agency'],
      vehicleType,
      vehicleName,
    ].whereType<Object>().join(' ').toUpperCase();

    final supported = lineText.contains('MRT') ||
        lineText.contains('LRT') ||
        lineText.contains('PNR') ||
        lineText.contains('TRAIN') ||
        lineText.contains('RAIL') ||
        lineText.contains('SUBWAY') ||
        lineText.contains('TRAM') ||
        lineText.contains('METRO') ||
        lineText.contains('BUS') ||
        lineText.contains('BUSWAY') ||
        lineText.contains('CAROUSEL') ||
        lineText.contains('P2P') ||
        lineText.contains('JEEP') ||
        lineText.contains('FX') ||
        lineText.contains('UV') ||
        lineText.contains('VAN');

    if (supported) return false;

    final explicitlyUnsupported = lineText.contains('FERRY') ||
        lineText.contains('BOAT') ||
        lineText.contains('SHIP') ||
        lineText.contains('WATER') ||
        lineText.contains('PIER') ||
        lineText.contains('PORT') ||
        lineText.contains('TRICYCLE') ||
        lineText.contains('TRIKE') ||
        lineText.contains('MOTORCYCLE') ||
        lineText.contains('TAXI') ||
        lineText.contains('RIDESHARE') ||
        lineText.contains('RIDE SHARE');

    return explicitlyUnsupported || !supported;
  }

  static bool _liveStepsUseUnsupportedPaidTransit(
    List<Map<String, dynamic>> steps,
  ) {
    return steps.any(_liveStepUsesUnsupportedPaidTransit);
  }

  static List<TravelMode> _liveModeSequence(List<Map<String, dynamic>> steps) {
    final sequence = <TravelMode>[];

    for (final step in steps) {
      final mode = _travelModeForLiveStep(step);
      if (mode == TravelMode.walking) continue;
      if (sequence.isNotEmpty && sequence.last == mode) continue;
      sequence.add(mode);
    }

    return sequence;
  }

  static MultiSegmentFareEstimate _estimateFareForLiveSteps(
    List<Map<String, dynamic>> steps, {
    required PassengerType type,
  }) {
    final segments = <FareSegment>[];

    for (final step in steps) {
      final mode = _travelModeForLiveStep(step);
      final distanceKm = _distanceKmForLiveStep(step);

      if (mode == TravelMode.walking) {
        segments.add(
          FareSegment(
            label: 'Walk',
            mode: TravelMode.walking,
            distanceKm: distanceKm,
            fare: 0,
          ),
        );
        continue;
      }

      segments.add(
        FareSegment(
          label: _rideFareLabelForMode(mode),
          mode: mode,
          distanceKm: distanceKm,
          fare: FareService.estimateFare(mode, distanceKm, type: type),
        ),
      );
    }

    return MultiSegmentFareEstimate(segments: segments);
  }

  static double _totalDistanceKmForLiveSteps(List<Map<String, dynamic>> steps) {
    return steps.fold<double>(
      0,
      (total, step) => total + _distanceKmForLiveStep(step),
    );
  }

  static double _walkDistanceKmForLiveSteps(List<Map<String, dynamic>> steps) {
    return steps.fold<double>(0, (total, step) {
      final mode = _travelModeForLiveStep(step);
      if (mode != TravelMode.walking) return total;
      return total + _distanceKmForLiveStep(step);
    });
  }

  static double _durationMinutesForDirections(Map<String, dynamic> directions) {
    final duration = directions['duration'];
    if (duration is num) return duration.toDouble() / 60.0;
    return 0;
  }

  static String _displayNameForLiveSteps(List<Map<String, dynamic>> steps) {
    return _modeSequenceTitle(_liveModeSequence(steps));
  }

  static String _modeSequenceTitle(List<TravelMode> sequence) {
    final deduped = <TravelMode>[];

    for (final mode in sequence) {
      if (mode == TravelMode.walking) continue;
      if (deduped.isNotEmpty && deduped.last == mode) continue;
      deduped.add(mode);
    }

    if (deduped.isEmpty) return 'Public transport';
    return deduped.map(_vehicleTitleForMode).join(' + ');
  }

  static String _vehicleTitleForMode(TravelMode mode) {
    switch (mode) {
      case TravelMode.jeepney:
        return 'Jeepney';
      case TravelMode.bus:
        return 'Bus';
      case TravelMode.train:
        return 'Train';
      case TravelMode.fx:
        return 'FX';
      case TravelMode.walking:
        return 'Walking';
    }
  }

  static String _rideFareLabelForMode(TravelMode mode) {
    switch (mode) {
      case TravelMode.jeepney:
        return 'Jeepney ride';
      case TravelMode.bus:
        return 'Bus ride';
      case TravelMode.train:
        return 'MRT/LRT ride';
      case TravelMode.fx:
        return 'FX ride';
      case TravelMode.walking:
        return 'Walk';
    }
  }
}
