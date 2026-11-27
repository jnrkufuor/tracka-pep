import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/board.dart';
import '../widgets/brand.dart';
import '../widgets/ds.dart';
import '../widgets/pep.dart';
import '../widgets/pitch_picker.dart';
import '../widgets/profile_fields.dart';
import 'auth_screen.dart' show PitchPainter;

/// Onboarding v2 (canvas page 1): Meet Pep, then five steps, then "All set".
///
///   1 Personal details   name, shirt name and number, date of birth, who you
///                        play with; under 18: your guardian's phone
///   2 Location           region (shown), town (private), how Pep talks to you
///   3 Your journey       your level now and your goal; picks the path below
///   4 Player profile     positions on a pitch, stronger and weaker foot, height, style
///   5 Schedule           team training, match day, time for extra training, kit
///                        (casual path: how often you play, what would help)
///
/// "Just looking around" skips 4 and 5. Nothing pushes a first clip: the last
/// page is the player's road, then Pep shows them around (or they explore).
/// Everything is saved with one PATCH /v1/me, plus their football as events
/// (POST /v1/events) so Pep can plan the week around it.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.startPage = 0});

  /// Which step to open on (0 = Meet Pep). Only the screen pictures in
  /// test/shots_test.dart use another value.
  final int startPage;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Page { meet, personal, location, journey, profile, schedule, casual, ready }

class _OnboardingScreenState extends State<OnboardingScreen> {
  final d = ProfileDraft();
  late _Page page = _Page.values[widget.startPage.clamp(0, _Page.values.length - 1)];
  bool busy = false;

