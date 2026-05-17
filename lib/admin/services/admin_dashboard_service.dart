import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AdminDashboardMetric {
  final String value;
  final String subtitle;
  final bool restricted;

  const AdminDashboardMetric({
    required this.value,
    required this.subtitle,
    this.restricted = false,
  });
}

class AdminDashboardStats {
  final DateTime loadedAt;
  final Map<String, AdminDashboardMetric> metrics;

  const AdminDashboardStats({
    required this.loadedAt,
    required this.metrics,
  });

  AdminDashboardMetric metric(String key) {
    return metrics[key] ??
        const AdminDashboardMetric(
          value: '—',
          subtitle: 'No data available.',
        );
  }
}

class AdminDashboardService {
  final FirebaseFirestore _firestore;

  AdminDashboardService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<AdminDashboardStats> loadStats() async {
    final results = await Future.wait<MapEntry<String, AdminDashboardMetric>>([
      _countUserbase(),
      _countCollection(
        key: 'users',
        collectionPath: 'users',
        successSubtitle: 'Registered user profile documents only.',
      ),
      _countCollection(
        key: 'sharedPlans',
        collectionPath: 'sharedPlans',
        successSubtitle: 'Collaborative and saved trip plans.',
      ),
      _countCollection(
        key: 'publicProfiles',
        collectionPath: 'publicProfiles',
        successSubtitle: 'Searchable public friend profiles.',
      ),
      _countCollection(
        key: 'friendCodes',
        collectionPath: 'friendCodes',
        successSubtitle: 'Generated friend invite codes.',
      ),
      _countCollection(
        key: 'locations',
        collectionPath: 'admin_locations',
        successSubtitle: 'Admin-managed location records.',
      ),
      _countCollection(
        key: 'featuredPlaces',
        collectionPath: 'admin_featured_places',
        successSubtitle: 'Admin-managed featured destination records.',
      ),
      _countCollection(
        key: 'terminalRoutes',
        collectionPath: 'admin_terminal_routes',
        successSubtitle: 'Verified terminal route references.',
      ),
      _countCollection(
        key: 'routeReports',
        collectionPath: 'route_correction_reports',
        successSubtitle: 'Submitted terminal route correction reports.',
      ),
      _countCollection(
        key: 'ads',
        collectionPath: 'admin_ads',
        successSubtitle: 'Admin-managed advertisement records.',
      ),
      _countCollection(
        key: 'adminUsers',
        collectionPath: 'admin_users',
        successSubtitle: 'Registered admin accounts.',
      ),
      _countQuery(
        key: 'activeAdmins',
        query: _firestore
            .collection('admin_users')
            .where('isActive', isEqualTo: true),
        successSubtitle: 'Admin accounts currently enabled.',
      ),
    ]);

    final metrics = Map<String, AdminDashboardMetric>.fromEntries(results);

    return AdminDashboardStats(
      loadedAt: DateTime.now(),
      metrics: metrics,
    );
  }

