import 'package:flutter_test/flutter_test.dart';
import 'package:tracka/api/models.dart';

void main() {
  test('a feed post carries the shirt name and nothing from Pep', () {
    final p = FeedPost.fromJson({
      'id': 'p1',
      'author': {'id': 'u1', 'shirtName': 'A. MENSAH', 'initials': 'AM', 'position': 'CM', 'ageGroup': 'U17', 'region': 'Ashanti'},
      'videoUrl': 'https://x/clip.mp4',
      'caption': 'Took me weeks.',
      'respect': 214,
      'respected': false,
    });
    expect(p.author.line, 'CM · U17 · Ashanti');
    expect(p.respect, 214);
  });

  test('challenges read this week, fun ones and past results', () {
    final c = ChallengesState.fromJson({
      'thisWeek': {
        'id': 'wall_passes_weak',
        'name': 'Weak-foot wall passes in 30 seconds',
        'group': 'Skills',
        'how': 'Weaker foot only.',
        'drill': 'wall_passes',
        'endsOn': '2026-11-29',
        'steps': ['Stand 2 big steps from a wall'],
        'best': '19',
        'band': 'Above average',
        'tries': 2,
        'playersIn': 312,
      },
      'fun': [
        {'id': 'crossbar', 'name': 'Crossbar challenge', 'how': 'Hit the bar.', 'playersIn': 1400},
      ],
      'past': [
        {'id': 'shuttle', 'name': '5-10-5 shuttle', 'group': 'Body', 'best': '5.3 s', 'band': 'Above average'},
      ],
      'comparedWith': 'U17 players',
    });
    expect(c.thisWeek.playersIn, 312);
    expect(c.fun.single.playersIn, 1400);
    expect(c.past.single.best, '5.3 s');
  });

  test('a pitch says how many more confirmations it needs', () {
    final p = Pitch.fromJson({'id': 'x', 'name': 'Suame park pitch', 'surface': 'dirt', 'size': '7-a-side', 'town': 'Kumasi', 'needs': 2});
    expect(p.confirmed, isFalse);
    expect(p.needs, 2);
  });
}
