import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/board.dart';
import '../widgets/ds.dart';
import '../widgets/pep.dart';
import 'home_screen.dart' show openUpload;
import 'profile_screen.dart' show EditProfileScreen;
import 'review_screens.dart';
import 'training_screens.dart';

/// The Pep tab (canvas: Pep tab, Focus and tests, How a test works).
///
/// Pep talks to you about your week and your growth: a greeting that knows
/// your next match, shortcuts (reviews, tips, schedule, sessions, focus,
/// health), what's growing, today's training, and what's new from Pep.
/// Ratings are bands and trends, never a 0-100 score (DESIGN.md). Purple is
/// Pep's colour; your main colour is you.
class PepScreen extends StatefulWidget {
  const PepScreen({super.key});

  @override
  State<PepScreen> createState() => _PepScreenState();

  /// "You have a match on Sunday. Today is your last big training day before it."
  static String weekLine(Week? w) {
    if (w == null) return "Here's your week with Pep.";
    final today = w.days.where((d) => d.isToday).firstOrNull;
    final match = w.days.where((d) => d.matchDay && !d.date.isBefore(today?.date ?? w.today)).firstOrNull;
    if (match == null) return 'No match this week. A good week to build.';
    if (match.isToday) return 'Match day today. Warm up well and enjoy it.';
    final gap = match.date.difference(today?.date ?? w.today).inDays;
    if (gap == 1) return 'You have a match tomorrow. Keep today light.';
    if (gap == 2) return 'You have a match on ${match.weekday}. Today is your last big training day before it.';
    return 'You have a match on ${match.weekday}.';
  }

}

