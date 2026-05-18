import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BrandColorMode {
  burgundy,
  light,
}

class ThemeModeService {
  static const String _preferenceKey = 'hala_theme_mode';
  static const String _brandPreferenceKey = 'hala_brand_color_mode';

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.light);
  static final ValueNotifier<BrandColorMode> brandColorMode =
      ValueNotifier<BrandColorMode>(BrandColorMode.burgundy);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedValue = prefs.getString(_preferenceKey);
    themeMode.value = _parseThemeMode(savedValue);
    if (savedValue != themeMode.value.name) {
      await prefs.setString(_preferenceKey, themeMode.value.name);
    }

    final savedBrandValue = prefs.getString(_brandPreferenceKey);
    brandColorMode.value = _parseBrandColorMode(savedBrandValue);
    if (savedBrandValue != brandColorMode.value.name) {
      await prefs.setString(_brandPreferenceKey, brandColorMode.value.name);
    }
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, mode.name);
  }

  static Future<void> setBrandColorMode(BrandColorMode mode) async {
    brandColorMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brandPreferenceKey, mode.name);
  }

  static String labelFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Light';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Light';
    }
  }

  static String descriptionFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Use the clean original light appearance.';
      case ThemeMode.light:
        return 'Use the clean original light appearance.';
      case ThemeMode.dark:
        return 'Use the clean original light appearance.';
    }
  }

  static String labelForBrand(BrandColorMode mode) {
    switch (mode) {
      case BrandColorMode.burgundy:
        return 'Burgundy';
      case BrandColorMode.light:
        return 'Light';
    }
  }

  static String descriptionForBrand(BrandColorMode mode) {
    switch (mode) {
      case BrandColorMode.burgundy:
        return 'Premium HalaPH identity and recommended default.';
      case BrandColorMode.light:
        return 'A cleaner light surface with the same Burgundy identity.';
    }
  }

  static ThemeMode _parseThemeMode(String? _) {
    return ThemeMode.light;
  }

  static BrandColorMode _parseBrandColorMode(String? value) {
    switch (value) {
      case 'burgundy':
        return BrandColorMode.burgundy;
      case 'light':
      case 'navy':
        return BrandColorMode.light;
      case 'system':
      case null:
        return BrandColorMode.burgundy;
      default:
        return BrandColorMode.burgundy;
    }
  }
}
