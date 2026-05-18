import 'dart:async';
import 'dart:developer' as developer;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:halaph/services/firebase_app_service.dart';
import 'package:halaph/models/friend.dart';
import 'package:halaph/models/plan.dart';

/// Centralized Firestore service layer that enforces production security rules
class FirestoreService {
  static const Duration _accountCleanupTimeout = Duration(seconds: 8);
  static const int _accountCleanupBatchLimit = 450;

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static firebase_auth.User? _currentUser;
  static StreamSubscription<firebase_auth.User?>? _authSubscription;

  /// Initialize the service and listen to auth changes
  static Future<void> initialize() async {
    await FirebaseAppService.initialize();

    _authSubscription =
        firebase_auth.FirebaseAuth.instance.authStateChanges().listen((user) {
      _currentUser = user;
      developer
          .log('FirestoreService: Auth state changed - User: ${user?.uid}');
    });

    _currentUser = firebase_auth.FirebaseAuth.instance.currentUser;
  }

  /// Get current authenticated user
  static firebase_auth.User? get currentUser => _currentUser;

  /// Get current user ID with validation
  static String? get currentUserId {
    final liveUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (liveUser != null) {
      _currentUser = liveUser;
      return liveUser.uid;
    }

    final user = _currentUser;
    if (user == null) {
      developer.log('FirestoreService: No authenticated user');
      return null;
    }
    return user.uid;
  }

