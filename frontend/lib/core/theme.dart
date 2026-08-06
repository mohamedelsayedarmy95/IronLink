import 'package:flutter/material.dart';

/// IronLink design tokens — Deep Navy × Military Gold.
/// Single source of truth: no hardcoded colors anywhere else in the app.
abstract class MilColors {
  static const navyDeep = Color(0xFF0A1128);   // primary background
  static const navySurface = Color(0xFF14213D); // cards / fields
  static const navyBorder = Color(0xFF1F2F52);

  static const gold = Color(0xFFD4AF37);        // brand accent
  static const goldBright = Color(0xFFF0C75E);  // highlights / focus
  static const goldDim = Color(0x66D4AF37);     // disabled / hints

  static const textHi = Color(0xFFF5F1E8);      // warm off-white
  static const textLo = Color(0xFF8B93A7);

  static const errorRed = Color(0xFF8B1E24);    // military red — snackbars
  static const success = Color(0xFF2E7D32);
}

ThemeData milTheme() {
  const scheme = ColorScheme.dark(
    primary: MilColors.gold,
    secondary: MilColors.goldBright,
    surface: MilColors.navySurface,
    error: MilColors.errorRed,
    onPrimary: MilColors.navyDeep,
    onSurface: MilColors.textHi,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  return base.copyWith(
    scaffoldBackgroundColor: MilColors.navyDeep,
    textTheme: base.textTheme.apply(
      bodyColor: MilColors.textHi,
      displayColor: MilColors.textHi,
      fontFamily: 'Cairo',
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MilColors.navySurface,
      hintStyle: const TextStyle(color: MilColors.textLo),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: MilColors.navyBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: MilColors.gold, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: MilColors.errorRed),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: MilColors.gold,
        foregroundColor: MilColors.navyDeep,
        disabledBackgroundColor: MilColors.goldDim,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: MilColors.errorRed,
      contentTextStyle: TextStyle(color: MilColors.textHi, fontSize: 15),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
