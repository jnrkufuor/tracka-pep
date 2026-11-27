import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/board.dart';
import '../widgets/ds.dart';
import 'feed_screens.dart';
import 'home_screen.dart' show openUpload;

/// Pitchside: the Feed, weekly challenges, places to play near you, and
/// opportunities (later). Canvas: Pitchside and "Feed button".
///
/// At the top, the Feed is a big picture card. As soon as you scroll, a small
/// Feed button waits bottom-right: a little phone (white frame, a blurred
/// clip, a play button) with a "Feed" tag, which folds into a pill while you
/// scroll and unfolds when you're back at the top ("morph 1b").
/// Pep never appears on other players' clips.
class PitchsideScreen extends StatefulWidget {
  const PitchsideScreen({super.key});

  @override
  State<PitchsideScreen> createState() => _PitchsideScreenState();
}

enum _Section { challenges, near, opportunities }

class _PitchsideScreenState extends State<PitchsideScreen> {
  _Section section = _Section.challenges;
  ChallengesState? challenges;
  List<Pitch>? pitches;
  String? feedThumb;
  int feedCount = 0;
  bool failed = false;
  bool scrolled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    try {
      final r = await Future.wait([api.challenges(), api.pitches()]);
      if (!mounted) return;
      setState(() {
        challenges = r[0] as ChallengesState;
        pitches = r[1] as List<Pitch>;
        failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
    try {
      final f = await api.feed();
      if (mounted) {
        setState(() {
          feedThumb = f.posts.firstOrNull?.thumbnailUrl;
          feedCount = f.posts.length;
        });
      }
    } catch (_) {}
  }

  void _feed() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedScreen()));

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          NotificationListener<ScrollUpdateNotification>(
            onNotification: (n) {
              if (n.depth == 0) {
                final now = n.metrics.pixels > 24;
                if (now != scrolled) setState(() => scrolled = now);
              }
              return false;
            },
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 150), children: [
                Row(children: [
                  Expanded(child: EnterFade(child: Text('Pitchside', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 30)))),
                  BRoundButton(icon: 'search', label: 'Search players', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen()))),
                ]),
                const SizedBox(height: 18),
                Semantics(
                  button: true,
                  label: 'Feed: clips from players your age and the ones you follow',
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: _feed,
                    child: BThumb(
                      url: feedThumb,
                      height: 340,
                      radius: 24,
                      children: [
                        if (feedCount > 0)
                          Positioned(left: 14, top: 14, child: BChip('$feedCount new', color: a.on, background: a.main)),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            const Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Feed', style: TextStyle(fontFamily: TType.display, fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
                                SizedBox(height: 4),
                                Text('Clips from players your age and the ones you follow',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xCCFFFFFF))),
                              ]),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 52,
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: a.main, shape: BoxShape.circle),
                              child: TIcon('play', size: 18, color: a.on),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SingleChips<_Section>(
                  options: const {
                    _Section.challenges: 'Challenges',
                    _Section.near: 'Near you',
                    _Section.opportunities: 'Opportunities',
                  },
                  value: section,
                  onChanged: (s) => setState(() => section = s),
                ),
                const SizedBox(height: 18),
                if (failed)
                  Panel(
                    child: Column(children: [
                      const Text("Couldn't load Pitchside.", style: TextStyle(color: Tk.inkSoft)),
                      TextButton(onPressed: _load, child: const Text('Try again')),
                    ]),
                  )
                else
                  AnimatedSwitcher(
                    duration: Motion.of(context, Motion.select),
                    child: switch (section) {
                      _Section.challenges => KeyedSubtree(key: const ValueKey('c'), child: _Challenges(state: challenges, reload: _load)),
                      _Section.near => KeyedSubtree(
                          key: const ValueKey('n'),
                          child: _Near(pitches: pitches, onChanged: (p) => setState(() => pitches = p)),
                        ),
                      _Section.opportunities => const KeyedSubtree(key: ValueKey('o'), child: _Opportunities()),
                    },
                  ),
              ]),
            ),
          ),
          Positioned(right: 16, bottom: 16, child: _FeedButton(folded: scrolled, thumb: feedThumb, onTap: _feed)),
        ]),
      ),
    );
  }
}

/// The floating Feed button (canvas "Feed button", morph 1b). At rest: a
/// little phone, 62 × 110, with a "Feed" tag. While you scroll: the phone
/// shrinks to 20 × 30 and sits inside an 82 × 44 pill with the word.
class _FeedButton extends StatelessWidget {
  const _FeedButton({required this.folded, required this.thumb, required this.onTap});