  /// Handle Firestore errors with user-friendly messages
  static String handleFirestoreError(dynamic error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You don\'t have permission to perform this action.';
        case 'unauthenticated':
          return 'Please sign in to continue.';
        case 'not-found':
          return 'The requested data was not found.';
        case 'already-exists':
          return 'This data already exists.';
        case 'unavailable':
          return 'Service is temporarily unavailable. Please try again.';
        case 'deadline-exceeded':
          return 'Request timed out. Please check your connection and try again.';
        default:
          return 'An error occurred: ${error.message}';
      }
    }
    return 'An unexpected error occurred.';
  }

  /// Validate required fields before Firestore write
  static bool validateRequiredFields(
      Map<String, dynamic> data, List<String> requiredFields) {
    for (final field in requiredFields) {
      if (!data.containsKey(field) || data[field] == null) {
        developer.log('FirestoreService: Missing required field: $field');
        return false;
      }
    }
    return true;
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

  static String _normalizeFriendCode(String? code) {
    final trimmed = code?.trim();
    if (trimmed == null || trimmed.isEmpty) return '';

    final compact = trimmed.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (RegExp(r'^[A-Z]{2}[0-9]{4}$').hasMatch(compact)) {
      return '${compact.substring(0, 2)}-${compact.substring(2)}';
    }

    return trimmed.toUpperCase();
  }

  static void _addCleanupCode(Set<String> cleanupCodes, String? value) {
    final code = _normalizeFriendCode(value);
    if (code.isNotEmpty) cleanupCodes.add(code);
  }

  static void _addOtherUid(
    Set<String> otherUids, {
    required String currentUid,
    String? value,
  }) {
    final uid = value?.trim();
    if (uid == null || uid.isEmpty || uid == currentUid) return;
    otherUids.add(uid);
  }

  static Future<int> _runAccountCleanupSection(
    String label,
    Future<int> Function() action,
  ) async {
    debugPrint('Account cleanup [$label]: start');
    try {
      final count = await action();
      if (count >= 0) {
        if (count == 0) {
          debugPrint('Account cleanup [$label]: empty section skipped');
        }
        debugPrint('Account cleanup [$label]: deleted count=$count');
      }
      return count;
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

  static Future<int> _deleteQueryDocs(
    Query<Map<String, dynamic>> query,
    String label,
  ) async {
    final snapshot = await query.get().timeout(_accountCleanupTimeout);
    if (snapshot.docs.isEmpty) {
      debugPrint('Account cleanup [$label]: empty query snapshot');
      return 0;
    }

    final batch = _AccountCleanupBatch(_db);
    for (final doc in snapshot.docs) {
      await batch.delete(doc.reference);
    }
    return batch.commit();
  }

  static Future<int> _deleteCollectionDocs(
    Query<Map<String, dynamic>> query,
    String label,
  ) {
    return _deleteQueryDocs(query, label);
  }

  static Future<int> _deleteDoc(
    DocumentReference<Map<String, dynamic>> ref,
    String label,
  ) async {
    await ref.delete().timeout(_accountCleanupTimeout);
    return 1;
  }

  static Future<void> prepareAccountDeletionProfile({
    required String uid,
    required String friendCode,
  }) async {
    final code = _normalizeFriendCode(friendCode);
    if (uid.trim().isEmpty) {
      throw StateError('Cannot prepare account deletion without a uid.');
    }
    if (code.isEmpty || code == 'HP-0000') {
      throw StateError(
          'Cannot prepare account deletion without a friend code.');
    }

    final liveUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (liveUser == null || liveUser.uid != uid) {
      throw StateError('Signed-in user changed before account cleanup.');
    }

    debugPrint('Account cleanup [profile preparation]: start');
    try {
      final friendCodeRef = _db.collection('friendCodes').doc(code);
      final friendCodeDoc =
          await friendCodeRef.get().timeout(_accountCleanupTimeout);
      final mappedUid = (friendCodeDoc.data()?['uid'] as String? ?? '').trim();
      if (friendCodeDoc.exists && mappedUid.isNotEmpty && mappedUid != uid) {
        throw StateError('Friend code $code belongs to a different user.');
      }

      if (!friendCodeDoc.exists || friendCodeDoc.data()?['code'] != code) {
        await friendCodeRef.set({
          'uid': uid,
          'code': code,
          if (!friendCodeDoc.exists) 'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(_accountCleanupTimeout);
      }

      final publicProfileRef = _db.collection('publicProfiles').doc(code);
      final publicProfileDoc =
          await publicProfileRef.get().timeout(_accountCleanupTimeout);
      final profileUid =
          (publicProfileDoc.data()?['uid'] as String? ?? '').trim();
      if (publicProfileDoc.exists &&
          profileUid.isNotEmpty &&
          profileUid != uid) {
        throw StateError('Public profile $code belongs to a different user.');
      }

      if (!publicProfileDoc.exists) {
        await publicProfileRef.set({
          'uid': uid,
          'code': code,
          'name': _bestEffortDisplayName(
                displayName: liveUser.displayName,
                email: liveUser.email,
              ) ??
              'Traveler',
          'email': liveUser.email,
          if (liveUser.photoURL?.trim().isNotEmpty == true)
            'avatarUrl': liveUser.photoURL!.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }).timeout(_accountCleanupTimeout);
      }

      debugPrint('Account cleanup [profile preparation]: deleted count=0');
    } on TimeoutException catch (error) {
      debugPrint(
        'Account cleanup [profile preparation]: failure reason=timeout $error',
      );
      rethrow;
    } on FirebaseException catch (error) {
      debugPrint(
        'Account cleanup [profile preparation]: failure reason=${error.code} ${error.message ?? ''}',
      );
      rethrow;
    } catch (error) {
      debugPrint(
          'Account cleanup [profile preparation]: failure reason=$error');
      rethrow;
    }
  }

  static String? _bestEffortDisplayName({
    String? displayName,
    String? email,
    String? publicProfileName,
  }) {
    return _usableName(displayName) ??
        _emailPrefix(email) ??
        _usableName(publicProfileName);
  }

  static Future<String?> _publicProfileNameByCode(String? code) async {
    final trimmed = code?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    try {
      final doc = await _db.collection('publicProfiles').doc(trimmed).get();
      final data = doc.data();
      return _usableName(data?['name'] as String?) ??
          _emailPrefix(data?['email'] as String?);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _publicProfileAvatarByCode(String? code) async {
    final trimmed = code?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    try {
      final doc = await _db.collection('publicProfiles').doc(trimmed).get();
      final avatar = (doc.data()?['avatarUrl'] as String?)?.trim();
      if (avatar == null || avatar.isEmpty) return null;
      return avatar;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _currentUserBestEffortName({String? code}) async {
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    final publicProfileName = await _publicProfileNameByCode(code);
    return _bestEffortDisplayName(
      displayName: user?.displayName,
      email: user?.email,
      publicProfileName: publicProfileName,
    );
  }

  static Map<String, dynamic> _friendRequestPayload({
    required String fromUid,
    required String toUid,
    required String fromCode,
    required String toCode,
    String? fromName,
    String? toName,
    String? fromAvatarUrl,
    String? toAvatarUrl,
  }) {
    final requestData = <String, dynamic>{
      'fromUid': fromUid,
      'toUid': toUid,
      'fromCode': fromCode,
      'toCode': toCode,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final usableFromName = _usableName(fromName);
    if (usableFromName != null) {
      requestData['fromName'] = usableFromName;
    }
    final usableToName = _usableName(toName);
    if (usableToName != null) {
      requestData['toName'] = usableToName;
    }

    final usableFromAvatarUrl = fromAvatarUrl?.trim();
    if (usableFromAvatarUrl != null && usableFromAvatarUrl.isNotEmpty) {
      requestData['fromAvatarUrl'] = usableFromAvatarUrl;
    }

    final usableToAvatarUrl = toAvatarUrl?.trim();
    if (usableToAvatarUrl != null && usableToAvatarUrl.isNotEmpty) {
      requestData['toAvatarUrl'] = usableToAvatarUrl;
    }

    return requestData;
  }

  @visibleForTesting
  static Map<String, dynamic> friendRequestPayloadForTesting({
    required String fromUid,
    required String toUid,
    required String fromCode,
    required String toCode,
    String? fromName,
    String? toName,
    String? fromAvatarUrl,
    String? toAvatarUrl,
  }) {
    return _friendRequestPayload(
      fromUid: fromUid,
      toUid: toUid,
      fromCode: fromCode,
      toCode: toCode,
      fromName: fromName,
      toName: toName,
      fromAvatarUrl: fromAvatarUrl,
      toAvatarUrl: toAvatarUrl,
    );
  }

  static Map<String, dynamic> _friendDocPayload({
    required String uid,
    required String code,
    required String? name,
    String? avatarUrl,
  }) {
    final data = <String, dynamic>{
      'uid': uid,
      'friendUid': uid,
      'friendId': uid,
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final usableName = _usableName(name);
    if (usableName != null) {
      data['name'] = usableName;
    }

    final usableAvatarUrl = avatarUrl?.trim();
    if (usableAvatarUrl != null && usableAvatarUrl.isNotEmpty) {
      data['avatarUrl'] = usableAvatarUrl;
    }

    return data;
  }

  @visibleForTesting
  static Map<String, dynamic> friendDocPayloadForTesting({
    required String uid,
    required String code,
    required String? name,
    String? avatarUrl,
  }) {
    return _friendDocPayload(
      uid: uid,
      code: code,
      name: name,
      avatarUrl: avatarUrl,
    );
  }

  /// Validate immutable fields are not changed
  static bool validateImmutableFields(
    Map<String, dynamic> newData,
    Map<String, dynamic> oldData,
    List<String> immutableFields,
  ) {
    for (final field in immutableFields) {
      if (oldData.containsKey(field) && newData.containsKey(field)) {
        if (oldData[field] != newData[field]) {
          developer.log(
              'FirestoreService: Attempted to change immutable field: $field');
          return false;
        }
      }
    }
    return true;
  }

  // ===== USER SYNC DATA =====

  /// Get user's private sync data
  static Future<Map<String, dynamic>?> getMySyncData(String namespace) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      final doc = await _db
          .collection('users')
          .doc(userId)
          .collection('sync')
          .doc(namespace)
          .get();

      return doc.exists ? doc.data() : null;
    } catch (e) {
      developer.log('FirestoreService: Error getting sync data: $e');
      rethrow;
    }
  }

  /// Save user's private sync data
  static Future<void> saveMySyncData(
      String namespace, Map<String, dynamic> data) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      data['_updatedAt'] = FieldValue.serverTimestamp();
      await _db
          .collection('users')
          .doc(userId)
          .collection('sync')
          .doc(namespace)
          .set(data, SetOptions(merge: true));
    } catch (e) {
      developer.log('FirestoreService: Error saving sync data: $e');
      rethrow;
    }
  }

  static Future<void> cleanupAccountData({
    required String uid,
    required String? friendCode,
  }) async {
    final code = _normalizeFriendCode(friendCode);
    final cleanupCodes = <String>{};
    final friendCodeRefs = <String, DocumentReference<Map<String, dynamic>>>{};
    final otherUids = <String>{};
    _addCleanupCode(cleanupCodes, code);

    try {
      debugPrint('FirestoreService.cleanupAccountData: start uid=$uid');

      await _runAccountCleanupSection('users/$uid/friends', () async {
        final snapshot = await _db
            .collection('users')
            .doc(uid)
            .collection('friends')
            .get()
            .timeout(_accountCleanupTimeout);
        if (snapshot.docs.isEmpty) {
          debugPrint(
              'Account cleanup [users/$uid/friends]: empty query snapshot');
          return 0;
        }

        final batch = _AccountCleanupBatch(_db);
        for (final doc in snapshot.docs) {
          final data = doc.data();
          _addOtherUid(
            otherUids,
            currentUid: uid,
            value: data['friendUid'] as String? ??
                data['uid'] as String? ??
                data['friendId'] as String? ??
                doc.id,
          );
          await batch.delete(doc.reference);
        }
        return batch.commit();
      });

      await _runAccountCleanupSection('users/$uid/friend_requests', () async {
        final snapshot = await _db
            .collection('users')
            .doc(uid)
            .collection('friend_requests')
            .get()
            .timeout(_accountCleanupTimeout);
        if (snapshot.docs.isEmpty) {
          debugPrint(
            'Account cleanup [users/$uid/friend_requests]: empty query snapshot',
          );
          return 0;
        }

        final batch = _AccountCleanupBatch(_db);
        for (final doc in snapshot.docs) {
          final data = doc.data();
          _addOtherUid(
            otherUids,
            currentUid: uid,
            value: data['fromUid'] as String? ?? doc.id,
          );
          _addOtherUid(
            otherUids,
            currentUid: uid,
            value: data['toUid'] as String?,
          );
          await batch.delete(doc.reference);
        }
        return batch.commit();
      });

      await _runAccountCleanupSection('friendRequests fromUid=$uid', () async {
        final snapshot = await _db
            .collection('friendRequests')
            .where('fromUid', isEqualTo: uid)
            .get()
            .timeout(_accountCleanupTimeout);
        if (snapshot.docs.isEmpty) {
          debugPrint(
            'Account cleanup [friendRequests fromUid=$uid]: empty query snapshot',
          );
          return 0;
        }

        final batch = _AccountCleanupBatch(_db);
        for (final doc in snapshot.docs) {
          final data = doc.data();
          _addOtherUid(
            otherUids,
            currentUid: uid,
            value: data['toUid'] as String?,
          );
          await batch.delete(doc.reference);
        }
        return batch.commit();
      });

      await _runAccountCleanupSection('friendRequests toUid=$uid', () async {
        final snapshot = await _db
            .collection('friendRequests')
            .where('toUid', isEqualTo: uid)
            .get()
            .timeout(_accountCleanupTimeout);
        if (snapshot.docs.isEmpty) {
          debugPrint(
            'Account cleanup [friendRequests toUid=$uid]: empty query snapshot',
          );
          return 0;
        }

        final batch = _AccountCleanupBatch(_db);
        for (final doc in snapshot.docs) {
          final data = doc.data();
          _addOtherUid(
            otherUids,
            currentUid: uid,
            value: data['fromUid'] as String?,
          );
          await batch.delete(doc.reference);
        }
        return batch.commit();
      });

      await _runAccountCleanupSection('other user relationship mirrors',
          () async {
        if (otherUids.isEmpty) return 0;

        final batch = _AccountCleanupBatch(_db);
        for (final otherUid in otherUids) {
          await batch.delete(
            _db
                .collection('users')
                .doc(otherUid)
                .collection('friends')
                .doc(uid),
          );
          await batch.delete(
            _db
                .collection('users')
                .doc(otherUid)
                .collection('friend_requests')
                .doc(uid),
          );
          await batch
              .delete(_db.collection('friendRequests').doc('${uid}_$otherUid'));
          await batch
              .delete(_db.collection('friendRequests').doc('${otherUid}_$uid'));
        }
        return batch.commit();
      });

      await _runAccountCleanupSection('users/$uid/sync', () {
        return _deleteCollectionDocs(
          _db.collection('users').doc(uid).collection('sync'),
          'users/$uid/sync',
        );
      });

      await _runAccountCleanupSection('users/$uid/favorites', () {
        return _deleteCollectionDocs(
          _db.collection('users').doc(uid).collection('favorites'),
          'users/$uid/favorites',
        );
      });

      await _runAccountCleanupSection('users/$uid/notifications', () {
        return _deleteCollectionDocs(
          _db.collection('users').doc(uid).collection('notifications'),
          'users/$uid/notifications',
        );
      });

      await _runAccountCleanupSection('users/$uid/activity', () {
        return _deleteCollectionDocs(
          _db.collection('users').doc(uid).collection('activity'),
          'users/$uid/activity',
        );
      });

      await _runAccountCleanupSection('friendCodes uid=$uid', () async {
        final snapshot = await _db
            .collection('friendCodes')
            .where('uid', isEqualTo: uid)
            .get()
            .timeout(_accountCleanupTimeout);
        if (snapshot.docs.isEmpty) {
          debugPrint(
              'Account cleanup [friendCodes uid=$uid]: empty query snapshot');
          return 0;
        }

        for (final doc in snapshot.docs) {
          _addCleanupCode(cleanupCodes, doc.id);
          _addCleanupCode(cleanupCodes, doc.data()['code'] as String?);
          friendCodeRefs[doc.reference.path] = doc.reference;
        }
        debugPrint('Account cleanup [friendCodes uid=$uid]: deleted count=0');
        return -1;
      });

      await _runAccountCleanupSection('friendCodes/$code', () async {
        if (code.isEmpty) return 0;

        final ref = _db.collection('friendCodes').doc(code);
        final doc = await ref.get().timeout(_accountCleanupTimeout);
        if (!doc.exists) {
          debugPrint('Account cleanup [friendCodes/$code]: missing doc no-op');
          return 0;
        }

        final mappedUid = (doc.data()?['uid'] as String? ?? '').trim();
        if (mappedUid.isNotEmpty && mappedUid != uid) {
          throw StateError('Refusing to delete unowned friendCodes/$code.');
        }

        _addCleanupCode(cleanupCodes, doc.id);
        _addCleanupCode(cleanupCodes, doc.data()?['code'] as String?);
        friendCodeRefs[ref.path] = ref;
        debugPrint('Account cleanup [friendCodes/$code]: deleted count=0');
        return -1;
      });

      await _runAccountCleanupSection('publicProfiles uid=$uid', () async {
        debugPrint(
          'Account cleanup [publicProfiles uid=$uid]: query unsupported by current rules',
        );
        return 0;
      });

      for (final cleanupCode in cleanupCodes) {
        await _runAccountCleanupSection(
          'publicProfiles/$cleanupCode',
          () async {
            final ref = _db.collection('publicProfiles').doc(cleanupCode);
            final doc = await ref.get().timeout(_accountCleanupTimeout);
            if (!doc.exists) {
              debugPrint(
                'Account cleanup [publicProfiles/$cleanupCode]: missing doc no-op',
              );
              return 0;
            }

            final profileUid = (doc.data()?['uid'] as String? ?? '').trim();
            if (profileUid.isNotEmpty && profileUid != uid) {
              throw StateError(
                'Refusing to delete unowned publicProfiles/$cleanupCode.',
              );
            }

            return _deleteDoc(ref, 'publicProfiles/$cleanupCode');
          },
        );
      }

      await _runAccountCleanupSection('friendCodes owned docs', () async {
        if (friendCodeRefs.isEmpty) return 0;

        final batch = _AccountCleanupBatch(_db);
        for (final ref in friendCodeRefs.values) {
          await batch.delete(ref);
        }
        return batch.commit();
      });

      await _runAccountCleanupSection('users/$uid', () {
        return _deleteDoc(_db.collection('users').doc(uid), 'users/$uid');
      });

      debugPrint('FirestoreService.cleanupAccountData: completed uid=$uid');
    } catch (error) {
      developer.log('FirestoreService: Account cleanup failed: $error');
      rethrow;
    }
  }

  // ===== FRIENDS (READ-ONLY) =====

  /// Get user's friends (read-only from client perspective)
  static Stream<List<Friend>> getMyFriends() {
    final userId = currentUserId;
    if (userId == null) {
      return Stream.value([]);
    }

    return _db
        .collection('users')
        .doc(userId)
        .collection('friends')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Friend(
                  id: doc.id,
                  uid: doc.data()['friendUid'],
                  name: doc.data()['name'] ?? 'Unknown',
                  role: doc.data()['role'] ?? 'Viewer',
                  code: doc.data()['code'] ?? '',
                  email: doc.data()['email'],
                  avatarUrl: doc.data()['avatarUrl'],
                ))
            .toList());
  }

  // ===== FRIEND REQUESTS =====

  /// Send friend request using mirror approach (write to both paths)
  static Future<void> sendFriendRequest({
    required String fromUid,
    required String toUid,
    required String fromCode,
    required String toCode,
    String? fromName,
    String? toName,
    String? fromAvatarUrl,
    String? toAvatarUrl,
  }) async {
    debugPrint(
        '### ENTERED FirestoreService.sendFriendRequest ACTIVE METHOD ###');

    if (fromUid == toUid) {
      throw Exception('Cannot send friend request to yourself');
    }

    final requestId = '$fromUid' '_' '$toUid';
    final requestData = _friendRequestPayload(
      fromUid: fromUid,
      toUid: toUid,
      fromCode: fromCode,
      toCode: toCode,
      fromName: fromName,
      toName: toName,
      fromAvatarUrl: fromAvatarUrl,
      toAvatarUrl: toAvatarUrl,
    );

    try {
      final batch = _db.batch();

      final liveAuthUid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
      final primaryPath = 'friendRequests/$requestId';
      final mirrorPath = 'users/$toUid/friend_requests/$fromUid';

      debugPrint('sendFriendRequest: FirebaseAuth uid=$liveAuthUid');
      debugPrint('sendFriendRequest: fromUid=$fromUid');
      debugPrint('sendFriendRequest: toUid=$toUid');
      debugPrint('sendFriendRequest: fromCode=$fromCode');
      debugPrint('sendFriendRequest: toCode=$toCode');
      debugPrint('sendFriendRequest: primary path=$primaryPath');
      debugPrint('sendFriendRequest: mirror path=$mirrorPath');
      debugPrint(
          'sendFriendRequest: payload keys=${requestData.keys.toList()}');
      debugPrint('sendFriendRequest: full payload=$requestData');

      // Top-level mirror
      final topRef = _db.collection('friendRequests').doc(requestId);
      batch.set(topRef, requestData);

      // Nested inbox mirror
      final nestedRef = _db
          .collection('users')
          .doc(toUid)
          .collection('friend_requests')
          .doc(fromUid);
      batch.set(nestedRef, requestData);

      await batch.commit();
      developer.log(
          'FirestoreService: Friend request sent from $fromUid to $toUid (toCode=$toCode)');
    } catch (e) {
      if (e is FirebaseException && e.code == 'already-exists') {
        developer.log(
            'FirestoreService: Friend request may already exist $fromUid -> $toUid');
      } else {
        developer.log('FirestoreService: Error sending friend request: $e');
        rethrow;
      }
    }
  }

  /// Create reciprocal friend docs in both users' friends collections
  static Future<void> ensureFriendDocs({
    required String uidA,
    required String uidB,
    String? nameA,
    String? codeA,
    String? nameB,
    String? codeB,
    String? avatarA,
    String? avatarB,
  }) async {
    try {
      final batch = _db.batch();

      // User A's friends collection: add User B
      final docARef =
          _db.collection('users').doc(uidA).collection('friends').doc(uidB);
      batch.set(
        docARef,
        _friendDocPayload(
          uid: uidB,
          code: codeB ?? '',
          name: nameB,
          avatarUrl: avatarB,
        ),
        SetOptions(merge: true),
      );

      // User B's friends collection: add User A
      final docBRef =
          _db.collection('users').doc(uidB).collection('friends').doc(uidA);
      batch.set(
        docBRef,
        _friendDocPayload(
          uid: uidA,
          code: codeA ?? '',
          name: nameA,
          avatarUrl: avatarA,
        ),
        SetOptions(merge: true),
      );

      await batch.commit();
      developer.log(
          'FirestoreService: Created reciprocal friend docs between $uidA and $uidB');
    } catch (e) {
      developer.log('FirestoreService: Error creating friend docs: $e');
      rethrow;
    }
  }

  /// Respond to friend request (accept/reject)
  static Future<void> respondToFriendRequest(
      String fromUid, bool accept) async {
    final toUid = currentUserId;
    if (toUid == null) throw Exception('User not authenticated');

    try {
      final batch = _db.batch();

      // Update nested request
      final nestedRef = _db
          .collection('users')
          .doc(toUid)
          .collection('friend_requests')
          .doc(fromUid);
      batch.update(nestedRef, {
        'status': accept ? 'accepted' : 'declined',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update top-level request
      final topRef =
          _db.collection('friendRequests').doc('$fromUid' '_' '$toUid');
      batch.update(topRef, {
        'status': accept ? 'accepted' : 'declined',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // If accepted, create reciprocal friend docs
      if (accept) {
        // Read request data to get names/codes
        final requestDoc = await nestedRef.get();
        final data = requestDoc.data();
        final fromCode = data?['fromCode'] as String?;
        final toCode = data?['toCode'] as String?;
        final fromName = _usableName(data?['fromName'] as String?) ??
            await _publicProfileNameByCode(fromCode);
        final toName = _usableName(data?['toName'] as String?) ??
            await _currentUserBestEffortName(code: toCode);
        final fromAvatarUrl = (data?['fromAvatarUrl'] as String?)?.trim();
        final resolvedFromAvatar =
            (fromAvatarUrl != null && fromAvatarUrl.isNotEmpty)
                ? fromAvatarUrl
                : await _publicProfileAvatarByCode(fromCode);
        final toAvatarUrl =
            firebase_auth.FirebaseAuth.instance.currentUser?.photoURL?.trim();
        final resolvedToAvatar = (toAvatarUrl != null && toAvatarUrl.isNotEmpty)
            ? toAvatarUrl
            : await _publicProfileAvatarByCode(toCode);
        await ensureFriendDocs(
          uidA: fromUid,
          uidB: toUid,
          nameA: fromName,
          codeA: fromCode,
          avatarA: resolvedFromAvatar,
          nameB: toName,
          codeB: toCode,
          avatarB: resolvedToAvatar,
        );
      }

      developer.log(
          'FirestoreService: Friend request $fromUid -> $toUid ${accept ? 'accepted' : 'rejected'}');
    } catch (e) {
      developer.log('FirestoreService: Error responding to friend request: $e');
      rethrow;
    }
  }

  /// Cancel pending friend request
  static Future<void> cancelFriendRequest(String toUid) async {
    final fromUid = currentUserId;
    if (fromUid == null) throw Exception('User not authenticated');

    try {
      await _db
          .collection('users')
          .doc(toUid)
          .collection('friend_requests')
          .doc(fromUid)
          .delete();

      developer.log(
          'FirestoreService: Friend request cancelled from $fromUid to $toUid');
    } catch (e) {
      developer.log('FirestoreService: Error cancelling friend request: $e');
      rethrow;
    }
  }

  /// Get incoming friend requests
  static Stream<List<Map<String, dynamic>>> getMyFriendRequests() {
    final userId = currentUserId;
    if (userId == null) {
      return Stream.value([]);
    }

    return _db
        .collection('users')
        .doc(userId)
        .collection('friend_requests')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList());
  }

  // ===== PUBLIC PROFILES =====

  /// Get public profile by exact code (no listing allowed)
  static Future<Map<String, dynamic>?> getPublicProfileByCode(
      String code) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    try {
      final doc = await _db.collection('publicProfiles').doc(code).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      developer.log('FirestoreService: Error getting public profile: $e');
      rethrow;
    }
  }

  /// Create public profile with proper validation
  static Future<void> createPublicProfile(
      String code, Map<String, dynamic> profileData) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      final requiredFields = ['uid', 'code', 'name', 'createdAt', 'updatedAt'];
      if (!validateRequiredFields(profileData, requiredFields)) {
        throw Exception('Missing required fields for public profile');
      }

      // Ensure immutable fields match
      profileData['uid'] = userId;
      profileData['code'] = code;
      profileData['createdAt'] = FieldValue.serverTimestamp();
      profileData['updatedAt'] = FieldValue.serverTimestamp();

      await _db.collection('publicProfiles').doc(code).set(profileData);

      developer.log(
          'FirestoreService: Public profile created for user $userId with code $code');
    } catch (e) {
      developer.log('FirestoreService: Error creating public profile: $e');
      rethrow;
    }
  }

  /// Update public profile (immutable fields protected)
  static Future<void> updatePublicProfile(
      String code, Map<String, dynamic> updateData) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      // Get current profile to validate immutable fields
      final doc = await _db.collection('publicProfiles').doc(code).get();
      if (!doc.exists) throw Exception('Profile not found');

      final currentData = doc.data()!;
      final immutableFields = ['uid', 'code', 'createdAt'];

      if (!validateImmutableFields(updateData, currentData, immutableFields)) {
        throw Exception('Cannot modify immutable fields');
      }

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _db.collection('publicProfiles').doc(code).update(updateData);

      developer
          .log('FirestoreService: Public profile updated for user $userId');
    } catch (e) {
      developer.log('FirestoreService: Error updating public profile: $e');
      rethrow;
    }
  }

  // ===== SHARED PLANS =====

  /// Get a single shared plan by ID
  static Future<TravelPlan?> getSharedPlan(String planId) async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final doc = await _db.collection('sharedPlans').doc(planId).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      data['id'] = doc.id; // Ensure document ID is included

      // Check if user has access to this plan
      final participantUids = List<String>.from(data['participantUids'] ?? []);
      if (!participantUids.contains(userId)) {
        developer.log(
            'FirestoreService: User $userId does not have access to plan $planId');
        return null;
      }

      return TravelPlan.fromJson(data);
    } catch (e) {
      developer.log('FirestoreService: Error getting shared plan $planId: $e');
      return null;
    }
  }

  /// Get friends stream for real-time updates
  static Stream<QuerySnapshot<Map<String, dynamic>>> getFriendsStream(
      String userId) {
    developer
        .log('FirestoreService: Setting up friends stream for user $userId');
    return _db
        .collection('users')
        .doc(userId)
        .collection('friends')
        .snapshots();
  }

  /// Remove friend from user's friends list
  static Future<void> removeFriend(String userId, String friendId) async {
    developer
        .log('FirestoreService: Removing friend $friendId from user $userId');
    await _db
        .collection('users')
        .doc(userId)
        .collection('friends')
        .doc(friendId)
        .delete();
  }

  /// Remove friend request
  static Future<void> removeFriendRequest(
      String userId, String requestId) async {
    developer.log(
        'FirestoreService: Removing friend request $requestId from user $userId');
    await _db
        .collection('users')
        .doc(userId)
        .collection('friend_requests')
        .doc(requestId)
        .delete();
  }

  /// Save friends list for a user
  static Future<void> saveFriends(String userId, List<Friend> friends) async {
    developer.log(
        'FirestoreService: Saving ${friends.length} friends for user $userId');

    final batch = _db.batch();
    final collection =
        _db.collection('users').doc(userId).collection('friends');

    // Get existing friends to delete
    final existingDocs = await collection.get();
    for (final doc in existingDocs.docs) {
      batch.delete(doc.reference);
    }

    // Add all friends
    for (final friend in friends) {
      final docRef = collection.doc(friend.uid ?? friend.id);
      batch.set(docRef, {
        'ownerUid': userId,
        'friendUid': friend.uid ?? friend.id,
        'friendId': friend.id,
        'name': friend.name,
        'role': friend.role,
        'code': friend.code,
        'email': friend.email,
        'avatarUrl': friend.avatarUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    developer
        .log('FirestoreService: Successfully saved friends for user $userId');
  }

  /// Get friends list for a user
  static Future<List<Friend>> getFriends(String userId) async {
    developer.log('FirestoreService: Getting friends for user $userId');

    try {
      final snapshot =
          await _db.collection('users').doc(userId).collection('friends').get();

      return snapshot.docs.map((doc) {
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
    } catch (e) {
      developer.log('FirestoreService: Error getting friends: $e');
      return [];
    }
  }

  /// Get pending friend requests for current user
  static Future<QuerySnapshot<Map<String, dynamic>>>
      getPendingFriendRequests() async {
    final userId = firebase_auth.FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      // Return empty snapshot using limit(0) - returns 0 docs
      return _db
          .collection('users')
          .doc('__no_user__')
          .collection('friend_requests')
          .limit(0)
          .get();
    }

    return _db
        .collection('users')
        .doc(userId)
        .collection('friend_requests')
        .get();
  }

  /// Get public profile by code
  static Future<Map<String, dynamic>?> getPublicProfile(String code) async {
    final userId = currentUserId;
    if (userId == null) return null;

    try {
      final doc = await _db.collection('publicProfiles').doc(code).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      developer.log('FirestoreService: Error getting public profile: $e');
      return null;
    }
  }

  /// Get shared plans with proper query (array-contains + limit)
  static Stream<List<TravelPlan>> getMySharedPlans() {
    final userId = currentUserId;
    if (userId == null) {
      return Stream.value([]);
    }

    developer.log(
        'FirestoreService: Setting up real-time listener for shared plans of user $userId');

    return _db
        .collection('sharedPlans')
        .where('participantUids', arrayContains: userId)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      developer.log(
          'FirestoreService: Real-time update received with ${snapshot.docs.length} plans');

      final plans = snapshot.docs.map((doc) {
        final data = doc.data();
        // Ensure document ID is included in the data
        data['id'] = doc.id;

        try {
          final plan = TravelPlan.fromJson(data);
          developer.log(
              'FirestoreService: Successfully parsed plan ${plan.id} with ${plan.participantUids.length} participants');
          return plan;
        } catch (e) {
          developer.log('FirestoreService: Failed to parse plan ${doc.id}: $e');
          // Return a minimal valid plan to avoid breaking the stream
          return TravelPlan(
            id: doc.id,
            title: data['title'] ?? 'Unknown Plan',
            startDate:
                (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
            endDate:
                (data['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
            participantUids:
                List<String>.from(data['participantUids'] ?? [userId]),
            createdBy: data['createdBy'] ?? userId,
            isShared: data['isShared'] ?? true,
          );
        }
      }).toList();

      developer.log(
          'FirestoreService: Processed ${plans.length} valid plans for user $userId');
      return plans;
    }).handleError((error) {
      developer.log('FirestoreService: Real-time listener error: $error');
      return <TravelPlan>[];
    });
  }

  /// Create shared plan with proper validation
  static Future<String> createSharedPlan(Map<String, dynamic> planData) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      final requiredFields = [
        'title',
        'startDate',
        'endDate',
        'participantUids',
        'createdBy',
        'ownerUid',
        'createdAt',
        'updatedAt'
      ];

      if (!validateRequiredFields(planData, requiredFields)) {
        throw Exception('Missing required fields for shared plan');
      }

      // Validate ownership
      if (planData['createdBy'] != userId || planData['ownerUid'] != userId) {
        throw Exception('createdBy and ownerUid must match current user');
      }

      // Validate participantUids includes owner
      final participantUids = List<String>.from(planData['participantUids']);
      if (!participantUids.contains(userId)) {
        throw Exception('participantUids must include the owner');
      }

      // Validate dates
      final startDate = (planData['startDate'] as Timestamp).toDate();
      final endDate = (planData['endDate'] as Timestamp).toDate();
      if (endDate.isBefore(startDate)) {
        throw Exception('endDate must be after startDate');
      }

      // Set server timestamps and ensure proper collaboration fields
      final finalPlanData = Map<String, dynamic>.from(planData);
      finalPlanData['createdAt'] = FieldValue.serverTimestamp();
      finalPlanData['updatedAt'] = FieldValue.serverTimestamp();
      finalPlanData['isShared'] = true; // Ensure this is marked as shared

      // Ensure all required collaboration fields are present
      finalPlanData['createdBy'] = userId;
      finalPlanData['ownerUid'] = userId;

      developer.log(
          'FirestoreService: Creating shared plan with ${finalPlanData['participantUids']} participants');

      final docRef = await _db.collection('sharedPlans').add(finalPlanData);

      developer.log(
          'FirestoreService: Shared plan created: ${docRef.id} for user $userId');
      return docRef.id;
    } catch (e) {
      developer.log('FirestoreService: Error creating shared plan: $e');
      rethrow;
    }
  }

  /// Update shared plan as owner (can change membership and status)
  static Future<void> updateSharedPlanAsOwner(
      String planId, Map<String, dynamic> updateData) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      // Get current plan to validate ownership
      final doc = await _db.collection('sharedPlans').doc(planId).get();
      if (!doc.exists) throw Exception('Plan not found');

      final currentData = doc.data()!;
      if (currentData['ownerUid'] != userId ||
          currentData['createdBy'] != userId) {
        throw Exception('Only plan owner can perform this update');
      }

      // Validate immutable fields
      final immutableFields = ['createdBy', 'ownerUid', 'createdAt'];
      if (!validateImmutableFields(updateData, currentData, immutableFields)) {
        throw Exception('Cannot modify immutable fields');
      }

      // Ensure owner is still in participantUids
      if (updateData.containsKey('participantUids')) {
        final participantUids =
            List<String>.from(updateData['participantUids']);
        if (!participantUids.contains(userId)) {
          throw Exception('Owner must remain in participantUids');
        }

        developer.log(
            'FirestoreService: Updating participants to: $participantUids');

        // Validate all participants are valid UIDs
        for (final participant in participantUids) {
          if (participant.isEmpty) {
            throw Exception('Invalid participant UID: empty string');
          }
        }
      }

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      developer.log(
          'FirestoreService: Updating shared plan $planId with fields: ${updateData.keys.toList()}');

      await _db.collection('sharedPlans').doc(planId).update(updateData);

      developer.log('FirestoreService: Shared plan updated as owner: $planId');
    } catch (e) {
      developer
          .log('FirestoreService: Error updating shared plan as owner: $e');
      rethrow;
    }
  }

  /// Update shared plan as participant (limited fields)
  static Future<void> updateSharedPlanAsParticipant(
      String planId, Map<String, dynamic> updateData) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      // Get current plan to validate participation
      final doc = await _db.collection('sharedPlans').doc(planId).get();
      if (!doc.exists) throw Exception('Plan not found');

      final currentData = doc.data()!;
      final participantUids = List<String>.from(currentData['participantUids']);

      if (!participantUids.contains(userId)) {
        throw Exception('Only plan participants can perform this update');
      }

      // Validate restricted fields for participants
      final restrictedFields = [
        'participantUids',
        'ownerUid',
        'createdBy',
        'createdAt',
        'status'
      ];
      for (final field in restrictedFields) {
        if (updateData.containsKey(field)) {
          throw Exception('Participants cannot modify $field');
        }
      }

      // Validate immutable fields
      final immutableFields = ['createdBy', 'ownerUid', 'createdAt'];
      if (!validateImmutableFields(updateData, currentData, immutableFields)) {
        throw Exception('Cannot modify immutable fields');
      }

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _db.collection('sharedPlans').doc(planId).update(updateData);

      developer
          .log('FirestoreService: Shared plan updated as participant: $planId');
    } catch (e) {
      developer.log(
          'FirestoreService: Error updating shared plan as participant: $e');
      rethrow;
    }
  }

  /// Delete shared plan (owner only)
  static Future<void> deleteSharedPlan(String planId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      // Get current plan to validate ownership
      final doc = await _db.collection('sharedPlans').doc(planId).get();
      if (!doc.exists) throw Exception('Plan not found');

      final currentData = doc.data()!;
      if (currentData['ownerUid'] != userId ||
          currentData['createdBy'] != userId) {
        throw Exception('Only plan owner can delete the plan');
      }

      await _db.collection('sharedPlans').doc(planId).delete();

      developer.log('FirestoreService: Shared plan deleted: $planId');
    } catch (e) {
      developer.log('FirestoreService: Error deleting shared plan: $e');
      rethrow;
    }
  }

  // ===== NOTIFICATIONS (READ-ONLY FOR CLIENT) =====

  /// Get user's notifications
  static Stream<List<Map<String, dynamic>>> getMyNotifications() {
    final userId = currentUserId;
    if (userId == null) {
      return Stream.value([]);
    }

    return _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList());
  }

  /// Mark notification as read (only allowed update for clients)
  static Future<void> markNotificationAsRead(String notificationId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .doc(notificationId)
          .update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      developer.log(
          'FirestoreService: Notification marked as read: $notificationId');
    } catch (e) {
      developer.log('FirestoreService: Error marking notification as read: $e');
      rethrow;
    }
  }

  // ===== ACTIVITY FEED =====

  /// Add activity entry
  static Future<void> addActivity(String type, String description,
      {Map<String, dynamic>? metadata}) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      final activityData = {
        'userId': userId,
        'type': type,
        'description': description,
        'timestamp': FieldValue.serverTimestamp(),
        if (metadata != null) 'metadata': metadata,
      };

      await _db
          .collection('users')
          .doc(userId)
          .collection('activity')
          .add(activityData);

      developer.log('FirestoreService: Activity added: $type');
    } catch (e) {
      developer.log('FirestoreService: Error adding activity: $e');
      rethrow;
    }
  }

  // ===== CACHED DESTINATIONS (READ-ONLY) =====

  /// Get cached destination (public read)
  static Future<Map<String, dynamic>?> getCachedDestination(
      String destinationId) async {
    try {
      final doc =
          await _db.collection('cached_destinations').doc(destinationId).get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      developer.log('FirestoreService: Error getting cached destination: $e');
      rethrow;
    }
  }

  /// Dispose resources
  static void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
  }

  /// Effective current user ID (handles stale auth state)
  static String? get effectiveCurrentUserId {
    final user = _currentUser;
    if (user == null) {
      developer.log('FirestoreService: No authenticated user (effective)');
      return null;
    }
    return user.uid;
  }

  // ===== FAVORITES =====

  /// Get my favorites
  static Future<List<Map<String, dynamic>>> getMyFavorites() async {
    final userId = currentUserId;
    if (userId == null) return <Map<String, dynamic>>[];

    try {
      final snapshot = await _db
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .get();
      return snapshot.docs
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
          .toList();
    } catch (e) {
      developer.log('FirestoreService: Error getting favorites: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// Add favorite
  static Future<void> addFavorite(Map<String, dynamic> data) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    final destinationId = data['destinationId'] as String? ?? '';
    if (destinationId.isEmpty) throw Exception('destinationId is required');

    try {
      final dataCopy = Map<String, dynamic>.from(data);
      dataCopy['updatedAt'] = FieldValue.serverTimestamp();
      await _db
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .doc(destinationId)
          .set(dataCopy);
      developer.log('FirestoreService: Added favorite $destinationId');
    } catch (e) {
      developer.log('FirestoreService: Error adding favorite: $e');
      rethrow;
    }
  }

  /// Remove favorite
  static Future<void> removeFavorite(String placeId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('User not authenticated');

    try {
      await _db
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .doc(placeId)
          .delete();
      developer.log('FirestoreService: Removed favorite $placeId');
    } catch (e) {
      developer.log('FirestoreService: Error removing favorite: $e');
      rethrow;
    }
  }
}

class _AccountCleanupBatch {
  final FirebaseFirestore _db;
  WriteBatch _batch;
  int _pendingCount = 0;
  int _committedCount = 0;

  _AccountCleanupBatch(this._db) : _batch = _db.batch();

  Future<void> delete(DocumentReference<Map<String, dynamic>> ref) async {
    _batch.delete(ref);
    _pendingCount++;
    if (_pendingCount >= FirestoreService._accountCleanupBatchLimit) {
      await _commitPending();
    }
  }

  Future<int> commit() async {
    await _commitPending();
    return _committedCount;
  }

  Future<void> _commitPending() async {
    if (_pendingCount == 0) return;
    final count = _pendingCount;
    await _batch.commit();
    _committedCount += count;
    _batch = _db.batch();
    _pendingCount = 0;
  }
}
