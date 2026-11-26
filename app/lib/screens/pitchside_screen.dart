import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'feed_screens.dart';
import 'home_screen.dart' show openUpload;

/// Pitchside: the Feed, weekly challenges, places to play near you, and
/// opportunities (later). Canvas page 4.
///
/// The Feed button is "morph 1b": a phone-shaped card with a white frame and a
/// blurred clip behind it, which shrinks into a pill as you scroll and stays
/// at the top of every Pitchside section. Pep never appears on other players' clips.
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
  bool failed = false;

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
      if (mounted && f.posts.isNotEmpty) setState(() => feedThumb = f.posts.first.thumbnailUrl);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(child: EnterFade(child: Text('Pitchside', style: t.headlineLarge))),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _FeedHeader(
                thumb: feedThumb,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedScreen())),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              sliver: SliverList.list(children: [
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
          ]),
        ),
      ),
    );
  }
}

/// The Feed button: a phone (white frame, blurred clip) that morphs into a pill.
class _FeedHeader extends SliverPersistentHeaderDelegate {
  _FeedHeader({required this.onTap, this.thumb});

  final VoidCallback onTap;
  final String? thumb;

  @override
  double get maxExtent => 176;

  @override
  double get minExtent => 60;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final reduced = Motion.reduced(context);
    final k = reduced ? (t < 0.5 ? 0.0 : 1.0) : Curves.easeOut.transform(t);
    final width = lerpDouble(132, 104, k)!;
    final height = lerpDouble(160, 44, k)!;
    final radius = lerpDouble(22, 999, k)!;
    return ColoredBox(
      color: Tk.bg,
      child: Align(
        alignment: Alignment.lerp(Alignment.centerLeft, Alignment.centerRight, k)!,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Semantics(
            button: true,
            label: 'Feed: clips from players your age and the ones you follow',
            excludeSemantics: true,
            child: Pressable(
              onTap: onTap,
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Stack(fit: StackFit.expand, children: [
                    if (thumb != null)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Image.network(thumb!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _FeedFill()),
                      )
                    else
                      const _FeedFill(),
                    Container(color: const Color(0x55000000)),
                    Center(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: lerpDouble(40, 24, k),
                          height: lerpDouble(40, 24, k),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x99000000)),
                          alignment: Alignment.center,
                          child: TIcon('play', size: lerpDouble(16, 11, k)!, color: Colors.white),
                        ),
                        SizedBox(width: lerpDouble(0, 8, k)),
                        if (k > 0.5) const Text('Feed', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                      ]),
                    ),
                    if (k <= 0.5)
                      const Positioned(
                        left: 12,
                        bottom: 10,
                        child: Text('Feed', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_FeedHeader old) => old.thumb != thumb;
}

class _FeedFill extends StatelessWidget {
  const _FeedFill();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5A4632), Color(0xFF1C1712)]),
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
    if (c == null) return const Column(children: [Skeleton(height: 190), SizedBox(height: 12), Skeleton(height: 120)]);
    final w = c.thisWeek;
    final days = w.endsOn.difference(DateTime.now()).inDays + 1;
    Widget stat(String value, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontFamily: TType.display, fontSize: 22, fontWeight: FontWeight.w800, color: Tk.ink)),
            Text(label, style: const TextStyle(fontSize: 12, color: Tk.muted)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('This week · ${w.group}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.accent.main)),
            const Spacer(),
            Text(days <= 1 ? 'Ends today' : 'Ends Sunday', style: const TextStyle(fontSize: 12, color: Tk.muted)),
          ]),
          const SizedBox(height: 8),
          Text(w.name, style: const TextStyle(fontFamily: TType.display, fontSize: 20, fontWeight: FontWeight.w800, color: Tk.ink)),
          const SizedBox(height: 4),
          Text(w.how, style: const TextStyle(fontSize: 13.5, color: Tk.inkSoft)),
          const SizedBox(height: 14),
          Row(children: [stat(w.best ?? '–', 'Your best'), stat('${w.tries}', 'Tries'), stat('${w.playersIn}', 'Players in')]),
          if (w.band != null) ...[
            const SizedBox(height: 10),
            if (Band.values.where((b) => b.label == w.band).isNotEmpty) BandPill(Band.values.firstWhere((b) => b.label == w.band)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengeRecordScreen(challenge: w))).then((_) => reload()),
              child: const Text('Film your go'),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      const SectionLabel('Just for fun'),
      for (final f in c.fun)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: () => openUpload(context, challenge: f.id, title: f.name).then((_) => reload()),
            child: Row(children: [
              const IconTile(icon: 'star', color: Tk.stone, background: Tk.stoneTile, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
                  Text(f.how, style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
                ]),
              ),
              Text('${f.playersIn} in', style: const TextStyle(fontSize: 12, color: Tk.muted)),
            ]),
          ),
        ),
      if (c.past.isNotEmpty) ...[
        const SizedBox(height: 10),
        const SectionLabel('Your challenges'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (final p in c.past)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                      Text([p.group, if (p.best != null) p.best!].join(' · '), style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
                    ]),
                  ),
                  if (p.band != null && Band.values.any((b) => b.label == p.band)) BandPill(Band.values.firstWhere((b) => b.label == p.band)),
                ]),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      Text('Compared with ${c.comparedWith} who tried it. Your attempts stay private unless you post them.',
          style: const TextStyle(fontSize: 12, color: Tk.faint)),
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