class _PepScreenState extends State<PepScreen> {
  FocusState? focus;
  List<ReviewTip>? tips;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    try {
      final f = await api.focus();
      if (mounted) setState(() => focus = f);
    } catch (_) {}
    try {
      final t = await api.tips();
      if (mounted) setState(() => tips = t);
    } catch (_) {}
  }

  String _greeting(String name) {
    final h = DateTime.now().hour;
    final part = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    return name.isEmpty ? '$part!' : '$part, $name!';
  }

  void _go(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _test() {
    final t = focus?.nextTest;
    _go(t == null ? const FocusScreen() : TestScreen(drill: t.drill, name: t.name));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = focus;
    final ready = s.videos.where((v) => v.status == 'READY').toList();
    final newest = ready.firstOrNull;
    final name = s.me?.profile.firstName ?? '';
    final tested = f?.bests.isNotEmpty ?? false;
    // Day one (canvas "Pep tab on day one"): a starter week, no tips yet.
    final dayOne = ready.isEmpty && !tested;
    final mood = switch (s.health?.status) {
      'pain' || 'injured' => PepMood.concerned,
      'sore' => PepMood.calm,
      _ => dayOne || newest != null ? PepMood.excited : pepIdleMood(),
    };
    // Goal "just looking around" (canvas: Pep tab without a goal): Pep offers
    // to coach you instead of showing a plan you didn't ask for.
    final looking = s.me?.profile.goal == 'looking';
    final children = looking ? _locked() : (dayOne ? _dayOne(s, name, mood) : _main(s, f, name, mood, ready, newest));
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await s.refresh();
            await _load();
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
            for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 18), c],
          ]),
        ),
      ),
    );
  }

  List<Widget> _locked() {
    Widget perk(String icon, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            IconTile(icon: icon, color: Tk.pep, background: Tk.pepTile, size: 40),
            const SizedBox(width: 14),
            Expanded(child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink))),
          ]),
        );
    return [
      const SizedBox(height: 12),
      const Center(child: PepFace(PepMood.asking, size: 96)),
      Column(children: [
        const Text('Pep', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.pep)),
        const SizedBox(height: 6),
        Text('Want me to coach you?', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 6),
        const Text("I coach players who have a goal. Pick one and here's what you get.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.45, color: Tk.muted)),
      ]),
      Column(children: [
        perk('calendar', 'A week built around your life'),
        perk('vision', "Pep's read on every clip you film"),
        perk('clock', 'Timed tests and PBs'),
        perk('chart', "A profile that shows how you're growing"),
      ]),
      BCta('Pick a goal', onTap: () => _go(const EditProfileScreen())),
      const Text('You can keep watching and doing challenges without one.', textAlign: TextAlign.center, style: bNote),
    ];
  }

  List<Widget> _dayOne(AppState s, String name, PepMood mood) {
    final w = s.week;
    final pos = s.me?.profile.positions.firstOrNull;
    final items = <(WeekDay, WeekItem)>[
      for (final d in w?.days ?? const <WeekDay>[])
        for (final i in d.items)
          if ((i.kind == 'pep' && i.mode != 'rest') || i.kind == 'test' || i.kind == 'match') (d, i),
    ];
    return [
      Row(children: [
        PepFace(mood, size: 52),
        const SizedBox(width: 14),
        Expanded(child: BHead(eyebrow: 'Pep', eyebrowColor: Tk.pep, title: name.isEmpty ? 'Hi.' : 'Hi $name.', size: 28, sub: 'Your first week is ready.')),
      ]),
      BPepNote(
        mood: PepMood.reading,
        title: 'Starter week',
        text: "It's built for every ${pos ?? 'player'}. Once I've seen your tests and a clip, it gets personal to you.",
      ),
      BLab('Your first week', link: 'Edit week', onLink: () => _go(const WeekScreen())),
      if (items.isNotEmpty)
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(children: [
            for (final (k, (d, i)) in items.indexed)
              BRow(
                icon: switch (i.kind) { 'test' => 'jump', 'match' => 'trophy', _ => 'pep' },
                iconColor: switch (i.kind) { 'test' => context.accent.main, 'match' => Tk.gold, _ => Tk.pep },
                tileColor: switch (i.kind) { 'test' => context.accent.tile, 'match' => Tk.goldTile, _ => Tk.pepTile },
                title: i.title,
                sub: [d.weekday.substring(0, 3), if (i.time != null) i.time!, if (i.durationMin != null) '${i.durationMin} min'].join(' · '),
                trailing: i.kind == 'test' && k == items.indexWhere((x) => x.$2.kind == 'test')
                    ? BChip('First', color: context.accent.on, background: context.accent.main, caps: true)
                    : null,
                divider: k < items.length - 1,
                onTap: i.isPep ? () => _go(SessionScreen(sessionKey: i.id)) : (i.kind == 'test' ? _test : null),
              ),
          ]),
        ),
      BCta('Start baseline tests', onTap: _test),
      const BLab('No tips yet'),
      const BDashed(
        padding: EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("I learn from your clips. Film one like this and I'll show you one thing you do well and one to work on.",
              style: TextStyle(fontSize: 13, height: 1.45, color: Tk.muted)),
          SizedBox(height: 14),
          _FilmTip('camera', 'Film from the side', 'Halfway line or touchline, phone sideways'),
          SizedBox(height: 14),
          _FilmTip('you', 'Keep your whole body in frame', 'Head to boots, the whole clip'),
          SizedBox(height: 14),
          _FilmTip('clock', '20 to 60 seconds', 'One drill or one passage of play'),
        ]),
      ),
    ];
  }

  List<Widget> _main(AppState s, FocusState? f, String name, PepMood mood, List<Video> ready, Video? newest) {
    final a = context.accent;
    // The canvas's icons and colours: Pep's things purple, your training in
    // your main colour, health in calm stone.
    final shortcuts = <(String, Color, String, int?, VoidCallback)>[
      ('vision', Tk.pep, 'Reviews', ready.isEmpty ? null : ready.length, () => _go(const ReviewsScreen())),
      ('help', Tk.pep, 'Tips', tips?.length, () => _go(const TipsScreen())),
      ('calendar', a.main, 'Schedule', null, () => _go(const WeekScreen())),
      ('pace', a.main, 'Sessions', null, () => _go(const SessionsScreen())),
      ('target', a.main, 'Focus', null, () => _go(const FocusScreen())),
      ('shield', Tk.stone, 'Health', null, () => _go(const HealthScreen())),
    ];
    return [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        _TapPep(mood: mood),
        const SizedBox(width: 12),
        Expanded(
          child: EnterFade(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Tk.pepTile,
                border: Border.all(color: const Color(0xFF3A12A8)),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft: Radius.circular(6),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_greeting(name), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
                const SizedBox(height: 3),
                Text(PepScreen.weekLine(s.week), style: const TextStyle(fontSize: 13.5, height: 1.4, color: Color(0xFFD9CCF7))),
              ]),
            ),
          ),
        ),
      ]),
      SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.only(top: 6),
          children: [
            for (final (icon, iconColour, label, count, onTap) in shortcuts)
              Semantics(
                button: true,
                label: count != null && count > 0 ? '$label, $count new' : label,
                excludeSemantics: true,
                child: Pressable(
                  onTap: onTap,
                  child: SizedBox(
                    width: 70,
                    child: Column(children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Container(
                          width: 58,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            shape: BoxShape.circle,
                            border: Border.all(color: (count ?? 0) > 0 ? a.main : Tk.lineStrong, width: (count ?? 0) > 0 ? 2 : 1.5),
                          ),
                          child: TIcon(icon, size: 22, color: iconColour),
                        ),
                        if ((count ?? 0) > 0)
                          Positioned(
                            right: -5,
                            top: -5,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              height: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: a.main, borderRadius: BorderRadius.circular(999)),
                              child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: a.on)),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      Text(label,
                          maxLines: 1,
                          style: TextStyle(fontSize: 11.5, fontWeight: (count ?? 0) > 0 ? FontWeight.w600 : FontWeight.w500, color: (count ?? 0) > 0 ? Tk.ink : Tk.muted)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
      if (f != null && f.growing.isNotEmpty)
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              PepFace(PepMood.proud, size: 20),
              SizedBox(width: 8),
              Text('YOUR GAME IS GROWING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .66, color: Tk.pep)),
            ]),
            const SizedBox(height: 10),
            Text('Every good player keeps growing. ${f.growing.length == 1 ? 'A big change' : 'Big changes'} in your game lately:',
                style: const TextStyle(fontSize: 14.5, height: 1.45, color: Tk.body)),
            const SizedBox(height: 4),
            for (final (k, x) in f.growing.indexed) _GrowRow(x, divider: k < f.growing.length - 1),
            const SizedBox(height: 8),
            Pressable(
              onTap: () => _go(const FocusScreen()),
              child: const Row(children: [
                Text('See your focus and tests', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Tk.muted)),
                SizedBox(width: 4),
                TIcon('chevron', size: 12, color: Tk.muted),
              ]),
            ),
          ]),
        ),
      const TrainingCard(),
      Pressable(
        onTap: () => showHealthSheet(context),
        child: const SafetyNote('In pain or injured? Rest, and see a doctor or physio. I can give you an easier plan.'),
      ),
      const BLab('New from Pep'),
      if (newest != null)
        Panel(
          padding: const EdgeInsets.all(12),
          onTap: () => _go(const ReviewsScreen()),
          child: Row(children: [
            SizedBox(width: 76, child: BThumb(url: newest.thumbnailUrl, height: 76, radius: 12)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  PepFace(PepMood.proud, size: 16),
                  SizedBox(width: 6),
                  Text('REVIEW READY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .66, color: Tk.pep)),
                ]),
                const SizedBox(height: 3),
                Text(newest.displayTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
                if (newest.reviewNote != null) Text(newest.reviewNote!, maxLines: 2, overflow: TextOverflow.ellipsis, style: bNote),
              ]),
            ),
          ]),
        ),
      if (tips != null && tips!.isNotEmpty)
        BPepNote(
          mood: PepMood.cheeky,
          title: 'Tip: ${tips!.first.title.toLowerCase()}',
          text: 'From ${tips!.first.videoTitle?.isNotEmpty == true ? tips!.first.videoTitle : 'your clip'}',
          onTap: () => _go(const TipsScreen()),
        ),
      if (f?.nextTest != null)
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: BRow(
            icon: 'clock',
            iconColor: Tk.pep,
            tileColor: Tk.pepTile,
            title: f!.nextTest!.date == null ? '${f.nextTest!.name}: due' : '${f.nextTest!.name} on ${_day(f.nextTest!.date!)}',
            sub: "About 20 minutes. I'll time you.",
            divider: false,
            trailing: const TIcon('chevron', size: 14, color: Tk.faint),
            onTap: _test,
          ),
        ),
      const InfoNote(InfoNote.pep),
    ];
  }
}

