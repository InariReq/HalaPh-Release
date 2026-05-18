import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:halaph/services/fare_service.dart';
import 'package:halaph/services/firebase_app_service.dart';
import 'package:halaph/services/firestore_service.dart';
import 'package:halaph/services/friend_service.dart';

class CommuterTypeService {
  static final CommuterTypeService _instance = CommuterTypeService._internal();
  factory CommuterTypeService() => _instance;
  CommuterTypeService._internal();

  final Map<String, PassengerType> _cacheByUid = {};
  final Map<String, Future<PassengerType>> _loadInFlightByUid = {};
  final Set<String> _loadedLogUidsThisSession = {};

  static const allowedKeys = <String>{
    'regular',
    'student',
    'senior',
    'pwd',
  };

  Future<PassengerType> loadCommuterType({bool forceRefresh = false}) async {
    String? uid;

    try {
      if (!await FirebaseAppService.initialize()) {
        return PassengerType.regular;
      }

      uid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        return PassengerType.regular;
      }

      if (!forceRefresh && _cacheByUid.containsKey(uid)) {
        return _cacheByUid[uid]!;
      }
      final inFlight = _loadInFlightByUid[uid];
      if (!forceRefresh && inFlight != null) return inFlight;

      final future = _loadRemoteCommuterType(uid);
      _loadInFlightByUid[uid] = future;
      return await future.whenComplete(() {
        if (identical(_loadInFlightByUid[uid], future)) {
          _loadInFlightByUid.remove(uid);
        }
      });
    } catch (error) {
      debugPrint('Failed to load commuter type: $error');

      if (uid != null && uid.isNotEmpty && _cacheByUid.containsKey(uid)) {
        return _cacheByUid[uid]!;
      }

      return PassengerType.regular;
    }
  }

  Future<PassengerType> _loadRemoteCommuterType(String uid) async {
    final code = await FriendService().getMyCode();
    final profile = await FirestoreService.getPublicProfile(code)
        .timeout(const Duration(seconds: 5));
    final rawType = profile?['commuterType'] as String?;

    final loadedType = fromKey(rawType);
    _cacheByUid[uid] = loadedType;
    if (_loadedLogUidsThisSession.add(uid)) {
      debugPrint(
        'Loaded commuter type ${keyFor(loadedType)} for uid=$uid code=$code',
      );
    }
    return loadedType;
  }

  Future<void> saveCommuterType(PassengerType type) async {
    final normalizedType = normalize(type);
    String? uid;

    try {
      if (!await FirebaseAppService.initialize()) {
        return;
      }

      uid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        return;
      }

      _cacheByUid[uid] = normalizedType;

      final code = await FriendService().getMyCode();
      final payload = <String, dynamic>{
        'commuterType': keyFor(normalizedType),
      };

      try {
        await FirestoreService.updatePublicProfile(code, payload)
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        await FriendService().ensurePublicProfilePublished();
        await FirestoreService.updatePublicProfile(code, payload)
            .timeout(const Duration(seconds: 5));
      }

      debugPrint(
        'Saved commuter type ${keyFor(normalizedType)} for uid=$uid code=$code',
      );
    } catch (error) {
      if (uid != null) {
        _cacheByUid.remove(uid);
      }
      debugPrint('Failed to save commuter type: $error');
    }
  }

  void clearCache() {
    _cacheByUid.clear();
    _loadInFlightByUid.clear();
  }

  void clearCurrentUserCache() {
    final uid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      _cacheByUid.remove(uid);
      _loadInFlightByUid.remove(uid);
    }
  }

  static PassengerType normalize(PassengerType type) {
    return switch (type) {
      PassengerType.student => PassengerType.student,
      PassengerType.senior => PassengerType.senior,
      PassengerType.pwd => PassengerType.pwd,
      PassengerType.regular || PassengerType.adult => PassengerType.regular,
    };
  }

  static PassengerType fromKey(String? key) {
    return switch ((key ?? '').trim().toLowerCase()) {
      'student' => PassengerType.student,
      'senior' => PassengerType.senior,
      'pwd' => PassengerType.pwd,
      _ => PassengerType.regular,
    };
  }

  static String keyFor(PassengerType type) {
    return switch (normalize(type)) {
      PassengerType.student => 'student',
      PassengerType.senior => 'senior',
      PassengerType.pwd => 'pwd',
      PassengerType.regular || PassengerType.adult => 'regular',
    };
  }

  static String labelFor(PassengerType type) {
    return switch (normalize(type)) {
      PassengerType.student => 'Student',
      PassengerType.senior => 'Senior',
      PassengerType.pwd => 'PWD',
      PassengerType.regular || PassengerType.adult => 'Regular',
    };
  }

  static IconData iconFor(PassengerType type) {
    return switch (normalize(type)) {
      PassengerType.student => Icons.school_rounded,
      PassengerType.senior => Icons.elderly_rounded,
      PassengerType.pwd => Icons.accessible_rounded,
      PassengerType.regular || PassengerType.adult => Icons.person_rounded,
    };
  }
}
