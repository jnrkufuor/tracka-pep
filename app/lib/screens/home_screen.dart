import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/board.dart';
import '../widgets/ds.dart';
import '../widgets/pep.dart';
import '../widgets/tour.dart' show TourKeys;
import 'feed_screens.dart';
import 'guardian_screens.dart' show GuardianCard;
import 'notifications_screen.dart' show NotificationsScreen;
import 'pep_screen.dart' show FocusScreen;
import 'pitchside_screen.dart' show ChallengeRecordScreen;
import 'profile_screen.dart' show EditProfileScreen;
import 'training_screens.dart';
import 'upload_screen.dart';
import 'uploads_screen.dart' show UploadsCard;
import 'video_screen.dart';
import 'videos_screen.dart';

/// Home (canvas: Home, Home: edit mode, Customise home).
///
/// A stack of cards the player chooses and orders (Customise home, saved in
/// settings as `homeCards`). "Your road" is always on. Growth, not time:
/// progress is shown as change ("0.3 s faster"), never as weeks left.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Every card Home can show: id → (name, what it shows).
const homeCardInfo = <String, (String, String)>{
  'road': ('Your road', 'Where you are and your goal'),
  'week': ("Today's session", 'What Pep picked for today'),
  'noticed': ('Pep noticed', 'One thing from your clips'),
  'progress': ('Tests and PBs', 'Your times and best scores'),
  'challenge': ('Challenge of the week', 'Your best and how many are in'),
  'readiness': ('Academy-ready profile', 'What academies look for, ticked off'),
  'streak': ('Training streak', 'Weeks in a row you hit your plan'),
  'clips': ('Latest clips', 'Your newest 2'),
  'pitchside': ('Worth a watch', 'Players your age on Pitchside'),
};

/// Pep's suggestion, by goal. Casual players see less training and more Pitchside.
List<String> defaultHomeCards(String? goal) => switch (goal) {
      'fun' || 'looking' => ['road', 'week', 'pitchside', 'challenge', 'clips'],
      'academy' => ['road', 'week', 'noticed', 'progress', 'readiness', 'challenge', 'streak', 'clips', 'pitchside'],
      _ => ['road', 'week', 'noticed', 'progress', 'challenge', 'streak', 'clips', 'pitchside'],
    };

List<String> homeCardsFor(AppSettings s, String? goal) {
  final chosen = (s.homeCards ?? defaultHomeCards(goal)).where(homeCardInfo.containsKey).toList();
  return ['road', ...chosen.where((c) => c != 'road')];
}

