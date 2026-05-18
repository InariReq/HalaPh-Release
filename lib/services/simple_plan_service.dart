import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:halaph/utils/firebase_modes.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:halaph/models/plan.dart';
import 'package:halaph/services/plan_notification_service.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/services/firebase_app_service.dart';
import 'package:halaph/services/friend_service.dart';

typedef _RemotePlanSnapshot = QuerySnapshot<Map<String, dynamic>>;

class SimplePlanService {
  static final Map<String, TravelPlan> _plans = {};
  static Future<void>? _initialization;
  static final Map<String, String> _ownerUids = {};
  static final Map<String, List<String>> _participantUids = {};
  static StreamSubscription<_RemotePlanSnapshot>? _remotePlansSubscription;
  static String? _loadedForUserId;
  static final Set<String> _recentlyDeletedPlanIds = {};
  static final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  static Stream<void> get changes => _changesController.stream;
  static bool debugAllowMemoryOnlyPlans = false;
  static bool _planLoadRetryScheduled = false;

  static Future<void> initialize({bool forceRefresh = false}) async {
    if (!forceRefresh && _initialization != null) return _initialization;

    // Use a lock to prevent race conditions
    final initialization = _initialization = _initialize(
      forceRefresh: forceRefresh,
    );
    try {
      await initialization;
    } finally {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
    }
  }

  static Future<void> _initialize({required bool forceRefresh}) async {
    if (FirebaseModes.offline) {
      // Offline mode: reset in-memory caches to a clean slate
      _plans.clear();
      _ownerUids.clear();
      _participantUids.clear();
      _loadedForUserId = null;
      return;
    }
    if (!await FirebaseAppService.initialize()) {
      resetCache();
      return;
    }

    final userId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      resetCache();
      return;
    }

    if (!forceRefresh && _loadedForUserId == userId) {
      _listenToRemotePlans(userId);
      return;
    }

