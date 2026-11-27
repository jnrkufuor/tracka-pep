import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/board.dart';
import '../widgets/ds.dart';
import '../widgets/pep.dart';
import 'upload_screen.dart';

/// Training screens (canvas: Pep › Schedule, Sessions, In a session, Training
/// done, Health, Move or skip, Edit your football).
///
/// The week comes from the server already planned (GET /v1/week): the app
/// only shows it and sends the player's choices back. See pep/players/training.py
/// for the rules (no Pep session on a match day or the day before, rest when hurt).

const _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _dayLabel(DateTime d) => '${d.day} ${_monthShort[d.month - 1]}';

/// Colour and icon for each kind of item, by job: you (main colour) for Pep's
/// sessions and tests, stone for your own football, gold for rest.
String _itemLine(WeekItem i) {
  final parts = <String>[
    if (i.time != null) i.time!,
    if ((i.durationMin ?? 0) > 0) '${i.durationMin} min',
    if (i.mode == 'light') 'light',
    if (i.moved) 'moved',
    if (i.repeats) 'every week',
  ];
  return parts.join(' · ');
}

// ───────────────────────────── today (Home and the Pep tab)

/// "Today" / "Next up": the next Pep session with a Start button, and a
/// gentle line when Pep has made things lighter because something hurts.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final w = s.week;
    if (w == null) return const SizedBox.shrink();
    final next = w.nextSession;
    final a = context.accent;
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(next == null ? 'This week' : (next.$1.isToday ? 'Today' : 'Next up · ${next.$1.weekday}'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: a.main, letterSpacing: 0.4)),
          const Spacer(),
          Pressable(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeekScreen())),
            child: const Text('Your week', style: TextStyle(fontSize: 13, color: Tk.muted, fontWeight: FontWeight.w500)),
          ),
        ]),
        const SizedBox(height: 8),
        if (next == null)
          const Text("You've done this week's sessions. Rest well.", style: TextStyle(fontSize: 15, color: Tk.ink))
        else ...[
          Text(next.$2.title, style: Theme.of(context).textTheme.titleLarge),
          if (_itemLine(next.$2).isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(_itemLine(next.$2), style: const TextStyle(fontSize: 13, color: Tk.muted)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionScreen(sessionKey: next.$2.id))),
              child: Text(next.$2.kind == 'rest' ? 'See what to do' : 'Start training'),
            ),
          ),
        ],
        if (w.health != 'fine') ...[
          const SizedBox(height: 12),
          Pressable(
            onTap: () => showHealthSheet(context),
            child: SafetyNote(w.health == 'sore'
                ? 'Pep has made your sessions lighter. Tap to update how your body feels.'
                : 'Pep has paused your training. Tap to update how your body feels.'),
          ),
        ],
      ]),
    );
  }
}

// ───────────────────────────── the week

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  DateTime? _start; // null = this week
  Week? _other; // a week other than this one, when browsing
  bool _loading = false;
  String? _error;

  Future<void> _load(DateTime? start) async {
    final s = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (start == null) {
        await s.loadWeek();
        _other = null;
      } else {
        _other = await s.api.week(start: start);
      }
      _start = start;
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final w = _other ?? s.week;
    final a = context.accent;
    if (w == null) {
      return BPage(eyebrow: 'Pep', title: 'Your schedule', children: [
        if (_error != null) StateView.error(onRetry: () => _load(_start)) else const Skeleton(height: 320),
      ]);
    }
    Widget legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Tk.muted)),
        ]);
    Future<void> add(String kind) async {
      await showEventSheet(context, initialKind: kind);
      if (mounted) await _load(_start);
    }

    return BPage(
      eyebrow: 'Pep',
      title: 'Your schedule',
      sub: 'Tap anything to change it.',
      topNote: '${w.start.day} – ${_dayLabel(w.start.add(const Duration(days: 6)))}',
      children: [
        Wrap(spacing: 14, runSpacing: 8, children: [
          legend(Tk.pep, 'Pep'),
          legend(a.main, 'Team'),
          legend(Tk.gold, 'Match or event'),
          legend(Tk.stone, 'School'),
        ]),
        Row(children: [
          BRoundButton(icon: 'back', label: 'Week before', onTap: () => _loading ? null : _load(w.start.subtract(const Duration(days: 7)))),
          Expanded(
            child: Text(_start == null ? 'This week' : '${_dayLabel(w.start)} – ${_dayLabel(w.start.add(const Duration(days: 6)))}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.lab)),
          ),
          BRoundButton(icon: 'chevron', label: 'Week after', onTap: () => _loading ? null : _load(w.start.add(const Duration(days: 7)))),
        ]),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(children: [
            for (final (i, d) in w.days.indexed)
              _DayBlock(day: d, past: d.date.isBefore(w.today) && !d.isToday, last: i == w.days.length - 1, onChanged: () => _load(_start)),
          ]),
        ),
        const BLab('Add to your schedule'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          BGhostChip(icon: 'calendar', label: 'School', onTap: () => add('school')),
          BGhostChip(icon: 'calendar', label: 'Team training', onTap: () => add('team')),
          BGhostChip(icon: 'flag', label: 'Match', onTap: () => add('match')),
          BGhostChip(icon: 'flag', label: 'Event', onTap: () => add('other')),
        ]),
        const BPepNote(
          mood: PepMood.reading,
          title: 'I plan around your life',
          text: 'Add school, team training and matches. I put my sessions in the free time and keep the day before a match easy.',
        ),
      ],
    );
  }
}

