import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the calm, high-trust dark aesthetic: near-black grounds,
/// soft metallic grays, and a restrained blue reserved for genuine actions.
/// Blue is deliberately scarce — if everything is accented, nothing reads as
/// actionable, which is what made the previous neon-cyan pass feel loud.
class IronColors {
  // ── Backgrounds & surfaces ──────────────────────────────────────────────
  static const Color backgroundPrimary = Color(0xFF0A0C10);
  static const Color backgroundSecondary = Color(0xFF0B0E14);
  static const Color surfacePrimary = Color(0xFF12151C);
  static const Color surfaceSecondary = Color(0xFF181C25);

  /// True black for OLED panels. Not the default: on standard screens the
  /// pure-black-to-text contrast is harsher to read against for long stretches.
  static const Color backgroundOled = Color(0xFF000000);

  // ── Borders ─────────────────────────────────────────────────────────────
  /// Dividers and card edges. Decorative only — at 1.46:1 it is deliberately
  /// below the 3:1 floor, which WCAG 1.4.11 permits for purely aesthetic
  /// boundaries but NOT for anything identifying a control.
  static const Color borderSubtle = Color(0xFF2A2F3A);

  /// Boundaries of actual controls (text fields, outlined buttons). WCAG
  /// 1.4.11 requires 3:1 for the visual information that identifies a
  /// component, and the spec's #2A2F3A measured 1.46:1 — invisible as an
  /// affordance. Verified 3.45:1 on background, 3.22:1 on surface.
  static const Color borderInteractive = Color(0xFF5C6780);

  static const Color borderFocused = Color(0xFF60A5FA);

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);

  /// Low-emphasis *content* (timestamps, captions, hints). The spec's
  /// #64748B measured 4.11:1 on background — under the 4.5:1 body-text floor.
  /// Chosen to clear 4.5:1 on every ground it can land on, accentSubtle
  /// included: worst case 4.69:1.
  static const Color textTertiary = Color(0xFF8593A8);

  /// Disabled controls only. WCAG 1.4.3 exempts inactive components from
  /// contrast minimums, and keeping this dimmer than textTertiary is what
  /// makes "disabled" legible as a state rather than just small gray text.
  static const Color textDisabled = Color(0xFF64748B);

  // ── Accent ──────────────────────────────────────────────────────────────
  /// Accent as a *fill* — buttons, badges, selected indicators. Carries
  /// textPrimary at 4.72:1.
  static const Color accentPrimary = Color(0xFF2563EB);

  /// Accent as *text or icon on a dark ground* — links, ghost buttons.
  /// #2563EB as text measures 3.79:1 and fails; this is verified 7.70:1 on
  /// background and 5.75:1 on accentSubtle. Fill and on-dark text genuinely
  /// need different values here; using one for both breaks one of them.
  static const Color accentText = Color(0xFF60A5FA);

  static const Color accentSubtle = Color(0xFF1E293B);

  // ── Semantic ────────────────────────────────────────────────────────────
  static const Color semanticSuccess = Color(0xFF10B981);
  static const Color semanticWarning = Color(0xFFF59E0B);
  static const Color semanticError = Color(0xFFEF4444);
  static const Color semanticInfo = Color(0xFF3B82F6);

  static const Color elevationShadow = Color(0x66000000);

  // ── Legacy aliases ──────────────────────────────────────────────────────
  // Screens written before this token set reference these names. They map onto
  // the tokens above so the palette change reaches every screen at once;
  // per-screen usage is retuned as each screen is reworked.
  static const Color darkPrimary = backgroundPrimary;
  static const Color darkSecondary = surfacePrimary;
  static const Color darkTertiary = borderSubtle;
  static const Color darkAccent = accentPrimary;
  static const Color darkTextPrimary = textPrimary;
  static const Color darkTextSecondary = textSecondary;
  static const Color darkTextTertiary = textTertiary;

  static const Color navyDeep = backgroundPrimary;
  static const Color navySurface = surfacePrimary;
  static const Color navyBorder = borderSubtle;

  /// Legacy screens use `gold` for accent-colored icons and text on dark
  /// grounds far more than for fills, so it maps to the on-dark-text value —
  /// mapping it to accentPrimary would leave those call sites at 3.79:1.
  static const Color gold = accentText;
  static const Color goldBright = accentText;

  /// Large empty-state glyphs and other non-actionable marks. Gray, not blue:
  /// a decorative icon is not an action and shouldn't compete with one.
  static const Color goldDim = textTertiary;

  static const Color textHi = textPrimary;
  static const Color textLo = textSecondary;
  static const Color success = semanticSuccess;
  static const Color warning = semanticWarning;
  static const Color error = semanticError;
  static const Color errorRed = semanticError;
  static const Color info = semanticInfo;
  static const Color white = Colors.white;
}

