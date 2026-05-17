import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:halaph/services/firebase_app_service.dart';
import 'package:halaph/utils/app_log.dart';

class RemoteSyncService {
  RemoteSyncService._internal();
  static final RemoteSyncService instance = RemoteSyncService._internal();

  static const Duration _timeout = Duration(seconds: 5);

  bool get isConfigured => FirebaseAppService.isInitialized;

  Future<Map<String, dynamic>?> loadNamespace(String namespace) async {
    try {
      final doc = await _firebaseDoc(namespace);
      if (doc == null) return null;
      final snapshot = await doc.get().timeout(_timeout);
      if (!snapshot.exists) return null;
      final data = Map<String, dynamic>.from(snapshot.data() ?? {});
      data.remove('_updatedAt');
      return data;
    } catch (error) {
      AppLog.throttledInfo(
        'firebase-sync-load-$namespace',
        'Firebase sync load failed for $namespace; showing saved data if available.',
      );
      return null;
    }
  }

  Future<bool> saveNamespace(
    String namespace,
    Map<String, dynamic> payload,
  ) async {
    try {
      final data = Map<String, dynamic>.from(payload);
      data['_updatedAt'] = FieldValue.serverTimestamp();
      final doc = await _firebaseDoc(namespace);
      if (doc == null) return false;
      await doc.set(data, SetOptions(merge: true)).timeout(_timeout);
      return true;
    } catch (error) {
      AppLog.error('Firebase sync save failed for $namespace: $error');
      return false;
    }
  }

  Future<bool> deleteNamespace(String namespace) async {
    try {
      final doc = await _firebaseDoc(namespace);
      if (doc == null) return false;
      await doc.delete().timeout(_timeout);
      return true;
    } catch (error) {
      AppLog.error('Firebase sync delete failed for $namespace: $error');
      return false;
    }
  }

  Future<DocumentReference<Map<String, dynamic>>?> _firebaseDoc(
    String namespace,
  ) async {
    final user = await _firebaseUser();
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('sync')
        .doc(namespace);
  }

  Future<firebase_auth.User?> _firebaseUser() async {
    if (!await FirebaseAppService.initialize()) return null;
    return firebase_auth.FirebaseAuth.instance.currentUser;
  }
}
