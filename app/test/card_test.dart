import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/api/models.dart';
import 'package:tracka/screens/card_screens.dart';
import 'package:tracka/theme/theme.dart';

final _card = {
  'shirtName': 'K. ASANTE',
  'shirtNumber': 8,
  'initials': 'KA',
  'positions': ['CM'],
  'positionName': 'Central midfielder',
  'foot': 'right',
  'region': 'Ashanti',
  'ageGroup': 'U17',
  'style': 'Playmaker',
  'pepSees': ['Looking around'],
  'bests': [
    {'label': '30 m sprint', 'value': '4.60', 'unit': 's'},
  ],
  'skills': [
    {'name': 'Passing forward', 'band': 'Above average', 'average': '22 wall passes in 30 s', 'confidence': 'medium', 'trend': 'up'},
  ],
  'comparedWith': 'U17 players',
  'clips': <Map<String, dynamic>>[],
  'under18': true,
};

void main() {
  test('card state reads the link and what is shown', () {
    final c = CardState.fromJson({
      'card': _card,
      'link': {'on': true, 'url': 'https://tracka.app/c/abc'},
      'show': {'bests': true, 'skills': false, 'clips': true},
      'portfolio': ['v1'],
      'canShare': true,
    });
    expect(c.linkOn, isTrue);
    expect(c.show['skills'], isFalse);
    expect(c.card.line, 'Right foot · Ashanti · U17');
  });

  testWidgets('the full card shows bands and the under-18 note, never a score', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: trackaTheme(),
      home: Scaffold(body: SingleChildScrollView(child: PlayerCardView(card: PlayerCard.fromJson(_card), full: true))),
    ));
    expect(find.text('K. ASANTE · 8'), findsOneWidget);
    expect(find.text('Above average'), findsOneWidget);
    expect(find.textContaining('Under 18'), findsOneWidget);
  });
}