class _DayBlock extends StatelessWidget {
  const _DayBlock({required this.day, required this.past, required this.last, required this.onChanged});

  final WeekDay day;
  final bool past;
  final bool last;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final label = '${day.weekday.length >= 3 ? day.weekday.substring(0, 3) : day.weekday} ${day.date.day}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(day.isToday ? 'Today' : label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: day.isToday ? a.main : (past ? Tk.faint : Tk.lab))),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(children: [
            if (day.items.isEmpty)
              BBlock(title: 'Rest', edge: Tk.faint, fill: Tk.field, faded: past)
            else
              for (final (k, i) in day.items.indexed) ...[
                if (k > 0) const SizedBox(height: 6),
                _ItemRow(item: i, day: day, past: past, onChanged: onChanged),
              ],
          ]),
        ),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.day, required this.past, required this.onChanged});

  final WeekItem item;
  final WeekDay day;
  final bool past;
  final VoidCallback onChanged;

  Future<void> _tap(BuildContext context) async {
    if (item.isPep) {
      if (item.status == 'planned' && !past) {
        await showSessionActions(context, item, day);
      } else {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionScreen(sessionKey: item.id)));
      }
    } else if (item.kind == 'test') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => UploadScreen(drill: item.drill)));
    } else {
      await showEventSheet(context, eventId: item.id);
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final (edge, fill) = switch (item.kind) {
      'pep' when item.mode == 'rest' => (Tk.faint, Tk.field),
      'pep' || 'test' => (Tk.pep, Tk.pepTile),
      'team' || 'game' => (a.main, a.tile),
      'match' || 'other' => (Tk.gold, Tk.goldTile),
      'rest' => (Tk.faint, Tk.field),
      _ => (Tk.stone, Tk.stoneTile),
    };
    final line = [_itemLine(item), if (item.isPep && item.mode != 'rest') 'Pep', if (item.status == 'skipped') 'skipped'].where((x) => x.isNotEmpty).join(' · ');
    return BBlock(
      title: item.title,
      sub: line,
      edge: edge,
      fill: fill,
      done: item.status == 'done',
      faded: item.status == 'skipped' || (past && item.status != 'done'),
      onTap: () => _tap(context),
    );
  }
}

/// Tap a planned Pep session: start it, move it to another day, or skip it.
/// Pep keeps the rest of the week as it is; moving to the day before a match
/// makes it a light session (the server decides, the app just shows it).
Future<void> showSessionActions(BuildContext context, WeekItem item, WeekDay day) {
  final s = context.read<AppState>();
  final week = s.week;
  return showEditSheet<void>(
    context,
    title: item.title,
    child: Builder(builder: (ctx) {
      final today = week?.today ?? DateTime.now();
      final options = List.generate(7, (i) => (week?.start ?? today).add(Duration(days: i)))
          .where((d) => !d.isBefore(today) && d != day.date)
          .toList();
      Future<void> run(Future<Week> Function() call, String done) async {
        try {
          s.setWeek(await call());
          if (ctx.mounted) Navigator.of(ctx).pop();
          if (context.mounted) showToast(context, done);
        } catch (e) {
          if (ctx.mounted) showToast(ctx, "Couldn't change it", detail: '$e', ok: false, aboveTabs: false);
        }
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${day.weekday} · ${_itemLine(item)}', style: const TextStyle(fontSize: 14, color: Tk.muted)),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionScreen(sessionKey: item.id)));
          },
          child: const Text('Start training'),
        ),
        const SizedBox(height: 22),
        if (options.isNotEmpty) ...[
          const SectionLabel('Move it to'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in options)
              OutlinedButton(
                onPressed: () => run(() => s.api.moveSession(item.id, d), 'Moved to ${_weekdayName(d)}'),
                child: Text(_weekdayName(d)),
              ),
          ]),
          const SizedBox(height: 18),
        ],
        TextButton(
          onPressed: () => run(() => s.api.skipSession(item.id), 'Skipped. The rest of your week stays the same.'),
          child: const Text('Skip this one'),
        ),
        if (item.moved)
          TextButton(
            onPressed: () => run(() => s.api.restoreSession(item.id), 'Back on its first day'),
            child: const Text('Put it back'),
          ),
      ]);
    }),
  );
}