class _HomeScreenState extends State<HomeScreen> {
  ProgressState? progress;
  ChallengesState? challenges;
  List<FeedPost>? feed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    try {
      final p = await api.progress();
      if (mounted) setState(() => progress = p);
    } catch (_) {}
    try {
      final c = await api.challenges();
      if (mounted) setState(() => challenges = c);
    } catch (_) {}
    try {
      final f = await api.feed();
      if (mounted) setState(() => feed = f.posts.take(4).toList());
    } catch (_) {}
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
  }

  /// The day picked in the week strip (canvas Home: "tap days"). Today at first.
  DateTime? picked;

  void _go(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;
    final name = me?.profile.firstName ?? '';
    final cards = homeCardsFor(s.settings, me?.profile.goal);
    final p = progress;
    final tested = p?.tests.isNotEmpty ?? false;
    final following = {for (final f in feed ?? const <FeedPost>[]) if (f.author.following) f.author.id}.length;
    final start = [
      (title: 'Tell Pep about your game', sub: 'Done when you signed up', done: true, go: () {}),
      (title: 'Do your baseline tests', sub: 'Sprint and juggling, about 15 min', done: tested, go: () => _go(const FocusScreen())),
      (title: 'Upload your first clip', sub: 'Any game or drill. 20 seconds is enough', done: s.videos.isNotEmpty, go: () => openUpload(context)),
      (title: 'Follow 3 players', sub: 'Fills up your Pitchside feed', done: following >= 3, go: () => widget.onOpenTab(1)),
    ];
    // Day one (canvas "Home on day one"): no tests and no clips yet, so the
    // progress and clip areas are dashed placeholders and Pep says hello.
    final dayOne = !tested && s.videos.isEmpty;
    final startOpen = start.any((x) => !x.done);
    final ready = s.videos.where((v) => v.status == 'READY').firstOrNull;
    final children = <Widget>[
      if (s.offline) const OfflineBanner(),
      const GuardianCard(),
      const UploadsCard(),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: EnterFade(child: BHead(eyebrow: dayOne ? 'Welcome' : _greeting(), title: name.isEmpty ? 'Hello' : name, size: 32))),
        BRoundButton(icon: 'settings', label: 'Customise home', onTap: () => _go(const CustomiseHomeScreen())),
        const SizedBox(width: 8),
        BRoundButton(
          icon: 'bell',
          label: s.unread > 0 ? 'Notifications, ${s.unread} new' : 'Notifications',
          dot: s.unread > 0,
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
            await s.loadUnread();
          },
        ),
      ]),
      KeyedSubtree(
        key: TourKeys.road,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _GoalPill(goal: me?.profile.goal),
          const SizedBox(height: 18),
          if (s.week != null)
            _WeekStrip(
              week: s.week!,
              firstWeek: dayOne,
              picked: picked,
              onPick: dayOne ? null : (d) => setState(() => picked = d),
            ),
        ]),
      ),
      if (dayOne)
        BPepNote(
          mood: PepMood.excited,
          title: name.isEmpty ? "Hi, I'm Pep" : "Hi $name, I'm Pep",
          text: 'Your first week is ready. Start with your baseline tests, so I know where you are now.',
          onTap: () => widget.onOpenTab(2),
        )
      else if (s.week != null)
        _DayCard(week: s.week!, picked: picked),
      if (startOpen) KeyedSubtree(key: TourKeys.progress, child: _StartHere(items: start)),
      if (dayOne) ...[
        const BLab('Your progress', note: 'Starts after your baseline'),
        const _ProgressSoon(),
        const BLab('Your clips'),
        Pressable(
          onTap: () => openUpload(context),
          child: const BDashed(
            child: Row(children: [
              IconTile(icon: 'clip', color: Tk.muted, background: Tk.field, size: 40),
              SizedBox(width: 14),
              Expanded(child: Text('Film any game or drill with the + button. Pep analyses every clip and sends you tips.', style: TextStyle(fontSize: 13, height: 1.45, color: Tk.muted))),
            ]),
          ),
        ),
      ] else ...[
        if (cards.any(_progressPages.contains))
          KeyedSubtree(
            key: startOpen ? null : TourKeys.progress,
            child: _ProgressPager(pages: [
              for (final c in cards)
                if (_progressPages.contains(c))
                  switch (c) {
                    'progress' => _ProgressCard(p: p),
                    'challenge' => _ChallengeCard(c: challenges),
                    'readiness' => _ReadinessCard(p: p),
                    _ => _StreakCard(p: p),
                  },
            ]),
          ),
        if (cards.contains('noticed') && ready != null)
          BPepNote(
            mood: PepMood.thinking,
            title: 'Pep noticed',
            text: ready.reviewNote ?? 'I watched ${ready.displayTitle}. Your tips are ready.',
            chip: 'Pep saw',
            onTap: () => _go(VideoScreen(videoId: ready.id)),
          ),
        if (cards.contains('clips')) ...[
          BLab('Your latest clips', link: 'See all', onLink: () => _go(const VideosScreen())),
          const _LatestClips(),
        ],
      ],
      if ((cards.contains('pitchside') || dayOne) && (feed?.isNotEmpty ?? false)) ...[
        BLab('Worth a watch', link: 'Pitchside', onLink: () => widget.onOpenTab(1)),
        Transform.translate(
          offset: const Offset(0, -12),
          child: const Text('Players your age near you, picked for what they did this week.', style: bNote),
        ),
        _WorthAWatch(posts: feed!),
      ],
    ];
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await s.refresh();
            await _load();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 18), c],
            ],
          ),
        ),
      ),
    );
  }
}

