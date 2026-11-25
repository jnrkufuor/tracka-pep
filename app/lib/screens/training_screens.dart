import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
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
(String, Color, Color) _look(BuildContext context, WeekItem i) {
  final a = context.accent;
  return switch (i.kind) {
    'pep' => ('pep', a.main, a.tile),
    'test' => ('pace', a.main, a.tile),
    'rest' => ('hurt', Tk.gold, Tk.goldTile),
    'match' => ('trophy', Tk.stone, Tk.stoneTile),
    _ => ('ball', Tk.stone, Tk.stoneTile),
  };
}

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
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Your week')),
      body: w == null
          ? (_error != null
              ? StateView.error(onRetry: () => _load(_start))
              : ListView(padding: const EdgeInsets.all(20), children: const [Skeleton(height: 60), SizedBox(height: 12), Skeleton(height: 240)]))
          : RefreshIndicator(
              onRefresh: () => _load(_start),
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
                Row(children: [
                  IconButton(
                    tooltip: 'Week before',
                    onPressed: _loading ? null : () => _load(w.start.subtract(const Duration(days: 7))),
                    icon: const TIcon('back', size: 18, color: Tk.ink),
                  ),
                  Expanded(
                    child: Text('${_dayLabel(w.start)} – ${_dayLabel(w.start.add(const Duration(days: 6)))}',
                        textAlign: TextAlign.center, style: t.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Week after',
                    onPressed: _loading ? null : () => _load(w.start.add(const Duration(days: 7))),
                    icon: const TIcon('chevron', size: 18, color: Tk.ink),
                  ),
                ]),
                const SizedBox(height: 10),
                for (final d in w.days) _DayBlock(day: d, past: d.date.isBefore(w.today), onChanged: () => _load(_start)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    await showEventSheet(context);
                    if (mounted) await _load(_start);
                  },
                  child: const Text('Add your football'),
                ),
                const SizedBox(height: 10),
                TextButton(onPressed: () => showHealthSheet(context), child: const Text("How's your body?")),
              ]),
            ),
    );
  }
}

class _DayBlock extends StatelessWidget {
  const _DayBlock({required this.day, required this.past, required this.onChanged});

  final WeekDay day;
  final bool past;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(day.isToday ? 'Today' : day.weekday,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: day.isToday ? a.main : (past ? Tk.faint : Tk.ink))),
          const SizedBox(width: 8),
          Text(_dayLabel(day.date), style: const TextStyle(fontSize: 12.5, color: Tk.faint)),
          if (day.matchDay) ...[
            const SizedBox(width: 8),
            const Text('Match day', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Tk.stone)),
          ],
        ]),
        const SizedBox(height: 6),
        if (day.items.isEmpty)
          const Padding(padding: EdgeInsets.only(left: 2), child: Text('Free', style: TextStyle(fontSize: 13, color: Tk.faint)))
        else
          for (final i in day.items) _ItemRow(item: i, day: day, past: past, onChanged: onChanged),
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
    final (icon, fg, bg) = _look(context, item);
    final faded = item.status == 'skipped' || past;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => _tap(context),
        child: Opacity(
          opacity: faded && item.status != 'done' ? 0.55 : 1,
          child: Row(children: [
            IconTile(icon: icon, color: fg, background: bg, size: 38),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                if (_itemLine(item).isNotEmpty) Text(_itemLine(item), style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
              ]),
            ),
            if (item.status == 'done') TIcon('check', size: 18, color: context.accent.main, stroke: 5),
            if (item.status == 'skipped') const Text('Skipped', style: TextStyle(fontSize: 12, color: Tk.faint)),
          ]),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<SessionPlan>(
        future: _plan,
        builder: (context, snap) {
          if (snap.hasError) {
            return StateView.error(onRetry: () => setState(() => _plan = context.read<AppState>().api.session(widget.sessionKey)));
          }
          if (!snap.hasData) {
            return ListView(padding: const EdgeInsets.all(20), children: const [
              Skeleton(height: 40, width: 220),
              SizedBox(height: 16),
              Skeleton(height: 90),
              SizedBox(height: 10),
              Skeleton(height: 90),
            ]);
          }
          final p = snap.data!;
          final t = Theme.of(context).textTheme;
          final canFinish = p.status == 'planned' && p.mode != 'rest' && !p.date.isAfter(DateTime.now());
          return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
            EnterFade(child: Text(p.title, style: t.headlineLarge)),
            const SizedBox(height: 4),
            Text(
              [if (p.minutes > 0) '${p.minutes} min', if (p.focus.isNotEmpty) 'Works on ${p.focus.join(' and ').toLowerCase()}'].join(' · '),
              style: const TextStyle(fontSize: 14, color: Tk.muted),
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < p.steps.length; i++)
              EnterFade(
                delay: Duration(milliseconds: 40 * i),
                child: Padding(padding: const EdgeInsets.only(bottom: 10), child: _StepCard(step: p.steps[i], n: i + 1)),
              ),
            const SizedBox(height: 6),
            SafetyNote(p.safety),
            const SizedBox(height: 20),
            if (canFinish)
              FilledButton(
                onPressed: () async {
                  final ok = await showDoneSheet(context, p.key);
                  if (ok && context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Finish training'),
              ),
            if (p.status == 'done')
              const Text("Done. Nice work.", textAlign: TextAlign.center, style: TextStyle(color: Tk.muted)),
            if (p.mode == 'rest')
              OutlinedButton(onPressed: () => showHealthSheet(context), child: const Text("Update how your body feels")),
          ]);
        },
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.n});

  final SessionStep step;
  final int n;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final needs = step.needs.where((n) => n != 'nothing').toList();
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: a.tile, shape: BoxShape.circle),
            child: Text('$n', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: a.main)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(step.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Tk.ink))),
          Text('${step.minutes} min', style: const TextStyle(fontSize: 12.5, color: Tk.faint)),
        ]),
        const SizedBox(height: 8),
        Text(step.how, style: const TextStyle(fontSize: 14, height: 1.45, color: Tk.inkSoft)),
        if (needs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('You need: ${needs.join(', ')}', style: const TextStyle(fontSize: 12.5, color: Tk.faint)),
        ],
        if (step.film != null) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UploadScreen(drill: step.film))),
            child: Text(step.test != null ? 'Film the test' : 'Film it and Pep counts'),
          ),
        ],
      ]),
    );
  }
}

