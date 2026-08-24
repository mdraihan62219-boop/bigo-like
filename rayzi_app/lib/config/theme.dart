import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Brand palette + app-wide light/dark themes.
///
/// Day/Night/System appearance is handled by [AppThemeController] at the
/// MaterialApp root; both themes below are complete ColorSchemes so every
/// widget reads readable contrast in either mode.
///
/// NOTE: this is the *appearance* mode, distinct from the purchasable
/// cosmetic "Theme" shop items (decorative profile skins) which are scoped
/// to profiles via equipped_theme_id and never touch MaterialApp.
class AppTheme {
  static const Color primaryColor = Color(0xFF6C63FF);
  static const Color secondaryColor = Color(0xFF00BFA6);
  static const Color accentColor = Color(0xFFFF6584);
  static const Color darkBackground = Color(0xFF1A1A2E);
  static const Color cardBackground = Color(0xFF16213E);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color goldColor = Color(0xFFFFD700);

  // Light-mode counterparts.
  static const Color lightBackground = Color(0xFFF6F7FB);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightTextPrimary = Color(0xFF1B1B2F);
  static const Color lightTextSecondary = Color(0xFF5F6470);

  /// Dark navy theme (the app's original look).
  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        primaryColor: primaryColor,
        scaffoldBackgroundColor: darkBackground,
        colorScheme: const ColorScheme.dark(
          primary: primaryColor,
          onPrimary: Colors.white, // was falling back to #381E72 → invisible button labels
          secondary: secondaryColor,
          onSecondary: Colors.black,
          surface: cardBackground,
          onSurface: textPrimary,
          error: Color(0xFFCF6679),
          onError: Colors.black,
          outline: textSecondary,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: darkBackground,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
              fontSize: 18.sp, fontWeight: FontWeight.w600, color: textPrimary),
        ),
        cardTheme: CardTheme(
          color: cardBackground,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: darkBackground,
          selectedItemColor: primaryColor,
          unselectedItemColor: textSecondary,
          type: BottomNavigationBarType.fixed,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
        dividerTheme: DividerThemeData(color: Colors.grey.shade700),
      );

  /// Real light theme (not an inversion placeholder).
  static ThemeData get lightTheme => ThemeData(
        brightness: Brightness.light,
        primaryColor: primaryColor,
        scaffoldBackgroundColor: lightBackground,
        colorScheme: const ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white,
          secondary: secondaryColor,
          onSecondary: Colors.white,
          surface: lightCard,
          onSurface: lightTextPrimary,
          error: Color(0xFFB3261E),
          onError: Colors.white,
          outline: lightTextSecondary,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: lightCard,
          foregroundColor: lightTextPrimary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: lightTextPrimary),
        ),
        cardTheme: CardTheme(
          color: lightCard,
          elevation: 0.5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: lightCard,
          selectedItemColor: primaryColor,
          unselectedItemColor: lightTextSecondary,
          type: BottomNavigationBarType.fixed,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
        dividerTheme: DividerThemeData(color: Colors.grey.shade300),
      );
}

/// Persists the user's appearance choice locally (survives restarts, no
/// network call) and exposes it as a listenable for MaterialApp.
class AppThemeController {
  AppThemeController._();
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);
  static const String _prefKey = 'app_theme_mode';

  /// Call once during bootstrap before runApp.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode.value = _decode(prefs.getString(_prefKey));
    } catch (_) {
      mode.value = ThemeMode.system;
    }
  }

  static Future<void> setMode(ThemeMode next) async {
    mode.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _encode(next));
    } catch (_) {
      // Persistence failure must not break the in-session switch.
    }
  }

  static ThemeMode _decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
