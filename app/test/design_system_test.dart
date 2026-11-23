import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/api/models.dart';
import 'package:tracka/theme/theme.dart';
import 'package:tracka/widgets/ds.dart';

/// Wraps a widget in the app theme so `context.accent` and text styles work.
Widget app(Widget child, {MainColour colour = MainColour.volt}) => MaterialApp(
      theme: trackaTheme(colour: colour),
      home: Scaffold(body: Center(child: child)),
    );

/// The check icon inside a chip.
final checks = find.byWidgetPredicate((w) => w is TIcon && w.name == 'check');

void main() {
  group('tokens', () {
    test('unknown or missing main colour falls back to Volt', () {
      expect(MainColour.fromName('pink'), MainColour.pink);
      expect(MainColour.fromName(null), MainColour.volt);
      expect(MainColour.fromName('purple'), MainColour.volt); // purple is Pep's, never offered
    });

    test('every main colour keeps black text readable (WCAG AA, 4.5:1)', () {
      for (final c in MainColour.values) {
        final ratio = (c.main.computeLuminance() + 0.05) / 0.05; // contrast against black
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '${c.label}: black text on it');
      }
    });

    test('every icon the app asks for exists in the generated line pack', () {
      const used = ['home', 'clip', 'pep', 'you', 'plus', 'check', 'close', 'info', 'hurt', 'nosignal', 'trophy', 'pin', 'flag'];
      for (final n in used) {
        expect(TIcon.names, contains(n), reason: 'run scripts/build_brand.py after adding "$n" there');
      }
    });

    test('confidence accepts the API words in any case', () {
      expect(Confidence.fromName('HIGH'), Confidence.high);
      expect(Confidence.fromName('medium'), Confidence.medium);
      expect(Confidence.fromName(null), Confidence.low);
    });

    test('settings from an older server get safe defaults', () {
      final s = AppSettings.fromJson({'units': 'mph'});
      expect(s.mainColour, 'volt');
      expect(s.reduceMotion, isFalse);
      expect(s.uploadOnWifiOnly, isTrue);
    });
  });

  group('widgets', () {
    testWidgets('band pill shows its words, Standout is solid main colour', (tester) async {
      await tester.pumpWidget(app(const BandPill(Band.standout), colour: MainColour.blue));
      expect(find.text('Standout'), findsOneWidget);
      final box = tester.widget<Container>(find.ancestor(of: find.text('Standout'), matching: find.byType(Container)).first);
      expect((box.decoration! as BoxDecoration).color, MainColour.blue.main);
    });

    testWidgets('single chips: no checkmark, tapping the picked one keeps it picked', (tester) async {
      var value = 'a';
      await tester.pumpWidget(app(StatefulBuilder(
        builder: (context, setState) => SingleChips<String>(
          options: const {'a': 'Challenges', 'b': 'Near you'},
          value: value,
          onChanged: (v) => setState(() => value = v),
        ),
      )));
      expect(checks, findsNothing);
      await tester.tap(find.text('Challenges'));
      await tester.pumpAndSettle();
      expect(value, 'a');
      await tester.tap(find.text('Near you'));
      await tester.pumpAndSettle();
      expect(value, 'b');
    });

    testWidgets('multi chips show a check on what you ticked', (tester) async {
      await tester.pumpWidget(app(MultiChips<String>(options: const {'cm': 'CM', 'dm': 'DM'}, values: const {'cm'}, onChanged: (_) {})));
      expect(checks, findsOneWidget);
    });

    testWidgets('a skill not measured yet shows its state, not a band', (tester) async {
      await tester.pumpWidget(app(const RatingRow(name: 'Receiving on the half-turn', state: 'Coming later')));
      expect(find.text('Coming later'), findsOneWidget);
      expect(find.byType(BandPill), findsNothing);
    });

    testWidgets('a failsafe state always offers one next step', (tester) async {
      var tapped = false;
      await tester.pumpWidget(app(SizedBox(height: 700, child: StateView.error(onRetry: () => tapped = true))));
      await tester.tap(find.text('Try again'));
      expect(tapped, isTrue);
    });
  });
}
