import 'package:flutter/foundation.dart';

class PlaceDisplayNameUtils {
  const PlaceDisplayNameUtils._();

  static String resolveDisplayName(
    Map<String, dynamic> data, {
    bool cleanRawName = true,
  }) {
    for (final field in const [
      'displayNameOverride',
      'adminDisplayName',
      'displayName',
    ]) {
      final value = _stringValue(data[field]);
      if (value.isNotEmpty) {
        if (field == 'displayNameOverride') {
          debugPrint('Featured place display name override used: $value');
        }
        return value;
      }
    }

    final rawName = originalName(data);
    if (cleanRawName) {
      final cleaned = cleanGoogleDisplayName(rawName);
      if (cleaned.isNotEmpty && cleaned != rawName) {
        return cleaned;
      }
      if (cleaned.isNotEmpty) return cleaned;
    }

    return rawName;
  }

  static String originalName(Map<String, dynamic> data) {
    for (final field in const [
      'originalName',
      'googleName',
      'rawName',
      'name',
      'title',
    ]) {
      final value = _stringValue(data[field]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String cleanGoogleDisplayName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    final normalized = _normalize(trimmed);
    if (_looksLikeSmNorth(normalized)) {
      if (normalized.startsWith('2f ') ||
          normalized.startsWith('2nd floor ') ||
          normalized.startsWith('second floor ')) {
        return 'SM City North EDSA';
      }
      if (normalized.startsWith('the block sm city north edsa')) {
        return 'The Block SM City North EDSA';
      }
      if (normalized.contains('sm city north edsa') ||
          normalized.contains('sm north edsa')) {
        final firstPart = _firstCommaPart(trimmed);
        if (firstPart.toLowerCase().startsWith('the block')) {
          return _titleCaseKnownAcronyms(firstPart);
        }
        return 'SM City North EDSA';
      }
    }

    final firstPart = _firstCommaPart(trimmed);
    if (firstPart.isNotEmpty) return _titleCaseKnownAcronyms(firstPart);
    return _titleCaseKnownAcronyms(trimmed);
  }

  static bool isAdminEditedOverride({
    required String value,
    required String prefilledValue,
  }) {
    return value.trim().isNotEmpty && value.trim() != prefilledValue.trim();
  }

  static String _firstCommaPart(String value) {
    return value
        .split(',')
        .map((part) => part.trim())
        .firstWhere((part) => part.isNotEmpty, orElse: () => '');
  }

  static bool _looksLikeSmNorth(String normalized) {
    return normalized.contains('sm city north edsa') ||
        normalized.contains('sm north edsa') ||
        normalized.contains('north avenue corner edsa');
  }

  static String _titleCaseKnownAcronyms(String value) {
    final words = value.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    return words.map((word) {
      final lower = word.toLowerCase();
      return switch (lower) {
        'sm' => 'SM',
        'edsa' => 'EDSA',
        'qc' => 'QC',
        '2f' => '2F',
        _ => lower[0].toUpperCase() + lower.substring(1),
      };
    }).join(' ');
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .join(' ');
  }

  static String _stringValue(Object? value) {
    if (value is! String) return '';
    return value.trim();
  }
}