const _progressPages = {'progress', 'challenge', 'readiness', 'streak'};

/// "Goal: get into an academy" under your name. Tap to change it.
class _GoalPill extends StatelessWidget {
  const _GoalPill({required this.goal});

  final String? goal;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
          decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFF262626))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            TIcon('flag', size: 14, color: context.accent.main),
            const SizedBox(width: 7),
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Goal: '),
                  TextSpan(text: _RoadCard.goals[goal] ?? 'pick one', style: const TextStyle(fontWeight: FontWeight.w600, color: Tk.ink)),
                ]),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFFD5D9CE)),
              ),
            ),
          ]),
        ),
      );
}

/// What a day is mostly about, for the week strip: (short word, ring colour).
(String, Color, double) _dayKind(BuildContext context, WeekDay d) {
  final kinds = d.items.map((i) => i.kind).toSet();
  if (d.matchDay || kinds.contains('match')) return ('Match', Tk.gold, 1);
  if (kinds.contains('test')) return ('Test', Tk.pep, 1);
  if (d.items.any((i) => i.kind == 'pep' && i.mode != 'rest')) return ('Pep', Tk.pep, 1);
  if (kinds.contains('school')) return ('School', context.accent.main, 1);
  if (kinds.any((k) => k == 'team' || k == 'game' || k == 'other')) return ('Team', context.accent.main, 1);
  return ('Rest', Tk.stone, .55);
}

/// The seven days (canvas Home "This week" / day one "Your first week").
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.week, required this.firstWeek, required this.picked, required this.onPick});

  final Week week;
  final bool firstWeek;
  final DateTime? picked;
  final ValueChanged<DateTime>? onPick;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final pep = week.days.expand((d) => d.items).where((i) => i.kind == 'pep' && i.mode != 'rest');
    final done = pep.where((i) => i.status == 'done').length;
    final match = week.days.where((d) => d.matchDay).firstOrNull;
    final sel = picked ?? week.todayDay?.date;
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Expanded(child: Text(firstWeek ? 'Your first week' : 'This week', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.lab))),
            Flexible(
              child: Text(
                firstWeek
                    ? 'Built by Pep from your schedule'
                    : '$done of ${pep.length} sessions${match == null ? '' : ' · match ${match.weekday.substring(0, 3)}'}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Tk.muted),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (final d in week.days)
            Expanded(
              child: Builder(builder: (context) {
                final (word, ring, ringOpacity) = _dayKind(context, d);
                final on = sel != null && DateUtils.isSameDay(d.date, sel);
                final past = d.date.isBefore(week.today) && !d.isToday;
                final allDone = d.items.isNotEmpty && d.items.where((i) => i.isPep).every((i) => i.status == 'done') && d.items.any((i) => i.isPep);
                final cell = Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: on ? a.tile : null,
                    borderRadius: BorderRadius.circular(12),
                    border: on ? Border.all(color: a.main, width: 1.5) : null,
                  ),
                  child: Column(children: [
                    Text(d.weekday.isEmpty ? '' : d.weekday.substring(0, 1),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: on ? Tk.ink : Tk.faint)),
                    const SizedBox(height: 6),
                    if (allDone)
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: a.main),
                        child: TIcon('check', size: 12, color: a.on, stroke: 6),
                      )
                    else
                      Opacity(
                        opacity: ringOpacity,
                        child: Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2))),
                      ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(word, maxLines: 1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: on ? Tk.ink : Tk.faint)),
                    ),
                  ]),
                );
                final shown = Opacity(opacity: past && !allDone && firstWeek ? .35 : 1, child: cell);
                return Semantics(
                  button: onPick != null,
                  selected: on,
                  label: '${d.weekday}: $word',
                  excludeSemantics: true,
                  child: onPick == null ? shown : Pressable(onTap: () => onPick!(d.date), child: shown),
                );
              }),
            ),
        ]),
      ]),
    );
  }
}

