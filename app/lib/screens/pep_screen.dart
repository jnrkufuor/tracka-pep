import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'home_screen.dart' show openUpload;
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

  void _go(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final f = focus;
    final ready = s.videos.where((v) => v.status == 'READY').toList();
    final newest = ready.firstOrNull;
    final t = Theme.of(context).textTheme;
    final shortcuts = <(String, String, int?, VoidCallback)>[
      ('clip', 'Reviews', ready.isEmpty ? null : ready.length, () => _go(const ReviewsScreen())),
      ('target', 'Tips', tips?.length, () => _go(const TipsScreen())),
      ('calendar', 'Schedule', null, () => _go(const WeekScreen())),
      ('streak', 'Sessions', null, () => _go(const WeekScreen())),
      ('vision', 'Focus', null, () => _go(const FocusScreen())),
      ('heart', 'Health', null, () => showHealthSheet(context)),
    ];
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await s.refresh();
            await _load();
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const IconTile(icon: 'pep', color: Tk.pep, background: Tk.pepTile, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  EnterFade(child: Text(_greeting(s.me?.profile.firstName ?? ''), style: t.headlineMedium)),
                  const SizedBox(height: 4),
                  Text(weekLine(s.week), style: const TextStyle(fontSize: 14, height: 1.4, color: Tk.inkSoft)),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: [
                for (final (icon, label, count, onTap) in shortcuts)
                  Panel(
                    padding: const EdgeInsets.all(12),
                    onTap: onTap,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Row(children: [
                        TIcon(icon, size: 20, color: Tk.pep),
                        const Spacer(),
                        if (count != null && count > 0)
                          Text('$count', style: const TextStyle(fontFamily: TType.display, fontSize: 16, fontWeight: FontWeight.w800, color: Tk.ink)),
                      ]),
                      Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            if (f != null && f.growing.isNotEmpty) ...[
              const SectionLabel('Your game is growing'),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Every good player keeps growing. Big changes in your game lately:', style: TextStyle(fontSize: 13.5, color: Tk.inkSoft)),
                  const SizedBox(height: 8),
                  for (final a in f.growing) _AreaRow(a),
                  TextButton(onPressed: () => _go(const FocusScreen()), child: const Text('See your focus and tests')),
                ]),
              ),
              const SizedBox(height: 18),
            ],
            const SectionLabel("Today's training"),
            const TodayCard(),
            const SizedBox(height: 8),
            const SafetyNote('In pain or injured? Rest, and see a doctor or physio. I can give you an easier plan.'),
            const SizedBox(height: 18),
            const SectionLabel('New from Pep'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                if (newest != null)
                  _NewRow(
                    icon: 'clip',
                    title: 'Review ready',
                    sub: '${newest.displayTitle}${newest.reviewNote == null ? '' : ' · ${newest.reviewNote}'}',
                    onTap: () => _go(const ReviewsScreen()),
                  ),
                if (tips != null && tips!.isNotEmpty)
                  _NewRow(icon: 'target', title: 'Tip: ${tips!.first.title.toLowerCase()}', sub: 'From ${tips!.first.videoTitle?.isNotEmpty == true ? tips!.first.videoTitle : 'your clip'}', onTap: () => _go(const TipsScreen())),
                if (f?.nextTest != null)
                  _NewRow(
                    icon: 'clock',
                    title: f!.nextTest!.date == null ? '${f.nextTest!.name}: due' : '${f.nextTest!.name} on ${_day(f.nextTest!.date!)}',
                    sub: "About 20 minutes. I'll time you.",
                    onTap: () => _go(TestScreen(drill: f.nextTest!.drill, name: f.nextTest!.name)),
                  ),
                if (newest == null && (tips?.isEmpty ?? true) && f?.nextTest == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("Send me a clip and I'll tell you what went well and what to work on.", style: TextStyle(color: Tk.inkSoft)),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            const InfoNote(InfoNote.pep),
          ]),
        ),
      ),
    );
  }
}

String _day(DateTime d) => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1];

Band? _band(String? name) => Band.fromName(name);

class _AreaRow extends StatelessWidget {
  const _AreaRow(this.a);