    try {
      final remotePlans = await _loadRemotePlans().timeout(
        const Duration(seconds: 10),
      );
      _plans
        ..clear()
        ..addEntries(remotePlans.map((plan) => MapEntry(plan.id, plan)));
      _loadedForUserId = userId;
      _planLoadRetryScheduled = false;
      _listenToRemotePlans(userId);
    } catch (error) {
      debugPrint('Plan load failed: $error');

      // Do not treat one slow Firebase read as final.
      // Keep any existing in-memory plans for the same user, start the live
      // listener, and retry once shortly after the UI becomes responsive.
      if (_loadedForUserId != userId) {
        _plans.clear();
        _ownerUids.clear();
        _participantUids.clear();
        _loadedForUserId = userId;
        _notifyChanged();
      }

      _listenToRemotePlans(userId);
      _schedulePlanLoadRetry(userId);
    }
  }

  static void _schedulePlanLoadRetry(String userId) {
    if (_planLoadRetryScheduled) return;

    _planLoadRetryScheduled = true;
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () async {
        if (_currentUserId() != userId) {
          _planLoadRetryScheduled = false;
          return;
        }

        try {
          await initialize(forceRefresh: true);
        } catch (error) {
          debugPrint('Plan load retry failed: $error');
          _planLoadRetryScheduled = false;
        }
      }),
    );
  }

  static List<TravelPlan> getUserPlans({String? ownerId}) {
    final identities = _identityCandidates(ownerId ?? 'current_user');
    return _plans.values
        .where(
          (plan) =>
              _isPlanOwner(plan, identities) &&
              !_isCollaborative(plan) &&
              !isPlanInTripHistory(plan),
        )
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
  }

  static List<TravelPlan> getCollaborativePlans({String? ownerId}) {
    final identities = _identityCandidates(ownerId ?? 'current_user');
    return _plans.values
        .where(
          (plan) =>
              _isPlanParticipant(plan, identities) &&
              _isCollaborative(plan) &&
              !isPlanInTripHistory(plan),
        )
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
  }

  static List<TravelPlan> getPlansSharedWithUser(String participantId) {
    final identities = _identityCandidates(participantId);
    return _plans.values
        .where(
          (plan) =>
              _isPlanParticipant(plan, identities) &&
              !_isPlanOwner(plan, identities) &&
              !isPlanInTripHistory(plan),
        )
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
  }

  static TravelPlan? getNextUpcomingPlan({String? userId}) {
    final identities = _identityCandidates(userId ?? 'current_user');
    final upcoming = _visibleCurrentOrFuturePlans(identities);

    return upcoming.isNotEmpty ? upcoming.first : null;
  }

  static List<TravelPlan> getAllUpcomingPlans({String? userId}) {
    final identities = _identityCandidates(userId ?? 'current_user');
    return _visibleCurrentOrFuturePlans(identities);
  }

  static bool isPlanInTripHistory(TravelPlan plan) {
    final today = _dayOnly(DateTime.now());
    return plan.isFinished || _dayOnly(plan.endDate).isBefore(today);
  }

  static TravelPlan createPlan({
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    required List<Destination> destinations,
    String? createdBy,
    String? bannerImage,
  }) {
    final id = _newPlanId();
    final uid = createdBy ?? _currentUserId() ?? 'demo_user';

    final itinerary = _buildItinerary(startDate, endDate, destinations);

    final plan = TravelPlan(
      id: id,
      title: title,
      startDate: startDate,
      endDate: endDate,
      participantUids: [uid],
      createdBy: uid,
      itinerary: itinerary,
      isShared: false,
      bannerImage: bannerImage,
    );

    _plans[id] = plan;
    _notifyChanged();
    _saveRemotePlanInBackground(plan);
    return plan;
  }

  static TravelPlan? getPlanById(String id) => _plans[id];

  static Future<bool> updatePlan({
    required String planId,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    List<Destination>? destinations,
    Map<int, List<Destination>>? itinerary,
    Map<String, String>? destinationTimes,
    Map<String, String>? destinationEndTimes,
    String? bannerImage,
    String? meetingPointName,
    String? meetingPointAddress,
    double? meetingPointLatitude,
    double? meetingPointLongitude,
    Map<String, ParticipantStartLocation>? participantStartLocations,
    bool replaceMeetingPoint = false,
    String? status,
  }) async {
    final existing = _plans[planId];
    if (existing == null) return false;

    final effectiveStartDate = startDate ?? existing.startDate;
    final effectiveEndDate = endDate ?? existing.endDate;
    final newItinerary = itinerary != null
        ? _buildItineraryFromDayMap(
            effectiveStartDate,
            effectiveEndDate,
            itinerary,
            destinationTimes: destinationTimes,
            destinationEndTimes: destinationEndTimes,
          )
        : destinations != null
            ? _buildItinerary(
                effectiveStartDate, effectiveEndDate, destinations)
            : existing.itinerary;

    final updated = TravelPlan(
      id: existing.id,
      title: title ?? existing.title,
      startDate: startDate ?? existing.startDate,
      endDate: endDate ?? existing.endDate,
      participantUids: existing.participantUids,
      createdBy: existing.createdBy,
      itinerary: newItinerary,
      isShared: existing.isShared,
      bannerImage: bannerImage ?? existing.bannerImage,
      meetingPointName:
          replaceMeetingPoint ? meetingPointName : existing.meetingPointName,
      meetingPointAddress: replaceMeetingPoint
          ? meetingPointAddress
          : existing.meetingPointAddress,
      meetingPointLatitude: replaceMeetingPoint
          ? meetingPointLatitude
          : existing.meetingPointLatitude,
      meetingPointLongitude: replaceMeetingPoint
          ? meetingPointLongitude
          : existing.meetingPointLongitude,
      participantStartLocations:
          participantStartLocations ?? existing.participantStartLocations,
      collaboratorUids: existing.collaboratorUids,
      status: status ?? existing.status,
    );

    try {
      await _saveRemotePlan(updated);
      _plans[planId] = updated;
      _notifyChanged();
      return true;
    } catch (error) {
      debugPrint('Failed to update plan: $error');
      return false;
    }
  }

  static Future<bool> deletePlan(String id) async {
    await PlanNotificationService.cancelPlanReminders(id);
    final existing = _plans[id];
    if (existing == null) {
      debugPrint('Delete failed: Plan $id not found locally');
      return false;
    }

    // Mark as recently deleted to prevent real-time listener from re-adding
    _recentlyDeletedPlanIds.add(id);

    final deleted = await _deleteRemotePlan(id);
    if (!deleted) {
      debugPrint('Delete failed: Remote delete failed for plan $id');
      _recentlyDeletedPlanIds.remove(id);
      return false;
    }
    _plans.remove(id);
    _ownerUids.remove(id);
    _participantUids.remove(id);
    _notifyChanged();
    // Clear the recently deleted marker after a delay
    Future.delayed(const Duration(seconds: 5), () {
      _recentlyDeletedPlanIds.remove(id);
    });
    return true;
  }

  static List<TravelPlan> getAllPlans() => _plans.values.toList();

  static Future<bool> markPlanFinished(String id) async {
    await PlanNotificationService.cancelPlanReminders(id);
    return updatePlan(planId: id, status: 'finished');
  }

  static Future<bool> markPlanActive(String id) async {
    return updatePlan(planId: id, status: 'active');
  }

  static Future<TravelPlan?> joinSharedPlan(
    String planId, {
    String? participantCode,
  }) async {
    if (FirebaseModes.offline) {
      // In offline mode, do not attempt remote join
      return null;
    }
    final normalizedPlanId = planId.trim();
    if (normalizedPlanId.isEmpty) return null;

    if (!await FirebaseAppService.initialize()) return null;
    final currentUid = _currentUserId();
    if (currentUid == null) return null;

    try {
      final doc = await _plansCollection
          .doc(normalizedPlanId)
          .get()
          .timeout(const Duration(seconds: 8));
      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      final plan = TravelPlan.fromJson(Map<String, dynamic>.from(data));
      final existingUids = data['participantUids'] is List
          ? List<String>.from(data['participantUids'] as List)
          : <String>[];
      final updatedUids = <String>{...existingUids, currentUid}.toList();

      final code = _normalizeCode(participantCode ?? '');
      final update = <String, Object>{
        'participantUids': FieldValue.arrayUnion([currentUid]),
        'isShared': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (code.isNotEmpty) {
        update['participantUids'] = FieldValue.arrayUnion([code]);
      }

      await doc.reference.update(update).timeout(const Duration(seconds: 8));

      final participantUids = <String>{...plan.participantUids};
      if (code.isNotEmpty) participantUids.add(code);
      final joined = TravelPlan(
        id: plan.id,
        title: plan.title,
        startDate: plan.startDate,
        endDate: plan.endDate,
        participantUids: participantUids.toList(),
        createdBy: plan.createdBy,
        itinerary: plan.itinerary,
        isShared: true,
        bannerImage: plan.bannerImage,
        meetingPointName: plan.meetingPointName,
        meetingPointAddress: plan.meetingPointAddress,
        meetingPointLatitude: plan.meetingPointLatitude,
        meetingPointLongitude: plan.meetingPointLongitude,
        participantStartLocations: plan.participantStartLocations,
        collaboratorUids: plan.collaboratorUids,
      );

      _plans[joined.id] = joined;
      _ownerUids[joined.id] = data['ownerUid'] as String? ?? currentUid;
      _participantUids[joined.id] = updatedUids;
      _loadedForUserId = currentUid;
      _listenToRemotePlans(currentUid);
      _notifyChanged();
      return joined;
    } catch (error) {
      debugPrint('Failed to join shared plan: $error');
      return null;
    }
  }

  static void resetCache() {
    unawaited(_remotePlansSubscription?.cancel());
    _remotePlansSubscription = null;
    _loadedForUserId = null;
    _plans.clear();
    _loadedForUserId = null;
    _initialization = null;
    _ownerUids.clear();
    _participantUids.clear();
  }

  static Future<void> refreshPlanReminders() async {
    for (final plan in _plans.values) {
      await PlanNotificationService.schedulePlanReminders(plan);
    }
  }

  static Future<void> cancelAllPlanReminders() async {
    for (final planId in _plans.keys) {
      await PlanNotificationService.cancelPlanReminders(planId);
    }
  }

  static Future<bool> updatePlanParticipants({
    required String planId,
    required List<String> participantUids,
    List<String> collaboratorUids = const [],
  }) async {
    final existing = _plans[planId];
    if (existing == null) return false;

    final ownerUid =
        _ownerUids[planId] ?? _currentUserId() ?? existing.createdBy;
    final selectedParticipants = participantUids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final collaboratorIds = collaboratorUids.isNotEmpty
        ? collaboratorUids
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
        : await _editorCollaboratorIdsForSelected(selectedParticipants);

    final pending = TravelPlan(
      id: existing.id,
      title: existing.title,
      startDate: existing.startDate,
      endDate: existing.endDate,
      participantUids: <String>{ownerUid, ...selectedParticipants}.toList(),
      createdBy: ownerUid,
      itinerary: existing.itinerary,
      isShared: selectedParticipants.isNotEmpty,
      bannerImage: existing.bannerImage,
      meetingPointName: existing.meetingPointName,
      meetingPointAddress: existing.meetingPointAddress,
      meetingPointLatitude: existing.meetingPointLatitude,
      meetingPointLongitude: existing.meetingPointLongitude,
      participantStartLocations: existing.participantStartLocations,
      collaboratorUids: collaboratorIds,
    );

    final resolvedParticipantUids = await _resolveRemoteParticipants(
      plan: pending,
      ownerUid: ownerUid,
      currentUid: _currentUserId() ?? ownerUid,
    );

    final updated = TravelPlan(
      id: existing.id,
      title: existing.title,
      startDate: existing.startDate,
      endDate: existing.endDate,
      participantUids: resolvedParticipantUids,
      createdBy: ownerUid,
      itinerary: existing.itinerary,
      isShared: resolvedParticipantUids.length > 1,
      bannerImage: existing.bannerImage,
      meetingPointName: existing.meetingPointName,
      meetingPointAddress: existing.meetingPointAddress,
      meetingPointLatitude: existing.meetingPointLatitude,
      meetingPointLongitude: existing.meetingPointLongitude,
      participantStartLocations: existing.participantStartLocations,
      collaboratorUids: collaboratorIds,
    );

    try {
      await _saveRemotePlan(updated);
      final remoteParticipantUids =
          _participantUids[planId] ?? resolvedParticipantUids;
      _plans[planId] = TravelPlan(
        id: updated.id,
        title: updated.title,
        startDate: updated.startDate,
        endDate: updated.endDate,
        participantUids: remoteParticipantUids,
        createdBy: updated.createdBy,
        itinerary: updated.itinerary,
        isShared: remoteParticipantUids.length > 1,
        bannerImage: updated.bannerImage,
        meetingPointName: updated.meetingPointName,
        meetingPointAddress: updated.meetingPointAddress,
        meetingPointLatitude: updated.meetingPointLatitude,
        meetingPointLongitude: updated.meetingPointLongitude,
        participantStartLocations: updated.participantStartLocations,
        collaboratorUids: collaboratorIds,
      );
      _notifyChanged();
      return true;
    } catch (error) {
      debugPrint('Failed to update plan collaborators: $error');
      _plans[planId] = existing;
      return false;
    }
  }

  static Future<TravelPlan> savePlan({
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    required Map<int, List<Destination>> itinerary,
    Map<String, String>? destinationTimes,
    Map<String, String>? destinationEndTimes,
    String createdBy = 'current_user',
    List<String> participantUids = const [],
    List<String> collaboratorUids = const [],
    String? bannerImage,
  }) async {
    final id = _newPlanId();

    final dayItineraries = <DayItinerary>[];
    final totalDays = endDate.difference(startDate).inDays + 1;

    for (int day = 0; day < totalDays; day++) {
      final date = startDate.add(Duration(days: day));
      final dests = itinerary[day + 1] ?? [];
      if (dests.isEmpty) continue;

      final items = <ItineraryItem>[];
      for (int i = 0; i < dests.length; i++) {
        final dest = dests[i];
        final timeStr = destinationTimes?[dest.id] ?? '10:00 AM';
        final (rawHour, rawMinute) = _parseTime(timeStr);
        final (hour, minute) = _normalizeStartTimeForDate(
          date,
          rawHour,
          rawMinute,
        );

        final endTimeStr = destinationEndTimes?[dest.id];
        final (rawEndHour, rawEndMinute) = endTimeStr == null
            ? (((hour + 1) % 24), minute)
            : _parseTime(endTimeStr);
        final (endHour, endMinute) = _normalizeEndTimeForDate(
          date,
          (hour, minute),
          rawEndHour,
          rawEndMinute,
        );

        debugPrint(
          'Plan time save: ${dest.name} start=$hour:${minute.toString().padLeft(2, '0')} end=$endHour:${endMinute.toString().padLeft(2, '0')}',
        );

        items.add(
          ItineraryItem(
            id: '${id}_item_${day}_$i',
            destination: dest,
            startTime: TimeOfDay(hour: hour, minute: minute),
            endTime: TimeOfDay(hour: endHour, minute: endMinute),
            dayNumber: day + 1,
            notes: 'Visit ${dest.name}',
          ),
        );
      }

      dayItineraries.add(DayItinerary(date: date, items: items));
    }

    // Normalize participant IDs (include creator + selected collaborators)
    final creator =
        createdBy.trim().isNotEmpty ? createdBy.trim() : 'current_user';
    final participants = <String>{creator}..addAll(
        participantUids
            .where((id) => id.trim().isNotEmpty)
            .map((id) => id.trim()),
      );

    final banner =
        _cleanImageUrl(bannerImage) ?? _firstDestinationImage(dayItineraries);

    final editorCollaboratorIds = collaboratorUids.isNotEmpty
        ? collaboratorUids
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList()
        : await _editorCollaboratorIdsForSelected(
            participants.where((id) => id != creator),
          );

    final plan = TravelPlan(
      id: id,
      title: title,
      startDate: startDate,
      endDate: endDate,
      participantUids: participants.toList(),
      createdBy: creator,
      itinerary: dayItineraries,
      isShared: participants.length > 1,
      bannerImage: banner,
      collaboratorUids: editorCollaboratorIds,
    );

    await _saveRemotePlan(plan);
    _plans[id] = plan;
    _notifyChanged();
    return plan;
  }

  static void clearAllPlans() {
    final ids = _plans.keys.toList();
    _plans.clear();
    _ownerUids.clear();
    _participantUids.clear();
    _notifyChanged();
    for (final id in ids) {
      unawaited(_deleteRemotePlan(id));
    }
  }

  static Future<bool> addDestinationToPlan({
    required String planId,
    required Destination destination,
    int dayNumber = 1,
    String startTime = '10:30 AM',
  }) async {
    final existing = _plans[planId];
    if (existing == null) return false;

    final safeDay = dayNumber.clamp(1, existing.totalDays).toInt();
    final targetDate = existing.startDate.add(Duration(days: safeDay - 1));
    final (hour, minute) = _parseTime(startTime);
    final newItem = ItineraryItem(
      id: '${planId}_item_${DateTime.now().microsecondsSinceEpoch}',
      destination: destination,
      startTime: TimeOfDay(hour: hour, minute: minute),
      endTime: TimeOfDay(hour: (hour + 1) % 24, minute: minute),
      dayNumber: safeDay,
      notes: 'Visit ${destination.name}',
    );

    final itinerary = existing.itinerary
        .map((day) => DayItinerary(date: day.date, items: List.of(day.items)))
        .toList();
    final dayIndex = itinerary.indexWhere(
      (day) => _sameDate(day.date, targetDate),
    );
    if (dayIndex >= 0) {
      itinerary[dayIndex] = DayItinerary(
        date: itinerary[dayIndex].date,
        items: [...itinerary[dayIndex].items, newItem],
      );
    } else {
      itinerary.add(DayItinerary(date: targetDate, items: [newItem]));
      itinerary.sort((a, b) => a.date.compareTo(b.date));
    }

    final updated = TravelPlan(
      id: existing.id,
      title: existing.title,
      startDate: existing.startDate,
      endDate: existing.endDate,
      participantUids: existing.participantUids,
      createdBy: existing.createdBy,
      itinerary: itinerary,
      isShared: existing.isShared,
      bannerImage: existing.bannerImage,
      meetingPointName: existing.meetingPointName,
      meetingPointAddress: existing.meetingPointAddress,
      meetingPointLatitude: existing.meetingPointLatitude,
      meetingPointLongitude: existing.meetingPointLongitude,
      participantStartLocations: existing.participantStartLocations,
      collaboratorUids: existing.collaboratorUids,
    );

    try {
      await _saveRemotePlan(updated);
      _plans[planId] = updated;
      _notifyChanged();
      return true;
    } catch (error) {
      debugPrint('Failed to add destination to plan: $error');
      return false;
    }
  }

  static List<DayItinerary> _buildItineraryFromDayMap(
    DateTime startDate,
    DateTime endDate,
    Map<int, List<Destination>> itinerary, {
    Map<String, String>? destinationTimes,
    Map<String, String>? destinationEndTimes,
  }) {
    final dayItineraries = <DayItinerary>[];
    final totalDays = endDate.difference(startDate).inDays + 1;

    for (int day = 0; day < totalDays; day++) {
      final date = startDate.add(Duration(days: day));
      final destinations = itinerary[day + 1] ?? [];
      if (destinations.isEmpty) continue;

      final items = <ItineraryItem>[];
      for (int index = 0; index < destinations.length; index++) {
        final destination = destinations[index];
        final startText = destinationTimes?[destination.id] ?? '10:00 AM';
        final (rawStartHour, rawStartMinute) = _parseTime(startText);
        final (startHour, startMinute) = _normalizeStartTimeForDate(
          date,
          rawStartHour,
          rawStartMinute,
        );

        final endText = destinationEndTimes?[destination.id];
        final (rawEndHour, rawEndMinute) = endText == null
            ? (((startHour + 1) % 24), startMinute)
            : _parseTime(endText);
        final (endHour, endMinute) = _normalizeEndTimeForDate(
          date,
          (startHour, startMinute),
          rawEndHour,
          rawEndMinute,
        );

        debugPrint(
          'Plan time update: ${destination.name} start=$startHour:${startMinute.toString().padLeft(2, '0')} end=$endHour:${endMinute.toString().padLeft(2, '0')}',
        );

        items.add(
          ItineraryItem(
            id: '${destination.id}_${day}_$index',
            destination: destination,
            startTime: TimeOfDay(hour: startHour, minute: startMinute),
            endTime: TimeOfDay(hour: endHour, minute: endMinute),
            dayNumber: day + 1,
            notes: 'Visit ${destination.name}',
          ),
        );
      }

      dayItineraries.add(DayItinerary(date: date, items: items));
    }

    return dayItineraries;
  }

  static List<DayItinerary> _buildItinerary(
    DateTime start,
    DateTime end,
    List<Destination> dests,
  ) {
    final days = end.difference(start).inDays + 1;
    final itineraries = <DayItinerary>[];

    for (int d = 0; d < days; d++) {
      final date = start.add(Duration(days: d));
      final perDay = (dests.length / days).ceil();
      final startIdx = d * perDay;
      final endIdx = (startIdx + perDay).clamp(0, dests.length);

      final items = <ItineraryItem>[];
      for (int i = startIdx; i < endIdx; i++) {
        final dest = dests[i];
        final hour = 9 + (i % 4) * 2;
        items.add(
          ItineraryItem(
            id: 'item_${DateTime.now().millisecondsSinceEpoch}_$i',
            destination: dest,
            startTime: TimeOfDay(hour: hour, minute: 0),
            endTime: TimeOfDay(hour: hour + 2, minute: 0),
            dayNumber: d + 1,
            notes: 'Visit ${dest.name}',
          ),
        );
      }

      if (items.isNotEmpty) {
        itineraries.add(DayItinerary(date: date, items: items));
      }
    }

    return itineraries;
  }

  static (int, int) _normalizeStartTimeForDate(
    DateTime date,
    int hour,
    int minute,
  ) {
    final now = DateTime.now();
    final planDate = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);

    if (planDate == today && hour < 12) {
      final candidate = DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      );
      final pmCandidate = candidate.add(const Duration(hours: 12));

      if (!candidate.isAfter(now) && pmCandidate.isAfter(now)) {
        return (hour + 12, minute);
      }
    }

    return (hour, minute);
  }

  static (int, int) _normalizeEndTimeForDate(
    DateTime date,
    (int, int) startTime,
    int hour,
    int minute,
  ) {
    final startAt = DateTime(
      date.year,
      date.month,
      date.day,
      startTime.$1,
      startTime.$2,
    );
    final endAt = DateTime(date.year, date.month, date.day, hour, minute);

    if (!endAt.isAfter(startAt) && hour < 12) {
      final pmEndAt = endAt.add(const Duration(hours: 12));
      if (pmEndAt.isAfter(startAt)) {
        return (hour + 12, minute);
      }
    }

    return (hour, minute);
  }

  static (int, int) _parseTime(String timeStr) {
    final normalized = timeStr.trim().toUpperCase();
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(
      normalized,
    );

    if (match == null) {
      return (10, 0);
    }

    var hour = int.tryParse(match.group(1) ?? '') ?? 10;
    final minute = (int.tryParse(match.group(2) ?? '') ?? 0).clamp(0, 59);
    final period = match.group(3);

    if (period == 'PM' && hour < 12) {
      hour += 12;
    } else if (period == 'AM' && hour == 12) {
      hour = 0;
    }

    return (hour.clamp(0, 23), minute);
  }

  static Future<List<TravelPlan>> _loadRemotePlans() async {
    if (FirebaseModes.offline) {
      return <TravelPlan>[];
    }
    final userId = _currentUserId();
    if (userId == null) return <TravelPlan>[];

    final snapshot = await _plansCollection
        .where('participantUids', arrayContains: userId)
        .get()
        .timeout(const Duration(seconds: 8));

    final plans = _decodeRemotePlanDocs(snapshot.docs, userId);
    return plans;
  }

  static List<TravelPlan> _decodeRemotePlanDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String userId,
  ) {
    _ownerUids.clear();
    _participantUids.clear();

    final plans = <TravelPlan>[];
    for (final doc in docs) {
      try {
        final plan = TravelPlan.fromFirestore(doc);
        final data = doc.data();
        plans.add(plan);
        _ownerUids[plan.id] = data['ownerUid'] as String? ?? userId;
        _participantUids[plan.id] = data['participantUids'] is List
            ? List<String>.from(data['participantUids'] as List)
            : <String>[userId];
      } catch (error) {
        debugPrint('Skipping invalid remote plan ${doc.id}: $error');
      }
    }
    return plans;
  }

  static void _listenToRemotePlans(String userId) {
    if (FirebaseModes.offline) return;
    if (_loadedForUserId == userId && _remotePlansSubscription != null) {
      return;
    }

    unawaited(_remotePlansSubscription?.cancel());
    _loadedForUserId = userId;
    _remotePlansSubscription = _plansCollection
        .where('participantUids', arrayContains: userId)
        .snapshots()
        .listen(
      (snapshot) {
        if (_currentUserId() != userId) return;
        final remotePlans = _decodeRemotePlanDocs(snapshot.docs, userId)
            .where((plan) => !_recentlyDeletedPlanIds.contains(plan.id))
            .toList();
        _plans
          ..clear()
          ..addEntries(remotePlans.map((plan) => MapEntry(plan.id, plan)));
        _loadedForUserId = userId;
        _notifyChanged();
      },
      onError: (Object error) {
        debugPrint('Plan live updates failed: $error');
      },
    );
  }

  // Legacy plan migration removed - no longer needed

  // Legacy plan migration removed - plans now only stored in sharedPlans collection

  static Future<void> _saveRemotePlan(TravelPlan plan) async {
    // Guard: reject empty plan ID
    if (plan.id.isEmpty) {
      throw StateError('Cannot save plan: plan ID is empty.');
    }

    if (FirebaseModes.offline) {
      _plans[plan.id] = plan;
      _ownerUids[plan.id] = plan.createdBy;
      _participantUids[plan.id] = plan.participantUids;
      _notifyChanged();
      return;
    }
    final currentUid = _currentUserId();
    if (currentUid == null) {
      if (debugAllowMemoryOnlyPlans) {
        _ownerUids[plan.id] ??= plan.createdBy;
        _participantUids[plan.id] = plan.participantUids;
        return;
      }
      throw StateError('Sign in before saving plans to Firebase.');
    }

    final existingOwnerUid = _ownerUids[plan.id];
    final ownerUid = existingOwnerUid ?? currentUid;
    var resolvedParticipantUids = await _resolveRemoteParticipants(
      plan: plan,
      ownerUid: ownerUid,
      currentUid: currentUid,
    );

    if (currentUid != ownerUid) {
      resolvedParticipantUids = {
        ...(_participantUids[plan.id] ?? <String>[ownerUid]),
        currentUid,
      }.toList();
    } else if (!resolvedParticipantUids.contains(ownerUid)) {
      resolvedParticipantUids = [...resolvedParticipantUids, ownerUid];
    }

    // Build clean payload with only fields allowed by planFields() in rules
    final data = plan.toJson();

    // Debug logging
    debugPrint('Saving plan to: sharedPlans/${plan.id}');
    debugPrint('Current UID: $currentUid');
    debugPrint('Owner UID: $ownerUid');
    debugPrint('Plan payload keys: ${data.keys.toList()}');

    // Force required fields to match rules
    data['createdBy'] = ownerUid;
    data['ownerUid'] = ownerUid;
    data['ownerId'] = ownerUid;
    data['participantUids'] =
        resolvedParticipantUids.map((e) => e.trim()).toSet().toList();
    data['collaboratorUids'] =
        plan.collaboratorUids.map((e) => e.trim()).toList();

    // Ensure timestamps
    data['updatedAt'] = FieldValue.serverTimestamp();
    if (!data.containsKey('createdAt') || data['createdAt'] == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }

    // Remove fields NOT in planFields() in firestore.rules
    // 'id' is NOT in planFields() - remove it
    const allowedFields = {
      'title',
      'description',
      'createdBy',
      'ownerId',
      'ownerUid',
      'participantUids',
      'collaboratorUids',
      'startDate',
      'endDate',
      'days',
      'itinerary',
      'itineraries',
      'items',
      'destinationIds',
      'bannerImage',
      'bannerImageUrl',
      'meetingPointName',
      'meetingPointAddress',
      'meetingPointLatitude',
      'meetingPointLongitude',
      'participantStartLocations',
      'isShared',
      'isPublic',
      'status',
      'version',
      'createdAt',
      'updatedAt',
    };
    data.removeWhere((key, value) => !allowedFields.contains(key));

    debugPrint('Final plan payload: $data');

    final planRef = _plansCollection.doc(plan.id);

    if (currentUid != ownerUid) {
      final editorData = <String, dynamic>{
        'title': data['title'],
        'startDate': data['startDate'],
        'endDate': data['endDate'],
        'itinerary': data['itinerary'],
        'isShared': data['isShared'],
        'bannerImage': data['bannerImage'],
        'meetingPointName': data.containsKey('meetingPointName')
            ? data['meetingPointName']
            : FieldValue.delete(),
        'meetingPointAddress': data.containsKey('meetingPointAddress')
            ? data['meetingPointAddress']
            : FieldValue.delete(),
        'meetingPointLatitude': data.containsKey('meetingPointLatitude')
            ? data['meetingPointLatitude']
            : FieldValue.delete(),
        'meetingPointLongitude': data.containsKey('meetingPointLongitude')
            ? data['meetingPointLongitude']
            : FieldValue.delete(),
        'participantStartLocations':
            data.containsKey('participantStartLocations')
                ? data['participantStartLocations']
                : FieldValue.delete(),
        'updatedAt': data['updatedAt'],
      };

      editorData.removeWhere((key, value) => value == null);

      debugPrint('Editor update payload keys: ${editorData.keys.toList()}');

      await planRef.update(editorData).timeout(const Duration(seconds: 8));
    } else {
      await planRef.set(data).timeout(const Duration(seconds: 8));
    }

    _ownerUids[plan.id] = ownerUid;
    _participantUids[plan.id] = resolvedParticipantUids;
    await PlanNotificationService.schedulePlanReminders(plan);
  }

  static void _saveRemotePlanInBackground(TravelPlan plan) {
    unawaited(
      _saveRemotePlan(plan).catchError((Object error) {
        debugPrint('Background plan sync failed: $error');
      }),
    );
  }

  static Future<List<String>> _resolveRemoteParticipants({
    required TravelPlan plan,
    required String ownerUid,
    required String currentUid,
  }) async {
    if (currentUid != ownerUid) {
      return {
        ...(_participantUids[plan.id] ?? <String>[ownerUid]),
        currentUid,
      }.toList();
    }

    final participantCodes =
        plan.participantUids.map(_normalizeCode).where(_isFriendCode).toSet();
    final creatorCode = _normalizeCode(plan.createdBy);
    final collaboratorCodes =
        participantCodes.where((code) => code != creatorCode).toList();

    if (collaboratorCodes.isEmpty) {
      return mergeResolvedParticipantsForTesting(
        ownerUid: ownerUid,
        selectedParticipants: plan.participantUids,
        resolvedCodeUids: const <String>[],
      );
    }

    try {
      final resolved = await FriendService()
          .resolveParticipantUids(participantCodes)
          .timeout(const Duration(seconds: 6));
      return mergeResolvedParticipantsForTesting(
        ownerUid: ownerUid,
        selectedParticipants: plan.participantUids,
        resolvedCodeUids: resolved,
      );
    } catch (e) {
      debugPrint('Failed to resolve some participants: $e');
      // Fallback: use existing resolved UIDs from Firebase if available
      final existingUids = _participantUids[plan.id] ?? <String>[];
      return mergeResolvedParticipantsForTesting(
        ownerUid: ownerUid,
        selectedParticipants: existingUids,
        resolvedCodeUids: const <String>[],
      );
    }
  }

  @visibleForTesting
  static List<String> mergeResolvedParticipantsForTesting({
    required String ownerUid,
    required Iterable<String> selectedParticipants,
    required Iterable<String> resolvedCodeUids,
  }) {
    final merged = <String>{ownerUid.trim()};
    for (final participant in selectedParticipants) {
      final trimmed = participant.trim();
      if (trimmed.isEmpty || _isFriendCode(trimmed)) continue;
      merged.add(trimmed);
    }
    for (final uid in resolvedCodeUids) {
      final trimmed = uid.trim();
      if (trimmed.isNotEmpty) merged.add(trimmed);
    }
    return merged.where((uid) => uid.isNotEmpty).toList();
  }

  static Future<bool> _deleteRemotePlan(String id) async {
    if (FirebaseModes.offline) {
      _plans.remove(id);
      _ownerUids.remove(id);
      _participantUids.remove(id);
      _notifyChanged();
      return true;
    }
    try {
      // Check if plan exists and verify ownership
      final doc = await _plansCollection.doc(id).get();
      if (!doc.exists) {
        debugPrint('Plan not found: $id');
        return false;
      }

      final data = doc.data();
      final createdBy = data?['createdBy'] as String? ?? '';
      final ownerUid = data?['ownerUid'] as String? ?? '';
      final ownerId = data?['ownerId'] as String? ?? '';
      final currentUid = _currentUserId();

      if (currentUid != createdBy &&
          currentUid != ownerUid &&
          currentUid != ownerId) {
        debugPrint('Delete blocked: user is not owner');
        return false; // Cannot delete plans you don't own
      }

      await _plansCollection
          .doc(id)
          .delete()
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (e) {
      debugPrint('Delete plan error: $e');
      return false;
    }
  }

  // Collaboration helpers: add/remove collaborator to a plan
  static Future<bool> addCollaborator(
    String planId,
    String collaboratorUid,
  ) async {
    final plan = _plans[planId];
    if (plan == null) return false;
    final ownerUid = _ownerUids[planId] ?? (plan.createdBy);
    if (collaboratorUid == ownerUid) {
      return false; // can't add owner as collaborator
    }
    try {
      // Debug logging
      debugPrint('Updating plan: sharedPlans/$planId');
      debugPrint('Current UID: ${_currentUserId()}');
      debugPrint('Operation: addCollaborator');
      debugPrint('Adding collaborator: $collaboratorUid');

      await _plansCollection.doc(planId).update({
        'participantUids': FieldValue.arrayUnion([collaboratorUid]),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 8));
      // Update local cache
      final list = List<String>.from(_participantUids[planId] ?? []);
      if (!list.contains(collaboratorUid)) list.add(collaboratorUid);
      _participantUids[planId] = list;
      _notifyChanged();
      return true;
    } catch (e) {
      debugPrint('Add collaborator failed: $e');
      return false;
    }
  }

  static Future<bool> removeCollaborator(
    String planId,
    String collaboratorUid,
  ) async {
    final plan = _plans[planId];
    if (plan == null) return false;
    final ownerUid = _ownerUids[planId] ?? (plan.createdBy);
    if (collaboratorUid == ownerUid) {
      return false; // cannot remove owner from plan
    }
    try {
      // Debug logging
      debugPrint('Updating plan: sharedPlans/$planId');
      debugPrint('Current UID: ${_currentUserId()}');
      debugPrint('Operation: removeCollaborator');
      debugPrint('Removing collaborator: $collaboratorUid');

      await _plansCollection.doc(planId).update({
        'participantUids': FieldValue.arrayRemove([collaboratorUid]),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 8));
      // Update local cache
      final list = List<String>.from(_participantUids[planId] ?? []);
      list.remove(collaboratorUid);
      _participantUids[planId] = list;
      _notifyChanged();
      return true;
    } catch (e) {
      debugPrint('Remove collaborator failed: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getPlanStatistics() async {
    final userId = _currentUserId();
    if (userId == null) return <String, dynamic>{};

    final userPlans = getUserPlans();
    final collaborativePlans = getCollaborativePlans();

    var totalDestinations = 0;
    var totalDays = 0;
    var upcomingTrips = 0;
    final now = DateTime.now();

    for (final plan in [...userPlans, ...collaborativePlans]) {
      for (final day in plan.itinerary) {
        totalDestinations += day.items.length;
        totalDays++;
      }
      if (plan.startDate.isAfter(now)) {
        upcomingTrips++;
      }
    }

    return <String, dynamic>{
      'totalPlans': userPlans.length + collaborativePlans.length,
      'userPlans': userPlans.length,
      'collaborativePlans': collaborativePlans.length,
      'totalDestinations': totalDestinations,
      'totalDays': totalDays,
      'upcomingTrips': upcomingTrips,
    };
  }

  static Future<List<TravelPlan>> searchPlans(String query) async {
    if (query.trim().isEmpty) return [];
    final lowerQuery = query.toLowerCase();

    final allPlans = getAllPlans();
    return allPlans.where((plan) {
      if (plan.title.toLowerCase().contains(lowerQuery)) return true;
      for (final day in plan.itinerary) {
        for (final item in day.items) {
          if (item.destination.name.toLowerCase().contains(lowerQuery)) {
            return true;
          }
        }
      }
      return false;
    }).toList();
  }

  static Future<bool> leavePlan(String planId) async {
    final currentUid = _currentUserId();
    if (currentUid == null) return false;

    try {
      final doc = await _plansCollection
          .doc(planId)
          .get()
          .timeout(const Duration(seconds: 5));
      if (!doc.exists) return false;

      final data = doc.data();
      if (data == null) return false;

      final ownerUid = data['ownerUid'] as String?;
      if (ownerUid == currentUid) {
        return false;
      }

      final removeValues = <String>[currentUid];
      // Also remove the current user's code from participantUids if available
      try {
        final friendService = FriendService();
        final myCode = await friendService.getMyCode();
        final normalizedCode = _normalizeCode(myCode);
        if (normalizedCode.isNotEmpty && normalizedCode != currentUid) {
          removeValues.add(normalizedCode);
        }
      } catch (_) {
        // If we fail to fetch the code, proceed without removing codes
      }
      final updates = <String, Object>{
        'participantUids': FieldValue.arrayRemove(removeValues),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await doc.reference.update(updates).timeout(const Duration(seconds: 5));

      _plans.remove(planId);
      _ownerUids.remove(planId);
      _participantUids.remove(planId);
      _notifyChanged();
      return true;
    } catch (e) {
      debugPrint('Failed to leave plan: $e');
      return false;
    }
  }

  static Future<bool> updateMyParticipantStartLocation({
    required String planId,
    required String participantId,
    required ParticipantStartLocation? startLocation,
  }) async {
    final existing = _plans[planId];
    if (existing == null) return false;

    final key = participantId.trim();
    if (key.isEmpty) return false;

    final updatedLocations = Map<String, ParticipantStartLocation>.from(
      existing.participantStartLocations,
    );
    if (startLocation == null) {
      updatedLocations.remove(key);
    } else {
      updatedLocations[key] = startLocation;
    }

    if (FirebaseModes.offline) {
      _plans[planId] = TravelPlan(
        id: existing.id,
        title: existing.title,
        startDate: existing.startDate,
        endDate: existing.endDate,
        participantUids: existing.participantUids,
        createdBy: existing.createdBy,
        itinerary: existing.itinerary,
        isShared: existing.isShared,
        bannerImage: existing.bannerImage,
        meetingPointName: existing.meetingPointName,
        meetingPointAddress: existing.meetingPointAddress,
        meetingPointLatitude: existing.meetingPointLatitude,
        meetingPointLongitude: existing.meetingPointLongitude,
        participantStartLocations: updatedLocations,
        collaboratorUids: existing.collaboratorUids,
        status: existing.status,
      );
      _notifyChanged();
      return true;
    }

    try {
      await _plansCollection.doc(planId).update({
        'participantStartLocations': updatedLocations.map(
          (entryKey, value) => MapEntry(entryKey, value.toJson()),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 8));

      _plans[planId] = TravelPlan(
        id: existing.id,
        title: existing.title,
        startDate: existing.startDate,
        endDate: existing.endDate,
        participantUids: existing.participantUids,
        createdBy: existing.createdBy,
        itinerary: existing.itinerary,
        isShared: existing.isShared,
        bannerImage: existing.bannerImage,
        meetingPointName: existing.meetingPointName,
        meetingPointAddress: existing.meetingPointAddress,
        meetingPointLatitude: existing.meetingPointLatitude,
        meetingPointLongitude: existing.meetingPointLongitude,
        participantStartLocations: updatedLocations,
        collaboratorUids: existing.collaboratorUids,
        status: existing.status,
      );
      _notifyChanged();
      return true;
    } catch (error) {
      debugPrint('Failed to update participant start location: $error');
      return false;
    }
  }

  static Future<void> removeParticipantFromOwnedActivePlans({
    required String ownerUid,
    required Set<String> participantIdentifiers,
  }) async {
    final owner = ownerUid.trim();
    final identifiers = participantIdentifiers
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (owner.isEmpty || identifiers.isEmpty || FirebaseModes.offline) return;

    try {
      final snapshot = await _plansCollection
          .where('ownerUid', isEqualTo: owner)
          .get()
          .timeout(const Duration(seconds: 8));

      for (final doc in snapshot.docs) {
        final data = doc.data();
        try {
          final plan = TravelPlan.fromJson({...data, 'id': doc.id});
          if (isPlanInTripHistory(plan)) {
            continue;
          }
        } catch (error) {
          debugPrint('Skipping unfriend plan cleanup for ${doc.id}: $error');
          continue;
        }

        final participantUids = (data['participantUids'] as List? ?? const [])
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();
        final collaboratorUids = (data['collaboratorUids'] as List? ?? const [])
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList();
        final startLocations = Map<String, dynamic>.from(
          data['participantStartLocations'] as Map? ?? const {},
        );

        final nextParticipants = participantUids
            .where((id) => !identifiers.contains(id))
            .toSet()
            .toList();
        final nextCollaborators = collaboratorUids
            .where((id) => !identifiers.contains(id))
            .toSet()
            .toList();
        for (final id in identifiers) {
          startLocations.remove(id);
        }

        final participantChanged =
            nextParticipants.length != participantUids.toSet().length;
        final collaboratorChanged =
            nextCollaborators.length != collaboratorUids.toSet().length;
        final startChanged = startLocations.length !=
            (data['participantStartLocations'] as Map? ?? const {}).length;

        if (!participantChanged && !collaboratorChanged && !startChanged) {
          continue;
        }

        if (nextParticipants.isEmpty || !nextParticipants.contains(owner)) {
          // Keep plan ownership consistent.
          continue;
        }

        await doc.reference.update({
          'participantUids': nextParticipants,
          'collaboratorUids': nextCollaborators,
          'isShared': nextParticipants.length > 1,
          'participantStartLocations': startLocations,
          'updatedAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 8));

        final local = _plans[doc.id];
        if (local != null) {
          _plans[doc.id] = TravelPlan(
            id: local.id,
            title: local.title,
            startDate: local.startDate,
            endDate: local.endDate,
            participantUids: nextParticipants,
            createdBy: local.createdBy,
            itinerary: local.itinerary,
            isShared: nextParticipants.length > 1,
            bannerImage: local.bannerImage,
            meetingPointName: local.meetingPointName,
            meetingPointAddress: local.meetingPointAddress,
            meetingPointLatitude: local.meetingPointLatitude,
            meetingPointLongitude: local.meetingPointLongitude,
            participantStartLocations: startLocations.map(
              (entryKey, value) => MapEntry(
                entryKey,
                value is ParticipantStartLocation
                    ? value
                    : ParticipantStartLocation.fromJson(
                        Map<String, dynamic>.from(value as Map),
                      ),
              ),
            ),
            collaboratorUids: nextCollaborators,
            status: local.status,
          );
        }
      }
      _notifyChanged();
    } catch (error) {
      debugPrint('Failed to remove participant from active plans: $error');
    }
  }

  static Future<void> cleanupAccountPlans({
    required String uid,
    String? friendCode,
  }) async {
    if (FirebaseModes.offline) {
      _plans.removeWhere(
        (_, plan) =>
            plan.createdBy == uid ||
            plan.participantUids.contains(uid) ||
            plan.collaboratorUids.contains(uid),
      );
      _ownerUids.removeWhere((_, ownerUid) => ownerUid == uid);
      _participantUids.clear();
      _notifyChanged();
      return;
    }

    final code = _normalizeCode(friendCode ?? '');
    final identifiers = <String>{uid};
    if (code.isNotEmpty && code != uid) identifiers.add(code);

    try {
      final docs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

      Future<void> collectPlanDocs(
        String label,
        Query<Map<String, dynamic>> query,
      ) async {
        debugPrint('Account cleanup [$label]: start');
        try {
          final snapshot =
              await query.get().timeout(const Duration(seconds: 8));
          if (snapshot.docs.isEmpty) {
            debugPrint('Account cleanup [$label]: empty section skipped');
          }
          debugPrint('Account cleanup [$label]: deleted count=0');
          for (final doc in snapshot.docs) {
            docs[doc.id] = doc;
          }
        } on TimeoutException catch (error) {
          debugPrint('Account cleanup [$label]: failure reason=timeout $error');
          rethrow;
        } on FirebaseException catch (error) {
          debugPrint(
            'Account cleanup [$label]: failure reason=${error.code} ${error.message ?? ''}',
          );
          rethrow;
        } catch (error) {
          debugPrint('Account cleanup [$label]: failure reason=$error');
          rethrow;
        }
      }

      await collectPlanDocs(
        'sharedPlans participantUids contains uid',
        _plansCollection.where('participantUids', arrayContains: uid),
      );
      if (code.isNotEmpty && code != uid) {
        debugPrint(
          'Account cleanup [sharedPlans participantUids contains code]: skipped unsupported query shape',
        );
      }

      final ownedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final joinedDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in docs.values) {
        final data = doc.data();
        final createdBy = (data['createdBy'] as String? ?? '').trim();
        final ownerUid = (data['ownerUid'] as String? ?? '').trim();
        final ownerId = (data['ownerId'] as String? ?? '').trim();
        final isOwner = identifiers.contains(createdBy) ||
            identifiers.contains(ownerUid) ||
            identifiers.contains(ownerId);

        if (isOwner) {
          ownedDocs.add(doc);
        } else {
          joinedDocs.add(doc);
        }
      }

      debugPrint('Account cleanup [sharedPlans owned plans]: start');
      var deletedOwnedPlans = 0;
      try {
        for (final doc in ownedDocs) {
          await doc.reference.delete().timeout(const Duration(seconds: 8));
          _plans.remove(doc.id);
          _ownerUids.remove(doc.id);
          _participantUids.remove(doc.id);
          deletedOwnedPlans++;
        }
        if (deletedOwnedPlans == 0) {
          debugPrint(
            'Account cleanup [sharedPlans owned plans]: empty section skipped',
          );
        }
        debugPrint(
          'Account cleanup [sharedPlans owned plans]: deleted count=$deletedOwnedPlans',
        );
      } on TimeoutException catch (error) {
        debugPrint(
          'Account cleanup [sharedPlans owned plans]: failure reason=timeout $error',
        );
        rethrow;
      } on FirebaseException catch (error) {
        debugPrint(
          'Account cleanup [sharedPlans owned plans]: failure reason=${error.code} ${error.message ?? ''}',
        );
        rethrow;
      } catch (error) {
        debugPrint(
          'Account cleanup [sharedPlans owned plans]: failure reason=$error',
        );
        rethrow;
      }

      debugPrint('Account cleanup [sharedPlans joined plans]: start');
      var updatedJoinedPlans = 0;
      try {
        for (final doc in joinedDocs) {
          final data = doc.data();
          final participantUids = (data['participantUids'] as List? ?? const [])
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList();
          final collaboratorUids =
              (data['collaboratorUids'] as List? ?? const [])
                  .whereType<String>()
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .toList();

          final nextParticipants = participantUids
              .where(
                (id) => !identifiers.any((value) => _sameIdentity(id, value)),
              )
              .toSet()
              .toList();
          final nextCollaborators = collaboratorUids
              .where(
                (id) => !identifiers.any((value) => _sameIdentity(id, value)),
              )
              .toSet()
              .toList();
          final startLocations = Map<String, dynamic>.from(
            data['participantStartLocations'] as Map? ?? const {},
          );
          final originalStartLocationCount = startLocations.length;
          startLocations.removeWhere(
            (key, _) => identifiers.any(
              (value) => _sameIdentity(key.toString(), value),
            ),
          );

          final participantChanged =
              nextParticipants.length != participantUids.toSet().length;
          final collaboratorChanged =
              nextCollaborators.length != collaboratorUids.toSet().length;
          final startChanged =
              startLocations.length != originalStartLocationCount;

          if (!participantChanged && !collaboratorChanged && !startChanged) {
            continue;
          }

          await doc.reference.update({
            'participantUids': nextParticipants,
            'collaboratorUids': nextCollaborators,
            'participantStartLocations': startLocations,
            'updatedAt': FieldValue.serverTimestamp(),
          }).timeout(const Duration(seconds: 8));

          _plans.remove(doc.id);
          _ownerUids.remove(doc.id);
          _participantUids.remove(doc.id);
          updatedJoinedPlans++;
        }
        if (updatedJoinedPlans == 0) {
          debugPrint(
            'Account cleanup [sharedPlans joined plans]: empty section skipped',
          );
        }
        debugPrint(
            'Account cleanup [sharedPlans joined plans]: deleted count=0');
        debugPrint(
          'Account cleanup [sharedPlans joined plans]: updated count=$updatedJoinedPlans',
        );
      } on TimeoutException catch (error) {
        debugPrint(
          'Account cleanup [sharedPlans joined plans]: failure reason=timeout $error',
        );
        rethrow;
      } on FirebaseException catch (error) {
        debugPrint(
          'Account cleanup [sharedPlans joined plans]: failure reason=${error.code} ${error.message ?? ''}',
        );
        rethrow;
      } catch (error) {
        debugPrint(
          'Account cleanup [sharedPlans joined plans]: failure reason=$error',
        );
        rethrow;
      }

      _notifyChanged();
    } catch (error) {
      debugPrint('Failed to clean up account plans: $error');
      rethrow;
    }
  }

  static String shareLink(String planId) =>
      'https://halaph.app/plan-details?planId=${Uri.encodeComponent(planId)}';

  static bool isPlanOwner(String planId) {
    final userId = _currentUserId();
    if (userId == null) return false;

    final plan = _plans[planId];
    if (plan == null) return false;

    return _isPlanOwner(plan, {userId});
  }

  static bool isPlanParticipant(String planId) {
    final userId = _currentUserId();
    if (userId == null) return false;

    final plan = _plans[planId];
    if (plan == null) return false;

    return _isPlanParticipant(plan, {userId}) && !_isPlanOwner(plan, {userId});
  }

  static bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static void _notifyChanged() {
    if (!_changesController.isClosed) {
      _changesController.add(null);
    }
  }

  static Future<List<String>> _editorCollaboratorIdsForSelected(
    Iterable<String> selectedParticipants,
  ) async {
    final selected = selectedParticipants
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    if (selected.isEmpty) return const <String>[];

    try {
      final friends = await FriendService().getFriends();
      final editors = <String>{};

      for (final friend in friends) {
        if (friend.role != 'Editor') continue;

        final code = _normalizeCode(friend.code);
        final uid = friend.uid?.trim();

        final matchesCode = code.isNotEmpty && selected.contains(code);
        final matchesUid =
            uid != null && uid.isNotEmpty && selected.contains(uid);

        if (!matchesCode && !matchesUid) continue;

        if (code.isNotEmpty) editors.add(code);
        if (uid != null && uid.isNotEmpty) editors.add(uid);
      }

      return editors.toList();
    } catch (error) {
      debugPrint('Failed to resolve editor collaborators: $error');
      return const <String>[];
    }
  }

  static bool canEditPlan(String planId, {String? userId}) {
    final plan = _plans[planId];
    if (plan == null) return false;

    final identities = _identityCandidates(userId ?? 'current_user');
    if (_isPlanOwner(plan, identities)) return true;

    return plan.collaboratorUids.any(
      (id) => _matchesAnyIdentity(id, identities),
    );
  }

  static Set<String> _identityCandidates(String? primaryId) {
    final identities = <String>{};
    void add(String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) identities.add(trimmed);
    }

    add(primaryId);
    add(_currentUserId());
    return identities;
  }

  static bool _isPlanOwner(TravelPlan plan, Set<String> identities) {
    return _matchesAnyIdentity(plan.createdBy, identities) ||
        _matchesAnyIdentity(_ownerUids[plan.id], identities);
  }

  static bool _isPlanParticipant(TravelPlan plan, Set<String> identities) {
    if (_isPlanOwner(plan, identities)) return true;
    if (plan.participantUids.any((id) => _matchesAnyIdentity(id, identities))) {
      return true;
    }

    final remoteParticipants = _participantUids[plan.id] ?? const <String>[];
    return remoteParticipants.any((id) => _matchesAnyIdentity(id, identities));
  }

  static bool _isCollaborative(TravelPlan plan) {
    final owner = (_ownerUids[plan.id] ?? plan.createdBy).trim();

    final participants = <String>{
      ...plan.participantUids
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
      ...(_participantUids[plan.id] ?? const <String>[])
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty),
    };

    final collaborators = plan.collaboratorUids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != owner)
        .toSet();

    final nonOwnerParticipants =
        participants.where((id) => id.isNotEmpty && id != owner).toSet();

    return nonOwnerParticipants.isNotEmpty || collaborators.isNotEmpty;
  }

  static List<TravelPlan> _visibleCurrentOrFuturePlans(Set<String> identities) {
    final today = _today();
    return _plans.values.where((plan) {
      if (isPlanInTripHistory(plan)) return false;
      return _isPlanParticipant(plan, identities) &&
          !_dayOnly(plan.endDate).isBefore(today);
    }).toList()
      ..sort(_compareCurrentOrUpcomingPlans);
  }

  static int _compareCurrentOrUpcomingPlans(TravelPlan a, TravelPlan b) {
    final today = _today();
    final aActive = !_dayOnly(a.startDate).isAfter(today) &&
        !_dayOnly(a.endDate).isBefore(today);
    final bActive = !_dayOnly(b.startDate).isAfter(today) &&
        !_dayOnly(b.endDate).isBefore(today);
    if (aActive != bActive) return aActive ? -1 : 1;

    final dateCompare = a.startDate.compareTo(b.startDate);
    if (dateCompare != 0) return dateCompare;

    final aHasBanner = _hasPlanBanner(a);
    final bHasBanner = _hasPlanBanner(b);
    if (aHasBanner != bHasBanner) return aHasBanner ? -1 : 1;

    return _planSortStamp(b).compareTo(_planSortStamp(a));
  }

  static bool _hasPlanBanner(TravelPlan plan) {
    final banner = plan.bannerImage?.trim();
    return banner != null && banner.isNotEmpty;
  }

  static int _planSortStamp(TravelPlan plan) {
    final parts = plan.id.split('_');
    if (parts.length >= 2 && parts.first == 'plan') {
      return int.tryParse(parts[1]) ?? 0;
    }
    return plan.startDate.millisecondsSinceEpoch;
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _dayOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static bool _matchesAnyIdentity(String? value, Set<String> identities) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return false;

    for (final identity in identities) {
      if (_sameIdentity(trimmed, identity)) return true;
    }
    return false;
  }

  static bool _sameIdentity(String left, String right) {
    final leftTrimmed = left.trim();
    final rightTrimmed = right.trim();
    if (leftTrimmed == rightTrimmed) return true;

    if (_isNormalizableParticipantId(leftTrimmed) &&
        _isNormalizableParticipantId(rightTrimmed)) {
      return _normalizeCode(leftTrimmed) == _normalizeCode(rightTrimmed);
    }

    return false;
  }

  static bool _isNormalizableParticipantId(String value) {
    final compact = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final lower = value.trim().toLowerCase();
    return RegExp(r'^[A-Za-z]{2}[0-9]{4}$').hasMatch(compact) ||
        lower == 'current_user' ||
        lower == 'demo_user';
  }

  static CollectionReference<Map<String, dynamic>> get _plansCollection =>
      FirebaseFirestore.instance.collection('sharedPlans');

  static String? _currentUserId() {
    if (!FirebaseAppService.isInitialized) return null;
    return firebase_auth.FirebaseAuth.instance.currentUser?.uid;
  }

  static String _newPlanId() {
    // Use UUID-style ID to avoid collisions across devices
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = (timestamp.hashCode.abs() % 100000).toString().padLeft(
          5,
          '0',
        );
    return 'plan_${timestamp}_$random';
  }

  static String _normalizeCode(String code) {
    final compact = code.trim().toUpperCase().replaceAll(
          RegExp(r'[^A-Z0-9]'),
          '',
        );
    if (RegExp(r'^[A-Z]{2}[0-9]{4}$').hasMatch(compact)) {
      return '${compact.substring(0, 2)}-${compact.substring(2)}';
    }
    return code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  static bool _isFriendCode(String value) {
    return RegExp(r'^[A-Z]{2}-\d{4}$').hasMatch(_normalizeCode(value));
  }

  static String? _firstDestinationImage(List<DayItinerary> itinerary) {
    for (final day in itinerary) {
      for (final item in day.items) {
        final imageUrl = _cleanImageUrl(item.destination.imageUrl);
        if (imageUrl != null) return imageUrl;
      }
    }
    return null;
  }

  static String? _cleanImageUrl(String? value) {
    final url = value?.trim() ?? '';
    if (url.isEmpty) return null;
    if (_isRandomImageUrl(url)) return null;
    return url;
  }

  static bool _isRandomImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('picsum.photos') ||
        lower.contains('source.unsplash.com') ||
        lower.contains('randomuser.me');
  }
}