/// The picked day, under the week (canvas Home: what's on, Pep's focus, go).
class _DayCard extends StatelessWidget {
  const _DayCard({required this.week, required this.picked});

  final Week week;
  final DateTime? picked;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final day = week.days.where((d) => DateUtils.isSameDay(d.date, picked ?? week.today)).firstOrNull ?? week.todayDay ?? week.days.first;
    final item = day.items.where((i) => i.isPep && i.mode != 'rest').firstOrNull ?? day.items.where((i) => i.kind == 'match').firstOrNull ?? day.items.firstOrNull;
    final (word, colour, _) = _dayKind(context, day);
    final kind = item?.kind ?? 'rest';
    final (icon, tile) = switch (kind) {
      'pep' || 'test' => ('pep', Tk.pepTile),
      'match' => ('trophy', Tk.goldTile),
      'rest' => ('clock', Tk.stoneTile),
      _ => ('ball', a.tile),
    };
    final label = day.isToday ? 'Today' : day.weekday;
    final title = item?.title ?? 'Rest day';
    final sub = [if (item?.time != null) item!.time!, if (item?.durationMin != null) '${item!.durationMin} min'].join(' · ');
    final focus = switch (kind) {
      'pep' => 'I picked this from your goal and your latest clips. Go at your own pace.',
      'test' => "Do it the same way every time, so we see real change. I'll time you from the video.",
      'match' => 'Match day. Warm up well, scan before you get the ball, and enjoy it.',
      'rest' => 'Rest is part of training. Sleep well and eat well: your body grows today.',
      _ => 'Team training. Tell me how it felt after, and I will plan around it.',
    };
    final canStart = item != null && item.isPep && item.mode != 'rest' && item.status == 'planned' && !day.date.isBefore(week.today);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconTile(icon: icon, color: colour, background: tile, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$label · $word'.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6, color: colour)),
              const SizedBox(height: 2),
              Text(title, style: const TextStyle(fontFamily: TType.display, fontSize: 20, fontWeight: FontWeight.w600, height: 1.15, color: Tk.ink)),
              if (sub.isNotEmpty) Text(sub, style: bNote),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        BPepNote(mood: kind == 'rest' ? PepMood.calm : PepMood.reading, text: focus),
        const SizedBox(height: 12),
        if (canStart)
          BCta('Start training', height: Tk.btnInCard, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SessionScreen(sessionKey: item.id))))
        else
          BCta('See your week', ghost: true, height: Tk.btnInCard, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeekScreen()))),
        if (week.health != 'fine') ...[
          const SizedBox(height: 12),
          Pressable(
            onTap: () => showHealthSheet(context),
            child: SafetyNote(week.health == 'sore'
                ? 'Pep has made your sessions lighter. Tap to update how your body feels.'
                : 'Pep has paused your training. Tap to update how your body feels.'),
          ),
        ],
      ]),
    );
  }
}

/// "Start here": four first steps, ticked off as you do them (canvas day one).
class _StartHere extends StatelessWidget {
  const _StartHere({required this.items});

  final List<({String title, String sub, bool done, VoidCallback go})> items;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final n = items.where((x) => x.done).length;
    final next = items.where((x) => !x.done).firstOrNull;
    final cta = switch (next?.title) {
      'Do your baseline tests' => 'Start baseline tests',
      'Upload your first clip' => 'Film your first clip',
      'Follow 3 players' => 'Find players to follow',
      _ => null,
    };
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Start here', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.lab))),
          Text('$n of ${items.length} done', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Tk.muted)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            height: 5,
            child: Stack(children: [
              const Positioned.fill(child: ColoredBox(color: Color(0xFF262626))),
              FractionallySizedBox(widthFactor: n / items.length, heightFactor: 1, child: ColoredBox(color: a.main)),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        for (final (i, x) in items.indexed)
          Pressable(
            onTap: x.done ? null : x.go,
            child: Container(
              padding: EdgeInsets.fromLTRB(0, 12, 0, i == items.length - 1 ? 6 : 12),
              decoration: i == items.length - 1 ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.line))),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: x.done ? a.main : null,
                    border: x.done ? null : Border.all(color: x == next ? a.main : const Color(0xFF3A3D36), width: 2),
                  ),
                  child: x.done
                      ? TIcon('check', size: 14, color: a.on, stroke: 6)
                      : Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: x == next ? a.main : Tk.faint)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: x.done ? Tk.faint : Tk.ink,
                          decoration: x.done ? TextDecoration.lineThrough : null,
                          decorationColor: Tk.faint,
                        )),
                    const SizedBox(height: 2),
                    Text(x.sub, style: bNote.copyWith(fontSize: 12.5)),
                  ]),
                ),
              ]),
            ),
          ),
        if (cta != null && next != null) ...[const SizedBox(height: 8), BCta(cta, height: Tk.btnInCard, onTap: next.go)],
      ]),
    );
  }
}