  // Location
  String voice = 'coach';
  // Schedule (team players)
  final Set<int> teamDays = {};
  bool noTeam = false;
  String matchDay = 'sat';
  String extra = '2-3h';
  final Set<String> kit = {'ball'};
  // Casual setup
  String often = 'weekly';
  final Set<int> playDays = {5, 6};
  final Set<String> games = {'5-a-side'};
  final Set<String> help = {'pitches', 'games'};
  bool _eventsSaved = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().me?.profile;
    if (p != null && p.displayName.isNotEmpty) {
      final parts = p.displayName.split(' ');
      d
        ..firstName = parts.first
        ..lastName = parts.skip(1).join(' ')
        ..birthDate = p.birthDate
        ..sex = p.sex
        ..region = p.region
        ..positionOrder = [...p.positions]
        ..foot = p.foot
        ..heightM = p.heightM;
    }
  }

  List<_Page> get flow => [
        _Page.meet,
        _Page.personal,
        _Page.location,
        _Page.journey,
        if (d.goal == 'fun') _Page.casual,
        if (d.goal != 'fun' && d.goal != 'looking') ...[_Page.profile, _Page.schedule],
        _Page.ready,
      ];

  /// "Step 2 of 5" (Meet Pep and All set aren't counted).
  (int, int) get stepOf {
    final steps = flow.where((p) => p != _Page.meet && p != _Page.ready).toList();
    return (steps.indexOf(page) + 1, steps.length);
  }

  bool get canContinue => switch (page) {
        _Page.meet || _Page.ready || _Page.schedule || _Page.casual => true,
        _Page.personal => d.firstName.trim().isNotEmpty &&
            d.lastName.trim().isNotEmpty &&
            d.birthDate != null &&
            d.sex != null &&
            (!d.minor || RegExp(r'\d').allMatches(d.guardianPhone).length >= 7),
        _Page.location => d.region != null,
        _Page.journey => d.level != null && d.goal != null,
        _Page.profile => d.positionOrder.isNotEmpty && d.foot != null,
      };

  void _go(int delta) {
    final i = flow.indexOf(page) + delta;
    if (i < 0 || i >= flow.length) return;
    setState(() => page = flow[i]);
  }

  int get _sessionsPerWeek => switch (extra) { 'none' => 0, '1h' => 2, 'more' => 4, _ => 3 };

  /// Save everything, then show "All set". Events are created once.
  Future<void> _save() async {
    final s = context.read<AppState>();
    setState(() => busy = true);
    try {
      final casual = d.goal == 'fun' || d.goal == 'looking';
      await s.saveProfile({
        ...d.toJsonV2(),
        if (d.goal == 'fun') 'casual': {'often': often, 'games': games.toList(), 'help': help.toList()},
        'settings': {
          'pepVoice': voice,
          if (!casual) 'sessionsPerWeek': _sessionsPerWeek,
          if (!casual) 'kit': kit.toList(),
          if (d.goal == 'fun') 'sessionsPerWeek': help.contains('fit') ? 1 : 0,
        },
      }, finish: false);
      if (d.minor && d.guardianPhone.trim().isNotEmpty && s.me?.guardianStatus == 'none') {
        // Texts the guardian a link to approve (a placeholder outbox until SMS is live).
        try {
          await s.api.setGuardian(phone: d.guardianPhone, relation: d.guardianRelation);
        } catch (_) {
          // Not fatal: they can send it again from the waiting screen.
        }
      }
      if (!_eventsSaved) {
        if (d.goal == 'fun' && playDays.isNotEmpty) {
          await s.api.addEvent({'kind': 'game', 'weekdays': playDays.toList()..sort()});
        } else if (!casual) {
          if (!noTeam && teamDays.isNotEmpty) await s.api.addEvent({'kind': 'team', 'weekdays': teamDays.toList()..sort()});
          final m = switch (matchDay) { 'sat' => [5], 'sun' => [6], _ => <int>[] };
          if (!noTeam && m.isNotEmpty) await s.api.addEvent({'kind': 'match', 'weekdays': m});
        }
        _eventsSaved = true;
      }
      if (mounted) setState(() => page = _Page.ready);
    } catch (e) {
      if (mounted) showToast(context, "Couldn't save that", detail: '$e', ok: false, aboveTabs: false);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _continue() {
    final next = flow.indexOf(page) + 1;
    if (flow[next] == _Page.ready) {
      _save();
    } else {
      _go(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (n, total) = stepOf;
    final showSteps = page != _Page.meet && page != _Page.ready;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          if (showSteps)
            Padding(
              // Canvas: round back button, one bar per step, "Step 2 of 5".
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(children: [
                Semantics(
                  button: true,
                  label: 'Back',
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: () => _go(-1),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: Tk.field, shape: BoxShape.circle),
                      child: const TIcon('back', size: 16, color: Tk.ink),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Row(children: [
                    for (var i = 1; i <= total; i++) ...[
                      if (i > 1) const SizedBox(width: 4),
                      Expanded(
                        child: AnimatedContainer(
                          duration: Motion.of(context, Motion.fill),
                          height: 5,
                          decoration: BoxDecoration(color: i <= n ? context.accent.main : const Color(0xFF262626), borderRadius: BorderRadius.circular(9)),
                        ),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(width: 14),
                Text('Step $n of $total', style: const TextStyle(fontSize: 12, color: Color(0xFFC2C6BA), fontWeight: FontWeight.w600)),
              ]),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.select),
              child: KeyedSubtree(key: ValueKey(page), child: _body()),
            ),
          ),
          if (page != _Page.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(children: [
                BCta(busy ? 'Saving…' : (page == _Page.meet ? "Let's go" : 'Continue'), onTap: canContinue && !busy ? _continue : null),
                if (page == _Page.schedule)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            teamDays.clear();
                            noTeam = true;
                            _save();
                          },
                    child: const Text("Skip, I'll set my week later"),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _body() => switch (page) {
        _Page.meet => _meet(),
        _Page.personal => _personal(),
        _Page.location => _location(),
        _Page.journey => _journey(),
        _Page.profile => _profile(),
        _Page.schedule => _schedule(),
        _Page.casual => _casual(),
        _Page.ready => _ready(),
      };

  Widget _scroll(String title, String? sub, List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        children: [
          // The step's name above its question (canvas: "Personal details").
          if (_eyebrow != null) ...[
            Text(_eyebrow!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.accent.main)),
            const SizedBox(height: 6),
          ],
          EnterFade(child: Text(title, style: Theme.of(context).textTheme.headlineLarge)),
          if (sub != null) ...[const SizedBox(height: 6), Text(sub, style: const TextStyle(fontSize: 14, color: Tk.muted))],
          const SizedBox(height: 22),
          ...children,
        ],
      );

  String? get _eyebrow => switch (page) {
        _Page.personal => 'Personal details',
        _Page.location => 'Location',
        _Page.journey => 'Your journey',
        _Page.profile => 'Player profile',
        _Page.schedule => 'Schedule',
        _Page.casual => 'How you play',
        _ => null,
      };

  Widget _label(String t, {String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Row(children: [
          Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.lab)),
          if (hint != null) Flexible(child: Text(' · $hint', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.lab))),
        ]),
      );

  // ───────────────────────────── Meet Pep

  /// Meet Pep (canvas: Meet Pep): Pep big and alone at the top, breathing,
  /// then what he does in three lines.
  Widget _meet() {
    Widget row(String ic, String t, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            IconTile(icon: ic, color: Tk.pep, background: Tk.pepTile, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
                Text(sub, style: const TextStyle(fontSize: 13, color: Tk.muted)),
              ]),
            ),
          ]),
        );
    final h = MediaQuery.sizeOf(context).height;
    final top = (h * 0.42).clamp(220.0, 400.0); // the board's 430 on an 844 phone, less on short ones
    return ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
      SizedBox(
        height: top,
        child: Center(child: EnterFade(child: PepFace(PepMood.justHere, size: (top * 0.42).clamp(110.0, 170.0)))),
      ),
      const Center(child: Text('YOUR COACH', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tk.pep, letterSpacing: 0.8))),
      const SizedBox(height: 6),
      Center(child: Text('Meet Pep.', style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 36))),
      const SizedBox(height: 24),
      row('clip', 'I watch your clips', 'And show you what to work on'),
      row('calendar', 'I plan your week', 'Around your team and your time'),
      row('chart', 'I track how you grow', 'With real tests, not guesses'),
    ]);
  }

  // ───────────────────────────── 1 · Personal details

  Widget _personal() {
    final age = d.age;
    final group = age == null ? null : age < 13 ? 'U13' : age < 15 ? 'U15' : age < 17 ? 'U17' : age < 20 ? 'U20' : 'Adult';
    return _scroll('Tell us about you', null, [
      _label('Full name', hint: 'private'),
      Row(children: [
        Expanded(
          child: TextFormField(
            initialValue: d.firstName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'First name'),
            onChanged: (v) => setState(() => d.firstName = v),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            initialValue: d.lastName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Last name'),
            onChanged: (v) => setState(() => d.lastName = v),
          ),
        ),
      ]),
      const SizedBox(height: 18),
      _label('Name on your shirt'),
      Row(children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            key: ValueKey(d.suggestedShirtName),
            initialValue: d.shirtName.isEmpty ? d.suggestedShirtName : d.shirtName,
            textCapitalization: TextCapitalization.characters,
            maxLength: 20,
            decoration: const InputDecoration(labelText: 'Shirt name', counterText: ''),
            onChanged: (v) => d.shirtName = v,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            initialValue: d.shirtNumber?.toString() ?? '',
            keyboardType: TextInputType.number,
            maxLength: 2,
            decoration: const InputDecoration(labelText: 'No.', counterText: ''),
            onChanged: (v) {
              final x = int.tryParse(v);
              d.shirtNumber = x != null && x >= 1 && x <= 99 ? x : null;
            },
          ),
        ),
      ]),
      const SizedBox(height: 18),
      _label('Date of birth'),
      BirthDateField(value: d.birthDate, onChanged: (v) => setState(() => d.birthDate = v)),
      if (group != null) ...[
        const SizedBox(height: 8),
        Text("You're $age · $group age group", style: TextStyle(fontSize: 13, color: context.accent.main, fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 10),
      const PepNote(
        mood: PepMood.listening,
        title: 'Why your real age matters',
        child: Text('I compare you with players your age, not adults. Scouts need it to be accurate, so use your real date of birth.'),
      ),
      const SizedBox(height: 18),
      _label('You play in'),
      SingleChips<String>(
        options: const {'male': "Boys' or men's football", 'female': "Girls' or women's football"},
        value: d.sex ?? '',
        onChanged: (v) => setState(() => d.sex = v),
        scroll: false,
      ),
      if (d.minor && d.birthDate != null) ...[
        const SizedBox(height: 22),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Under 18? A parent or guardian OKs your account',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
            const SizedBox(height: 4),
            const Text("We'll text them a link to say yes. They decide who can see you, and your account stays private until then.",
                style: TextStyle(fontSize: 13, color: Tk.muted)),
            const SizedBox(height: 14),
            SingleChips<String>(
              options: const {'parent': 'Parent', 'guardian': 'Guardian', 'coach': 'Coach'},
              value: d.guardianRelation,
              onChanged: (v) => setState(() => d.guardianRelation = v),
              scroll: false,
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: d.guardianPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Their phone number', prefixText: '+233  '),
              onChanged: (v) => setState(() => d.guardianPhone = v),
            ),
            const SizedBox(height: 6),
            if (context.read<AppState>().meta?.guardianSelfConfirm ?? true) CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: d.guardianConsent,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('They have already said yes', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Until approval texts are switched on, tick this once they agree.',
                  style: TextStyle(fontSize: 12.5, color: Tk.faint)),
              onChanged: (v) => setState(() => d.guardianConsent = v ?? false),
            ),
          ]),
        ),
      ],
    ]);
  }

  // ───────────────────────────── 2 · Location

  Widget _location() {
    final regions = context.watch<AppState>().meta?.regions ?? const <String>[];
    return _scroll('Where are you based?', null, [
      _label('Region', hint: 'others see this'),
      RegionPicker(regions: regions, value: d.region, onChanged: (v) => setState(() => d.region = v)),
      const SizedBox(height: 14),
      _label('Town', hint: 'private'),
      TextFormField(
        initialValue: d.town,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Town', hintText: 'Kumasi'),
        onChanged: (v) => d.town = v,
      ),
      const SizedBox(height: 22),
      const Padding(
        padding: EdgeInsets.only(top: 4, bottom: 8),
        child: Row(children: [
          PepFace(PepMood.listening, size: 18),
          SizedBox(width: 8),
          Text('How should Pep talk to you?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.lab)),
        ]),
      ),
      // Two cards with how each one sounds (canvas: Location).
      for (final (k, t, q) in const [
        ('street', 'Street talk', '"Charlie, you dey check your shoulder well!"'),
        ('coach', 'Coach talk', '"Good scanning before you received the ball."'),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            inMutuallyExclusiveGroup: true,
            checked: voice == k,
            button: true,
            label: '$t. $q',
            excludeSemantics: true,
            child: Pressable(
              onTap: () => setState(() => voice = k),
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.select),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: voice == k ? context.accent.tile : const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: voice == k ? context.accent.main : const Color(0xFF222222), width: voice == k ? 1.5 : 1),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
                      const SizedBox(height: 2),
                      Text(q, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Tk.muted)),
                    ]),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: voice == k ? context.accent.main : null,
                      border: voice == k ? null : Border.all(color: const Color(0xFF3A3D36), width: 2),
                    ),
                    child: voice == k ? TIcon('check', size: 12, color: context.accent.on, stroke: 6) : null,
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // ───────────────────────────── 3 · Your journey

  static const _levels = {
    'fun': 'Just for fun',
    'amateur': 'Amateur league',
    'school': 'School team',
    'club': 'Local club',
    'academy': 'Academy',
    'pro': 'Semi-pro or pro',
  };

  static const _goals = [
    ('fun', 'users', 'Play more, have fun', 'Find games, stay fit, enjoy it'),
    ('school', 'flag', 'Make my school team', 'Get picked when trials come round'),
    ('academy', 'trophy', 'Get into an academy', 'Build a profile academies trust'),
    ('standout', 'up', 'Stand out where I play', 'More minutes, move up a level'),
    ('better', 'target', 'Just get better', 'No big target, steady progress'),
    ('looking', 'eye2', 'Just looking around', 'See what players are posting'),
  ];

  (String, String) get _mode => switch (d.goal) {
        'fun' => ('Casual mode', "I'll find pitches and games near you and keep you fit for your next match. No filming needed unless you want to."),
        'school' => ('Trial-ready', 'I learn what school coaches pick for in your position and build a plan around it.'),
        'academy' when d.level == 'academy' => ('Academy mode', "You're already in. I go deep on your position and compare you with your age group, honestly."),
        'academy' => ('Pathway mode', 'I help you build a profile academies can trust: timed tests and full-match clips.'),
        'standout' => ('Push mode', 'I compare you with players at your level and tell you straight what will get you more minutes.'),
        'better' => ('Steady mode', 'Small goals each week that fit around your football.'),
        'looking' => ('Explore mode', 'Look around Pitchside. Whenever you want a plan, tell me your goal.'),
        _ => ('', ''),
      };

  Widget _journey() {
    final a = context.accent;
    return _scroll("Where are you, and what's your goal?", null, [
      _label('Your level now'),
      SingleChips<String>(options: _levels, value: d.level ?? '', onChanged: (v) => setState(() => d.level = v), scroll: false),
      const SizedBox(height: 22),
      _label('Your goal', hint: 'you can change it anytime'),
      for (final g in _goals)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: d.goal == g.$1 ? a.main : null,
            onTap: () => setState(() => d.goal = g.$1),
            child: Semantics(
              selected: d.goal == g.$1,
              child: Row(children: [
                IconTile(icon: g.$2, color: d.goal == g.$1 ? a.main : Tk.stone, background: d.goal == g.$1 ? a.tile : Tk.stoneTile, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g.$3, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
                    Text(g.$4, style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      if (d.goal != null) ...[
        const SizedBox(height: 10),
        PepNote(mood: PepMood.excited, title: 'How Pep will coach you · ${_mode.$1}', child: Text(_mode.$2)),
      ],
    ]);
  }

  // ───────────────────────────── 4 · Player profile

  static const _styles = {
    'gk': ['Shot-stopper', 'Sweeper keeper', 'Commands the box', 'Good with my feet'],
    'cb': ['Ball-playing', 'Stopper', 'Strong in the air', 'Reads the game'],
    'fb': ['Overlapping', 'Defensive', 'Inverted', 'Wing-back'],
    'dm': ['Ball winner', 'Deep playmaker', 'Anchor'],
    'cm': ['Box to box', 'Playmaker', 'Ball winner', 'Engine'],
    'am': ['Creator', 'Shadow striker', 'Dribbler'],
    'w': ['Inside forward', 'Speed winger', 'Crosser', 'Dribbler'],
    'st': ['Poacher', 'Target forward', 'Pressing forward', 'All-round striker'],
  };

  static String _family(String pos) => switch (pos) {
        'GK' => 'gk',
        'CB' => 'cb',
        'LB' || 'RB' || 'LWB' || 'RWB' => 'fb',
        'CDM' => 'dm',
        'CM' => 'cm',
        'CAM' => 'am',
        'LM' || 'RM' || 'LW' || 'RW' => 'w',
        _ => 'st',
      };

  static const _weak = ['Hard to use', 'Simple passes', 'OK for short passes', 'Good for most things', 'Strong as my best'];

  Widget _profile() {
    final main = d.positionOrder.isEmpty ? null : d.positionOrder.first;
    final styles = main == null ? const <String>[] : [..._styles[_family(main)]!, 'Not sure'];
    return _scroll('Positions and playing style', null, [
      _label('Your positions', hint: 'up to 4'),
      PitchPicker(
        positions: d.positionOrder,
        onChanged: (v) => setState(() {
          final mainChanged = v.isEmpty || main == null || v.first != main;
          d.positionOrder = v;
          if (mainChanged) d.style = null;
        }),
      ),
      const SizedBox(height: 22),
      _label('Stronger foot'),
      SingleChips<String>(
        options: const {'left': 'Left', 'right': 'Right', 'both': 'Both'},
        value: d.foot ?? '',
        onChanged: (v) => setState(() => d.foot = v),
        scroll: false,
      ),
      const SizedBox(height: 18),
      _label('Weaker foot', hint: d.weakFoot == null ? 'tap 1 to 5' : '${d.weakFoot} · ${_weak[d.weakFoot! - 1]}'),
      SingleChips<int>(
        options: const {1: '1', 2: '2', 3: '3', 4: '4', 5: '5'},
        value: d.weakFoot ?? 0,
        onChanged: (v) => setState(() => d.weakFoot = v),
        scroll: false,
      ),
      const SizedBox(height: 18),
      _label('Height', hint: 'optional'),
      HeightField(value: d.heightM, onChanged: (v) => setState(() => d.heightM = v)),
      if (styles.isNotEmpty) ...[
        const SizedBox(height: 18),
        _label('Your style as a ${PitchPicker.nameOf(main!).toLowerCase()}'),
        SingleChips<String>(
          options: {for (final s in styles) s: s},
          value: d.style ?? '',
          onChanged: (v) => setState(() => d.style = v == 'Not sure' ? null : v),
          scroll: false,
        ),
        const SizedBox(height: 8),
        const PepNote(
          mood: PepMood.thinking,
          child: Text("This is how you see your game. After a few clips I'll give you my read too, and you can compare."),
        ),
      ],
    ]);
  }

  // ───────────────────────────── 5 · Schedule

  static const _days = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'};

  Widget _schedule() {
    final sessions = _sessionsPerWeek;
    return _scroll('Your training week', null, [
      _label('Team training'),
      MultiChips<int>(
        options: _days,
        values: noTeam ? <int>{} : teamDays,
        onChanged: (v) => setState(() {
          noTeam = false;
          teamDays
            ..clear()
            ..addAll(v);
        }),
      ),
      const SizedBox(height: 8),
      MultiChips<String>(
        options: const {'none': 'No team right now'},
        values: noTeam ? {'none'} : <String>{},
        onChanged: (v) => setState(() => noTeam = v.isNotEmpty),
      ),
      if (!noTeam) ...[
        const SizedBox(height: 20),
        _label('Matches usually on'),
        SingleChips<String>(
          options: const {'sat': 'Saturday', 'sun': 'Sunday', 'weekdays': 'Weekdays', 'unsure': 'Not sure'},
          value: matchDay,
          onChanged: (v) => setState(() => matchDay = v),
          scroll: false,
        ),
      ],
      const SizedBox(height: 20),
      _label('Time for extra training each week'),
      SingleChips<String>(
        options: const {'none': 'None', '1h': '1 hour', '2-3h': '2–3 hours', 'more': 'More'},
        value: extra,
        onChanged: (v) => setState(() => extra = v),
        scroll: false,
      ),
      const SizedBox(height: 20),
      _label("What you've got"),
      MultiChips<String>(
        options: const {'ball': 'A ball', 'wall': 'A wall', 'space': 'Space to run', 'cones': 'Cones', 'gym': 'A gym'},
        values: kit,
        onChanged: (v) => setState(() {
          kit
            ..clear()
            ..addAll(v);
        }),
      ),
      const SizedBox(height: 16),
      PepNote(
        mood: PepMood.reading,
        child: Text(
          sessions == 0
              ? 'No extra sessions for now. You can add them any time.'
              : '$sessions short sessions a week, none on match days, light the day before a match.',
        ),
      ),
    ]);
  }

  // ───────────────────────────── 5 · Casual setup

  Widget _casual() {
    return _scroll('When and where do you play?', null, [
      _label('How often'),
      SingleChips<String>(
        options: const {'most': 'Most days', 'weekly': 'Every week', 'monthly': 'A few times a month', 'whenever': 'Whenever I can'},
        value: often,
        onChanged: (v) => setState(() => often = v),
        scroll: false,
      ),
      const SizedBox(height: 20),
      _label('Usually on'),
      MultiChips<int>(
        options: _days,
        values: playDays,
        onChanged: (v) => setState(() {
          playDays
            ..clear()
            ..addAll(v);
        }),
      ),
      const SizedBox(height: 20),
      _label('What kind of games'),
      MultiChips<String>(
        options: const {
          '5-a-side': '5-a-side',
          '7-a-side': '7-a-side',
          '11-a-side': '11-a-side',
          'astro': 'Astro turf',
          'grass': 'Grass',
          'beach': 'Beach',
        },
        values: games,
        onChanged: (v) => setState(() {
          games
            ..clear()
            ..addAll(v);
        }),
      ),
      const SizedBox(height: 20),
      _label('What would help'),
      MultiChips<String>(
        options: const {
          'pitches': 'Find pitches near me',
          'games': 'Find a game to join',
          'fit': 'Stay fit between games',
          'warmups': "Warm-ups so I don't get hurt",
          'tricks': 'Learn a few tricks',
        },
        values: help,
        onChanged: (v) => setState(() {
          help
            ..clear()
            ..addAll(v);
        }),
      ),
    ]);
  }

  // ───────────────────────────── All set

  Widget _ready() {
    final s = context.read<AppState>();
    final a = context.accent;
    final age = s.me?.profile.age;
    final goal = _goals.where((g) => g.$1 == d.goal).firstOrNull;
    final here = [
      if (d.level != null) _levels[d.level],
      if (d.positionOrder.isNotEmpty) d.positionOrder.first,
      if (age != null) (age < 13 ? 'U13' : age < 15 ? 'U15' : age < 17 ? 'U17' : age < 20 ? 'U20' : 'Adult'),
    ].join(' · ');
    final h = MediaQuery.sizeOf(context).height;
    final hero = (h * 0.6).clamp(300.0, 540.0);
    Widget stop(Widget mark, String title, String sub, Color colour) => Row(children: [
          SizedBox(width: 30, child: Center(child: mark)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colour)),
              Text(sub, style: const TextStyle(fontSize: 13, color: Tk.muted)),
            ]),
          ),
        ]);
    // Canvas "All set": a pitch at the top fading to black, your road below it.
    return ListView(padding: EdgeInsets.zero, children: [
      SizedBox(
        height: hero,
        child: Stack(fit: StackFit.expand, children: [
          const CustomPaint(painter: PitchPainter()),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .4, 1],
                colors: [Color(0x4D000000), Color(0x1A000000), Color(0xFF000000)],
              ),
            ),
          ),
          const Positioned(left: 24, top: 40, child: TrackaLogo(size: 30)),
          Positioned(
            left: 24,
            right: 24,
            bottom: 8,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('All set, ${d.firstName.trim()}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: a.main)),
              const SizedBox(height: 6),
              Text(d.goal == 'fun' || d.goal == 'looking' ? 'Your game\nstarts today.' : 'Your road\nstarts today.',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 40, height: 1)),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
        child: Stack(children: [
          // The road: main colour from you, fading through grey to your gold goal.
          Positioned(
            left: 14,
            top: 20,
            bottom: 20,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, .45, .6, 1],
                  colors: [a.main, a.main, const Color(0xFF3A3D36), Tk.gold],
                ),
              ),
            ),
          ),
          Column(children: [
            stop(
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: a.main, boxShadow: [BoxShadow(color: a.main.withValues(alpha: .18), spreadRadius: 6)]),
                child: TIcon('pin', size: 14, color: a.on),
              ),
              "You're here",
              here.isEmpty ? 'Starting out' : here,
              a.main,
            ),
            const SizedBox(height: 24),
            stop(
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Tk.bg, border: Border.all(color: a.main, width: 2)),
                child: Text('1', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: a.main)),
              ),
              d.goal == 'fun' ? 'Keep playing' : d.goal == 'looking' ? 'Look around' : 'Put in the work',
              'Grow, work, have fun',
              Tk.ink,
            ),
            const SizedBox(height: 24),
            stop(
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Tk.gold, borderRadius: BorderRadius.circular(9)),
                child: const TIcon('flag', size: 14, color: Colors.black),
              ),
              goal?.$3 ?? 'Find your goal',
              'Your goal',
              Tk.gold,
            ),
          ]),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(children: [
          BCta('Show me around', onTap: () async {
            await showHowPepWorks(context);
            s.startTour();
            await s.finishOnboarding();
          }),
          TextButton(onPressed: s.finishOnboarding, child: const Text("I'll explore myself")),
        ]),
      ),
    ]);
  }
}