  final bool folded;
  final String? thumb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final d = Motion.of(context, Motion.morph);
    const curve = Cubic(.45, 0, .2, 1);
    return Semantics(
      button: true,
      label: 'Open the feed',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 90,
          height: 130,
          child: Stack(clipBehavior: Clip.none, children: [
            AnimatedPositioned(
              duration: d,
              curve: curve,
              right: 0,
              bottom: folded ? 0 : 16,
              width: folded ? 82 : 62,
              height: folded ? 44 : 110,
              child: AnimatedContainer(
                duration: d,
                curve: curve,
                decoration: BoxDecoration(
                  color: Tk.card2,
                  borderRadius: BorderRadius.circular(folded ? 22 : 14),
                  border: Border.all(color: const Color(0x29FFFFFF)),
                  boxShadow: const [BoxShadow(color: Color(0xA6000000), blurRadius: 34, offset: Offset(0, 14))],
                ),
              ),
            ),
            AnimatedPositioned(
              duration: d,
              curve: curve,
              right: folded ? 52 : 0,
              bottom: folded ? 7 : 16,
              width: folded ? 20 : 62,
              height: folded ? 30 : 110,
              child: AnimatedContainer(
                duration: d,
                curve: curve,
                padding: EdgeInsets.all(folded ? 1.5 : 3),
                decoration: BoxDecoration(color: Tk.ink, borderRadius: BorderRadius.circular(folded ? 6 : 14)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(folded ? 4.5 : 11),
                  child: Stack(fit: StackFit.expand, children: [
                    if (thumb != null)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: Image.network(thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _FeedFill()),
                      )
                    else
                      const _FeedFill(),
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: .44,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: a.main, shape: BoxShape.circle),
                            child: FittedBox(child: Padding(padding: const EdgeInsets.all(6), child: TIcon('play', size: 12, color: a.on))),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: d,
              curve: curve,
              right: folded ? 8 : 6,
              bottom: folded ? 10 : 2,
              child: AnimatedContainer(
                duration: d,
                curve: curve,
                height: 24,
                padding: EdgeInsets.symmetric(horizontal: folded ? 4 : 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: folded ? const Color(0x00121212) : Tk.card2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: folded ? const Color(0x00FFFFFF) : const Color(0x33FFFFFF)),
                ),
                child: const Text('Feed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Tk.ink)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FeedFill extends StatelessWidget {
  const _FeedFill();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2B3A1E), Color(0xFF101810)]),
        ),
      );
}

// ---------------------------------------------------------------- challenges

class _Challenges extends StatelessWidget {
  const _Challenges({required this.state, required this.reload});

  final ChallengesState? state;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final c = state;
    final a = context.accent;
    if (c == null) return const Column(children: [Skeleton(height: 150), SizedBox(height: 12), Skeleton(height: 110)]);
    final w = c.thisWeek;
    final days = w.endsOn.difference(DateTime.now()).inDays + 1;
    String count(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';
    Band? band(String? label) => Band.values.where((b) => b.label == label).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // This week's challenge: the big one, in your main colour.
      Pressable(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengeRecordScreen(challenge: w))).then((_) => reload()),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Color.alphaBlend(a.main.withValues(alpha: .14), const Color(0xFF111111))),
            gradient: LinearGradient(
              begin: const Alignment(-.8, -1),
              end: const Alignment(.8, 1),
              stops: const [0, .6],
              colors: [Color.alphaBlend(a.main.withValues(alpha: .10), const Color(0xFF111111)), const Color(0xFF111111)],
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              TIcon('trophy', size: 13, color: a.main),
              const SizedBox(width: 6),
              Expanded(
                child: Text('THIS WEEK · ${w.group.toUpperCase()}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .63, color: a.main)),
              ),
              Text(days <= 1 ? 'Ends today' : 'Ends Sunday', style: bNote),
            ]),
            const SizedBox(height: 8),
            Text(w.name, style: const TextStyle(fontFamily: TType.display, fontSize: 19, height: 1.2, fontWeight: FontWeight.w700, color: Tk.ink)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text(['${count(w.playersIn)} players in', if (w.best != null) 'your best ${w.best}'].join(' · '), style: bNote)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: a.main, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  TIcon('camera', size: 14, color: a.on),
                  const SizedBox(width: 6),
                  Text('Film your go', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: a.on)),
                ]),
              ),
            ]),
          ]),
        ),
      ),
      if (c.fun.isNotEmpty) ...[
        const SizedBox(height: 14),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: c.fun.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final f = c.fun[i];
              return SizedBox(
                width: 150,
                child: Panel(
                  padding: const EdgeInsets.all(12),
                  onTap: () => openUpload(context, challenge: f.id, title: f.name).then((_) => reload()),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const IconTile(icon: 'star', color: Tk.gold, background: Tk.goldTile, size: 34),
                    const SizedBox(height: 8),
                    Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, height: 1.3, fontWeight: FontWeight.w600, color: Tk.ink)),
                    const Spacer(),
                    Text('${count(f.playersIn)} in', style: bNote.copyWith(fontSize: 11.5)),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
      if (c.past.isNotEmpty) ...[
        const SizedBox(height: 20),
        const BLab('Your challenges'),
        const SizedBox(height: 10),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(children: [
            for (final (i, p) in c.past.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: i == c.past.length - 1 ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.line))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                      const SizedBox(height: 2),
                      Text(p.group, style: bNote),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (p.best != null) Text(p.best!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.ink)),
                    if (band(p.band) != null) ...[const SizedBox(height: 4), BandPill(band(p.band)!)],
                  ]),
                ]),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(16)),
        child: Text('Your results count on your skill areas in Me, compared with ${c.comparedWith}. Your attempts stay private unless you post them.',
            style: const TextStyle(fontSize: 13, height: 1.4, color: Tk.inkSoft)),
      ),
    ]);
  }
}

