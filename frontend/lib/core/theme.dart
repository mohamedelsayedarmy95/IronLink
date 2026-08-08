import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class IronColors {
  // Dark theme colors
  static const Color darkPrimary = Color(0xFF0F172A); // Navy bg
  static const Color darkSecondary = Color(0xFF1E293B);
  static const Color darkTertiary = Color(0xFF334155);
  static const Color darkAccent = Color(0xFFD4AF37); // Metallic gold
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFFE2E8F0);
  static const Color darkTextTertiary = Color(0xFFCBD5E1);

  // Light theme colors
  static const Color lightPrimary = Color(0xFFF8FAFC); // Almost white
  static const Color lightSecondary = Color(0xFFF1F5F9);
  static const Color lightTertiary = Color(0xFFE2E8F0);
  static const Color lightAccent = Color(0xFFD4AF37); // Metallic gold
  static const Color lightTextPrimary = Color(0xFF0F172A); // Navy text
  static const Color lightTextSecondary = Color(0xFF1E293B);
  static const Color lightTextTertiary = Color(0xFF334155);

  // Common colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFFAB005);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Legacy fixed dark/gold palette aliases, used throughout the existing
  // screens which predate the light/dark theme split above.
  static const Color navyDeep = darkPrimary;
  static const Color navySurface = darkSecondary;
  static const Color navyBorder = darkTertiary;
  static const Color gold = darkAccent;
  static const Color goldBright = Color(0xFFE9CB6B);
  static const Color goldDim = Color(0xFF8A7638);
  static const Color textHi = darkTextPrimary;
  static const Color textLo = darkTextTertiary;
  static const Color errorRed = error;
  static const Color white = Colors.white;
}

class IronTypography {
  // Font families
  static const String fontPrimary = 'Inter'; // Clean, modern sans-serif
  static const String fontSecondary = 'Tajawal'; // For headings/names

  // Text styles
  static TextStyle displayLarge({Color? color}) => GoogleFonts.tajawal(
        fontSize: 57,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle displayMedium({Color? color}) => GoogleFonts.tajawal(
        fontSize: 45,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: -0.5,
        height: 1.3,
      );

  static TextStyle displaySmall({Color? color}) => GoogleFonts.tajawal(
        fontSize: 36,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: -0.5,
        height: 1.4,
      );

  static TextStyle headlineLarge({Color? color}) => GoogleFonts.inter(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: 0,
        height: 1.2,
      );

  static TextStyle headlineMedium({Color? color}) => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: 0,
        height: 1.3,
      );

  static TextStyle headlineSmall({Color? color}) => GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: 0,
        height: 1.4,
      );

  static TextStyle titleLarge({Color? color}) => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
        height: 1.5,
      );

  static TextStyle titleMedium({Color? color}) => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
        height: 1.5,
      );

  static TextStyle titleSmall({Color? color}) => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
        height: 1.5,
      );

  static TextStyle bodyLarge({Color? color}) => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: color,
        letterSpacing: 0.5,
        height: 1.5,
      );

  static TextStyle bodyMedium({Color? color}) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: color,
        letterSpacing: 0.25,
        height: 1.4,
      );

  static TextStyle bodySmall({Color? color}) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: color,
        letterSpacing: 0.4,
        height: 1.3,
      );

  static TextStyle labelLarge({Color? color}) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.1,
        height: 1.4,
      );

  static TextStyle labelMedium({Color? color}) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.5,
        height: 1.3,
      );

  static TextStyle labelSmall({Color? color}) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: color,
        letterSpacing: 0.5,
        height: 1.2,
      );
}

class IronSpacing {
  // Base 4px spacing system
  static const double xs = 4.0; // Extra small
  static const double sm = 8.0; // Small
  static const double md = 12.0; // Medium
  static const double lg = 16.0; // Large
  static const double xl = 24.0; // Extra large
  static const double xxl = 32.0; // Double extra large
}

