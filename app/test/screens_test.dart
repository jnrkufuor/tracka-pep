// Every main screen at every phone width the design is checked at (360, 390,
// 412, 430 px), with normal and extra-large text, and with higher contrast.
// A layout that doesn't fit throws "A RenderFlex overflowed", which fails here,
// so a screen that breaks on a small phone is caught before a player sees it.
//
// The API is faked with fixtures (MockClient), so these run in milliseconds.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tracka/api/api_client.dart';
import 'package:tracka/api/cache.dart';
import 'package:tracka/main.dart' show highContrastFilter;
import 'package:tracka/screens/auth_screen.dart';
import 'package:tracka/screens/card_screens.dart';
import 'package:tracka/screens/feed_screens.dart';
import 'package:tracka/screens/guardian_screens.dart';
import 'package:tracka/screens/home_screen.dart';
import 'package:tracka/screens/notifications_screen.dart';
import 'package:tracka/screens/pep_screen.dart';
import 'package:tracka/screens/review_screens.dart';
import 'package:tracka/screens/settings_screen.dart';
import 'package:tracka/screens/shell.dart';
import 'package:tracka/screens/training_screens.dart';
import 'package:tracka/screens/uploads_screen.dart';
import 'package:tracka/screens/videos_screen.dart';
import 'package:tracka/state/app_state.dart';
import 'package:tracka/state/net.dart';
import 'package:tracka/theme/theme.dart';

final _today = DateTime.now();
String _d(int add) => _today.add(Duration(days: add)).toIso8601String().substring(0, 10);

