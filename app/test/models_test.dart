import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/api/models.dart';
import 'package:tracka/theme/theme.dart';
import 'package:tracka/widgets/common.dart';

void main() {
  test('parses a video with its analysis', () {
    final v = Video.fromJson({
      'id': 'v1',
      'title': '',
      'clipType': 'drill',
      'createdAt': '2026-11-16T20:00:00+00:00',
      'status': 'READY',
      'overallScore': 71,
      'analysis': {
        'overallScore': 71,
        'confidence': 'MEDIUM',
        'skills': [
          {'name': 'Pace', 'score': 80, 'source': 'drill', 'confidence': 'HIGH'}
        ],
        'moments': [
          {'atSeconds': 3.2, 'kind': 'GOOD', 'text': 'Top speed here'}
        ],
        'metrics': {'top_speed_ms': 7.5, 'distance_m': null},
      },
    });
    expect(v.displayTitle, 'Drill');
    expect(v.processing, isFalse);
    expect(v.analysis!.skills.single.sourceLabel, 'Timed drill');
    expect(v.analysis!.moments.single.good, isTrue);
    expect(v.analysis!.metrics['distance_m'], isNull);
  });

  test('speed respects the units setting', () {
    expect(AppSettings(units: 'kmh').speed(7.5), '27.0');
    expect(AppSettings(units: 'mph').speed(7.5), '16.8');
    expect(AppSettings().speed(null), '–');
  });

  test('coach summary parses trend pairs', () {
    final c = CoachSummary.fromJson({
      'clipsUploaded': 4,
      'clipsAnalysed': 3,
      'clipsNeeded': 3,
      'processing': 1,
      'overallScore': 64,
      'trend': [
        {'week': '2026-11-09', 'score': 60},
        {'week': '2026-11-16', 'score': 66},
      ],
    });
    expect(c.trend.last, ('2026-11-16', 66));
    expect(c.confidence, 'LOW');
  });

  testWidgets('kit number and score bar render', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: trackaTheme(),
      home: const Scaffold(body: Column(children: [KitNumber(74), ScoreBar(74), Pill('High')])),
    ));
    await tester.pumpAndSettle();
    expect(find.text('74'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
  });

  test('the week finds the next planned Pep session from today', () {
    final w = Week.fromJson({
      'start': '2026-11-23',
      'today': '2026-11-24',
      'health': {'status': 'fine'},
      'days': [
        {'date': '2026-11-23', 'weekday': 'Monday', 'items': [
          {'id': 'pep-2026-11-23', 'kind': 'pep', 'title': 'Pep session', 'status': 'planned', 'mode': 'normal'},
        ]},
        {'date': '2026-11-24', 'weekday': 'Tuesday', 'isToday': true, 'items': [
          {'id': 'e1', 'kind': 'team', 'title': 'Team training', 'status': 'planned', 'time': '16:00', 'repeats': true},
        ]},
        {'date': '2026-11-25', 'weekday': 'Wednesday', 'items': [
          {'id': 'pep-2026-11-25', 'kind': 'pep', 'title': 'Pep session', 'status': 'skipped'},
          {'id': 'pep-2026-11-26', 'kind': 'pep', 'title': 'Light session', 'status': 'planned', 'mode': 'light', 'moved': true},
        ]},
      ],
    });
    expect(w.todayDay!.items.single.isFootball, isTrue);
    final next = w.nextSession!;
    expect(next.$2.id, 'pep-2026-11-26'); // Monday is in the past, Wednesday's first is skipped
    expect(next.$2.moved, isTrue);
  });

  test('a session plan lists its steps and safety note', () {
    final p = SessionPlan.fromJson({
      'key': 'pep-2026-11-25', 'date': '2026-11-25', 'mode': 'normal', 'title': 'Pep session', 'minutes': 30,
      'focus': [{'id': 'scanning', 'name': 'Looking around before the ball comes'}],
      'steps': [{'id': 'warmup', 'name': 'Warm-up', 'minutes': 5, 'how': 'Jog.', 'needs': ['nothing']}],
      'safety': 'Stop if anything hurts.', 'status': 'planned',
    });
    expect(p.steps.single.minutes, 5);
    expect(p.focus.single, startsWith('Looking'));
  });
}
