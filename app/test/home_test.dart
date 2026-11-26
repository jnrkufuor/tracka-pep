import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/api/models.dart';
import 'package:tracka/screens/home_screen.dart';

void main() {
  test('your road is always first; the rest follows your choice or Pep\'s', () {
    expect(homeCardsFor(AppSettings(), 'academy').take(3), ['road', 'week', 'noticed']);
    expect(homeCardsFor(AppSettings(), 'fun'), contains('pitchside'));
    expect(homeCardsFor(AppSettings(homeCards: ['clips', 'road', 'nope']), null), ['road', 'clips']);
  });

  test('progress reads tests, streak and readiness', () {
    final p = ProgressState.fromJson({
      'tests': [
        {'label': '30 m sprint', 'unit': 's', 'first': 4.9, 'latest': 4.6, 'change': 0.3, 'better': true, 'weeks': 4, 'line': 'About 2 metres ahead.'},
      ],
      'streak': {'weeks': 6, 'best': 9, 'thisWeek': {'done': 2, 'planned': 3}},
      'readiness': {'done': 3, 'total': 5, 'next': 'A full-match clip', 'steps': [{'name': 'Baseline tests', 'done': true}]},
    });
    expect(p.tests.single.better, isTrue);
    expect(p.streakWeeks, 6);
    expect(p.readyNext, 'A full-match clip');
  });
}