final Map<String, Object> fixtures = {
  '/v1/me': {
    'id': 'u1',
    'email': 'kwame@example.com',
    'profile': {
      'displayName': 'Kwame Asante',
      'birthDate': '2010-03-14',
      'age': 16,
      'sex': 'male',
      'positions': ['CM', 'CDM'],
      'region': 'Ashanti',
      'foot': 'right',
      'heightM': 1.74,
      'shirtName': 'K. ASANTE',
      'shirtNumber': 8,
      'level': 'club',
      'goal': 'academy',
      'style': 'Playmaker',
      'weakFoot': 3,
      'town': 'Kumasi',
      'guardianConsent': true,
    },
    'settings': {'mainColour': 'volt'},
    'profileComplete': true,
    'needsGuardian': false,
    'guardianStatus': 'approved',
  },
  '/v1/meta': {
    'positions': ['GK', 'CB', 'CM', 'ST'],
    'regions': ['Ashanti', 'Greater Accra'],
    'drills': {
      'sprint_30m': {'label': '30 m sprint', 'how': 'Flat out from a standing start.', 'needs_calibration': true, 'cones_m': [[0, 0], [30, 0]]},
    },
    'textsLive': false,
    'guardianSelfConfirm': true,
  },
  '/v1/videos': [
    {'id': 'v1', 'title': 'Sunday match, 2nd half', 'clipType': 'match', 'createdAt': '2026-11-22T15:00:00Z', 'status': 'READY', 'reviewNote': 'You looked around more. 3 tips inside.'},
    {'id': 'v2', 'title': 'Weak-foot wall passes', 'clipType': 'drill', 'createdAt': '2026-11-20T15:00:00Z', 'status': 'FAILED'},
  ],
  '/v1/coach': {
    'clipsUploaded': 2,
    'clipsAnalysed': 1,
    'skillAreas': {
      'ageGroup': 'U17',
      'comparedWith': 'U17 players',
      'measured': 1,
      'groups': [
        {
          'name': 'Reading the game',
          'items': [
            {'id': 'scanning', 'name': 'Looking around before the ball comes', 'key': true, 'state': 'measured', 'band': 'strong', 'average': '4.2 head checks a minute', 'confidence': 'high', 'trend': 'growing', 'measurements': 4},
            {'id': 'finding_space', 'name': 'Finding space between the lines', 'key': true, 'state': 'coming_later'},
          ],
        },
      ],
    },
  },
  '/v1/week': {
    'start': _d(-_today.weekday + 1),
    'today': _d(0),
    'sessionsPerWeek': 3,
    'days': [
      for (var i = 0; i < 7; i++)
        {
          'date': _d(i - _today.weekday + 1),
          'weekday': const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][i],
          'isToday': i == _today.weekday - 1,
          'matchDay': i == 5,
          'items': [
            if (i == _today.weekday - 1) {'id': 'pep-x', 'kind': 'pep', 'title': 'Scanning rondo and turns', 'status': 'planned', 'durationMin': 30, 'mode': 'normal'},
            if (i == 5) {'id': 'e1', 'kind': 'match', 'title': 'Saturday 5-a-side', 'status': 'planned', 'time': '16:00'},
          ],
        },
    ],
  },
  '/v1/health': {'status': 'fine'},
  '/v1/progress': {
    'tests': [
      {'label': '30 m sprint', 'unit': 's', 'first': 4.9, 'latest': 4.6, 'change': 0.3, 'better': true, 'weeks': 4, 'line': 'Over a 30 m race, that puts you about 2 metres ahead of where you were.'},
    ],
    'streak': {'weeks': 6, 'best': 9, 'thisWeek': {'done': 1, 'planned': 3}},
    'readiness': {'done': 3, 'total': 5, 'next': 'A full-match clip', 'steps': [for (var i = 0; i < 5; i++) {'name': 'Step $i', 'done': i < 3}]},
  },
  '/v1/challenges': {
    'thisWeek': {
      'id': 'wall_passes_weak',
      'name': 'Weak-foot wall passes in 30 seconds',
      'group': 'Skills',
      'how': 'Weaker foot only. Every clean pass back to you counts.',
      'drill': 'wall_passes',
      'endsOn': _d(3),
      'steps': ['Stand 2 big steps from a wall', 'Phone 3 to 4 steps back, on its side', 'Go when the timer beeps'],
      'best': '19',
      'band': 'Above average',
      'tries': 2,
      'playersIn': 312,
    },
    'fun': [
      {'id': 'crossbar', 'name': 'Crossbar challenge', 'how': 'Hit the bar from the edge of the box.', 'playersIn': 1400},
    ],
    'past': [
      {'id': 'shuttle', 'name': '5-10-5 shuttle', 'group': 'Body', 'best': '5.3 s', 'band': 'Above average'},
    ],
    'comparedWith': 'U17 players',
  },
  '/v1/feed': {
    'posts': [
      {
        'id': 'p1',
        'author': {'id': 'u2', 'shirtName': 'A. MENSAH', 'initials': 'AM', 'position': 'CM', 'ageGroup': 'U17', 'region': 'Greater Accra'},
        'videoUrl': 'https://example.com/clip.mp4',
        'caption': 'Weak-foot volley at the end of training. Took me weeks.',
        'challenge': 'Crossbar challenge',
        'respect': 214,
      },
    ],
    'canPost': true,
  },
  '/v1/focus': {
    'focus': [
      {'id': 'scanning', 'name': 'Looking around before the ball comes', 'group': 'Reading the game', 'band': 'strong', 'trend': 'growing', 'state': 'measured'},
      {'id': 'weak_foot', 'name': 'Weak foot', 'group': 'Skills', 'trend': 'new', 'state': 'not_seen'},
    ],
    'growing': [
      {'id': 'scanning', 'name': 'Looking around before the ball comes', 'group': 'Reading the game', 'band': 'strong', 'trend': 'growing', 'state': 'measured'},
    ],
    'nextTest': {'drill': 'sprint_30m', 'name': 'Speed test: 30 m sprint', 'date': _d(2)},
    'bests': [
      {'metric': 'sprint_30m_s', 'label': '30 m sprint', 'value': '4.60', 'unit': 's'},
    ],
  },
  '/v1/tips': [
    {
      'area': 'scanning',
      'areaName': 'Looking around before the ball comes',
      'group': 'Reading the game',
      'title': 'Look before you get the ball',
      'text': "Twice you turned into a player you hadn't seen. A quick look over your shoulder shows you where the space is.",
      'atSeconds': 760,
      'drill': {'id': 'scanning_rondo', 'name': 'Scanning rondo', 'minutes': 12, 'how': '3 against 1.', 'needs': ['ball', 'friends']},
      'videoId': 'v1',
      'videoTitle': 'Sunday match, 2nd half',
    },
  ],
  '/v1/card': {
    'link': {'on': true, 'url': 'https://tracka.app/c/abc123def4'},
    'show': {'bests': true, 'skills': true, 'clips': true},
    'portfolio': ['v1'],
    'canShare': true,
    'card': {
      'shirtName': 'K. ASANTE',
      'shirtNumber': 8,
      'initials': 'KA',
      'positions': ['CM'],
      'positionName': 'Central midfielder',
      'foot': 'right',
      'region': 'Ashanti',
      'level': 'Local club',
      'ageGroup': 'U17',
      'style': 'Playmaker',
      'pepSees': ['Looking around before the ball comes', 'Passing forward'],
      'bests': [
        {'label': '30 m sprint', 'value': '4.60', 'unit': 's'},
        {'label': 'Juggles in a row', 'value': '20', 'unit': ''},
        {'label': '5-10-5 shuttle', 'value': '5.30', 'unit': 's'},
      ],
      'skills': [
        {'name': 'Looking around before the ball comes', 'band': 'Strong', 'average': '4.2 head checks a minute', 'confidence': 'high', 'trend': 'growing'},
      ],
      'comparedWith': 'U17 players',
      'clips': <Object>[],
      'under18': true,
    },
  },
  '/v1/pitches': {
    'region': 'Ashanti',
    'pitches': [
      {'id': 'x1', 'name': 'Bantama community field', 'surface': 'grass', 'size': 'full size', 'town': 'Kumasi', 'confirmations': 6, 'confirmed': true},
      {'id': 'x2', 'name': 'Suame park pitch', 'surface': 'dirt', 'size': '7-a-side', 'town': 'Kumasi', 'needs': 2},
    ],
  },
  '/v1/notifications': {
    'items': [
      {'id': 'n1', 'kind': 'reviews', 'group': 'pep', 'title': "Pep's read on Sunday match, 2nd half is ready", 'body': '3 tips, starting at 12:40', 'createdAt': DateTime.now().toUtc().toIso8601String()},
      {'id': 'n2', 'kind': 'respect', 'group': 'activity', 'title': 'Ama and 3 others gave you respect', 'body': 'On your clip', 'createdAt': '2026-11-20T10:00:00Z', 'read': true},
    ],
    'unread': 1,
  },
  '/v1/guardian': {
    'needed': true,
    'status': 'approved',
    'name': 'Ama',
    'phone': '+233 24 ••• 4567',
    'permissions': {'account': true, 'post': true, 'shareCard': true, 'search': false},
    'requests': <Object>[],
  },
};

