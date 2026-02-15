import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════
//  CourtSwiss Design Tokens – Premium "Black Card" Design System
// ═══════════════════════════════════════════════════════════════════

/// Core brand colours.
abstract final class CsColors {
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color lime = Color(0xFFC1FF72);

  // Card surfaces
  static const Color blackCard = Color(0xFF0B0B0B);
  static const Color blackCard2 = Color(0xFF141414);

  // Grays
  static const Color gray50 = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray300 = Color(0xFFD1D5DB);
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray500 = Color(0xFF6B7280);
  static const Color gray600 = Color(0xFF4B5563);
  static const Color gray700 = Color(0xFF374151);
  static const Color gray800 = Color(0xFF1F2937);
  static const Color gray900 = Color(0xFF111827);

  // Semantic accent colours
  static const Color amber = Color(0xFFF59E0B);
  static const Color blue = Color(0xFF3B82F6);
  static const Color purple = Color(0xFFA855F7);
  static const Color emerald = Color(0xFF34D399);

  // Semantic (used by status chips etc.)
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
}

/// Opacity constants for layering white text on dark surfaces.
abstract final class CsOpacity {
  static const double primary = 1.0;
  static const double secondary = 0.7;
  static const double tertiary = 0.45;
  static const double hint = 0.30;
  static const double border = 0.10;
}

/// Border radii.
abstract final class CsRadii {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double full = 999.0;
}

/// Pre-built box shadows.
abstract final class CsShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color(0x14000000), // black 8 %
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x0A000000), // black 4 %
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x1A000000), // black 10 %
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x0D000000), // black 5 %
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> subtle = [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
}

/// Animation durations used across the app.
abstract final class CsDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration entrance = Duration(milliseconds: 320);
  static const Duration sheet = Duration(milliseconds: 280);
  static const Duration sheetReverse = Duration(milliseconds: 220);
  static const Duration dialog = Duration(milliseconds: 200);
}

/// Centralised motion styles for sheets & dialogs.
abstract final class CsMotion {
  /// BottomSheet slide-in: 280 ms easeOutCubic, dismiss: 220 ms easeInCubic.
  static final AnimationStyle sheet = AnimationStyle(
    duration: CsDurations.sheet,
    reverseDuration: CsDurations.sheetReverse,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Dialog appear: 200 ms easeOutCubic.
  static final AnimationStyle dialog = AnimationStyle(
    duration: CsDurations.dialog,
    reverseDuration: const Duration(milliseconds: 160),
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
}

/// Stagger delay multiplier for list entrance animations.
const Duration csStaggerDelay = Duration(milliseconds: 40);

// ═══════════════════════════════════════════════════════════════════
//  Text Styles (system fonts – no google_fonts dependency)
// ═══════════════════════════════════════════════════════════════════

abstract final class CsTextStyles {
  // Display / headline
  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    height: 1.15,
    color: CsColors.black,
  );
  static const TextStyle displayMedium = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.2,
    color: CsColors.black,
  );

  // Title
  static const TextStyle titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.3,
    color: CsColors.black,
  );
  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.35,
    color: CsColors.black,
  );
  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.35,
    color: CsColors.black,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: CsColors.gray700,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: CsColors.gray600,
  );
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: CsColors.gray500,
  );

  // Label / caption
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.4,
    color: CsColors.black,
  );
  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 1.4,
    color: CsColors.gray500,
  );

  // ── On-dark variants (white text on black cards) ──────────
  static TextStyle onDarkPrimary = const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: CsColors.white,
  );
  static TextStyle onDarkSecondary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: CsColors.white.withValues(alpha: CsOpacity.secondary),
  );
  static TextStyle onDarkTertiary = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: CsColors.white.withValues(alpha: CsOpacity.tertiary),
  );
  static TextStyle onDarkHint = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: CsColors.white.withValues(alpha: CsOpacity.hint),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  Page background gradient (light → white)
// ═══════════════════════════════════════════════════════════════════

const LinearGradient csPageGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x80F9FAFB), // gray50 ~50 % opacity
    CsColors.white,
  ],
);

// ═══════════════════════════════════════════════════════════════════
//  ThemeData builder
// ═══════════════════════════════════════════════════════════════════