String _weekdayName(DateTime d) => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1];

// ───────────────────────────── one session

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionKey});

  final String sessionKey;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late Future<SessionPlan> _plan = context.read<AppState>().api.session(widget.sessionKey);

  /// Which step you're on, how long is left on it, and whether the clock runs
  /// (canvas: In a session). The clock is a guide; you move on when ready.
  int _at = 0;
  int? _left;
  bool _running = false;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _toggle(SessionPlan p) {
    setState(() {
      _left ??= p.steps[_at].minutes * 60;
      _running = !_running;
    });
    _tick?.cancel();
    if (_running) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _left = (_left ?? 0) - 1;
          if (_left! <= 0) {
            _left = 0;
            _running = false;
            _tick?.cancel();
          }
        });
      });
    }
  }

  void _next(SessionPlan p) {
    _tick?.cancel();
    setState(() {
      _running = false;
      if (_at < p.steps.length - 1) {
        _at++;
        _left = p.steps[_at].minutes * 60;
      } else {
        _at = p.steps.length;
      }
    });
    if (_at >= p.steps.length) _finish(p);
  }

  Future<void> _finish(SessionPlan p) async {
    final ok = await showDoneSheet(context, p.key, title: p.title, minutes: p.minutes);
    if (ok && mounted) Navigator.of(context).pop();
  }

  String _clock(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return FutureBuilder<SessionPlan>(
      future: _plan,
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData) {
          return BPage(children: [
            if (snap.hasError)
              StateView.error(onRetry: () => setState(() => _plan = context.read<AppState>().api.session(widget.sessionKey)))
            else ...[const Skeleton(height: 220), const Skeleton(height: 260)],
          ]);
        }
        final p = snap.data!;
        final live = p.status == 'planned' && p.mode != 'rest' && !p.date.isAfter(DateTime.now()) && p.steps.isNotEmpty;
        final at = _at.clamp(0, p.steps.length - 1);
        final step = p.steps.isEmpty ? null : p.steps[at];
        final left = _left ?? (step?.minutes ?? 0) * 60;
        final film = p.steps.where((x) => x.film != null).firstOrNull;
        return Scaffold(
          body: SafeArea(
            child: EnterFade(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
                Row(children: [
                  BRoundButton(icon: 'back', label: 'Back', onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(["Today's training", if (p.minutes > 0) '${p.minutes} min'].join(' · '), style: bNote),
                      Text(p.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Tk.ink)),
                    ]),
                  ),
                  PepFace(_running ? PepMood.counting : PepMood.focused, size: 26),
                ]),
                const SizedBox(height: 18),
                if (step != null && live)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFF222222)),
                      gradient: LinearGradient(
                        begin: const Alignment(-.6, -1),
                        end: const Alignment(.6, 1),
                        stops: const [0, .7],
                        colors: [Color.alphaBlend(a.main.withValues(alpha: .08), const Color(0xFF111111)), const Color(0xFF111111)],
                      ),
                    ),
                    child: Column(children: [
                      Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
                        BChip('Now', color: a.on, background: a.main, caps: true),
                        if (p.focus.isNotEmpty) BChip(p.focus.first, color: Tk.ink, background: const Color(0xFF1C1C1C), caps: true),
                      ]),
                      const SizedBox(height: 10),
                      Text(step.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Tk.ink)),
                      const SizedBox(height: 10),
                      Text(_clock(left),
                          style: TextStyle(fontFamily: TType.display, fontSize: 60, height: 1, fontWeight: FontWeight.w800, color: a.main, fontFeatures: const [FontFeature.tabularFigures()])),
                      const SizedBox(height: 10),
                      Text(step.how, textAlign: TextAlign.center, style: bNote.copyWith(fontSize: 13)),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: BCta(_running ? 'Pause' : (_left == null ? 'Start' : 'Go on'), ghost: true, height: 48, onTap: () => _toggle(p))),
                        const SizedBox(width: 10),
                        Expanded(child: BCta(at < p.steps.length - 1 ? 'Next drill' : 'Finish', height: 48, onTap: () => _next(p))),
                      ]),
                    ]),
                  ),
                if (step != null && live) const SizedBox(height: 18),
                Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Column(children: [
                    for (final (i, x) in p.steps.indexed)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.line))),
                        child: Row(children: [
                          _StepMark(n: i + 1, done: p.status == 'done' || (live && i < at), now: live && i == at),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(x.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: live && i < at ? Tk.faint : Tk.ink)),
                              const SizedBox(height: 2),
                              Text(x.how, maxLines: live && i == at ? 1 : 3, overflow: TextOverflow.ellipsis, style: bNote),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          Text('${x.minutes} min', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Tk.muted)),
                        ]),
                      ),
                    if (film != null)
                      Pressable(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UploadScreen(drill: film.film))),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(children: [
                            const TIcon('camera', size: 14, color: Tk.muted),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Film the ${film.name.toLowerCase()} if you can. I\'ll count it from the video.', style: bNote)),
                          ]),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 18),
                SafetyNote(p.safety),
                const SizedBox(height: 18),
                if (live) ...[
                  BCta('Finish training', ghost: true, onTap: () => _finish(p)),
                  Center(
                    child: TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Stop for today', style: TextStyle(color: Tk.faint))),
                  ),
                ],
                if (p.status == 'done') const Text('Done. Nice work.', textAlign: TextAlign.center, style: TextStyle(color: Tk.muted)),
                if (p.mode == 'rest') BCta('Update how your body feels', ghost: true, onTap: () => showHealthSheet(context)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _StepMark extends StatelessWidget {
  const _StepMark({required this.n, required this.done, required this.now});

  final int n;
  final bool done;
  final bool now;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? a.main : null,
        border: done ? null : Border.all(color: now ? a.main : const Color(0xFF3A3D36), width: 2),
        boxShadow: now ? [BoxShadow(color: a.main.withValues(alpha: .14), spreadRadius: 5)] : null,
      ),
      child: done
          ? TIcon('check', size: 13, color: a.on, stroke: 6)
          : Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: now ? a.main : Tk.faint)),
    );
  }
}

