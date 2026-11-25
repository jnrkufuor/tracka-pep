import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/theme/theme.dart';
import 'package:tracka/widgets/tour.dart';

void main() {
  testWidgets("Pep's tour walks four steps and can be skipped", (tester) async {
    var done = 0;
    await tester.pumpWidget(MaterialApp(
      theme: trackaTheme(),
      home: Scaffold(
        body: Stack(children: [
          Column(children: [
            const SizedBox(height: 80),
            KeyedSubtree(key: TourKeys.road, child: const SizedBox(height: 90, width: 300)),
          ]),
          Positioned.fill(child: TourOverlay(onDone: () => done++)),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 of 4'), findsOneWidget);
    expect(find.text('Your goal and your week'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Find me here'), findsOneWidget); // no target on screen: shown in the middle
    await tester.tap(find.text('Got it'));
    expect(done, 1);
  });
}
