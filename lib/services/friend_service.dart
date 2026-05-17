import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import 'package:halaph/models/destination.dart';
import 'package:halaph/models/friend.dart';
import 'package:halaph/services/firebase_app_service.dart';
import 'package:halaph/services/firestore_service.dart';
import 'package:halaph/services/remote_sync_service.dart';

class FriendAddResult {
  final bool success;
  final String message;
  final Friend? friend;

  const FriendAddResult({
    required this.success,
    required this.message,
    this.friend,
  });
}

class FriendService {
  static final FriendService _instance = FriendService._internal();
  factory FriendService() => _instance;
  FriendService._internal();

  String? _cachedUserId;
  String? _cachedCode;
  Future<String>? _myCodeLoadInFlight;
  final Set<String> _publishedProfileFingerprints = {};
  List<Friend>? _cachedFriends;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _friendsSubscription;
  final _friendsController = StreamController<List<Friend>>.broadcast();

  Stream<List<Friend>> get friendsStream => _friendsController.stream;

  Future<String> getMyCode({bool forceRefresh = false}) {
    final inFlight = _myCodeLoadInFlight;
    if (!forceRefresh && inFlight != null) return inFlight;

    final future = _loadMyCode(forceRefresh: forceRefresh);
    _myCodeLoadInFlight = future;
    return future.whenComplete(() {
      if (identical(_myCodeLoadInFlight, future)) {
        _myCodeLoadInFlight = null;
      }
    });
  }

  Future<String> _loadMyCode({required bool forceRefresh}) async {
    final userId = await _currentUserId();
    if (userId == null) return 'HP-0000';

    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    final seed = firebaseUser?.email ?? firebaseUser?.displayName ?? 'traveler';

    if (!forceRefresh && _cachedUserId == userId && _cachedCode != null) {
      return _cachedCode!;
    }

    if (forceRefresh) {
      final existingCode = await _findExistingFriendCodeForUid(userId);
      if (existingCode != null && existingCode.isNotEmpty) {
        final claimedCode = await _claimOrGenerateAvailableCode(
          preferredCode: existingCode,
          uid: userId,
          seed: seed,
        );
        _cachedUserId = userId;
        _cachedCode = claimedCode;
        await RemoteSyncService.instance.saveNamespace('profile', {
          'code': claimedCode,
        });
        await _publishPublicProfile(claimedCode);
        return claimedCode;
      }
    }

    final remoteProfile = await RemoteSyncService.instance.loadNamespace(
      'profile',
    );
    final remoteCode = remoteProfile?['code'] as String?;
    if (remoteCode != null && remoteCode.isNotEmpty) {
      final normalizedCode = _normalizeCode(remoteCode);
      final claimedCode = await _claimOrGenerateAvailableCode(
        preferredCode: normalizedCode,
        uid: userId,
        seed: seed,
      );
      _cachedUserId = userId;
      _cachedCode = claimedCode;
      if (claimedCode != normalizedCode) {
        await RemoteSyncService.instance.saveNamespace('profile', {
          'code': claimedCode,
        });
      }
      await _publishPublicProfile(claimedCode);
      return claimedCode;
    }

    final generated = _generateCode(seed, firebaseUser?.uid);
    final claimedCode = await _claimOrGenerateAvailableCode(
      preferredCode: generated,
      uid: userId,
      seed: seed,
    );
    _cachedUserId = userId;
    _cachedCode = claimedCode;
    await RemoteSyncService.instance.saveNamespace('profile', {
      'code': claimedCode,
    });
    await _publishPublicProfile(claimedCode);
    return claimedCode;
  }

