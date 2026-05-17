import 'package:flutter/foundation.dart';

class AppLog {
  AppLog._();

  static final Map<String, DateTime> _lastInfoAt = {};

  static void info(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  static void throttledInfo(
    String key,
    String message, {
    Duration interval = const Duration(minutes: 1),
  }) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    final last = _lastInfoAt[key];
    if (last != null && now.difference(last) < interval) return;
    _lastInfoAt[key] = now;
    debugPrint(message);
  }

  static void error(String message) {
    debugPrint(message);
  }
}
