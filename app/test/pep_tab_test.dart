import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/api/models.dart';
import 'package:tracka/screens/pep_screen.dart';

Week _week(int matchIn) {
  final start = DateTime(2026, 11, 23);
  const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  return Week.fromJson({
    'start': '2026-11-23',
    'today': '2026-11-27',
    'days': [
      for (var i = 0; i < 7; i++)
        {
          'date': start.add(Duration(days: i)).toIso8601String().substring(0, 10),
          'weekday': names[i],
          'isToday': i == 4,
          'matchDay': i == 4 + matchIn,
          'items': <Map<String, dynamic>>[],
        },
    ],
  });
}

void main() {
  test('the Pep tab greeting knows the next match', () {
    expect(PepScreen.weekLine(_week(2)), 'You have a match on Sunday. Today is your last big training day before it.');
    expect(PepScreen.weekLine(_week(1)), 'You have a match tomorrow. Keep today light.');
    expect(PepScreen.weekLine(_week(0)), 'Match day today. Warm up well and enjoy it.');
    expect(PepScreen.weekLine(_week(9)), 'No match this week. A good week to build.');
  });

  test('focus reads bands and trends, never a score', () {
    final f = FocusState.fromJson({
      'focus': [
        {'id': 'scanning', 'name': 'Looking around', 'group': 'Reading the game', 'band': 'strong', 'trend': 'growing', 'state': 'measured'},
      ],
      'growing': <Map<String, dynamic>>[],
      'nextTest': {'drill': 'sprint_30m', 'name': 'Speed test: 30 m sprint', 'date': '2026-11-30'},
      'bests': [
        {'metric': 'sprint_30m_s', 'label': '30 m sprint', 'value': '4.60', 'unit': 's'},
      ],
    });
    expect(f.focus.single.trendWords, 'Growing');
    expect(f.nextTest!.drill, 'sprint_30m');
    expect(f.bests.single.value, '4.60');
  });
}