/// A brand-new player: no clips, no tests yet (the canvas's "day one" boards).
const dayOneFixtures = <String, Object>{'/v1/videos': <Object>[], '/v1/progress': <String, Object>{}, '/v1/focus': <String, Object>{}};

http.Client fakeServer({Map<String, Object> overrides = const {}}) => MockClient((req) async {
      final path = req.url.path;
      final body = overrides[path] ?? fixtures[path] ?? (path.startsWith('/v1/') ? <String, Object>{} : null);
      if (body == null) return http.Response('not found', 404);
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });

Future<AppState> readyState({bool dayOne = false}) async {
  final api = ApiClient(client: fakeServer(overrides: dayOne ? dayOneFixtures : const {}), cache: MemoryCache());
  final s = AppState(api: api, net: FakeNet());
  s.me = await api.me();
  s.meta = await api.meta();
  s.stage = Stage.ready;
  await s.refresh();
  return s;
}

final screens = <String, Widget Function()>{
  'Welcome': () => const WelcomeScreen(),
  'Sign up: phone': () => const PhoneScreen(),
  'Sign up: email': () => const AuthScreen(signUp: true),
  'Log in': () => const AuthScreen(signUp: false),
  'Tabs: Home': () => const Shell(),
  'Tabs: Pitchside': () => const Shell(initialTab: 1),
  'Tabs: Pep': () => const Shell(initialTab: 2),
  'Tabs: Me': () => const Shell(initialTab: 3),
  'Customise home': () => const CustomiseHomeScreen(),
  'Focus and tests': () => const FocusScreen(),
  'Reviews': () => const ReviewsScreen(),
  'Tips': () => const TipsScreen(),
  'Share your card': () => const ShareCardScreen(),
  'Privacy': () => const PrivacyScreen(),
  'Settings': () => const SettingsScreen(),
  'Accessibility': () => const AccessibilityScreen(),
  'Your data': () => const DataScreen(),
  'Help': () => const HelpScreen(),
  'Notifications': () => const NotificationsScreen(),
  'Notification settings': () => const NotificationSettingsScreen(),
  'Your guardian': () => const GuardianScreen(),
  'Uploads': () => const UploadsScreen(),
  'Your clips': () => const VideosScreen(),
  'Search players': () => const SearchScreen(),
  'Schedule': () => const WeekScreen(),
  'Sessions': () => const SessionsScreen(),
  'Health': () => const HealthScreen(),
};

void main() {
  for (final width in [360.0, 390.0, 412.0, 430.0]) {
    for (final (label, textScale, contrast) in [('normal text', 1.0, false), ('XL text', 1.3, false), ('higher contrast', 1.0, true)]) {
      testWidgets('every main screen fits at $width px, $label', (tester) async {
        tester.view.physicalSize = Size(width * 3, 800 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final s = await tester.runAsync(readyState);
        for (final MapEntry(key: name, value: make) in screens.entries) {
          // Keep the full report of the first layout error, so a failure names the
          // widget and the file:line that overflowed.
          final errors = <FlutterErrorDetails>[];
          final previous = FlutterError.onError;
          FlutterError.onError = errors.add;
          await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
            value: s!,
            child: MaterialApp(
              theme: trackaTheme(),
              builder: (context, child) {
                Widget app = MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!);
                if (contrast) app = ColorFiltered(colorFilter: highContrastFilter, child: app);
                return app;
              },
              home: make(),
            ),
          ));
          // Let the fake API answer and the fades finish (pumpAndSettle would wait
          // forever on the loading skeleton's pulse).
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          FlutterError.onError = previous;
          expect(errors.isEmpty ? null : errors.first.toString(), isNull, reason: '$name at $width px, $label');
          expect(tester.takeException(), isNull, reason: '$name at $width px, $label');
          // Fitting isn't enough: a part that grows too big hides the rest without
          // any error. The tab bar must stay a bar at the bottom of the screen.
          if (name.startsWith('Tabs')) {
            final bar = tester.getRect(find.byType(TabBarT));
            expect(bar.height, lessThan(140), reason: 'tab bar height at $width px, $label');
            expect(bar.bottom, closeTo(800, 1), reason: 'tab bar sits at the bottom');
          }
        }
        await tester.pumpWidget(const SizedBox());
        s!.dispose();
      });
    }
  }
}