/// Day one: what your progress will show once you've done your baseline.
class _ProgressSoon extends StatelessWidget {
  const _ProgressSoon();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('chart', 'Getting better', 'After 2 tests'),
      ('trophy', 'Challenges', 'Every Monday'),
      ('you', 'Profile', '0 of 5'),
      ('streak', 'Streak', 'After week 1'),
    ];
    Widget cell((String, String, String) x) => Row(children: [
          IconTile(icon: x.$1, color: Tk.muted, background: Tk.field, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Tk.lab)),
              Text(x.$3, style: const TextStyle(fontSize: 11, color: Tk.muted)),
            ]),
          ),
        ]);
    return BDashed(
      child: Column(children: [
        Row(children: [Expanded(child: cell(items[0])), const SizedBox(width: 12), Expanded(child: cell(items[1]))]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: cell(items[2])), const SizedBox(width: 12), Expanded(child: cell(items[3]))]),
      ]),
    );
  }
}

/// "Your progress": one card at a time, with dots to switch (canvas Home).
class _ProgressPager extends StatefulWidget {
  const _ProgressPager({required this.pages});

  final List<Widget> pages;

  @override
  State<_ProgressPager> createState() => _ProgressPagerState();
}

class _ProgressPagerState extends State<_ProgressPager> {
  int i = 0;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final n = widget.pages.length;
    final at = i.clamp(0, n - 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: Text('Your progress', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.lab))),
        if (n > 1)
          for (var k = 0; k < n; k++)
            Semantics(
              button: true,
              selected: k == at,
              label: 'Progress card ${k + 1} of $n',
              excludeSemantics: true,
              child: Pressable(
                onTap: () => setState(() => i = k),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: AnimatedContainer(
                    duration: Motion.of(context, Motion.select),
                    width: k == at ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(color: k == at ? a.main : const Color(0xFF3A3D36), borderRadius: BorderRadius.circular(9)),
                  ),
                ),
              ),
            ),
      ]),
      const SizedBox(height: 10),
      GestureDetector(
        onHorizontalDragEnd: (e) {
          final v = e.primaryVelocity ?? 0;
          if (v < -150 && at < n - 1) setState(() => i = at + 1);
          if (v > 150 && at > 0) setState(() => i = at - 1);
        },
        child: AnimatedSwitcher(duration: Motion.of(context, Motion.select), child: KeyedSubtree(key: ValueKey(at), child: widget.pages[at])),
      ),
    ]);
  }
}

/// Your two newest clips, side by side, with Pep's status on each.
class _LatestClips extends StatelessWidget {
  const _LatestClips();

  @override
  Widget build(BuildContext context) {
    final vids = context.watch<AppState>().videos.take(2).toList();
    Widget tile(Video v) => Pressable(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: v.id))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BThumb(url: v.thumbnailUrl, height: 120, children: [
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    PepFace(v.processing ? PepMood.watching : PepMood.justHere, size: 14),
                    const SizedBox(width: 5),
                    Text(v.processing ? 'Pep is watching' : v.status == 'FAILED' ? "Couldn't read" : 'Analysed',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(v.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Tk.ink)),
            Text(v.processing ? 'Ready in about 10 min' : (v.reviewNote ?? 'Tips ready'), maxLines: 1, overflow: TextOverflow.ellipsis, style: bNote),
          ]),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, v) in vids.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: tile(v))],
      if (vids.length == 1) ...[const SizedBox(width: 10), const Expanded(child: SizedBox())],
    ]);
  }
}

