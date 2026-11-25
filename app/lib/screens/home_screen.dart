import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/common.dart' show TrackaLogo;
import '../widgets/ds.dart';
import 'feed_screens.dart';
import 'guardian_screens.dart' show GuardianCard;
import 'notifications_screen.dart' show BellButton;
import 'pitchside_screen.dart' show ChallengeRecordScreen;
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;
    final t = Theme.of(context).textTheme;
    final cards = homeCardsFor(s.settings, me?.profile.goal);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await s.refresh();
            await _load();
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 28), children: [
            Row(children: [
              const TrackaLogo(size: 28),
              const Spacer(),
              const BellButton(),
              IconButton(
                tooltip: 'Customise home',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomiseHomeScreen())),
                icon: const TIcon('settings', size: 21, color: Tk.ink),
              ),
            ]),
            const SizedBox(height: 14),
            if (s.offline) ...[const OfflineBanner(), const SizedBox(height: 12)],
            const GuardianCard(),
            const UploadsCard(),
            Text(_greeting(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.accent.main)),
            Text(me?.profile.firstName ?? 'Hello', style: t.displayMedium),
            const SizedBox(height: 16),
            for (final c in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onLongPress: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomiseHomeScreen())),
                  child: _card(c),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _card(String id) => switch (id) {
        'road' => const _RoadCard(),
        'week' => const TodayCard(),
        'noticed' => const _NoticedCard(),
        'progress' => _ProgressCard(p: progress),
        'challenge' => _ChallengeCard(c: challenges),
        'readiness' => _ReadinessCard(p: progress),
        'streak' => _StreakCard(p: progress),
        'clips' => const _ClipsCard(),
        'pitchside' => _PitchsideCard(posts: feed),
        _ => const SizedBox.shrink(),
      };
}

Future<void> openUpload(BuildContext context, {String? drill, String? challenge, String? title}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => UploadScreen(drill: drill, challenge: challenge, title: title)));

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.accent.main, letterSpacing: 0.3)),
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

class _NoticedCard extends StatelessWidget {
  const _NoticedCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final v = s.videos.where((v) => v.status == 'READY').firstOrNull;
    if (v == null) {
      return Panel(
        onTap: () => openUpload(context),
        child: const Row(children: [
          IconTile(icon: 'pep', color: Tk.pep, background: Tk.pepTile, size: 40),
          SizedBox(width: 12),
          Expanded(child: Text("Send me a clip and I'll tell you one thing I noticed.", style: TextStyle(color: Tk.inkSoft))),
        ]),
      );
    }
    return Panel(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: v.id))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const IconTile(icon: 'pep', color: Tk.pep, background: Tk.pepTile, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Pep noticed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tk.pep)),
            const SizedBox(height: 2),
            Text(v.reviewNote ?? 'Pep watched ${v.displayTitle}.', style: const TextStyle(fontSize: 14.5, height: 1.4, color: Tk.ink)),
            Text(v.displayTitle, style: const TextStyle(fontSize: 12, color: Tk.muted)),
          ]),
        ),
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
        const _Label('Your progress'),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                x.better ? '${fmt(x.change, x.unit)} ${x.unit == 's' ? 'faster' : 'more'}' : 'from ${fmt(x.first, x.unit)}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: x.better ? context.accent.main : Tk.muted),
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
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(x.streakWeeks == 1 ? 'week in a row' : 'weeks in a row', style: const TextStyle(fontSize: 13, color: Tk.muted)),
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

class _ClipsCard extends StatelessWidget {
  const _ClipsCard();

  @override
  Widget build(BuildContext context) {
    final vids = context.watch<AppState>().videos.take(2).toList();
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Label(
          'Your latest clips',
          trailing: Pressable(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VideosScreen())),
            child: const Text('See all', style: TextStyle(fontSize: 13, color: Tk.muted)),
          ),
        ),
        const SizedBox(height: 8),
        if (vids.isEmpty)
          Row(children: [
            const Expanded(child: Text('No clips yet. Film a match, a drill or a challenge.', style: TextStyle(color: Tk.inkSoft))),
            TextButton(onPressed: () => openUpload(context), child: const Text('Add a clip')),
          ]),
        for (final v in vids)
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: v.id))),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 48,
                    child: v.thumbnailUrl == null
                        ? const ColoredBox(color: Tk.card2, child: Center(child: TIcon('play', size: 14, color: Tk.faint)))
                        : Image.network(v.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Tk.card2)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v.displayTitle, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                    Text(
                      v.processing ? 'Pep is watching' : v.status == 'FAILED' ? "Pep couldn't read it" : (v.reviewNote ?? 'Analysed'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: v.processing ? Tk.pep : Tk.muted),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _PitchsideCard extends StatelessWidget {
  const _PitchsideCard({required this.posts});

  final List<FeedPost>? posts;

  @override
  Widget build(BuildContext context) {
    final p = posts;
    if (p == null || p.isEmpty) return const SizedBox.shrink();
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Label('Worth a watch'),
        const SizedBox(height: 4),
        const Text('Players your age on Pitchside.', style: TextStyle(fontSize: 13, color: Tk.muted)),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: p.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FeedScreen(posts: p, startAt: i))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 104,
                  child: Stack(fit: StackFit.expand, children: [
                    if (p[i].thumbnailUrl != null)
                      Image.network(p[i].thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Tk.card2))
                    else
                      const ColoredBox(color: Tk.card2),
                    const DecoratedBox(
                      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)])),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p[i].author.shirtName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text(p[i].author.line, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, color: Tk.inkSoft)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Customise home: switch cards on or off and drag to reorder. Saves as you go.
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