ThemeData buildCsTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: CsColors.white,
    colorSchemeSeed: CsColors.lime,
  );

  return base.copyWith(
    // ── Color Scheme override ──
    colorScheme: base.colorScheme.copyWith(
      primary: CsColors.black,
      onPrimary: CsColors.white,
      secondary: CsColors.lime,
      onSecondary: CsColors.black,
      surface: CsColors.white,
      onSurface: CsColors.black,
      error: CsColors.error,
    ),

    // ── AppBar ──
    appBarTheme: AppBarTheme(
      backgroundColor: CsColors.white.withValues(alpha: 0.95),
      foregroundColor: CsColors.black,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: CsTextStyles.titleMedium.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: const IconThemeData(color: CsColors.black, size: 22),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),

    // ── Card ──
    cardTheme: CardThemeData(
      color: CsColors.blackCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CsRadii.lg),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
    ),

    // ── Filled/Elevated Button ──
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CsColors.black,
        foregroundColor: CsColors.white,
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CsRadii.md),
        ),
        textStyle: CsTextStyles.labelLarge,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: CsColors.black,
        foregroundColor: CsColors.white,
        elevation: 0,
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CsRadii.md),
        ),
        textStyle: CsTextStyles.labelLarge,
      ),
    ),

    // ── Outlined Button ──
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CsColors.black,
        minimumSize: const Size(64, 48),
        side: BorderSide(color: CsColors.gray200),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CsRadii.md),
        ),
        textStyle: CsTextStyles.labelLarge,
      ),
    ),

    // ── Text Button ──
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CsColors.black,
        textStyle: CsTextStyles.labelLarge,
      ),
    ),

    // ── Input Decoration ──
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CsColors.gray50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CsRadii.md),
        borderSide: BorderSide(color: CsColors.gray200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CsRadii.md),
        borderSide: BorderSide(color: CsColors.gray200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CsRadii.md),
        borderSide: const BorderSide(color: CsColors.black, width: 1.5),
      ),
      labelStyle: CsTextStyles.bodyMedium,
      hintStyle: CsTextStyles.bodyMedium.copyWith(color: CsColors.gray400),
    ),

    // ── Chip ──
    chipTheme: ChipThemeData(
      backgroundColor: CsColors.gray100,
      labelStyle: CsTextStyles.labelSmall,
      shape: const StadiumBorder(),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),

    // ── Floating Action Button ──
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: CsColors.black,
      foregroundColor: CsColors.white,
      elevation: 4,
      shape: CircleBorder(),
    ),

    // ── Divider ──
    dividerTheme: DividerThemeData(
      color: CsColors.gray200.withValues(alpha: 0.6),
      thickness: 1,
      space: 1,
    ),

    // ── BottomSheet ──
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: CsColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CsRadii.xl)),
      ),
    ),

    // ── Dialog ──
    dialogTheme: DialogThemeData(
      backgroundColor: CsColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CsRadii.lg),
      ),
      titleTextStyle: CsTextStyles.titleLarge,
    ),

    // ── Date Picker ──
    datePickerTheme: DatePickerThemeData(
      backgroundColor: CsColors.white,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: CsColors.black,
      headerForegroundColor: CsColors.white,
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return CsColors.white;
        return CsColors.gray900;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return CsColors.black;
        return null;
      }),
      todayForegroundColor: WidgetStateProperty.all(CsColors.black),
      todayBorder: const BorderSide(color: CsColors.black),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CsRadii.xl),
      ),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: CsColors.gray600,
      ),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: CsColors.black,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    // ── Popup Menu (3-dot overflow) ──
    popupMenuTheme: PopupMenuThemeData(
      color: CsColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: const Color(0x28000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      textStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: CsColors.gray900,
      ),
    ),

    // ── Time Picker ──
    timePickerTheme: TimePickerThemeData(
      backgroundColor: CsColors.white,
      hourMinuteColor: CsColors.gray100,
      hourMinuteTextColor: CsColors.gray900,
      dayPeriodColor: CsColors.gray100,
      dayPeriodTextColor: CsColors.gray900,
      dayPeriodBorderSide: const BorderSide(color: CsColors.gray200),
      dialHandColor: CsColors.black,
      dialBackgroundColor: CsColors.gray50,
      dialTextColor: CsColors.gray900,
      entryModeIconColor: CsColors.gray500,
      helpTextStyle: CsTextStyles.labelSmall.copyWith(color: CsColors.gray500),
      hourMinuteTextStyle: const TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w500,
        color: CsColors.gray900,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CsRadii.xl),
      ),
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: CsColors.gray600,
      ),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: CsColors.black,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    // ── SnackBar ──
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF0E0E0E),
      contentTextStyle: const TextStyle(
        color: CsColors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CsRadii.lg),
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 6,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    ),

    // ── Text Theme ──
    textTheme: TextTheme(
      displayLarge: CsTextStyles.displayLarge,
      displayMedium: CsTextStyles.displayMedium,
      titleLarge: CsTextStyles.titleLarge,
      titleMedium: CsTextStyles.titleMedium,
      titleSmall: CsTextStyles.titleSmall,
      bodyLarge: CsTextStyles.bodyLarge,
      bodyMedium: CsTextStyles.bodyMedium,
      bodySmall: CsTextStyles.bodySmall,
      labelLarge: CsTextStyles.labelLarge,
      labelSmall: CsTextStyles.labelSmall,
    ),

    // ── Switch ──
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return CsColors.lime;
        return CsColors.gray400;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return CsColors.black;
        }
        return CsColors.gray200;
      }),
    ),

    // ── Progress Indicator ──
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CsColors.black,
      linearTrackColor: Color(0xFFE5E7EB),
    ),
  );
}