// ───────────────────────────── training done

/// "Training done!" (canvas: Training done): how it felt, whether anything
/// hurt, send the clip. Something hurt → Pep makes the next session easier
/// and points to an adult, doctor or physio. Returns true when logged.
Future<bool> showDoneSheet(BuildContext context, String key, {String? title, int? minutes}) async =>
    await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SessionDoneScreen(sessionKey: key, title: title, minutes: minutes))) ?? false;

class SessionDoneScreen extends StatefulWidget {
  const SessionDoneScreen({super.key, required this.sessionKey, this.title, this.minutes});

  final String sessionKey;
  final String? title;
  final int? minutes;

  @override
  State<SessionDoneScreen> createState() => _SessionDoneScreenState();
}

class _SessionDoneScreenState extends State<SessionDoneScreen> {
  String effort = 'right';
  bool hurt = false;
  bool saving = false;

  Future<void> _done() async {
    final s = context.read<AppState>();
    setState(() => saving = true);
    try {
      final next = await s.api.finishSession(widget.sessionKey, effort: effort, hurt: hurt);
      await s.loadWeek();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showToast(context, 'Training logged', detail: next);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      showToast(context, "Couldn't save it", detail: '$e', ok: false, aboveTabs: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = [if (widget.title != null) widget.title!, if ((widget.minutes ?? 0) > 0) '${widget.minutes} min'].join(' · ');
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: EnterFade(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 32, 20, 16), children: [
                Center(child: PepFace(hurt ? PepMood.concerned : PepMood.celebrating, size: 76)),
                const SizedBox(height: 10),
                Text('Training done!', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 6),
                Text('${line.isEmpty ? '' : '$line. '}It\'s saved in your schedule.', textAlign: TextAlign.center, style: bNote.copyWith(fontSize: 14)),
                const SizedBox(height: 20),
                Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 14, bottom: 10),
                      child: Text('How did it feel?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Tk.lab)),
                    ),
                    BSeg<String>(options: const {'easy': 'Easy', 'right': 'Just right', 'hard': 'Hard'}, value: effort, onChanged: (v) => setState(() => effort = v)),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const Padding(
                      padding: EdgeInsets.only(top: 14, bottom: 10),
                      child: Text('Did anything hurt?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Tk.lab)),
                    ),
                    BSeg<bool>(options: const {false: 'No', true: 'Yes'}, value: hurt, onChanged: (v) => setState(() => hurt = v)),
                    const SizedBox(height: 14),
                  ]),
                ),
                if (hurt) ...[
                  const SizedBox(height: 14),
                  Pressable(
                    onTap: () => showHealthSheet(context),
                    child: const SafetyNote("Rest, and tell a parent or coach. If it still hurts, see a doctor or physio. I'll make your next session easier."),
                  ),
                ] else if (effort == 'hard') ...[
                  const SizedBox(height: 14),
                  const BPepNote(mood: PepMood.listening, text: "Thanks for telling me. I'll make the next one a bit easier."),
                ],
                const SizedBox(height: 14),
                Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: BRow(
                    icon: 'camera',
                    iconColor: Tk.pep,
                    tileColor: Tk.pepTile,
                    tile: 40,
                    title: 'Filmed it?',
                    sub: "Send it and I'll review it with you.",
                    trailing: const TIcon('chevron', size: 12, color: Tk.faint),
                    divider: false,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen())),
                  ),
                ),
              ]),
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: BCta(saving ? 'Saving…' : 'Done', onTap: saving ? null : _done)),
        ]),
      ),
    );
  }
}