/// Tap Pep and he bounces (canvas Pep tab: "Tap Pep").
class _TapPep extends StatefulWidget {
  const _TapPep({required this.mood});

  final PepMood mood;

  @override
  State<_TapPep> createState() => _TapPepState();
}

class _TapPepState extends State<_TapPep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Tap Pep',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () {
            if (!Motion.reduced(context)) _c.forward(from: 0);
          },
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) {
              // pt-a: up and tilt left, tilt right, settle with a squash.
              final p = const Cubic(.3, 1.4, .5, 1).transform(_c.value);
              double k(List<double> v) {
                const at = [0.0, .25, .45, .65, .85, 1.0];
                for (var i = 0; i < at.length - 1; i++) {
                  if (p <= at[i + 1]) return v[i] + (v[i + 1] - v[i]) * ((p - at[i]) / (at[i + 1] - at[i]));
                }
                return v.last;
              }

              final y = k([0, -10, -4, -6, 0, 0]);
              final sc = k([1, 1.12, 1.08, 1.1, 1, 1]);
              final r = k([0, -8, 8, -5, 0, 0]) * math.pi / 180;
              return Transform(
                alignment: const Alignment(0, .8),
                transform: Matrix4.translationValues(0, y, 0)
                  ..multiply(Matrix4.rotationZ(r))
                  ..multiply(Matrix4.diagonal3Values(sc, sc, 1)),
                child: child,
              );
            },
            child: PepFace(widget.mood, size: 58),
          ),
        ),
      );
}