/// Players your age, in a row you scroll sideways (canvas "Worth a watch").
class _WorthAWatch extends StatelessWidget {
  const _WorthAWatch({required this.posts});

  final List<FeedPost> posts;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 180,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final p = posts[i];
            return SizedBox(
              width: 112,
              child: Pressable(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FeedScreen(posts: posts, startAt: i))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  BThumb(url: p.thumbnailUrl, height: 136, children: [
                    if (p.caption.isNotEmpty)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Text(p.caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, height: 1.25, fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    Positioned(
                      right: 7,
                      top: 7,
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                        child: const TIcon('play', size: 10, color: Colors.white),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(p.author.shirtName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                  Text(p.author.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Tk.muted)),
                ]),
              ),
            );
          },
        ),
      );
}

Future<void> openUpload(BuildContext context, {String? drill, String? challenge, String? title}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => UploadScreen(drill: drill, challenge: challenge, title: title)));

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.lab)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]);
}

class _RoadCard extends StatelessWidget {
  const _RoadCard();

  static const goals = {
    'fun': 'play more and have fun',
    'school': 'make my school team',
    'academy': 'get into an academy',
    'standout': 'stand out where I play',
    'better': 'just get better',
    'looking': 'look around',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppState>().me?.profile;
    final goal = goals[p?.goal];
    final here = [if (p?.positions.isNotEmpty ?? false) p!.positions.first, if (p?.region != null) p!.region!].join(' · ');
    return Panel(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _Label('Your road'),
            const SizedBox(height: 6),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Goal: ', style: TextStyle(color: Tk.muted)),
              TextSpan(text: goal ?? 'pick one in your profile', style: const TextStyle(fontWeight: FontWeight.w600, color: Tk.ink)),
            ]), style: const TextStyle(fontSize: 15)),
            if (here.isNotEmpty) Text("You're here: $here", style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
          ]),
        ),
        const IconTile(icon: 'flag', color: Tk.gold, background: Tk.goldTile, size: 40),
      ]),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.p});

  final ProgressState? p;

  @override
  Widget build(BuildContext context) {
    final x = p?.tests.firstOrNull;
    String fmt(double v, String unit) => unit == 's' ? '${v.toStringAsFixed(1)} s' : v.toStringAsFixed(0);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Label('Tests and PBs'),
        const SizedBox(height: 8),
        if (x == null) ...[
          const Text('Timed tests, retaken every 2 weeks', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
          const SizedBox(height: 4),
          const Text('Do a test twice and your progress shows here.', style: TextStyle(fontSize: 13, color: Tk.muted)),
        ] else ...[
          Text(x.label, style: const TextStyle(fontSize: 13, color: Tk.muted)),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmt(x.latest, x.unit), style: const TextStyle(fontFamily: TType.display, fontSize: 32, fontWeight: FontWeight.w800, color: Tk.ink)),
            const SizedBox(width: 10),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  x.better ? '${fmt(x.change, x.unit)} ${x.unit == 's' ? 'faster' : 'more'}' : 'from ${fmt(x.first, x.unit)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: x.better ? context.accent.main : Tk.muted),
                ),
              ),
            ),
          ]),
          Text('From ${fmt(x.first, x.unit)} to ${fmt(x.latest, x.unit)} in ${x.weeks} week${x.weeks == 1 ? '' : 's'}.',
              style: const TextStyle(fontSize: 13, color: Tk.inkSoft)),
          if (x.line != null) Text(x.line!, style: const TextStyle(fontSize: 13, color: Tk.inkSoft)),
        ],
      ]),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.c});

  final ChallengesState? c;

  @override
  Widget build(BuildContext context) {
    final w = c?.thisWeek;
    if (w == null) return const SizedBox.shrink();
    final days = w.endsOn.difference(DateTime.now()).inDays + 1;
    return Panel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengeRecordScreen(challenge: w))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label('Challenge of the week',
            trailing: Text(days <= 1 ? 'Ends today' : 'Ends in $days days', style: const TextStyle(fontSize: 12, color: Tk.muted))),
        const SizedBox(height: 6),
        Text(w.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Tk.ink)),
        const SizedBox(height: 6),
        Text(w.best == null ? '${w.playersIn} players in. Film your go.' : 'Your best: ${w.best} · ${w.playersIn} players in',
            style: const TextStyle(fontSize: 13, color: Tk.inkSoft)),
      ]),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.p});

  final ProgressState? p;

  @override
  Widget build(BuildContext context) {
    final x = p;
    if (x == null) return const SizedBox.shrink();
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Label('Academy-ready profile'),
        const SizedBox(height: 6),
        Text('${x.readyDone} of ${x.readyTotal} done.${x.readyNext == null ? '' : ' Next: ${x.readyNext!.toLowerCase()}.'}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
        const SizedBox(height: 10),
        Row(children: [
          for (final st in x.readySteps)
            Expanded(
              child: Container(
                height: 6,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(color: st.done ? context.accent.main : Tk.lineStrong, borderRadius: BorderRadius.circular(999)),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.p});

  final ProgressState? p;

  @override
  Widget build(BuildContext context) {
    final x = p;
    if (x == null) return const SizedBox.shrink();
    final left = x.weekPlanned - x.weekDone;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Label('Training streak'),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${x.streakWeeks}', style: const TextStyle(fontFamily: TType.display, fontSize: 32, fontWeight: FontWeight.w800, color: Tk.ink)),
          const SizedBox(width: 8),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(x.streakWeeks == 1 ? 'week in a row' : 'weeks in a row', style: const TextStyle(fontSize: 13, color: Tk.muted)),
            ),
          ),
        ]),
        Text(
          [
            if (x.bestStreak > x.streakWeeks) 'Your best is ${x.bestStreak} weeks.',
            if (left > 0) 'One more session this week keeps it going.' else if (x.weekPlanned > 0) 'This week is done. Nice.',
          ].join(' '),
          style: const TextStyle(fontSize: 13, color: Tk.inkSoft),
        ),
      ]),
    );
  }
}