// ───────────────────────────── how your body feels

/// Health: guide and refer. Pep never diagnoses or gives food plans; it
/// changes the plan (lighter, or rest) and points to the right people.
/// How's your body: opens Pep › Health (canvas: Health: guide and refer).
Future<void> showHealthSheet(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HealthScreen()));

/// Pep › Health (canvas: "Health: guide and refer"). Pep is a football coach,
/// not a doctor: he says what to do and who can help, and changes the plan
/// (keep it, make it easier, pause it). No food plans, no diagnosis.
class HealthScreen extends StatelessWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final status = s.health?.status ?? s.week?.health ?? 'fine';
    final plan = switch (status) { 'sore' => 'easier', 'pain' || 'injured' => 'pause', _ => 'keep' };
    Future<void> set(String p) async {
      try {
        await s.setHealth(switch (p) { 'easier' => 'sore', 'pause' => 'injured', _ => 'fine' });
      } catch (e) {
        if (context.mounted) showToast(context, "Couldn't save it", detail: '$e', ok: false, aboveTabs: false);
      }
    }

    Widget step(int n, String t, String d, {bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2E2508)))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Color(0xFF2A2205), shape: BoxShape.circle),
              child: Text('$n', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tk.gold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.ink)),
                const SizedBox(height: 2),
                Text(d, style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFFD8C998))),
              ]),
            ),
          ]),
        );
    return BPage(
      eyebrow: 'Pep',
      title: 'Health',
      sub: "I'm a football coach, not a doctor. Here's what to do, and who can help.",
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          decoration: BoxDecoration(color: Tk.goldTile, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF5A4512), width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 12, 0, 6),
              child: Row(children: [
                TIcon('shield', size: 18, color: Tk.gold),
                SizedBox(width: 10),
                Text('If something hurts', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFFF0DFAE))),
              ]),
            ),
            step(1, 'Stop and rest', "Don't play through pain."),
            step(2, 'Tell an adult', 'A parent, guardian or your coach.'),
            step(3, 'See a doctor or physio', "If it's swollen, you can't put weight on it, or it still hurts after a few days.", last: true),
          ]),
        ),
        const SafetyNote("If it's serious, like a head injury or a lot of pain, get help straight away.", icon: 'info'),
        const BLab('Your plan while you recover'),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BSeg<String>(options: const {'keep': 'Keep my plan', 'easier': 'Make it easier', 'pause': 'Pause it'}, value: plan, onChanged: set),
            const SizedBox(height: 12),
            Text(
              switch (plan) {
                'easier' => 'Shorter sessions, no sprints, no tests. Follow what your doctor or physio says first.',
                'pause' => "Nothing new until you say you're ready. Your progress is safe.",
                _ => "Change this any time. When you're back, I start you slowly.",
              },
              style: bNote.copyWith(fontSize: 12.5),
            ),
          ]),
        ),
        const BLab('Food and water'),
        const Panel(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(children: [
            BRow(icon: 'streak', title: 'Drink water through the day', sub: 'More on hot days and match days', iconColor: Tk.muted),
            BRow(icon: 'spot', title: 'Eat a proper meal before you play', sub: 'A few hours before, not right before', iconColor: Tk.muted),
            BRow(icon: 'you', title: 'Want a food plan?', sub: "Ask a doctor or nutritionist. I don't make food plans.", iconColor: Tk.muted, divider: false),
          ]),
        ),
      ],
    );
  }
}