  Future<MapEntry<String, AdminDashboardMetric>> _countUserbase() async {
    String clean(String value) => value.trim();
    String cleanEmail(String value) => value.trim().toLowerCase();

    final appUids = <String>{};
    final appEmails = <String>{};

    void addUidField(Map<String, dynamic> data) {
      for (final key in ['uid', 'userId', 'ownerUid']) {
        final value = data[key];
        if (value is String && clean(value).isNotEmpty) {
          appUids.add(clean(value));
        }
      }

      final email = data['email'];
      if (email is String && cleanEmail(email).isNotEmpty) {
        appEmails.add(cleanEmail(email));
      }
    }

    try {
      final adminUids = <String>{};
      final adminEmails = <String>{};

      final adminUsersSnapshot =
          await _firestore.collection('admin_users').get().timeout(
                const Duration(seconds: 5),
              );

      for (final doc in adminUsersSnapshot.docs) {
        final data = doc.data();

        final docId = clean(doc.id);
        if (docId.isNotEmpty) {
          adminUids.add(docId);
        }

        for (final key in ['uid', 'userId', 'ownerUid']) {
          final value = data[key];
          if (value is String && clean(value).isNotEmpty) {
            adminUids.add(clean(value));
          }
        }

        final email = data['email'];
        if (email is String && cleanEmail(email).isNotEmpty) {
          adminEmails.add(cleanEmail(email));
        }
      }

      final usersSnapshot = await _firestore.collection('users').get().timeout(
            const Duration(seconds: 5),
          );
      for (final doc in usersSnapshot.docs) {
        final docId = clean(doc.id);
        if (docId.isNotEmpty) {
          appUids.add(docId);
        }
        addUidField(doc.data());
      }

      final publicProfilesSnapshot =
          await _firestore.collection('publicProfiles').get().timeout(
                const Duration(seconds: 5),
              );
      for (final doc in publicProfilesSnapshot.docs) {
        addUidField(doc.data());
      }

      final friendCodesSnapshot =
          await _firestore.collection('friendCodes').get().timeout(
                const Duration(seconds: 5),
              );
      for (final doc in friendCodesSnapshot.docs) {
        addUidField(doc.data());
      }

      final beforeUidCount = appUids.length;
      final beforeEmailCount = appEmails.length;

      appUids.removeAll(adminUids);
      appEmails.removeAll(adminEmails);

      final count = appUids.isNotEmpty ? appUids.length : appEmails.length;

      debugPrint(
        'Admin dashboard userbase count: $count '
        'from $beforeUidCount uid candidate(s), '
        '$beforeEmailCount email candidate(s), '
        'excluding ${adminUids.length} admin uid(s) and '
        '${adminEmails.length} admin email(s).',
      );

      return MapEntry(
        'userbase',
        AdminDashboardMetric(
          value: count.toString(),
          subtitle:
              'Unique non-admin app users from users, public profiles, and friend codes.',
        ),
      );
    } on FirebaseException catch (error) {
      debugPrint(
        'Admin dashboard userbase failed: ${error.code} ${error.message}',
      );

      if (error.code == 'permission-denied') {
        return const MapEntry(
          'userbase',
          AdminDashboardMetric(
            value: 'Restricted',
            subtitle: 'Firestore rules block userbase reads.',
            restricted: true,
          ),
        );
      }

      return MapEntry(
        'userbase',
        AdminDashboardMetric(
          value: '—',
          subtitle: 'Could not load userbase.',
        ),
      );
    } on TimeoutException {
      debugPrint('Admin dashboard userbase failed: timed out');

      return const MapEntry(
        'userbase',
        AdminDashboardMetric(
          value: 'Timed out',
          subtitle: 'Firestore did not respond quickly enough.',
        ),
      );
    } catch (error) {
      debugPrint('Admin dashboard userbase failed: $error');

      return const MapEntry(
        'userbase',
        AdminDashboardMetric(
          value: '—',
          subtitle: 'Could not load userbase.',
        ),
      );
    }
  }

  Future<MapEntry<String, AdminDashboardMetric>> _countCollection({
    required String key,
    required String collectionPath,
    required String successSubtitle,
  }) {
    return _countQuery(
      key: key,
      query: _firestore.collection(collectionPath),
      successSubtitle: successSubtitle,
    );
  }

  Future<MapEntry<String, AdminDashboardMetric>> _countQuery({
    required String key,
    required Query<Map<String, dynamic>> query,
    required String successSubtitle,
  }) async {
    try {
      final snapshot = await query.count().get().timeout(
            const Duration(seconds: 5),
          );
      final count = snapshot.count;

      debugPrint('Admin dashboard $key count: ${count ?? 'unknown'}');

      return MapEntry(
        key,
        AdminDashboardMetric(
          value: count == null ? '—' : count.toString(),
          subtitle: successSubtitle,
        ),
      );
    } on FirebaseException catch (error) {
      debugPrint(
        'Admin dashboard stats failed: $key ${error.code} ${error.message}',
      );

      if (error.code == 'permission-denied') {
        return MapEntry(
          key,
          const AdminDashboardMetric(
            value: 'Restricted',
            subtitle: 'Firestore rules do not allow this admin read yet.',
            restricted: true,
          ),
        );
      }

      return MapEntry(
        key,
        AdminDashboardMetric(
          value: '—',
          subtitle: 'Could not load this metric: ${error.code}.',
        ),
      );
    } on TimeoutException {
      debugPrint('Admin dashboard stats failed: $key timed out');

      return MapEntry(
        key,
        const AdminDashboardMetric(
          value: 'Timed out',
          subtitle: 'Firestore did not respond quickly enough.',
        ),
      );
    } catch (error) {
      debugPrint('Admin dashboard stats failed: $key $error');

      return MapEntry(
        key,
        const AdminDashboardMetric(
          value: '—',
          subtitle: 'Could not load this metric.',
        ),
      );
    }
  }
}