/// Film an attempt: the steps, then the usual upload (marked as this challenge).
class ChallengeRecordScreen extends StatelessWidget {
  const ChallengeRecordScreen({super.key, required this.challenge});

  final WeeklyChallenge challenge;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
          Text('This week', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.accent.main)),
          const SizedBox(height: 4),
          Text(challenge.name, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 18),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              for (final (i, s) in challenge.steps.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: context.accent.tile),
                      child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.accent.main)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s, style: const TextStyle(fontSize: 14.5, color: Tk.ink))),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          const SafetyNote(SafetyNote.drill),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => openUpload(context, drill: challenge.drill, challenge: challenge.id, title: challenge.name),
            child: const Text('Choose or record the clip'),
          ),
          const SizedBox(height: 10),
          const InfoNote('Pep counts your attempt. It stays private unless you post it.'),
        ]),
      );
}

// ---------------------------------------------------------------- near you

class _Near extends StatelessWidget {
  const _Near({required this.pitches, required this.onChanged});

  final List<Pitch>? pitches;
  final ValueChanged<List<Pitch>> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = pitches;
    final s = context.read<AppState>();
    if (p == null) return const Skeleton(height: 200);
    final region = s.me?.profile.region;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel(region == null ? 'Places to play' : 'Places to play · $region'),
      if (p.isEmpty)
        const Panel(child: Text('No pitches added near you yet. Add the one you play on.', style: TextStyle(color: Tk.inkSoft))),
      for (final x in p)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              IconTile(icon: 'pin', color: x.confirmed ? context.accent.main : Tk.stone, background: x.confirmed ? context.accent.tile : Tk.stoneTile, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
                  Text('${x.surface[0].toUpperCase()}${x.surface.substring(1)} · ${x.size} · ${x.town}', style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
                  Text(
                    x.confirmed ? 'Confirmed by ${x.confirmations} players' : 'Needs ${x.needs} more player${x.needs == 1 ? '' : 's'} to confirm',
                    style: TextStyle(fontSize: 12, color: x.confirmed ? Tk.faint : Tk.gold),
                  ),
                ]),
              ),
              if (!x.addedByMe && !x.confirmedByMe)
                TextButton(
                  onPressed: () async {
                    try {
                      onChanged(await s.api.confirmPitch(x.id));
                    } catch (e) {
                      if (context.mounted) showToast(context, "Couldn't confirm it", detail: '$e', ok: false);
                    }
                  },
                  child: const Text('Confirm'),
                ),
            ]),
          ),
        ),
      const SizedBox(height: 6),
      const Text('Pitches players add show here once 2 other players confirm them.', style: TextStyle(fontSize: 12, color: Tk.faint)),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: () => _addPitch(context), child: const Text('Add a pitch')),
    ]);
  }

  Future<void> _addPitch(BuildContext context) async {
    final s = context.read<AppState>();
    var name = '', town = '', surface = 'grass', size = '5-a-side';
    await showEditSheet<void>(
      context,
      title: 'Add a pitch',
      child: StatefulBuilder(
        builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(decoration: const InputDecoration(labelText: 'Name', hintText: 'Bantama community field'), onChanged: (v) => setSheet(() => name = v)),
          const SizedBox(height: 10),
          TextField(decoration: const InputDecoration(labelText: 'Town', hintText: 'Kumasi'), onChanged: (v) => setSheet(() => town = v)),
          const SizedBox(height: 14),
          SingleChips<String>(
            options: const {'grass': 'Grass', 'astro': 'Astro', 'dirt': 'Dirt', 'sand': 'Sand', 'indoor': 'Indoor'},
            value: surface,
            onChanged: (v) => setSheet(() => surface = v),
          ),
          const SizedBox(height: 10),
          SingleChips<String>(
            options: const {'5-a-side': '5-a-side', '7-a-side': '7-a-side', 'full size': 'Full size'},
            value: size,
            onChanged: (v) => setSheet(() => size = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: name.trim().length < 3 || town.trim().length < 2
                ? null
                : () async {
                    try {
                      onChanged(await s.api.addPitch(name: name.trim(), surface: surface, size: size, town: town.trim()));
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    } catch (e) {
                      if (ctx.mounted) showToast(ctx, "Couldn't add it", detail: '$e', ok: false, aboveTabs: false);
                    }
                  },
            child: const Text('Add pitch'),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- opportunities

class _Opportunities extends StatelessWidget {
  const _Opportunities();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Trials, academy open days and school trials', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Tk.ink)),
        const SizedBox(height: 6),
        const Text("Coming later. They'll show here when they're near you. Only real, checked opportunities.",
            style: TextStyle(fontSize: 13.5, height: 1.45, color: Tk.muted)),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text("Tell me when there's one near me"),
          value: s.settings.notifyOpportunities,
          onChanged: (v) => s.saveSettings({'notifyOpportunities': v}),
        ),
      ]),
    );
  }
}
