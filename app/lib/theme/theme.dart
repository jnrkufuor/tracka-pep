import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

export 'tokens.dart';
export 'motion.dart';

/// Older colour names, kept so screens not yet rebuilt in the new design still
/// compile. They now point at the new tokens (pure black, no red).
/// New code: use [T] and `context.accent` instead (see tokens.dart).
class TColors {
  static const bg = Tk.bg;
  static const surface = Tk.card;
  static const surface2 = Tk.card2;
  static const surface3 = Tk.field;
  static const line = Tk.lineStrong;
  static const lineSoft = Tk.line;

  static const ink = Tk.ink;
  static const inkSoft = Tk.muted;
  static const inkFaint = Tk.faint;

  static const neon = Color(0xFFE5FF00); // Volt; new code reads context.accent.main
  static const onNeon = Tk.bg;
  static const cherry = Tk.gold; // "work on" and errors are gold now: no red in Tracka
  static const sun = Tk.stone;
  static const violet = Tk.pep;

  static Color forConfidence(String? c) => switch (c) {
        'HIGH' => neon,
        'MEDIUM' => sun,
        _ => cherry,
      };
}

class TRadius {
  static const sm = 14.0;
  static const md = 20.0;
  static const lg = 26.0;
  static const xl = 40.0;
}

/// Type: Bricolage Grotesque (extra bold) for headings and big numbers,
/// Figtree for everything you read.
class TType {
  static const display = 'Bricolage';
  static const text = 'Figtree';

  /// Small uppercase labels above a section.
  static const eyebrow = TextStyle(
    fontFamily: text,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.9,
    color: Tk.faint,
  );

  /// A big measured number (4.6 s, 19 passes).
  static const stat = TextStyle(fontFamily: display, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1);
}

/// The app theme, coloured with the player's main colour.
///
/// Rebuilt when the colour changes (MaterialApp gets a new theme and animates
/// between them). Everything Material draws (buttons, switches, fields,
/// progress bars) picks the colour up from here; our own widgets read
/// `context.accent`.
ThemeData trackaTheme({MainColour colour = MainColour.volt}) {
  final a = Accent(colour);
  const d = TType.display;
  const t = TextTheme(
    displayLarge: TextStyle(fontFamily: d, fontSize: 46, fontWeight: FontWeight.w800, letterSpacing: -1.8, height: 1.0),
    displayMedium: TextStyle(fontFamily: d, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1.4, height: 1.02),
    headlineLarge: TextStyle(fontFamily: d, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1.0, height: 1.05),
    headlineMedium: TextStyle(fontFamily: d, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.7, height: 1.1),
    titleLarge: TextStyle(fontFamily: d, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleMedium: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 15.5, height: 1.45),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45),
    bodySmall: TextStyle(fontSize: 12.5, height: 1.4, color: Tk.muted),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );
  final scheme = ColorScheme.dark(
    primary: a.main,
    onPrimary: a.on,
    secondary: Tk.pep,
    surface: Tk.card,
    onSurface: Tk.ink,
    error: Tk.gold,
    onError: Tk.bg,
  );
  OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tk.rField),
        borderSide: BorderSide(color: c, width: 1.5),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: TType.text,
    scaffoldBackgroundColor: Tk.bg,
    extensions: [a],
    textTheme: t.apply(bodyColor: Tk.ink, displayColor: Tk.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: Tk.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Tk.ink,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Tk.bg,
      ),
      titleTextStyle: TextStyle(fontFamily: d, fontSize: 20, fontWeight: FontWeight.w800, color: Tk.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tk.field,
      hintStyle: const TextStyle(color: Tk.faint),
      labelStyle: const TextStyle(color: Tk.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: border(Tk.lineStrong),
      enabledBorder: border(Tk.lineStrong),
      focusedBorder: border(a.main),
      errorBorder: border(Tk.gold),
      focusedErrorBorder: border(Tk.gold),
      errorStyle: const TextStyle(color: Tk.gold),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: a.main,
        foregroundColor: a.on,
        disabledBackgroundColor: Tk.field,
        disabledForegroundColor: Tk.faint,
        minimumSize: const Size(64, 54),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: TType.text, fontSize: 15.5, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Tk.ink,
        side: const BorderSide(color: Tk.lineStrong, width: 1.5),
        minimumSize: const Size(64, 50),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: TType.text, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Tk.muted,
        textStyle: const TextStyle(fontFamily: TType.text, fontWeight: FontWeight.w600),
      ),
    ),
    // Toasts sit at the bottom, above the tabs (see widgets/toast.dart).
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1A1A1A),
      contentTextStyle: const TextStyle(fontFamily: TType.text, color: Tk.ink, fontWeight: FontWeight.w600, fontSize: 14),
      actionTextColor: a.main,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF2E2E2E)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Tk.bg,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: Tk.bg,
      showDragHandle: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Tk.rSheet))),
    ),
    dividerTheme: const DividerThemeData(color: Tk.line, thickness: 1, space: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? a.on : Tk.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? a.main : Tk.field),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: a.main, linearTrackColor: Tk.line),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
    }),
  );
}