/// Pep › Sessions (canvas: Sessions): today's training, what's coming up,
/// what you've done lately.
class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final w = s.week;
    final a = context.accent;
    final next = w?.nextSession;
    final coming = <(WeekDay, WeekItem)>[
      for (final d in w?.days ?? const <WeekDay>[])
        if (!d.date.isBefore(w!.today))
          for (final i in d.items)
            if ((i.isPep && i.mode != 'rest' || i.kind == 'test') && i.status == 'planned' && i.id != next?.$2.id) (d, i),
    ];
    final done = <(WeekDay, WeekItem)>[
      for (final d in (w?.days ?? const <WeekDay>[]).reversed)
        for (final i in d.items)
          if (i.status == 'done' && (i.isPep || i.kind == 'test')) (d, i),
    ];
    void open(WeekItem i) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => i.kind == 'test' ? UploadScreen(drill: i.drill) : SessionScreen(sessionKey: i.id)));
    return BPage(
      eyebrow: 'Pep',
      title: 'Sessions',
      sub: 'Short training sessions I build for you, around your schedule.',
      children: [
        const TrainingCard(),
        if (coming.isNotEmpty) ...[
          const BLab('Coming up'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Column(children: [
              for (final (k, (d, i)) in coming.indexed)
                BRow(
                  icon: i.kind == 'test' ? 'clock' : 'pace',
                  leading: TIcon(i.kind == 'test' ? 'clock' : 'pace', size: 16, color: Tk.inkSoft),
                  round: true,
                  title: i.title,
                  sub: [d.weekday, if ((i.durationMin ?? 0) > 0) '${i.durationMin} min', if (i.mode == 'light') 'easy before the match', if (i.kind == 'test') "I'll time you"].join(' · '),
                  trailing: const TIcon('chevron', size: 12, color: Tk.faint),
                  divider: k < coming.length - 1,
                  onTap: () => open(i),
                ),
            ]),
          ),
        ],
        if (done.isNotEmpty) ...[
          const BLab('Done lately'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Column(children: [
              for (final (k, (d, i)) in done.indexed)
                Opacity(
                  opacity: .75,
                  child: BRow(
                    icon: 'check',
                    leading: TIcon('check', size: 16, color: a.on, stroke: 6),
                    round: true,
                    tileColor: a.main,
                    title: i.title,
                    sub: '${d.weekday} · done',
                    divider: k < done.length - 1,
                    onTap: () => open(i),
                  ),
                ),
            ]),
          ),
        ],
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeekScreen())),
            child: const Text('See your schedule', style: TextStyle(color: Tk.muted)),
          ),
        ),
      ],
    );
  }
}

/// Today's training (canvas: Pep tab and Sessions): cone tile, what it is,
/// a big play button, what it trains, how long.
class TrainingCard extends StatelessWidget {
  const TrainingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = context.accent;
    final next = s.week?.nextSession;
    void go(Widget p) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => p));
    return Panel(
      onTap: next == null ? () => go(const WeekScreen()) : () => go(SessionScreen(sessionKey: next.$2.id)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: a.tile, borderRadius: BorderRadius.circular(14)),
            child: TIcon('cone', size: 20, color: a.main),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(next == null ? 'THIS WEEK' : (next.$1.isToday ? "TODAY'S TRAINING" : 'NEXT · ${next.$1.weekday.toUpperCase()}'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .66, color: a.main)),
              const SizedBox(height: 2),
              Text(next?.$2.title ?? 'All sessions done',
                  style: const TextStyle(fontFamily: TType.display, fontSize: 20, fontWeight: FontWeight.w600, height: 1.15, color: Tk.ink)),
            ]),
          ),
          if (next != null)
            Semantics(
              label: 'Start training',
              child: Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: a.main, shape: BoxShape.circle),
                child: TIcon('play', size: 16, color: a.on),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Text(
          next == null ? "You've done this week's sessions. Rest well, and I'll plan next week." : 'I picked this from your goal and your latest clips.',
          style: const TextStyle(fontSize: 13.5, height: 1.45, color: Tk.lab),
        ),
        if (next != null) ...[
          const SizedBox(height: 4),
          Text([if ((next.$2.durationMin ?? 0) > 0) '${next.$2.durationMin} minutes', if (next.$2.mode == 'light') 'easy, before your match'].join(' · '), style: bNote),
        ],
      ]),
    );
  }
}

