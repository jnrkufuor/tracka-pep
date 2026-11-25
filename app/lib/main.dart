import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
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
void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..start(),
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
    return MaterialApp(
      title: 'Tracka',
      debugShowCheckedModeBanner: false,
      theme: trackaTheme(colour: MainColour.fromName(colour)),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear((mq.textScaler.scale(14) / 14 * scale).clamp(0.85, 2.0))), child: child!);
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

