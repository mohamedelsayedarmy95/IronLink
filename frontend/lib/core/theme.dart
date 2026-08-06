import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// IronLink Design System
///
/// This file contains the core design tokens for the IronLink app:
/// - Colors (IronColors)
/// - Typography (IronTypography)
/// - Spacing (IronSpacing)
///
/// Additionally, it provides light and dark theme data.

class IronColors {
  // Dark Mode Palette
  static const Color darkBackground = Color(0xFF0A0A0A); // Almost black
  static const Color darkSurface = Color(0xFF1A1A1A);    // Slightly lighter
  static const Color darkGold = Color(0xFFF5D76E);       // Warm gold
  static const Color darkGoldDark = Color(0xFFD4AF37);   // Darker gold for gradients
  static const Color darkAccent = Color(0xFF4A90E2);     // Blue accent
  static const Color darkTextPrimary = Color(0xFFFFFFFF); // White
  static const Color darkTextSecondary = Color(0xFFB0B0B0); // Light gray
  static const Color darkTextDisabled = Color(0xFF606060); // Dark gray
  static const Color darkDivider = Color(0xFF303030);    // Divider lines
  static const Color darkError = Color(0xFFE74C3C);      // Red for errors
  static const Color darkSuccess = Color(0xFF2ECC71);    // Green for success
  static const Color darkWarning = Color(0xFFF1C40F);    // Yellow for warning

  // Light Mode Palette
  static const Color lightBackground = Color(0xFFFAFAFA); // Off-white
  static const Color lightSurface = Color(0xFFFFFFFF);    // White
  static const Color lightGold = Color(0xFFF5D76E);       // Warm gold
  static const Color lightGoldDark = Color(0xFFD4AF37);   // Darker gold for gradients
  static const Color lightAccent = Color(0xFF4A90E2);     // Blue accent
  static const Color lightTextPrimary = Color(0xFF0A0A0A); // Almost black
  static const Color lightTextSecondary = Color(0xFF505050); // Dark gray
  static const Color lightTextDisabled = Color(0xFF909090); // Medium gray
  static const Color lightDivider = Color(0xFFE0E0E0);    // Divider lines
  static const Color lightError = Color(0xFFE74C3C);      // Red for errors
  static const Color lightSuccess = Color(0xFF2ECC71);    // Green for success
  static const Color lightWarning = Color(0xFFF1C40F);    // Yellow for warning

  /// Returns the appropriate color for the current theme.
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkBackground
          : lightBackground;

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSurface
          : lightSurface;