// ───────────────────────────── training done

/// "How was it?" after a session: how hard (Easy / Just right / Hard) and
/// whether anything hurt. Something hurt → Pep makes sessions lighter and
/// points to an adult, coach, doctor or physio. Returns true when logged.
Future<bool> showDoneSheet(BuildContext context, String key) async {
  final s = context.read<AppState>();
  var effort = 'right';
  var hurt = false;
  var saving = false;
  final logged = await showEditSheet<bool>(
    context,
    title: 'How was it?',
    child: StatefulBuilder(
      builder: (ctx, setState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionLabel('How hard was it?'),
        const SizedBox(height: 8),
        SingleChips<String>(
          options: const {'easy': 'Easy', 'right': 'Just right', 'hard': 'Hard'},
          value: effort,
          onChanged: (v) => setState(() => effort = v),
          scroll: false,
        ),
        const SizedBox(height: 22),
        const SectionLabel('Did anything hurt?'),
        const SizedBox(height: 8),
        SingleChips<bool>(
          options: const {false: 'No', true: 'Yes'},
          value: hurt,
          onChanged: (v) => setState(() => hurt = v),
          scroll: false,
        ),
        if (hurt) ...[
          const SizedBox(height: 14),
          const SafetyNote("Pep will make your next sessions lighter. Don't play through pain, and tell an adult or your coach."),
        ],
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: saving
                ? null
                : () async {
                    setState(() => saving = true);
                    try {
                      final next = await s.api.finishSession(key, effort: effort, hurt: hurt);
                      await s.loadWeek();
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                      if (context.mounted) showToast(context, 'Training logged', detail: next);
                    } catch (e) {
                      setState(() => saving = false);
                      if (ctx.mounted) showToast(ctx, "Couldn't save it", detail: '$e', ok: false, aboveTabs: false);
                    }
                  },
            child: const Text('Done'),
          ),
        ),
      ]),
    ),
  );
  return logged ?? false;
}

// ───────────────────────────── how your body feels

/// Health: guide and refer. Pep never diagnoses or gives food plans; it
/// changes the plan (lighter, or rest) and points to the right people.
Future<void> showHealthSheet(BuildContext context) {
  final s = context.read<AppState>();
  var status = s.health?.status ?? 'fine';
  final area = TextEditingController(text: s.health?.area ?? '');
  return showEditSheet<void>(
    context,
    title: "How's your body?",
    child: StatefulBuilder(
      builder: (ctx, setState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChips<String>(
          options: const {'fine': 'Feeling fine', 'sore': 'A bit sore', 'pain': 'In pain', 'injured': 'Injured'},
          value: status,
          onChanged: (v) async {
            setState(() => status = v);
            try {
              await s.setHealth(v, area: v == 'fine' ? null : area.text.trim().isEmpty ? null : area.text.trim());
            } catch (e) {
              if (ctx.mounted) showToast(ctx, "Couldn't save it", detail: '$e', ok: false, aboveTabs: false);
            }
          },
          scroll: false,
        ),
        if (status != 'fine') ...[
          const SizedBox(height: 18),
          TextField(
            controller: area,
            decoration: const InputDecoration(labelText: 'Where? (optional)', hintText: 'Left ankle'),
            onSubmitted: (v) => s.setHealth(status, area: v.trim().isEmpty ? null : v.trim()),
          ),
          const SizedBox(height: 14),
          SafetyNote(switch (status) {
            'sore' => 'Pep has made your sessions lighter. Stop if anything hurts.',
            'pain' => "Rest today. Don't play through pain. Tell an adult or your coach.",
            _ => 'Rest, and see a doctor or physio. Pep pauses your training until you say you are ready.',
          }),
          const SizedBox(height: 10),
          const InfoNote("Pep is a football coach, not a doctor. If it's serious, like a head injury or a lot of pain, get help straight away."),
        ],
      ]),
    ),
  );
}

// ───────────────────────────── your own football

/// Add or change your own football: team training, matches, school, games.
/// Pep fits its sessions around these. Adding has its own button; changing an
/// existing one saves as you go (the edit-sheet rule), with Remove at the end.
Future<void> showEventSheet(BuildContext context, {String? eventId}) async {
  final s = context.read<AppState>();
  FootballEvent? found;
  if (eventId != null) {
    try {
      found = (await s.api.events()).where((e) => e.id == eventId).firstOrNull;
    } catch (_) {}
  }
  if (!context.mounted) return;
  final existing = found;
  var kind = existing?.kind ?? 'team';
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