ThemeData ironLinkLightTheme() {
  return ThemeData(
    // Color scheme
    colorScheme: ColorScheme.light(
      primary: IronColors.lightPrimary,
      secondary: IronColors.lightSecondary,
      tertiary: IronColors.lightTertiary,
      background: IronColors.lightPrimary,
      surface: IronColors.lightSecondary,
      onPrimary: IronColors.lightTextPrimary,
      onSecondary: IronColors.lightTextSecondary,
      onTertiary: IronColors.lightTextTertiary,
      onBackground: IronColors.lightTextPrimary,
      onSurface: IronColors.lightTextSecondary,
    ),
    // Typography
    fontFamily: IronTypography.fontPrimary,
    textTheme: TextTheme(
      displayLarge: IronTypography.displayLarge(color: IronColors.lightTextPrimary),
      displayMedium: IronTypography.displayMedium(color: IronColors.lightTextPrimary),
      displaySmall: IronTypography.displaySmall(color: IronColors.lightTextPrimary),
      headlineLarge: IronTypography.headlineLarge(color: IronColors.lightTextPrimary),
      headlineMedium: IronTypography.headlineMedium(color: IronColors.lightTextPrimary),
      headlineSmall: IronTypography.headlineSmall(color: IronColors.lightTextPrimary),
      titleLarge: IronTypography.titleLarge(color: IronColors.lightTextPrimary),
      titleMedium: IronTypography.titleMedium(color: IronColors.lightTextPrimary),
      titleSmall: IronTypography.titleSmall(color: IronColors.lightTextPrimary),
      bodyLarge: IronTypography.bodyLarge(color: IronColors.lightTextPrimary),
      bodyMedium: IronTypography.bodyMedium(color: IronColors.lightTextPrimary),
      bodySmall: IronTypography.bodySmall(color: IronColors.lightTextPrimary),
      labelLarge: IronTypography.labelLarge(color: IronColors.lightTextPrimary),
      labelMedium: IronTypography.labelMedium(color: IronColors.lightTextPrimary),
      labelSmall: IronTypography.labelSmall(color: IronColors.lightTextPrimary),
    ),
    // Component themes
    cardTheme: CardThemeData(
      color: IronColors.lightSecondary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: IronColors.lightTertiary.withOpacity(0.3),
          width: 1,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: IronColors.lightAccent,
        foregroundColor: IronColors.lightTextPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: IronColors.lightTextPrimary,
        side: BorderSide(
          color: IronColors.lightAccent,
          width: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: IronColors.lightAccent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: IronColors.lightSecondary.withOpacity(0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: IronColors.lightAccent,
          width: 2,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: IronColors.lightTertiary,
          width: 1,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: IronTypography.bodyMedium(
        color: IronColors.lightTextTertiary,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: IronColors.lightTertiary.withOpacity(0.2),
      thickness: 1,
      space: IronSpacing.md,
    ),
    // Glassmorphism effect (applied via GlassCard widget)
  );
}

ThemeData ironLinkDarkTheme() {
  return ThemeData(
    // Color scheme
    colorScheme: ColorScheme.dark(
      primary: IronColors.darkPrimary,
      secondary: IronColors.darkSecondary,
      tertiary: IronColors.darkTertiary,
      background: IronColors.darkPrimary,
      surface: IronColors.darkSecondary,
      onPrimary: IronColors.darkTextPrimary,
      onSecondary: IronColors.darkTextSecondary,
      onTertiary: IronColors.darkTextTertiary,
      onBackground: IronColors.darkTextPrimary,
      onSurface: IronColors.darkTextSecondary,
    ),
    // Typography
    fontFamily: IronTypography.fontPrimary,
    textTheme: TextTheme(
      displayLarge: IronTypography.displayLarge(color: IronColors.darkTextPrimary),
      displayMedium: IronTypography.displayMedium(color: IronColors.darkTextPrimary),
      displaySmall: IronTypography.displaySmall(color: IronColors.darkTextPrimary),
      headlineLarge: IronTypography.headlineLarge(color: IronColors.darkTextPrimary),
      headlineMedium: IronTypography.headlineMedium(color: IronColors.darkTextPrimary),
      headlineSmall: IronTypography.headlineSmall(color: IronColors.darkTextPrimary),
      titleLarge: IronTypography.titleLarge(color: IronColors.darkTextPrimary),
      titleMedium: IronTypography.titleMedium(color: IronColors.darkTextPrimary),
      titleSmall: IronTypography.titleSmall(color: IronColors.darkTextPrimary),
      bodyLarge: IronTypography.bodyLarge(color: IronColors.darkTextPrimary),
      bodyMedium: IronTypography.bodyMedium(color: IronColors.darkTextPrimary),
      bodySmall: IronTypography.bodySmall(color: IronColors.darkTextPrimary),
      labelLarge: IronTypography.labelLarge(color: IronColors.darkTextPrimary),
      labelMedium: IronTypography.labelMedium(color: IronColors.darkTextPrimary),
      labelSmall: IronTypography.labelSmall(color: IronColors.darkTextPrimary),
    ),
    // Component themes
    cardTheme: CardThemeData(
      color: IronColors.darkSecondary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: IronColors.darkTertiary.withOpacity(0.3),
          width: 1,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: IronColors.darkAccent,
        foregroundColor: IronColors.darkTextPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: IronColors.darkTextPrimary,
        side: BorderSide(
          color: IronColors.darkAccent,
          width: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: IronColors.darkAccent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: IronColors.darkSecondary.withOpacity(0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: IronColors.darkAccent,
          width: 2,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: IronColors.darkTertiary,
          width: 1,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: IronTypography.bodyMedium(
        color: IronColors.darkTextTertiary,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: IronColors.darkTertiary.withOpacity(0.2),
      thickness: 1,
      space: IronSpacing.md,
    ),
    // Glassmorphism effect (applied via GlassCard widget)
  );
}