  static Color gold(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkGold
          : lightGold;

  static Color goldDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkGoldDark
          : lightGoldDark;

  static Color accent(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkAccent
          : lightAccent;

  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkTextPrimary
          : lightTextPrimary;

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkTextSecondary
          : lightTextSecondary;

  static Color textDisabled(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkTextDisabled
          : lightTextDisabled;

  static Color divider(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkDivider
          : lightDivider;

  static Color error(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkError
          : lightError;

  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSuccess
          : lightSuccess;

  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkWarning
          : lightWarning;
}

class IronTypography {
  /// Define font families
  static const String fontEnglish = 'Inter';
  static const String fontArabic = 'Tajawal'; // or 'Cairo'

  /// Text styles for dark and light modes are handled by the ThemeData,
  /// but we can define base styles that are then adapted by the theme.
  /// We'll use GoogleFonts to create the text styles.

  /// Display / Headline
  static TextStyle headline1({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 96,
        fontWeight: FontWeight.w300,
        color: IronColors.textPrimary(context),
        height: 1.2,
      );

  static TextStyle headline2({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 60,
        fontWeight: FontWeight.w300,
        color: IronColors.textPrimary(context),
        height: 1.2,
      );

  static TextStyle headline3({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 48,
        fontWeight: FontWeight.w400,
        color: IronColors.textPrimary(context),
        height: 1.2,
      );

  /// Title styles
  static TextStyle titleLarge({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: IronColors.textPrimary(context),
      );

  static TextStyle titleMedium({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: IronColors.textPrimary(context),
      );

  static TextStyle titleSmall({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: IronColors.textPrimary(context),
      );

  /// Body styles
  static TextStyle bodyLarge({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: IronColors.textPrimary(context),
        height: 1.5,
      );

  static TextStyle bodyMedium({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: IronColors.textPrimary(context),
        height: 1.5,
      );

  static TextStyle bodySmall({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: IronColors.textPrimary(context),
        height: 1.5,
      );

  /// Caption / Label
  static TextStyle labelLarge({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: IronColors.textSecondary(context),
      );

  static TextStyle labelMedium({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: IronColors.textSecondary(context),
      );

  static TextStyle labelSmall({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: IronColors.textSecondary(context),
      );

  /// Button text
  static TextStyle buttonLarge({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: IronColors.textPrimary(context),
      );

  static TextStyle buttonMedium({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: IronColors.textPrimary(context),
      );

  static TextStyle buttonSmall({required BuildContext context}) =>
      GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: IronColors.textPrimary(context),
      );
}

class IronSpacing {
  /// Consistent spacing values (in pixels)
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;

  /// For use in padding and margins
  static EdgeInsets all(double size) => EdgeInsets.all(size);
  static EdgeInsets symmetric({double vertical = 0, double horizontal = 0}) =>
      EdgeInsets.symmetric(vertical: vertical, horizontal: horizontal);
  static EdgeInsets only({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) => EdgeInsets.only(left: left, top: top, right: right, bottom: bottom);
}

/// Returns the Light ThemeData for IronLink.
ThemeData ironLinkLightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: IronColors.lightBackground,
    colorScheme: ColorScheme.light(
      primary: IronColors.lightGold,
      secondary: IronColors.lightAccent,
      background: IronColors.lightBackground,
      surface: IronColors.lightSurface,
      error: IronColors.lightError,
    ),
    // We'll define the textTheme explicitly using the colors from the colorScheme
    textTheme: TextTheme(
      displayLarge: GoogleFonts.inter(
        fontSize: 96,
        fontWeight: FontWeight.w300,
        color: IronColors.lightTextPrimary,
        height: 1.2,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 60,
        fontWeight: FontWeight.w300,
        color: IronColors.lightTextPrimary,
        height: 1.2,
      ),
      displaySmall: GoogleFonts.inter(
        fontSize: 48,
        fontWeight: FontWeight.w400,
        color: IronColors.lightTextPrimary,
        height: 1.2,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: IronColors.lightTextPrimary,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: IronColors.lightTextPrimary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: IronColors.lightTextPrimary,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: IronColors.lightTextPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: IronColors.lightTextPrimary,
        height: 1.5,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: IronColors.lightTextPrimary,
        height: 1.5,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: IronColors.lightTextPrimary,
        height: 1.5,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: IronColors.lightTextSecondary,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: IronColors.lightTextSecondary,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: IronColors.lightTextSecondary,
      ),
    ),
    fontFamily: 'Inter',
  );
}

/// Returns the Dark ThemeData for IronLink.
ThemeData ironLinkDarkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: IronColors.darkBackground,
    colorScheme: ColorScheme.dark(
      primary: IronColors.darkGold,
      secondary: IronColors.darkAccent,
      background: IronColors.darkBackground,
      surface: IronColors.darkSurface,
      error: IronColors.darkError,
    ),
    // We'll define the textTheme explicitly using the colors from the colorScheme
    textTheme: TextTheme(
      displayLarge: GoogleFonts.inter(
        fontSize: 96,
        fontWeight: FontWeight.w300,
        color: IronColors.darkTextPrimary,
        height: 1.2,
      ),
      displayMedium: GoogleFonts.inter(
        fontSize: 60,
        fontWeight: FontWeight.w300,
        color: IronColors.darkTextPrimary,
        height: 1.2,
      ),
      displaySmall: GoogleFonts.inter(
        fontSize: 48,
        fontWeight: FontWeight.w400,
        color: IronColors.darkTextPrimary,
        height: 1.2,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: IronColors.darkTextPrimary,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: IronColors.darkTextPrimary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: IronColors.darkTextPrimary,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: IronColors.darkTextPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: IronColors.darkTextPrimary,
        height: 1.5,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14
),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: IronColors.darkTextPrimary,
        height: 1.5,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: IronColors.darkTextSecondary,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: IronColors.darkTextSecondary,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: IronColors.darkTextSecondary,
      ),
    ),
    fontFamily: 'Inter',
  );
}

/// A helper function to get the current theme based on the brightness.
ThemeData ironLinkTheme(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? ironLinkDarkTheme()
      : ironLinkLightTheme();
}