/// "How Pep works" (canvas: Pep › Before you start). Shown once, before the
/// player's first day: what Pep is, where numbers come from, that Pep is not
/// a doctor, that their coach comes first, and that clips stay private.
Future<void> showHowPepWorks(BuildContext context) {
  Widget row(String ic, Color c, Color bg, String t, String d) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(icon: ic, color: c, background: bg, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
              const SizedBox(height: 2),
              Text(d, style: const TextStyle(fontSize: 13, height: 1.45, color: Tk.muted)),
            ]),
          ),
        ]),
      );
  return showEditSheet<void>(
    context,
    title: 'How Pep works',
    child: Builder(
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row('pep', Tk.pep, Tk.pepTile, 'Pep is an AI coach', 'It can get things wrong or miss things in a clip. Its tips are a guide, not orders.'),
        row('chart', ctx.accent.main, ctx.accent.tile, 'Numbers come from your clips',
            'Times and counts are measured from video, not guessed. A far or shaky camera can throw them off.'),
        row('hurt', Tk.gold, Tk.goldTile, 'Pep is not a doctor',
            'It never diagnoses injuries or gives food plans. If something hurts, stop and see a doctor or physio.'),
        row('users', Tk.stone, Tk.stoneTile, 'Your coach comes first', 'Check big changes to your training with your coach or a trusted adult.'),
        row('lock', Tk.stone, Tk.stoneTile, 'Your clips stay private', 'Nothing is shared unless you choose to. Under 18? Your guardian decides too.'),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Got it'))),
      ]),
    ),
  );
}