  Future<String?> _findExistingFriendCodeForUid(String uid) async {
    if (uid.trim().isEmpty) return null;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('friendCodes')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));

      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      final data = doc.data();
      final rawCode = data['code'] as String? ?? doc.id;
      final code = _normalizeCode(rawCode);

      if (code.isEmpty || code == 'HP-0000') return null;

      debugPrint('FriendService: refreshed friend code from Firebase: $code');
      return code;
    } catch (error) {
      debugPrint('FriendService: friend code refresh lookup skipped: $error');
      return null;
    }
  }

  Future<String> _claimOrGenerateAvailableCode({
    required String preferredCode,
    required String uid,
    required String seed,
  }) async {
    var candidate = _normalizeCode(preferredCode);

    for (var attempt = 0; attempt < 50; attempt++) {
      if (candidate.isEmpty || candidate == 'HP-0000') {
        candidate = _generateCode('$seed-$attempt', uid);
      }

      final docRef =
          FirebaseFirestore.instance.collection('friendCodes').doc(candidate);
      final doc = await docRef.get();

      if (!doc.exists) {
        await docRef.set({
          'uid': uid,
          'code': candidate,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return candidate;
      }

      final existingUid = doc.data()?['uid'] as String?;
      if (existingUid == uid) {
        final existingCode = doc.data()?['code'] as String?;
        if (existingCode != candidate) {
          await docRef.update({
            'code': candidate,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        return candidate;
      }

      candidate = _generateCode('$seed-$uid-$attempt', uid);
    }

    throw Exception('Could not generate an available friend code.');
  }

  /// Ensure friend code exists in friendCodes collection
  Future<void> ensureFriendCodeExists() async {
    final userId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final code = await getMyCode();
      if (code.isEmpty || code == 'HP-0000') return;

      // Self-heal the friendCodes/{code} mapping
      await _selfHealFriendCodeMapping(code: code, uid: userId);
    } catch (e) {
      debugPrint('Failed to ensure friend code exists: $e');
    }
  }

  /// Self-heal friendCodes/{code} document
  /// Ensures the document has the correct 'code' field and valid uid
  Future<void> _selfHealFriendCodeMapping({
    required String code,
    required String uid,
  }) async {
    final normalizedCode = _normalizeCode(code);
    debugPrint('selfHealFriendCodeMapping: code=$normalizedCode');
    debugPrint('selfHealFriendCodeMapping: uid=$uid');

    // Validate code format
    final normalizedCheck = _normalizeCode(code);
    if (!(RegExp(r'^[A-Z]{2}-\d{4}$').hasMatch(normalizedCheck))) {
      debugPrint('selfHealFriendCodeMapping: invalid code format, skipping');
      return;
    }

    // Validate uid
    if (uid.isEmpty) {
      debugPrint('selfHealFriendCodeMapping: empty uid, skipping');
      return;
    }

    try {
      final docRef = FirebaseFirestore.instance
          .collection('friendCodes')
          .doc(normalizedCode);
      final doc = await docRef.get();

      debugPrint(
        'selfHealFriendCodeMapping: friendCodes/$normalizedCode exists ${doc.exists}',
      );

      if (!doc.exists) {
        // Create missing document
        debugPrint('selfHealFriendCodeMapping: creating missing document');
        await docRef.set({
          'uid': uid,
          'code': normalizedCode,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('selfHealFriendCodeMapping: write performed true (created)');
        return;
      }

      final data = doc.data()!;
      final existingCode = data['code'] as String?;
      final existingUid = data['uid'] as String?;

      debugPrint(
        'selfHealFriendCodeMapping: missing code field ${existingCode == null}',
      );
      debugPrint('selfHealFriendCodeMapping: existing uid=$existingUid');

      // Check if uid matches
      if (existingUid != null && existingUid != uid) {
        debugPrint('selfHealFriendCodeMapping: WARNING uid mismatch, stopping');
        return;
      }

      // Fix missing or incorrect code field
      if (existingCode == null || existingCode != normalizedCode) {
        debugPrint(
          'selfHealFriendCodeMapping: fixing code field to $normalizedCode',
        );
        await docRef.update({
          'code': normalizedCode,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint(
          'selfHealFriendCodeMapping: write performed true (updated code)',
        );
      } else {
        debugPrint(
          'selfHealFriendCodeMapping: write performed false (no changes needed)',
        );
      }
    } catch (e) {
      debugPrint('selfHealFriendCodeMapping: error $e');
    }
  }

  Future<List<Friend>> getFriends({bool forceRefresh = false}) async {
    final userId = await _currentUserId();
    if (userId == null) return const <Friend>[];

    if (!forceRefresh && _cachedUserId == userId && _cachedFriends != null) {
      return List<Friend>.from(_cachedFriends!);
    }

    final friends = await _loadRemoteFriends();
    friends.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    _cachedUserId = userId;
    _cachedFriends = List<Friend>.from(friends);
    _startFriendsListener(userId);
    return List<Friend>.from(_cachedFriends!);
  }

  void _startFriendsListener(String userId) {
    _friendsSubscription?.cancel();
    _friendsSubscription = FirestoreService.getFriendsStream(userId).listen((
      snapshot,
    ) {
      final friends = snapshot.docs.map((doc) {
        final data = doc.data();
        return Friend(
          id: data['friendId'] as String? ?? doc.id,
          uid: data['friendUid'] as String?,
          name: data['name'] as String? ?? 'Unknown',
          role: data['role'] as String? ?? 'Viewer',
          code: data['code'] as String? ?? '',
          email: data['email'] as String?,
          avatarUrl: data['avatarUrl'] as String?,
        );
      }).toList();
      unawaited(_publishHydratedFriends(friends));
    }, onError: (error) => debugPrint('Friends live updates failed: $error'));
  }

  Future<void> removeFriend(String friendId) async {
    final userId = await _currentUserId();
    if (userId == null) return;

    final friends = await getFriends();
    Friend? targetFriend;
    for (final friend in friends) {
      if (friend.id == friendId || friend.uid == friendId) {
        targetFriend = friend;
        break;
      }
    }

    final targetUid = targetFriend?.uid?.trim().isNotEmpty == true
        ? targetFriend!.uid!.trim()
        : friendId.trim();

    if (targetUid.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final targetCode = _normalizeCode(targetFriend?.code ?? '');

    Future<void> safeDelete(DocumentReference<Map<String, dynamic>> ref) async {
      try {
        await ref.delete();
      } catch (error) {
        debugPrint('Skipping delete for ${ref.path}: $error');
      }
    }

    await safeDelete(
      db.collection('users').doc(userId).collection('friends').doc(targetUid),
    );
    await safeDelete(
      db.collection('users').doc(targetUid).collection('friends').doc(userId),
    );
    await safeDelete(
        db.collection('friendRequests').doc('${userId}_$targetUid'));
    await safeDelete(
        db.collection('friendRequests').doc('${targetUid}_$userId'));
    await safeDelete(
      db
          .collection('users')
          .doc(userId)
          .collection('friend_requests')
          .doc(targetUid),
    );
    await safeDelete(
      db
          .collection('users')
          .doc(targetUid)
          .collection('friend_requests')
          .doc(userId),
    );

    try {
      final outbound = await db
          .collection('friendRequests')
          .where('fromUid', isEqualTo: userId)
          .where('toUid', isEqualTo: targetUid)
          .get();
      for (final doc in outbound.docs) {
        await doc.reference.delete();
      }

      final inbound = await db
          .collection('friendRequests')
          .where('fromUid', isEqualTo: targetUid)
          .where('toUid', isEqualTo: userId)
          .get();
      for (final doc in inbound.docs) {
        await doc.reference.delete();
      }
    } catch (error) {
      debugPrint('Stale friend request cleanup skipped: $error');
    }

    await _removeUnfriendedUserFromOwnedActivePlans(
      ownerUid: userId,
      removedUid: targetUid,
      removedCode: targetCode,
    );

    _cachedFriends = friends
        .where(
          (friend) =>
              friend.id != friendId &&
              friend.uid != friendId &&
              friend.id != targetUid &&
              friend.uid != targetUid,
        )
        .toList();
  }

  Future<String> getPublicCommuterTypeLabel(Friend friend) async {
    final code = _normalizeCode(friend.code);
    if (code.isEmpty || !await FirebaseAppService.initialize()) {
      return 'Regular';
    }

    try {
      final profile = await FirestoreService.getPublicProfile(code);
      final rawType =
          (profile?['commuterType'] as String?)?.trim().toLowerCase();
      return switch (rawType) {
        'student' => 'Student',
        'senior' => 'Senior',
        'pwd' => 'PWD',
        _ => 'Regular',
      };
    } catch (_) {
      return 'Regular';
    }
  }

  Future<List<String>> getPublicFavoriteIds(Friend friend) async {
    final code = _normalizeCode(friend.code);
    if (code.isEmpty || !await FirebaseAppService.initialize()) {
      return const <String>[];
    }

    try {
      final profile = await FirestoreService.getPublicProfile(code);
      final rawFavorites = profile?['favoritePlaceIds'];
      if (rawFavorites is! List) return const <String>[];
      return rawFavorites
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<List<Destination>> getPublicFavoritePlaces(Friend friend) async {
    final code = _normalizeCode(friend.code);
    if (code.isEmpty || !await FirebaseAppService.initialize()) {
      return const <Destination>[];
    }

    try {
      final profile = await FirestoreService.getPublicProfile(code);
      final rawPlaces = profile?['favoritePlaces'];
      if (rawPlaces is! List) return const <Destination>[];
      final places = <Destination>[];
      for (final rawPlace in rawPlaces) {
        if (rawPlace is! Map) continue;
        try {
          places.add(Destination.fromJson(Map<String, dynamic>.from(rawPlace)));
        } catch (_) {}
      }
      return places;
    } catch (_) {
      return const <Destination>[];
    }
  }

  Future<void> publishFavoritePlaceIds(List<String> ids) async {
    if (!await FirebaseAppService.initialize()) return;
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    final code = _normalizeCode(await getMyCode());
    if (code.isEmpty) return;

    final deduped = ids
        .where((id) => id.trim().isNotEmpty)
        .map((id) => id.trim())
        .toSet()
        .toList();

    try {
      await FirestoreService.updatePublicProfile(code, {
        'favoritePlaceIds': deduped,
      }).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> publishFavoritePlaces(List<Destination> destinations) async {
    if (!await FirebaseAppService.initialize()) return;
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    final code = _normalizeCode(await getMyCode());
    if (code.isEmpty) return;

    final deduped = <String, Destination>{
      for (final destination in destinations) destination.id: destination,
    };

    try {
      await FirestoreService.updatePublicProfile(code, {
        'favoritePlaceIds': deduped.keys.toList(),
        'favoritePlaces':
            deduped.values.map((destination) => destination.toJson()).toList(),
      }).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<void> updateFriendRole(String friendId, String role) async {
    final userId = await _currentUserId();
    if (userId == null) return;

    final normalizedRole = role == 'Editor' ? 'Editor' : 'Viewer';
    final friends = await getFriends();

    Friend? targetFriend;
    for (final friend in friends) {
      if (friend.id == friendId || friend.uid == friendId) {
        targetFriend = friend;
        break;
      }
    }

    final targetUid = targetFriend?.uid?.trim().isNotEmpty == true
        ? targetFriend!.uid!.trim()
        : friendId.trim();

    if (targetUid.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('friends')
        .doc(targetUid)
        .set({
      'role': normalizedRole,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _cachedFriends = friends.map((friend) {
      if (friend.id != friendId && friend.uid != friendId) return friend;
      return Friend(
        id: friend.id,
        uid: friend.uid,
        name: friend.name,
        role: normalizedRole,
        code: friend.code,
        email: friend.email,
        avatarUrl: friend.avatarUrl,
      );
    }).toList();
  }

  Future<List<Friend>> _loadRemoteFriends() async {
    final userId = await _currentUserId();
    if (userId == null) return [];

    List<Friend> friends = [];
    if (await FirebaseAppService.initialize()) {
      friends = await _loadFriendsFromFirestore(userId);
    }

    if (friends.isEmpty) {
      final payload = await RemoteSyncService.instance.loadNamespace('friends');
      final rawFriends = payload?['friends'];
      if (rawFriends is! List) return [];
      friends = rawFriends
          .whereType<Map>()
          .map((entry) => Friend.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
    }

    return _hydrateFriends(friends);
  }

  Future<void> _publishHydratedFriends(List<Friend> friends) async {
    final hydrated = await _hydrateFriends(friends);
    hydrated.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    _cachedFriends = List<Friend>.from(hydrated);
    _friendsController.add(hydrated);
  }

  Future<List<Friend>> _hydrateFriends(List<Friend> friends) async {
    return Future.wait(friends.map(_hydrateFriend));
  }

  Future<Friend> _hydrateFriend(Friend friend) async {
    final code = _normalizeCode(friend.code);
    if (code.isEmpty) return friend;

    try {
      final profile = await findPublicProfileByCode(code);
      if (profile == null) return friend;

      final displayName =
          profile.name.trim().isNotEmpty ? profile.name.trim() : friend.name;
      final avatarUrl = profile.avatarUrl?.trim().isNotEmpty == true
          ? profile.avatarUrl!.trim()
          : friend.avatarUrl;

      if (displayName == friend.name && avatarUrl == friend.avatarUrl) {
        return friend;
      }

      return Friend(
        id: friend.id,
        uid: friend.uid,
        name: displayName,
        role: friend.role,
        code: friend.code,
        email: profile.email ?? friend.email,
        avatarUrl: avatarUrl,
      );
    } catch (_) {
      return friend;
    }
  }

  Future<void> _removeUnfriendedUserFromOwnedActivePlans({
    required String ownerUid,
    required String removedUid,
    required String removedCode,
  }) async {
    if (!await FirebaseAppService.initialize()) return;

    final identifiers = <String>{removedUid.trim()};
    if (removedCode.isNotEmpty) identifiers.add(removedCode);
    if (identifiers.every((value) => value.isEmpty)) return;

    try {
      final today = DateTime.now();
      final dayOnly = DateTime(today.year, today.month, today.day);
      final snapshot = await FirebaseFirestore.instance
          .collection('sharedPlans')
          .where('ownerUid', isEqualTo: ownerUid)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final createdBy = (data['createdBy'] as String? ?? '').trim();
        if (createdBy != ownerUid) continue;
        final rawEndDate = data['endDate'];
        if (rawEndDate is! Timestamp) continue;
        final endDate = rawEndDate.toDate();
        final endDay = DateTime(endDate.year, endDate.month, endDate.day);
        if (endDay.isBefore(dayOnly)) continue;

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
          if (id.isNotEmpty) startLocations.remove(id);
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

        await doc.reference.update({
          'participantUids': nextParticipants,
          'collaboratorUids': nextCollaborators,
          'participantStartLocations': startLocations,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (error) {
      debugPrint('Unfriend plan cleanup skipped: $error');
    }
  }

  Future<List<Friend>> _loadFriendsFromFirestore(String userId) async {
    if (!await FirebaseAppService.initialize()) return [];

    try {
      return await FirestoreService.getFriends(userId);
    } catch (e) {
      debugPrint('Failed to load friends: $e');
      return [];
    }
  }

  Future<Friend?> findPublicProfileByCode(String rawCode) async {
    final code = _normalizeCode(rawCode);
    if (code.isEmpty) return null;
    if (!await FirebaseAppService.initialize()) return null;

    try {
      final profile = await FirestoreService.getPublicProfile(code);
      if (profile == null) return null;
      return Friend(
        id: profile['uid'] as String? ?? '',
        uid: profile['uid'] as String? ?? '',
        name: profile['name'] as String? ?? '',
        role: 'Viewer',
        code: profile['code'] as String? ?? '',
        email: profile['email'] as String?,
        avatarUrl: profile['avatarUrl'] as String?,
      );
    } catch (e) {
      debugPrint('Error finding public profile: $e');
      return null;
    }
  }

  Future<void> ensurePublicProfilePublished() async {
    final code = await getMyCode();
    if (code.isEmpty) return;
    await _publishPublicProfile(code);
  }

  Future<List<String>> resolveParticipantUids(Iterable<String> codes) async {
    final currentUid = await _currentUserId();
    if (currentUid == null) return const <String>[];

    final uids = <String>{currentUid};
    final normalizedCodes = codes.map(_normalizeCode).where((code) {
      return code.isNotEmpty;
    }).toSet();
    if (normalizedCodes.isEmpty) return uids.toList();

    final myCode = _normalizeCode(await getMyCode());
    final friends = await getFriends();
    final byCode = {
      for (final friend in friends) _normalizeCode(friend.code): friend,
    };

    for (final code in normalizedCodes) {
      if (code == myCode) {
        uids.add(currentUid);
        continue;
      }

      final cachedFriend = byCode[code];
      if (cachedFriend?.uid?.isNotEmpty == true) {
        uids.add(cachedFriend!.uid!);
        continue;
      }

      final profile = await findPublicProfileByCode(code);
      if (profile?.uid?.isNotEmpty == true) {
        uids.add(profile!.uid!);
      }
    }
    return uids.toList();
  }

  Future<List<Map<String, dynamic>>> searchUsersByName(String query) async {
    if (query.trim().isEmpty) return const [];
    final currentUid = await _currentUserId();
    if (currentUid == null) return const [];

    try {
      // Search by exact code match instead of listing all profiles
      final code = _normalizeCode(query);
      if (code.isNotEmpty) {
        final profile = await findPublicProfileByCode(code);
        if (profile != null && profile.uid != currentUid) {
          return [
            {
              'uid': profile.uid ?? '',
              'name': profile.name,
              'email': profile.email ?? '',
              'code': profile.code,
              'avatarUrl': profile.avatarUrl ?? '',
            },
          ];
        }
      }

      // Search by name/email using friends list and known profiles
      final results = <Map<String, dynamic>>[];
      final lowerQuery = query.toLowerCase();

      // Check friends first
      final friends = await getFriends();
      for (final friend in friends) {
        if (friend.uid == currentUid) continue;
        final name = friend.name.toLowerCase();
        final email = (friend.email ?? '').toLowerCase();
        final code = friend.code.toLowerCase();

        if (name.contains(lowerQuery) ||
            email.contains(lowerQuery) ||
            code.contains(lowerQuery)) {
          results.add({
            'uid': friend.uid ?? '',
            'name': friend.name,
            'email': friend.email ?? '',
            'code': friend.code,
            'avatarUrl': friend.avatarUrl ?? '',
          });
        }
      }

      return results;
    } catch (e) {
      debugPrint('Failed to search users: $e');
      return const [];
    }
  }

  Future<bool> isAlreadyFriends(String userUid) async {
    if (userUid.isEmpty) return false;
    final friends = await getFriends();
    return friends.any((f) => f.uid == userUid);
  }

  Future<Map<String, dynamic>> getFriendActivitySummary() async {
    final friends = await getFriends();
    final summary = <String, dynamic>{
      'totalFriends': friends.length,
      'recentlyAdded': <Friend>[],
    };

    try {
      final currentUserId = await _currentUserId();
      if (currentUserId != null) {
        final allFriends = await FirestoreService.getFriends(currentUserId);
        summary['recentlyAdded'] = allFriends.take(5).toList();
      }
      return summary;
    } catch (e) {
      debugPrint('Error getting friend activity summary: $e');
      return summary;
    }
  }

  void clearCache() {
    _cachedUserId = null;
    _cachedCode = null;
    _myCodeLoadInFlight = null;
    _publishedProfileFingerprints.clear();
    _cachedFriends = null;
    _friendsSubscription?.cancel();
    _friendsSubscription = null;
  }

  @visibleForTesting
  static String? bestEffortDisplayNameFromValues({
    String? displayName,
    String? email,
    String? publicProfileName,
  }) {
    final authName = _usableName(displayName);
    if (authName != null) return authName;

    final emailName = _emailPrefix(email);
    if (emailName != null) return emailName;

    return _usableName(publicProfileName);
  }

  static String? _usableName(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.toLowerCase() == 'unknown') return null;
    return trimmed;
  }

  static String? _emailPrefix(String? email) {
    final trimmed = email?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final prefix = trimmed.split('@').first.trim();
    return prefix.isEmpty ? null : prefix;
  }

  Future<String?> _currentUserBestEffortName({String? profileCode}) async {
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    String? publicProfileName;
    if (profileCode != null && profileCode.trim().isNotEmpty) {
      publicProfileName = (await findPublicProfileByCode(profileCode))?.name;
    }
    return bestEffortDisplayNameFromValues(
      displayName: firebaseUser?.displayName,
      email: firebaseUser?.email,
      publicProfileName: publicProfileName,
    );
  }

  Future<String?> _publicProfileBestEffortName(String rawCode) async {
    final profile = await findPublicProfileByCode(rawCode);
    return _usableName(profile?.name) ?? _emailPrefix(profile?.email);
  }

  Future<String?> _currentUserId() async {
    if (!await FirebaseAppService.initialize()) return null;
    final userId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
    if (_cachedUserId != null && _cachedUserId != userId) {
      clearCache();
    }
    return userId;
  }

  Future<void> syncCurrentUserAvatarToPublicProfile(String avatarUrl) async {
    final usableAvatarUrl = avatarUrl.trim();
    if (usableAvatarUrl.isEmpty) return;

    if (!await FirebaseAppService.initialize()) return;
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return;

    try {
      final code = await getMyCode(forceRefresh: true);
      if (code.isEmpty || code == 'HP-0000') return;

      await RemoteSyncService.instance.saveNamespace('profile', {
        'code': code,
        'avatarUrl': usableAvatarUrl,
      });

      await _syncCurrentUserProfileAvatar(
        uid: firebaseUser.uid,
        avatarUrl: usableAvatarUrl,
      );
      await _publishPublicProfile(code, avatarUrl: usableAvatarUrl);
      await _syncFriendCodeAvatarIfSupported(
        code: code,
        uid: firebaseUser.uid,
        avatarUrl: usableAvatarUrl,
      );
    } catch (error) {
      debugPrint('Profile avatar public sync failed: $error');
    }
  }

  Future<void> _syncCurrentUserProfileAvatar({
    required String uid,
    required String avatarUrl,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'photoUrl': avatarUrl,
        'avatarUrl': avatarUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('Current user avatar sync skipped: $error');
    }
  }

  Future<void> _syncFriendCodeAvatarIfSupported({
    required String code,
    required String uid,
    required String avatarUrl,
  }) async {
    try {
      final docRef =
          FirebaseFirestore.instance.collection('friendCodes').doc(code);
      final doc = await docRef.get().timeout(const Duration(seconds: 5));
      final data = doc.data();
      if (!doc.exists || data == null || data['uid'] != uid) return;
      if (!data.containsKey('avatarUrl')) return;

      await docRef.set({
        'uid': uid,
        'code': code,
        'avatarUrl': avatarUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
    } on FirebaseException catch (error) {
      debugPrint('Friend code avatar sync skipped: ${error.code}');
    } catch (error) {
      debugPrint('Friend code avatar sync skipped: $error');
    }
  }

  Future<void> _publishPublicProfile(
    String rawCode, {
    String? avatarUrl,
  }) async {
    final code = _normalizeCode(rawCode);
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (code.isEmpty || firebaseUser == null) return;
    final displayName = bestEffortDisplayNameFromValues(
          displayName: firebaseUser.displayName,
          email: firebaseUser.email,
        ) ??
        'Traveler';
    final effectiveAvatarUrl = avatarUrl?.trim().isNotEmpty == true
        ? avatarUrl!.trim()
        : firebaseUser.photoURL?.trim() ?? '';
    final fingerprint = [
      firebaseUser.uid,
      code,
      displayName,
      firebaseUser.email ?? '',
      effectiveAvatarUrl,
    ].join('|');
    if (_publishedProfileFingerprints.contains(fingerprint)) return;

    try {
      final data = {
        'uid': firebaseUser.uid,
        'code': code,
        'name': displayName,
        'email': firebaseUser.email,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (effectiveAvatarUrl.isNotEmpty) {
        data['avatarUrl'] = effectiveAvatarUrl;
      }

      await FirestoreService.updatePublicProfile(
        code,
        data,
      ).timeout(const Duration(seconds: 5));
      _publishedProfileFingerprints.add(fingerprint);
    } catch (_) {
      try {
        final profileRef =
            FirebaseFirestore.instance.collection('publicProfiles').doc(code);

        final fallbackData = <String, dynamic>{
          'uid': firebaseUser.uid,
          'code': code,
          'name': displayName,
          'email': firebaseUser.email,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (effectiveAvatarUrl.isNotEmpty) {
          fallbackData['avatarUrl'] = effectiveAvatarUrl;
        }

        await profileRef
            .set(fallbackData, SetOptions(merge: true))
            .timeout(const Duration(seconds: 5));
        _publishedProfileFingerprints.add(fingerprint);
      } catch (_) {}
    }
  }

  /// Returns true if already friends (or reverse accepted was repaired).
  Future<bool> _ensureNotAlreadyFriendsOrRepairAccepted({
    required String currentUid,
    required String targetUid,
    required String myCode,
    required String targetCode,
  }) async {
    // 1. Check current user's friend doc
    debugPrint('friendRepair: checking current friend doc');
    final myFriendDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUid)
        .collection('friends')
        .doc(targetUid)
        .get();

    if (myFriendDoc.exists) {
      debugPrint('friendRepair: already friends true (current doc exists)');
      return true;
    }

    // 2. Skip reciprocal friend doc read - rules deny other user friend reads
    debugPrint(
      'friendRepair: skipping reciprocal friend doc read because rules deny other user friend reads',
    );

    // 3. Check current user mirror accepted request first
    debugPrint('friendRepair: checking current mirror accepted request');
    final mirrorRequestDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUid)
        .collection('friend_requests')
        .doc(targetUid)
        .get();

    if (mirrorRequestDoc.exists) {
      final data = mirrorRequestDoc.data();
      debugPrint('friendRepair: current mirror status=${data?['status']}');
      if (data != null && data['status'] == 'accepted') {
        debugPrint(
          'friendRepair: accepted mirror found, repairing friend docs',
        );
        final targetName = _usableName(data['fromName'] as String?) ??
            await _publicProfileBestEffortName(targetCode);
        final currentName = _usableName(data['toName'] as String?) ??
            await _currentUserBestEffortName(profileCode: myCode);
        final targetAvatar =
            (await findPublicProfileByCode(targetCode))?.avatarUrl;
        final currentAvatar =
            firebase_auth.FirebaseAuth.instance.currentUser?.photoURL;
        await FirestoreService.ensureFriendDocs(
          uidA: targetUid,
          uidB: currentUid,
          nameA: targetName,
          codeA: targetCode,
          avatarA: targetAvatar,
          nameB: currentName,
          codeB: myCode,
          avatarB: currentAvatar,
        );
        debugPrint('friendRepair: ensureFriendDocs success');
        return true;
      }
    }

    // 4. Check reverse accepted top-level request (wrap in try/catch)
    debugPrint('friendRepair: checking reverse accepted request');
    try {
      final reverseRequestId = '${targetUid}_$currentUid';
      final reverseRequestDoc = await FirebaseFirestore.instance
          .collection('friendRequests')
          .doc(reverseRequestId)
          .get();

      if (reverseRequestDoc.exists) {
        final data = reverseRequestDoc.data();
        if (data != null && data['status'] == 'accepted') {
          debugPrint(
            'friendRepair: reverse accepted request found, repairing friend docs',
          );
          final targetName = _usableName(data['fromName'] as String?) ??
              await _publicProfileBestEffortName(targetCode);
          final currentName = _usableName(data['toName'] as String?) ??
              await _currentUserBestEffortName(profileCode: myCode);
          final targetAvatar =
              (await findPublicProfileByCode(targetCode))?.avatarUrl;
          final currentAvatar =
              firebase_auth.FirebaseAuth.instance.currentUser?.photoURL;
          await FirestoreService.ensureFriendDocs(
            uidA: targetUid,
            uidB: currentUid,
            nameA: targetName,
            codeA: targetCode,
            avatarA: targetAvatar,
            nameB: currentName,
            codeB: myCode,
            avatarB: currentAvatar,
          );
          debugPrint('friendRepair: ensureFriendDocs success');
          return true;
        }
      }
    } catch (e) {
      debugPrint(
        'friendRepair: reverse accepted request read failed, continuing',
      );
    }

    debugPrint('friendRepair: already friends false');
    return false;
  }

  Future<FriendAddResult> addFriendByCode(String rawCode) async {
    final code = _normalizeCode(rawCode);

    debugPrint('addFriendByCode: raw input=$rawCode');
    debugPrint('addFriendByCode: normalized input=$code');

    // Validate format
    if (code.isEmpty || !RegExp(r'^[A-Z]{2}-\d{4}$').hasMatch(code)) {
      return const FriendAddResult(
        success: false,
        message: 'Invalid friend code format. Use format like AB-1234.',
      );
    }

    final myCode = await getMyCode();
    debugPrint('addFriendByCode: myCode=$myCode');

    if (code == myCode) {
      return const FriendAddResult(
        success: false,
        message: 'You cannot add your own code.',
      );
    }

    final friends = await getFriends();
    final exists = friends.any((friend) => _normalizeCode(friend.code) == code);
    if (exists) {
      return const FriendAddResult(
        success: false,
        message: 'This friend is already added.',
      );
    }

    try {
      await _publishPublicProfile(myCode);

      // Direct Firestore query to friendCodes collection (public read)
      debugPrint('addFriendByCode: looking up friendCodes/$code');
      final codeDoc = await FirebaseFirestore.instance
          .collection('friendCodes')
          .doc(code)
          .get();

      debugPrint('addFriendByCode: friendCodes/$code exists ${codeDoc.exists}');

      if (!codeDoc.exists || codeDoc.data()?['uid'] == null) {
        debugPrint(
          'addFriendByCode: friendCodes/$code missing or no uid, returning not found',
        );
        return const FriendAddResult(
          success: false,
          message:
              'Friend code not found. Ask them to open the app first so their code is registered.',
        );
      }

      final toUid = codeDoc.data()!['uid'] as String;
      debugPrint('addFriendByCode: targetUid=$toUid');

      final currentUid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
      debugPrint('addFriendByCode: current FirebaseAuth uid=$currentUid');

      if (currentUid == null) {
        return const FriendAddResult(
          success: false,
          message: 'You must be signed in to add friends.',
        );
      }

      final fromName = await _currentUserBestEffortName(profileCode: myCode);
      final toName = _usableName(codeDoc.data()?['name'] as String?) ??
          await _publicProfileBestEffortName(code);

      // Check if already friends or reverse accepted needs repair
      final alreadyFriends = await _ensureNotAlreadyFriendsOrRepairAccepted(
        currentUid: currentUid,
        targetUid: toUid,
        myCode: myCode,
        targetCode: code,
      );

      if (alreadyFriends) {
        return const FriendAddResult(
          success: true,
          message: 'Already friends.',
        );
      }

      debugPrint('Sending friend request: from $currentUid to $toUid');
      debugPrint('Sending friend request: fromCode=$myCode');
      debugPrint('Sending friend request: toCode=$code');

      // Send friend request to the target user's friend_requests collection
      await FirestoreService.sendFriendRequest(
        fromUid: currentUid,
        toUid: toUid,
        fromCode: myCode,
        toCode: code,
        fromName: fromName,
        toName: toName,
        fromAvatarUrl:
            firebase_auth.FirebaseAuth.instance.currentUser?.photoURL,
      ).timeout(const Duration(seconds: 8));

      debugPrint('Friend request sent successfully');

      return FriendAddResult(success: true, message: 'Friend request sent!');
    } catch (e) {
      debugPrint('Failed to send friend request: $e');
      return FriendAddResult(
        success: false,
        message:
            'Failed to send friend request: ${e.toString().split(':').first}',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getPendingFriendRequests() async {
    final currentUid = await _currentUserId();
    if (currentUid == null) {
      debugPrint('getPendingFriendRequests: No current user');
      return const [];
    }

    debugPrint('getPendingFriendRequests: Checking for user $currentUid');

    try {
      final snapshot = await FirestoreService.getPendingFriendRequests();

      debugPrint(
        'getPendingFriendRequests: Found ${snapshot.docs.length} total requests',
      );

      final requests = snapshot.docs.where((doc) {
        final data = doc.data();
        final status = data['status'] as String? ?? '';
        debugPrint('Request ${doc.id}: status=$status');
        return status == 'pending';
      }).map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'fromUid': data['fromUid'] as String? ?? '',
          'fromName': data['fromName'] as String? ?? 'Unknown',
          'fromCode': data['fromCode'] as String? ?? '',
          'fromEmail': data['fromEmail'] as String? ?? '',
          'fromAvatarUrl': data['fromAvatarUrl'] as String? ?? '',
          'status': data['status'] as String? ?? 'pending',
          'createdAt': data['createdAt'],
        };
      }).toList();

      debugPrint(
        'getPendingFriendRequests: Returning ${requests.length} pending requests',
      );
      return requests;
    } catch (e) {
      debugPrint('Failed to load friend requests: $e');
      return const [];
    }
  }

  Future<FriendAddResult> acceptFriendRequest(
    Map<String, dynamic> request,
  ) async {
    final currentUid = await _currentUserId();
    if (currentUid == null) {
      return const FriendAddResult(
        success: false,
        message: 'You must be signed in to accept friend requests.',
      );
    }

    final fromUid = request['fromUid'] as String?;
    final fromName = request['fromName'] as String? ?? 'Unknown';
    final fromCode = request['fromCode'] as String? ?? '';
    final fromEmail = request['fromEmail'] as String?;
    final fromAvatarUrl = request['fromAvatarUrl'] as String?;

    if (fromUid == null || fromUid.isEmpty) {
      return const FriendAddResult(
        success: false,
        message: 'Invalid friend request.',
      );
    }

    try {
      final myCode = await getMyCode();

      debugPrint('=== ACCEPT FRIEND REQUEST ===');
      debugPrint('Current UID: $currentUid');
      debugPrint('From UID: $fromUid');
      debugPrint('My Code: $myCode');

      // Use centralized Firestore service for friend request acceptance
      await FirestoreService.respondToFriendRequest(fromUid, true);
      debugPrint('Batch write SUCCESS!');

      _cachedFriends = null;

      final friend = Friend(
        id: fromUid,
        uid: fromUid,
        name: fromName,
        role: 'Viewer',
        code: fromCode,
        email: fromEmail,
        avatarUrl: fromAvatarUrl,
      );

      return FriendAddResult(
        success: true,
        message: '$fromName is now your friend!',
        friend: friend,
      );
    } catch (e) {
      debugPrint('Failed to accept friend request: $e');
      return FriendAddResult(
        success: false,
        message:
            'Failed to accept friend request: ${e.toString().split(':').first}',
      );
    }
  }

  Future<bool> declineFriendRequest(Map<String, dynamic> request) async {
    final currentUid = await _currentUserId();
    if (currentUid == null) return false;

    final fromUid = request['fromUid'] as String?;
    if (fromUid == null || fromUid.isEmpty) return false;

    try {
      await FirestoreService.respondToFriendRequest(
        fromUid,
        false,
      ).timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      debugPrint('Failed to decline friend request: $e');
      return false;
    }
  }

  String _normalizeCode(String code) {
    final compact = code.trim().toUpperCase().replaceAll(
          RegExp(r'[^A-Z0-9]'),
          '',
        );
    if (RegExp(r'^[A-Z]{2}[0-9]{4}$').hasMatch(compact)) {
      return '${compact.substring(0, 2)}-${compact.substring(2)}';
    }
    return code.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  }

  String _generateCode(String seed, String? uid) {
    final cleaned = seed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final prefix =
        (cleaned.isEmpty ? 'HP' : cleaned).padRight(2, 'H').substring(0, 2);
    final uniquenessSeed = uid?.isNotEmpty == true ? '$seed-$uid' : seed;
    final numeric = (uniquenessSeed.hashCode.abs() % 10000).toString().padLeft(
          4,
          '0',
        );
    return '$prefix-$numeric';
  }
}
