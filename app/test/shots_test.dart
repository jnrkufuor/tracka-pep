// Pictures of the app's main screens, with the real fonts, at a 390 x 844
// phone. Not a pass/fail test: CI runs it with --update-goldens and saves the
// PNGs to the `app-shots` branch, so the screens can be put next to their
// boards on the design canvas and compared by eye (.github/workflows/app.yml).
//
// Run locally: flutter test --tags shots --update-goldens test/shots_test.dart
@Tags(['shots'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tracka/screens/auth_screen.dart';
import 'package:tracka/screens/onboarding_screen.dart';
import 'package:tracka/screens/settings_screen.dart';
import 'package:tracka/screens/shell.dart';
import 'package:tracka/state/app_state.dart';
import 'package:tracka/theme/theme.dart';
import 'package:tracka/widgets/pep.dart';

import 'screens_test.dart' show readyState;

Future<void> _loadFonts() async {
  for (final (family, files) in [
    ('Figtree', ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold']),
    ('Bricolage', ['Medium', 'SemiBold', 'Bold', 'ExtraBold']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      final name = family == 'Bricolage' ? 'BricolageGrotesque-$f' : 'Figtree-$f';
      loader.addFont(rootBundle.load('assets/fonts/$name.ttf'));
    }
    await loader.load();
  }
}

/// All 20 moods on one page, to compare with "Pep's 20 moods".
class _Moods extends StatelessWidget {
  const _Moods();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: GridView.count(
            crossAxisCount: 4,
            padding: const EdgeInsets.all(16),
            children: [
              for (final m in PepMood.values)
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  PepFace(m, size: 52, breathe: false),
                  const SizedBox(height: 6),
                  Text(m.name, style: const TextStyle(fontSize: 12, color: Tk.muted)),
                ]),
            ],
          ),
        ),
      );
}

void main() {
  setUpAll(_loadFonts);

  final shots = <String, Widget Function()>{
    '01-welcome': () => const WelcomeScreen(),
    '02-sign-up-phone': () => const PhoneScreen(),
    '03-sign-up-email': () => const AuthScreen(signUp: true),
    '04-log-in': () => const AuthScreen(signUp: false),
    '05-meet-pep': () => const OnboardingScreen(),
    '06-step-1-personal': () => const OnboardingScreen(startPage: 1),
    '07-step-2-location': () => const OnboardingScreen(startPage: 2),
    '08-step-3-journey': () => const OnboardingScreen(startPage: 3),
    '09-step-4-profile': () => const OnboardingScreen(startPage: 4),
    '10-step-5-schedule': () => const OnboardingScreen(startPage: 5),
    '10b-all-set': () => const OnboardingScreen(startPage: 7),
    '11-home': () => const Shell(),
    '12-pitchside': () => const Shell(initialTab: 1),
    '13-pep': () => const Shell(initialTab: 2),
    '14-me': () => const Shell(initialTab: 3),
    '15-settings': () => const SettingsScreen(),
    '16-home-day-one': () => const Shell(),
    '17-pep-day-one': () => const Shell(initialTab: 2),
    '18-me-day-one': () => const Shell(initialTab: 3),
    '20-pep-moods': () => const _Moods(),
  };

  for (final MapEntry(key: name, value: make) in shots.entries) {
    testWidgets('picture: $name', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final s = (await tester.runAsync(() => readyState(dayOne: name.contains('day-one'))))!;
      await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
        value: s,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: trackaTheme(), home: make()),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    });
  }

  tearDownAll(() {
    // A marker so CI knows the pictures were written by this run.
    File('test/shots/.made').writeAsStringSync(DateTime.now().toIso8601String());
  });
}