/// Type scale. Latin renders in Inter; Arabic glyphs fall through to IBM Plex
/// Sans Arabic, so mixed-script lines keep one weight and baseline instead of
/// visibly switching families mid-sentence.
class IronTypography {
  static const String fontPrimary = 'Inter';
  static const String fontArabic = 'IBM Plex Sans Arabic';

  static String get _arabicFallback =>
      GoogleFonts.ibmPlexSansArabic().fontFamily!;

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    required double height,
    required double letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      ).copyWith(fontFamilyFallback: [_arabicFallback]);

  static TextStyle displayLarge({Color? color}) => _base(
      size: 32, weight: FontWeight.w700, height: 1.2, letterSpacing: -0.5, color: color);

  static TextStyle displayMedium({Color? color}) => _base(
      size: 28, weight: FontWeight.w700, height: 1.2, letterSpacing: -0.3, color: color);

  static TextStyle displaySmall({Color? color}) => _base(
      size: 24, weight: FontWeight.w700, height: 1.3, letterSpacing: 0, color: color);

  static TextStyle headlineLarge({Color? color}) => _base(
      size: 20, weight: FontWeight.w600, height: 1.3, letterSpacing: 0, color: color);

  static TextStyle headlineMedium({Color? color}) => _base(
      size: 18, weight: FontWeight.w600, height: 1.4, letterSpacing: 0, color: color);

  /// Retained for callers predating the spec scale, which has no `headlineSmall`.
  static TextStyle headlineSmall({Color? color}) => headlineMedium(color: color);

  static TextStyle titleLarge({Color? color}) => headlineLarge(color: color);
  static TextStyle titleMedium({Color? color}) => headlineMedium(color: color);
  static TextStyle titleSmall({Color? color}) => bodyLarge(color: color);

  static TextStyle bodyLarge({Color? color}) => _base(
      size: 16, weight: FontWeight.w400, height: 1.5, letterSpacing: 0, color: color);

  static TextStyle bodyMedium({Color? color}) => _base(
      size: 14, weight: FontWeight.w400, height: 1.5, letterSpacing: 0, color: color);

  static TextStyle bodySmall({Color? color}) => _base(
      size: 12, weight: FontWeight.w400, height: 1.5, letterSpacing: 0, color: color);

  static TextStyle labelLarge({Color? color}) => _base(
      size: 14, weight: FontWeight.w600, height: 1.2, letterSpacing: 0.5, color: color);

  static TextStyle labelMedium({Color? color}) => _base(
      size: 12, weight: FontWeight.w500, height: 1.2, letterSpacing: 0.5, color: color);

  static TextStyle labelSmall({Color? color}) => _base(
      size: 10, weight: FontWeight.w500, height: 1.2, letterSpacing: 0.5, color: color);
}

/// 4px baseline grid.
class IronSpacing {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;
}

class IronRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
}

/// Motion curves and durations. Kept as tokens so timing stays consistent
/// across screens rather than being re-guessed at each call site.
class IronMotion {
  static const Duration entrance = Duration(milliseconds: 280);
  static const Duration exit = Duration(milliseconds: 220);
  static const Duration page = Duration(milliseconds: 300);
  static const Duration press = Duration(milliseconds: 150);
  static const Duration toast = Duration(milliseconds: 200);

  static const Curve entranceCurve = Cubic(0.25, 0.46, 0.45, 0.94);
  static const Curve exitCurve = Cubic(0.55, 0.085, 0.68, 0.53);
  static const Curve pageCurve = Cubic(0.25, 0.1, 0.25, 1.0);
  static const Curve pressCurve = Cubic(0.2, 0.0, 0.0, 1.0);
}