class _FilmTip extends StatelessWidget {
  const _FilmTip(this.icon, this.title, this.sub);

  final String icon;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) => Row(children: [
        IconTile(icon: icon, color: Tk.muted, background: Tk.field, size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.ink)),
            Text(sub, style: bNote),
          ]),
        ),
      ]);
}

/// One growing area with a three-bar "how fast" pill (canvas Pep tab).
class _GrowRow extends StatelessWidget {
  const _GrowRow(this.a, {required this.divider});

  final AreaLine a;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.accent;
    final bars = switch (a.trend) { 'growing' => a.band == 'well_above' || a.band == 'above' ? 3 : 2, 'steady' => 1, _ => 1 };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: divider ? const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.line))) : null,
      child: Row(children: [
        TIcon(switch (a.group.toLowerCase()) { 'reading the game' => 'vision', 'body' => 'pace', 'attitude' => 'heart', _ => 'pass' }, size: 16, color: Tk.inkSoft),
        const SizedBox(width: 10),
        Expanded(child: Text(a.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Tk.body))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: c.tile, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (i, h) in [6.0, 9.0, 12.0].indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              Container(width: 4, height: h, decoration: BoxDecoration(color: i < bars ? c.main : Tk.lineStrong, borderRadius: BorderRadius.circular(3))),
            ],
            const SizedBox(width: 6),
            Text(bars == 3 ? 'Growing fast' : a.trendWords, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.main)),
          ]),
        ),
      ]),
    );
  }
}

String _day(DateTime d) => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1];

/// Pep › Focus and tests: what we're working on, and how we check it.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  FocusState? f;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await context.read<AppState>().api.focus();
      if (mounted) setState(() => f = v);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = f;
    final a = context.accent;
    if (failed || v == null) {
      return BPage(eyebrow: 'Pep', title: 'Focus and tests', children: [
        if (failed) StateView.error(onRetry: _load) else ...[const Skeleton(height: 180), const Skeleton(height: 140)],
      ]);
    }
    return BPage(
      eyebrow: 'Pep',
      title: 'Focus and tests',
      sub: "What we're working on, and how we check it.",
      children: [
        const BLab('Working on now'),
        if (v.focus.isEmpty)
          const BDashed(child: Text("Send a clip or do a test and I'll pick your focus.", style: TextStyle(fontSize: 13, height: 1.45, color: Tk.muted)))
        else
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Column(children: [
              for (final (i, x) in v.focus.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: i == v.focus.length - 1 ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.line))),
                  child: Row(children: [
                    IconTile(icon: _areaIcon(x.group), color: a.main, background: a.tile, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(x.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
                        const SizedBox(height: 4),
                        Align(alignment: Alignment.centerLeft, child: TrendPill(x)),
                        const SizedBox(height: 6),
                        Text('${x.group} · I check this in your clips.', style: bNote),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
        const BPepNote(mood: PepMood.reading, text: 'I pick these from your goal and your clips. When one is going well, we move on to the next.'),
        if (v.nextTest != null) ...[
          const BLab('Next test'),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconTile(icon: 'clock', color: a.main, background: a.tile, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v.nextTest!.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Tk.ink)),
                    Text(v.nextTest!.date == null ? 'Due now · about 20 min' : '${_day(v.nextTest!.date!)} · about 20 min', style: bNote),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              const Text('Do it the same way each time so you can see real change.', style: TextStyle(fontSize: 13.5, height: 1.45, color: Tk.inkSoft)),
              const SizedBox(height: 12),
              BCta('See how it works', ghost: true, height: Tk.btnInCard, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TestScreen(drill: v.nextTest!.drill, name: v.nextTest!.name)))),
            ]),
          ),
        ],
        const BLab('Your best so far'),
        if (v.bests.isEmpty)
          const BDashed(child: Text('No tests yet. Your first one sets your starting point.', style: TextStyle(fontSize: 13, height: 1.45, color: Tk.muted)))
        else
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Column(children: [
              for (final (i, b) in v.bests.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: i == v.bests.length - 1 ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.line))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.ink)),
                        Text(b.unit == 's' ? 'Timed by Pep' : 'Counted by Pep', style: bNote),
                      ]),
                    ),
                    Text('${b.value}${b.unit.isEmpty ? '' : ' ${b.unit}'}',
                        style: const TextStyle(fontFamily: TType.display, fontSize: 18, fontWeight: FontWeight.w700, color: Tk.ink)),
                  ]),
                ),
            ]),
          ),
        const InfoNote(InfoNote.measured),
      ],
    );
  }
}

