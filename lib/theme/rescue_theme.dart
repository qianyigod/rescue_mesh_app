import 'package:flutter/material.dart';

class RescuePalette {
  static const background = Color(0xFFF3F6F8);
  static const panel = Color(0xFFFFFFFF);
  static const panelRaised = Color(0xFFEAF1F4);
  static const border = Color(0xFFC8D4DB);
  static const critical = Color(0xFFD84444);
  static const criticalSoft = Color(0xFFF8DCDD);
  static const accent = Color(0xFF2C6B88);
  static const accentSoft = Color(0xFFDCEBF2);
  static const success = Color(0xFF1E8A5C);
  static const successSoft = Color(0xFFD8EFE5);
  static const warning = Color(0xFFF29B38);
  static const textPrimary = Color(0xFF14212B);
  static const textMuted = Color(0xFF617684);
}

ThemeData buildRescueTheme() {
  const scheme = ColorScheme.light(
    primary: RescuePalette.critical,
    secondary: RescuePalette.accent,
    surface: RescuePalette.panel,
    error: RescuePalette.critical,
  );

  final base = ThemeData.light(useMaterial3: true);

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: RescuePalette.background,
    canvasColor: RescuePalette.background,
    cardTheme: CardThemeData(
      color: RescuePalette.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: RescuePalette.border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: RescuePalette.panel,
      foregroundColor: RescuePalette.textPrimary,
      centerTitle: false,
      elevation: 0,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: RescuePalette.panel,
      selectedItemColor: RescuePalette.critical,
      unselectedItemColor: RescuePalette.textMuted,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
    dividerColor: RescuePalette.border,
    textTheme: base.textTheme.apply(
      bodyColor: RescuePalette.textPrimary,
      displayColor: RescuePalette.textPrimary,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: RescuePalette.accent,
      textColor: RescuePalette.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RescuePalette.panel,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: RescuePalette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: RescuePalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: RescuePalette.accent, width: 1.4),
      ),
    ),
  );
}
