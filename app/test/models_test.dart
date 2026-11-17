import 'package:flutter/material.dart';
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
}
