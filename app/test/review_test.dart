import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/api/models.dart';
import 'package:tracka/screens/review_screens.dart';
import 'package:tracka/theme/theme.dart';

final _json = {
  'headline': {'title': 'You looked around more', 'text': 'You checked your shoulder more.'},
  'wentWell': [
    {'atSeconds': 760.0, 'kind': 'GOOD', 'title': 'Turned and played forward', 'text': 'You checked twice.', 'area': 'scanning', 'areaName': 'Looking around'},
  ],
  'workOn': [
    {'atSeconds': 1982.0, 'kind': 'WORK_ON', 'title': 'Passed back under pressure', 'text': "You didn't look first."},
  ],
  'tips': [
    {
      'area': 'scanning',
      'areaName': 'Looking around',
      'group': 'Reading the game',
      'title': 'Look before you get the ball',
      'text': 'A quick look shows you the space.',
      'atSeconds': 1982.0,
      'drill': {'id': 'scanning_rondo', 'name': 'Scanning rondo', 'minutes': 12, 'how': '3 against 1.', 'needs': ['ball', 'friends']},
    },
  ],
  'areas': [
    {'id': 'scanning', 'name': 'Looking around', 'group': 'Reading the game', 'kind': 'GOOD'},
  ],
  'source': 'gemini',
};

void main() {
  test('clip times read like a match clock', () {
    expect(clipTime(7), '0:07');
    expect(clipTime(760), '12:40');
  });

  testWidgets('a review shows the story, and tapping a moment seeks the video there', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    double? seekedTo;
    await tester.pumpWidget(MaterialApp(
      theme: trackaTheme(),
      home: Scaffold(
        body: SingleChildScrollView(child: ReviewView(review: Review.fromJson(_json), onSeek: (s) => seekedTo = s)),
      ),
    ));
    expect(find.text('You looked around more'), findsOneWidget);
    expect(find.text('Try the drill · 12 min'), findsOneWidget);
    expect(find.text('In your plan this week'), findsOneWidget);
    await tester.tap(find.text('Turned and played forward'));
    expect(seekedTo, 760);
    await tester.tap(find.text('Try the drill · 12 min'));
    await tester.pumpAndSettle();
    expect(find.text('Scanning rondo'), findsWidgets);
    expect(find.textContaining('Stop if anything hurts'), findsOneWidget);
  });
}