  final AreaLine a;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
              Text('${a.group} · ${a.trendWords}', style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
            ]),
          ),
          if (_band(a.band) != null) BandPill(_band(a.band)!),
        ]),
      );
}

class _NewRow extends StatelessWidget {
  const _NewRow({required this.icon, required this.title, required this.sub, required this.onTap});

  final String icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            IconTile(icon: icon, color: Tk.pep, background: Tk.pepTile, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
              ]),
            ),
            const TIcon('chevron', size: 14, color: Tk.faint),
          ]),
        ),
      );
}

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
    if (failed) return Scaffold(appBar: AppBar(), body: StateView.error(onRetry: _load));
    if (v == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        const Text('PEP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tk.pep, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Text('Focus and tests', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text("What we're working on, and how we check it.", style: TextStyle(fontSize: 13.5, color: Tk.muted)),
        const SizedBox(height: 18),
        const SectionLabel('Working on now'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (final a in v.focus) _AreaRow(a),
            if (v.focus.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Send a clip or do a test and I\'ll pick your focus.')),
          ]),
        ),
        const SizedBox(height: 6),
        const Text('I pick these from your goal and your clips. When one is going well, we move on to the next.',
            style: TextStyle(fontSize: 12, color: Tk.faint)),
        if (v.nextTest != null) ...[
          const SizedBox(height: 18),
          const SectionLabel('Next test'),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.nextTest!.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Tk.ink)),
              Text(v.nextTest!.date == null ? 'Due now · about 20 min' : '${_day(v.nextTest!.date!)} · about 20 min',
                  style: const TextStyle(fontSize: 13, color: Tk.muted)),
              const SizedBox(height: 6),
              const Text('Do it the same way each time so you can see real change.', style: TextStyle(fontSize: 13.5, color: Tk.inkSoft)),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TestScreen(drill: v.nextTest!.drill, name: v.nextTest!.name))),
                child: const Text('See how it works'),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        const SectionLabel('Your best so far'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (final b in v.bests)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.label, style: const TextStyle(fontSize: 14.5, color: Tk.ink)),
                      Text(b.unit == 's' ? 'Timed by Pep' : 'Counted by Pep', style: const TextStyle(fontSize: 12, color: Tk.muted)),
                    ]),
                  ),
                  Text('${b.value}${b.unit.isEmpty ? '' : ' ${b.unit}'}',
                      style: const TextStyle(fontFamily: TType.display, fontSize: 18, fontWeight: FontWeight.w800, color: Tk.ink)),
                ]),
              ),
            if (v.bests.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No tests yet. Your first one sets your starting point.')),
          ]),
        ),
        const SizedBox(height: 14),
        const InfoNote(InfoNote.measured),
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
    final d = context.read<AppState>().meta?.drills[drill];
    final steps = [
      ('Warm up for 5 minutes', 'Jog, skips, a few short sprints at half speed.'),
      (d?.label ?? name, d?.how ?? 'Follow the steps on the upload screen.'),
      ('Film it', d?.needsCalibration ?? false ? 'Phone side-on, and mark the cones when you upload.' : 'Phone on its side, all of you in shot.'),
    ];
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        const Text('TEST', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tk.pep, letterSpacing: 0.8)),
        const SizedBox(height: 4),
        Text(name, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text('About 20 minutes. Do it the same way every time.', style: TextStyle(fontSize: 13.5, color: Tk.muted)),
        const SizedBox(height: 18),
        const SectionLabel('How it works'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (final (i, (title, how)) in steps.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: context.accent.tile),
                    child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.accent.main)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                      Text(how, style: const TextStyle(fontSize: 13, color: Tk.muted)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        const Text('I time you from the video. Your best goes into Focus and tests, and onto your skill areas in Me.',
            style: TextStyle(fontSize: 12.5, color: Tk.faint)),
        const SizedBox(height: 12),
        const SafetyNote("Stop if anything hurts. Skip the test if you're sick or injured."),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => openUpload(context, drill: drill, title: name), child: const Text('Film the test')),
      ]),
    );
  }
}
