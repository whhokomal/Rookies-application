import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available app-level theme choices exposed to the user (Profile ->
/// Theme Appearance).
enum AppThemeMode { light, dark, system }

/// Single source of truth for the user's chosen theme appearance.
/// Persists the choice across app restarts and drives both
/// `MaterialApp.themeMode` (in main.dart) and every `AppColors.*` value
/// below, so the whole app's constants stay in sync with the selection.
class ThemeService extends ChangeNotifier with WidgetsBindingObserver {
  static final ThemeService instance = ThemeService._();
  ThemeService._();

  static const _prefsKey = 'theme_mode';

  @override
  void didChangePlatformBrightness() {
    // Only matters when the user picked "System" — repaint so AppColors
    // picks up the OS's new brightness immediately, without needing a
    // restart or navigation.
    if (_mode == AppThemeMode.system) notifyListeners();
  }

  AppThemeMode _mode = AppThemeMode.system;
  AppThemeMode get mode => _mode;

  /// Resolves 'system' against the device's current platform brightness.
  bool get isDark {
    if (_mode == AppThemeMode.dark) return true;
    if (_mode == AppThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  ThemeMode get themeMode {
    switch (_mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  String get label {
    switch (_mode) {
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.system:
        return 'System';
    }
  }

  /// Call once during app startup (e.g. in `main()`) before `runApp`.
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    _mode = AppThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => AppThemeMode.system,
    );
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}