class CustomiseHomeScreen extends StatelessWidget {
  const CustomiseHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final goal = s.me?.profile.goal;
    final on = homeCardsFor(s.settings, goal);
    final off = homeCardInfo.keys.where((k) => !on.contains(k)).toList();
    Future<void> save(List<String> cards) => s.saveSettings({'homeCards': cards});
    Widget row(String id, {required bool isOn, Key? key}) => ListTile(
          key: key,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Text(homeCardInfo[id]!.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(homeCardInfo[id]!.$2),
          trailing: id == 'road'
              ? const Text('Always on', style: TextStyle(fontSize: 12, color: Tk.faint))
              : Switch(
                  value: isOn,
                  onChanged: (v) => save(v ? [...on, id] : on.where((c) => c != id).toList()),
                ),
        );
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('Customise home', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text('Switch cards on or off. Drag to move them.', style: TextStyle(fontSize: 13.5, color: Tk.muted)),
        const SizedBox(height: 16),
        const SectionLabel('On your home'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorder: (from, to) {
              final list = [...on];
              final item = list.removeAt(from);
              list.insert(to > from ? to - 1 : to, item);
              save(list);
            },
            children: [for (final id in on) row(id, isOn: true, key: ValueKey(id))],
          ),
        ),
        if (off.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionLabel('More cards you can add'),
          Panel(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: [for (final id in off) row(id, isOn: false)])),
        ],
        const SizedBox(height: 16),
        OutlinedButton(onPressed: () => save(defaultHomeCards(goal)), child: const Text("Reset to Pep's suggestion")),
      ]),
    );
  }
}
