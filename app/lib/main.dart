import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/notifications_screen.dart' show openLink;
import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'theme/theme.dart';

/// Tracka, the player app. One codebase: Android, iOS and the web.
///
/// The app decides what to show from [AppState.stage]:
///   starting   → splash (mark fades in) while we check for a saved login
///   signedOut  → welcome + sign up / log in
///   onboarding → build your profile (Pep needs age and positions)
///   ready      → the tabs: Home, Pitchside, + (add a clip), Pep, Me
/// Lets a tapped push open a screen from outside the widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()
        ..onPushOpened = ((data) {
          final nav = navigatorKey.currentState;
          if (nav != null) openLink(nav, data);
        })
        ..start(),
      child: const TrackaApp(),
    ),
  );
}

class TrackaApp extends StatelessWidget {
  const TrackaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final stage = context.select<AppState, Stage>((s) => s.stage);
    // The player's main colour and reduce-motion choice re-theme the whole app.
    final colour = context.select<AppState, String>((s) => s.settings.mainColour);
    Motion.appSetting = context.select<AppState, bool>((s) => s.settings.reduceMotion);
    // Settings › Accessibility › Text size, on top of the phone's own text size.
    final scale = context.select<AppState, double>((s) => s.settings.textScale);
    final contrast = context.select<AppState, bool>((s) => s.settings.highContrast);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Tracka',
      debugShowCheckedModeBanner: false,
      theme: trackaTheme(colour: MainColour.fromName(colour)),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // The bridge lets packages that still use the old built-in Material library
        // (package:flutter/material.dart) find our theme and words.
        Widget app = MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear((mq.textScaler.scale(14) / 14 * scale).clamp(0.85, 2.0)),
            highContrast: contrast || mq.highContrast,
          ),
          child: child!,
        );
        // Settings › Accessibility › Higher contrast: every grey gets brighter against the
        // black, so faint text and lines are easier to read. Black stays black.
        if (contrast) app = ColorFiltered(colorFilter: highContrastFilter, child: app);
        return MaterialUiCompatibilityBridge(child: app);
      },
      home: AnimatedSwitcher(
        duration: Motion.enter,
        child: switch (stage) {
          Stage.starting => const SplashScreen(key: ValueKey('splash')),
          Stage.signedOut => const WelcomeScreen(key: ValueKey('welcome')),
          Stage.onboarding => const OnboardingScreen(key: ValueKey('onboarding')),
          Stage.ready => const Shell(key: ValueKey('shell')),
        },
      ),
    );
  }
}


/// Each colour channel × 1.3, minus a little: black stays black, greys brighten
/// (faint #8C9183 becomes about #AEB4A3, muted #A7AC9C about #D1D7C5).
const highContrastFilter = ColorFilter.matrix(<double>[
  1.3, 0, 0, 0, -8, //
  0, 1.3, 0, 0, -8, //
  0, 0, 1.3, 0, -8, //
  0, 0, 0, 1, 0,
]);
