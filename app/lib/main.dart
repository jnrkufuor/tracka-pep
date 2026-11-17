import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shell.dart';
import 'state/app_state.dart';
import 'theme/theme.dart';
import 'widgets/common.dart';

/// Tracka, the player app. One codebase: Android, iOS and the web.
///
/// The app decides what to show from [AppState.stage]:
///   starting   → splash while we check for a saved login
///   signedOut  → welcome + sign up / log in
///   onboarding → build your profile (Pep needs age and positions)
///   ready      → the tabs: Home, Videos, Pep, Opportunities, Profile
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
    return MaterialApp(
      title: 'Tracka',
      debugShowCheckedModeBanner: false,
      theme: trackaTheme(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: switch (stage) {
          Stage.starting => const _Splash(key: ValueKey('splash')),
          Stage.signedOut => const WelcomeScreen(key: ValueKey('welcome')),
          Stage.onboarding => const OnboardingScreen(key: ValueKey('onboarding')),
          Stage.ready => const Shell(key: ValueKey('shell')),
        },
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: TrackaLogo(size: 48)));
  }
}