String _areaIcon(String group) => switch (group.toLowerCase()) {
      'reading the game' => 'vision',
      'body' => 'pace',
      'attitude' => 'heart',
      _ => 'ball',
    };

/// How fast an area is growing, as three little bars (canvas: Focus and tests).
class TrendPill extends StatelessWidget {
  const TrendPill(this.a, {super.key});

  final AreaLine a;

  @override
  Widget build(BuildContext context) {
    final c = context.accent;
    final bars = switch (a.trend) { 'growing' => a.band == 'well_above' || a.band == 'above' ? 3 : 2, 'steady' => 1, 'dipping' => 1, _ => 1 };
    final growing = a.trend == 'growing';
    final fg = growing ? c.main : (a.trend == 'dipping' ? Tk.gold : Tk.stone);
    final bg = growing ? c.tile : (a.trend == 'dipping' ? Tk.goldTile : Tk.stoneTile);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (i, h) in [6.0, 9.0, 12.0].indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(width: 4, height: h, decoration: BoxDecoration(color: i < bars ? fg : Tk.lineStrong, borderRadius: BorderRadius.circular(3))),
        ],
        const SizedBox(width: 6),
        Text(bars == 3 && growing ? 'Growing fast' : a.trendWords, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

/// How a test works: what you need, the steps, then film it.
class TestScreen extends StatelessWidget {
  const TestScreen({super.key, required this.drill, required this.name});

  final String drill;
  final String name;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final d = context.read<AppState>().meta?.drills[drill];
    final cones = d?.cones.length ?? 0;
    final needs = [
      if (cones > 0) ('cone', '$cones cones or markers'),
      ('camera', 'Your phone'),
      ('users', 'A friend to film, or a phone stand'),
    ];
    final steps = [
      ('Warm up for 5 minutes', 'Jog, skips, a few short sprints at half speed.'),
      (d?.label ?? name, d?.how ?? 'Follow the steps on the upload screen.'),
      ('Film it', d?.needsCalibration ?? false ? 'Phone side-on, and mark the cones when you upload.' : 'Phone on its side, all of you in shot.'),
    ];
    return BPage(
      eyebrow: 'Test',
      title: name,
      sub: 'About 20 minutes. Do it the same way every time.',
      bottom: BCta('Film the test', icon: 'camera', onTap: () => openUpload(context, drill: drill, title: name)),
      children: [
        const BLab('You need'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (icon, label) in needs)
            Container(
              constraints: const BoxConstraints(minHeight: Tk.btnSmall),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFF2A2A2A))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                TIcon(icon, size: 14, color: Tk.inkSoft),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Tk.ink)),
              ]),
            ),
        ]),
        const BLab('How it works'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(children: [
            for (final (i, (title, how)) in steps.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: i == steps.length - 1 ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.line))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: a.tile),
                    child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: a.main)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                      const SizedBox(height: 2),
                      Text(how, style: bNote.copyWith(fontSize: 12.5)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
        const BPepNote(mood: PepMood.counting, text: 'I time you from the video. Your best goes into Focus and tests, and onto your skill areas in Me.'),
        const SafetyNote("Stop if anything hurts. Skip the test if you're sick or injured."),
      ],
    );
  }
}