// ───────────────────────────── your own football

/// Add or change your own football: team training, matches, school, games.
/// Pep fits its sessions around these. Adding has its own button; changing an
/// existing one saves as you go (the edit-sheet rule), with Remove at the end.
Future<void> showEventSheet(BuildContext context, {String? eventId, String? initialKind}) async {
  final String? kindArg = initialKind;
  final s = context.read<AppState>();
  FootballEvent? found;
  if (eventId != null) {
    try {
      found = (await s.api.events()).where((e) => e.id == eventId).firstOrNull;
    } catch (_) {}
  }
  if (!context.mounted) return;
  final existing = found;
  var kind = existing?.kind ?? kindArg ?? 'team';
  final days = {...?existing?.weekdays};
  final time = TextEditingController(text: existing?.time ?? '16:00');
  var saving = false;
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  Map<String, dynamic> body() {
    final t = time.text.trim();
    return {'weekdays': days.toList()..sort(), if (RegExp(r'^\d\d:\d\d$').hasMatch(t)) 'time': t};
  }

  Future<void> saveExisting() async {
    if (existing == null || days.isEmpty) return;
    try {
      await s.api.updateEvent(existing.id, body());
      await s.loadWeek();
    } catch (e) {
      if (context.mounted) showToast(context, "Couldn't save that", detail: '$e', ok: false, aboveTabs: false);
    }
  }

  await showEditSheet<void>(
    context,
    title: existing == null ? 'Add your football' : existing.title,
    child: StatefulBuilder(
      builder: (ctx, setState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (existing == null) ...[
          const SectionLabel('What is it?'),
          const SizedBox(height: 8),
          SingleChips<String>(
            options: const {'team': 'Team training', 'match': 'Match', 'school': 'School training', 'game': 'Game with friends'},
            value: kind,
            onChanged: (v) => setState(() => kind = v),
            scroll: false,
          ),
          const SizedBox(height: 20),
        ],
        const SectionLabel('Which days, every week?'),
        const SizedBox(height: 8),
        MultiChips<int>(
          options: {for (var i = 0; i < 7; i++) i: names[i]},
          values: days,
          onChanged: (v) {
            setState(() {
              days
                ..clear()
                ..addAll(v);
            });
            saveExisting();
          },
        ),
        const SizedBox(height: 20),
        TextField(
          controller: time,
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(labelText: 'Time (24 hour)', hintText: '16:00'),
          onSubmitted: (_) => saveExisting(),
        ),
        const SizedBox(height: 24),
        if (existing == null)
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: saving || days.isEmpty
                  ? null
                  : () async {
                      setState(() => saving = true);
                      try {
                        await s.api.addEvent({'kind': kind, ...body()});
                        await s.loadWeek();
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (context.mounted) showToast(context, 'Added', detail: 'Pep has fitted your week around it.');
                      } catch (e) {
                        setState(() => saving = false);
                        if (context.mounted) showToast(context, "Couldn't add it", detail: '$e', ok: false, aboveTabs: false);
                      }
                    },
              child: const Text('Add it'),
            ),
          )
        else
          Center(
            child: TextButton(
              onPressed: () async {
                try {
                  await s.api.deleteEvent(existing.id);
                  await s.loadWeek();
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) showToast(context, 'Removed', detail: 'Pep has fitted your week again.');
                } catch (e) {
                  if (context.mounted) showToast(context, "Couldn't remove it", detail: '$e', ok: false, aboveTabs: false);
                }
              },
              child: const Text('Remove'),
            ),
          ),
      ]),
    ),
  );
  // Leaving the sheet with a new time typed but not submitted still saves it.
  await saveExisting();
}
