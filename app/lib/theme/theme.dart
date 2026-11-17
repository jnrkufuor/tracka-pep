import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tracka's night-match palette: YesBut's design language, darker and sportier.
/// Every colour in the app comes from here (see docs/DESIGN.md).
class TColors {
  static const bg = Color(0xFF0A0B09); // pitch at night
  static const surface = Color(0xFF121410);
  static const surface2 = Color(0xFF191C16);
  static const surface3 = Color(0xFF22261E);
  static const line = Color(0xFF2A2F25);
  static const lineSoft = Color(0xFF1E221B);

  static const ink = Color(0xFFF2F4EC); // chalk
  static const inkSoft = Color(0xFFA7ACA0);
  static const inkFaint = Color(0xFF6E7366);

  static const neon = Color(0xFFE5FF00); // the floodlight
  static const onNeon = Color(0xFF0A0B09);
  static const cherry = Color(0xFFFF4858); // LOW, work on, errors
  static const sun = Color(0xFFFFD100); // MEDIUM
  static const violet = Color(0xFF8C73FF); // processing, AI-observed

  static Color forConfidence(String? c) => switch (c) {
        'HIGH' => neon,
        'MEDIUM' => sun,
        _ => cherry,
      };
}

class TRadius {
  static const sm = 14.0;
  static const md = 22.0;
  static const lg = 30.0;
  static const xl = 40.0;
}

class TType {
  static const display = 'Bricolage';
  static const text = 'SansFlex';

  /// Uppercase micro-labels with wide tracking, like broadcast graphics.
  static const eyebrow = TextStyle(
    fontFamily: text,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.8,
    color: TColors.inkFaint,
  );
}

ThemeData trackaTheme() {
  const d = TType.display;
  const t = TextTheme(
    displayLarge: TextStyle(fontFamily: d, fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -2, height: 0.98),
    displayMedium: TextStyle(fontFamily: d, fontSize: 38, fontWeight: FontWeight.w700, letterSpacing: -1.5, height: 1.0),
    headlineLarge: TextStyle(fontFamily: d, fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -1.0, height: 1.05),
    headlineMedium: TextStyle(fontFamily: d, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.7, height: 1.1),
    titleLarge: TextStyle(fontFamily: d, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    bodyLarge: TextStyle(fontSize: 15.5, height: 1.45),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45),
    bodySmall: TextStyle(fontSize: 12.5, height: 1.35),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );
  final scheme = const ColorScheme.dark(
    primary: TColors.neon,
    onPrimary: TColors.onNeon,
    secondary: TColors.violet,
    surface: TColors.surface,
    onSurface: TColors.ink,
    error: TColors.cherry,
  );
  OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(TRadius.sm),
        borderSide: BorderSide(color: c),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: TType.text,
    scaffoldBackgroundColor: TColors.bg,
    textTheme: t.apply(bodyColor: TColors.ink, displayColor: TColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: TColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: TColors.ink,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: TColors.bg,
      ),
      titleTextStyle: TextStyle(fontFamily: d, fontSize: 20, fontWeight: FontWeight.w700, color: TColors.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TColors.surface2,
      hintStyle: const TextStyle(color: TColors.inkFaint),
      labelStyle: const TextStyle(color: TColors.inkSoft),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: border(TColors.line),
      enabledBorder: border(TColors.line),
      focusedBorder: border(TColors.neon),
      errorBorder: border(TColors.cherry),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TColors.neon,
        foregroundColor: TColors.onNeon,
        disabledBackgroundColor: TColors.surface3,
        minimumSize: const Size(64, 54),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: TType.text, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: TColors.ink,
        side: const BorderSide(color: TColors.line),
        minimumSize: const Size(64, 50),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: TType.text, fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: TColors.neon,
        textStyle: const TextStyle(fontFamily: TType.text, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: TColors.ink,
      contentTextStyle: const TextStyle(color: TColors.bg, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TRadius.md)),
    ),
    dividerTheme: const DividerThemeData(color: TColors.lineSoft, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? TColors.onNeon : TColors.inkSoft),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? TColors.neon : TColors.surface3),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: TColors.neon, linearTrackColor: TColors.surface3),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}