/// Token access via `Theme.of(context).extension<IronTokens>()`, for widgets
/// that should follow the active theme rather than reach for constants.
@immutable
class IronTokens extends ThemeExtension<IronTokens> {
  const IronTokens({
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surfacePrimary,
    required this.surfaceSecondary,
    required this.borderSubtle,
    required this.borderInteractive,
    required this.accentPrimary,
    required this.accentText,
    required this.accentSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color surfacePrimary;
  final Color surfaceSecondary;
  final Color borderSubtle;
  final Color borderInteractive;
  final Color accentPrimary;
  final Color accentText;
  final Color accentSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  static const dark = IronTokens(
    backgroundPrimary: IronColors.backgroundPrimary,
    backgroundSecondary: IronColors.backgroundSecondary,
    surfacePrimary: IronColors.surfacePrimary,
    surfaceSecondary: IronColors.surfaceSecondary,
    borderSubtle: IronColors.borderSubtle,
    borderInteractive: IronColors.borderInteractive,
    accentPrimary: IronColors.accentPrimary,
    accentText: IronColors.accentText,
    accentSubtle: IronColors.accentSubtle,
    textPrimary: IronColors.textPrimary,
    textSecondary: IronColors.textSecondary,
    textTertiary: IronColors.textTertiary,
  );

  @override
  IronTokens copyWith({
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? surfacePrimary,
    Color? surfaceSecondary,
    Color? borderSubtle,
    Color? borderInteractive,
    Color? accentPrimary,
    Color? accentText,
    Color? accentSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
  }) =>
      IronTokens(
        backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
        backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
        surfacePrimary: surfacePrimary ?? this.surfacePrimary,
        surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
        borderSubtle: borderSubtle ?? this.borderSubtle,
        borderInteractive: borderInteractive ?? this.borderInteractive,
        accentPrimary: accentPrimary ?? this.accentPrimary,
        accentText: accentText ?? this.accentText,
        accentSubtle: accentSubtle ?? this.accentSubtle,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
      );

  @override
  IronTokens lerp(ThemeExtension<IronTokens>? other, double t) {
    if (other is! IronTokens) return this;
    return IronTokens(
      backgroundPrimary: Color.lerp(backgroundPrimary, other.backgroundPrimary, t)!,
      backgroundSecondary: Color.lerp(backgroundSecondary, other.backgroundSecondary, t)!,
      surfacePrimary: Color.lerp(surfacePrimary, other.surfacePrimary, t)!,
      surfaceSecondary: Color.lerp(surfaceSecondary, other.surfaceSecondary, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderInteractive: Color.lerp(borderInteractive, other.borderInteractive, t)!,
      accentPrimary: Color.lerp(accentPrimary, other.accentPrimary, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    );
  }
}

ThemeData ironLinkDarkTheme() {
  const scheme = ColorScheme.dark(
    primary: IronColors.accentPrimary,
    onPrimary: IronColors.textPrimary,
    secondary: IronColors.accentSubtle,
    onSecondary: IronColors.textPrimary,
    surface: IronColors.surfacePrimary,
    onSurface: IronColors.textPrimary,
    error: IronColors.semanticError,
    onError: IronColors.textPrimary,
    outline: IronColors.borderSubtle,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: IronColors.backgroundPrimary,
    extensions: const [IronTokens.dark],
    fontFamily: GoogleFonts.inter().fontFamily,
    textTheme: TextTheme(
      displayLarge: IronTypography.displayLarge(color: IronColors.textPrimary),
      displayMedium: IronTypography.displayMedium(color: IronColors.textPrimary),
      displaySmall: IronTypography.displaySmall(color: IronColors.textPrimary),
      headlineLarge: IronTypography.headlineLarge(color: IronColors.textPrimary),
      headlineMedium: IronTypography.headlineMedium(color: IronColors.textPrimary),
      headlineSmall: IronTypography.headlineMedium(color: IronColors.textPrimary),
      titleLarge: IronTypography.headlineLarge(color: IronColors.textPrimary),
      titleMedium: IronTypography.headlineMedium(color: IronColors.textPrimary),
      titleSmall: IronTypography.bodyLarge(color: IronColors.textPrimary),
      bodyLarge: IronTypography.bodyLarge(color: IronColors.textPrimary),
      bodyMedium: IronTypography.bodyMedium(color: IronColors.textSecondary),
      bodySmall: IronTypography.bodySmall(color: IronColors.textSecondary),
      labelLarge: IronTypography.labelLarge(color: IronColors.textPrimary),
      labelMedium: IronTypography.labelMedium(color: IronColors.textSecondary),
      labelSmall: IronTypography.labelSmall(color: IronColors.textTertiary),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: IronColors.backgroundPrimary,
      surfaceTintColor: Colors.transparent,
      foregroundColor: IronColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: IronTypography.headlineLarge(color: IronColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: IronColors.surfacePrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IronRadius.md),
        side: const BorderSide(color: IronColors.borderSubtle),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: IronColors.accentPrimary,
        foregroundColor: IronColors.textPrimary,
        disabledBackgroundColor: IronColors.surfaceSecondary,
        disabledForegroundColor: IronColors.textDisabled,
        // 48px minimum touch target (WCAG 2.2 AA).
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(
            horizontal: IronSpacing.lg, vertical: IronSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IronRadius.md),
        ),
        textStyle: IronTypography.labelLarge(),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: IronColors.textPrimary,
        side: const BorderSide(color: IronColors.borderInteractive),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(
            horizontal: IronSpacing.lg, vertical: IronSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IronRadius.md),
        ),
        textStyle: IronTypography.labelLarge(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: IronColors.accentText,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(
            horizontal: IronSpacing.md, vertical: IronSpacing.sm),
        textStyle: IronTypography.labelLarge(),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: IronColors.surfacePrimary,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: IronSpacing.md, vertical: IronSpacing.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IronRadius.md),
        borderSide: const BorderSide(color: IronColors.borderInteractive),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IronRadius.md),
        borderSide: const BorderSide(color: IronColors.borderInteractive),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IronRadius.md),
        borderSide: const BorderSide(color: IronColors.borderFocused, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IronRadius.md),
        borderSide: const BorderSide(color: IronColors.semanticError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(IronRadius.md),
        borderSide: const BorderSide(color: IronColors.semanticError, width: 2),
      ),
      labelStyle: IronTypography.bodyMedium(color: IronColors.textSecondary),
      hintStyle: IronTypography.bodyMedium(color: IronColors.textTertiary),
      errorStyle: IronTypography.bodySmall(color: IronColors.semanticError),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: IronColors.backgroundPrimary,
      surfaceTintColor: Colors.transparent,
      indicatorColor: IronColors.accentSubtle,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? IronTypography.labelMedium(color: IronColors.accentText)
            : IronTypography.labelMedium(color: IronColors.textTertiary),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: IronColors.backgroundSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(IronRadius.lg)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: IronColors.surfaceSecondary,
      contentTextStyle: IronTypography.bodyMedium(color: IronColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IronRadius.md),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: IronColors.backgroundSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IronRadius.lg),
      ),
      titleTextStyle: IronTypography.headlineLarge(color: IronColors.textPrimary),
      contentTextStyle: IronTypography.bodyMedium(color: IronColors.textSecondary),
    ),
    dividerTheme: const DividerThemeData(
      color: IronColors.borderSubtle,
      thickness: 1,
      space: IronSpacing.md,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: IronColors.accentText,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _IronPageTransitions(),
        TargetPlatform.iOS: _IronPageTransitions(),
      },
    ),
  );
}

/// Shared push/pop transition: a short fade with a slight rise, matching the
/// spec's page timing. Material's default zoom transition is heavier than the
/// rest of the motion language and reads as a different product mid-flow.
class _IronPageTransitions extends PageTransitionsBuilder {
  const _IronPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Honour the platform's reduced-motion setting: fade only, no travel.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final curved =
        CurvedAnimation(parent: animation, curve: IronMotion.pageCurve);

    if (reduceMotion) {
      return FadeTransition(opacity: curved, child: child);
    }

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.02), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}
