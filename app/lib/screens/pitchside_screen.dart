import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'videos_screen.dart';

/// Pitchside: watch other players, take on challenges, find people to play
/// with near you (canvas page 4).
///
/// The community feed, challenges and "near you" need new API routes, so for
/// now each section shows a calm "coming soon" scene, and your own clips are
/// one tap away. The layout and chips are the final ones, so the sections can
/// fill in without moving anything. Pep never appears on other players' clips.
class PitchsideScreen extends StatefulWidget {
  const PitchsideScreen({super.key});

  @override
  State<PitchsideScreen> createState() => _PitchsideScreenState();
}

enum _Section { challenges, near, opportunities }

class _PitchsideScreenState extends State<PitchsideScreen> {
  _Section section = _Section.challenges;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [
          EnterFade(child: Text('Pitchside', style: t.headlineLarge)),
          const SizedBox(height: 18),
          EnterFade(
            child: Panel(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Feed', style: t.headlineMedium),
                  const SizedBox(width: 10),
                  const _Soon(),
                ]),
                const SizedBox(height: 6),
                const Text('Clips from players your age and the ones you follow.', style: TextStyle(color: Tk.muted, fontSize: 13.5)),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VideosScreen())),
                  child: const Text('See your own clips'),
                ),
              ]),
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
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.select),
            child: switch (section) {
              _Section.challenges => const _Empty(
                  key: ValueKey('c'),
                  icon: 'trophy',
                  title: 'Weekly challenges are coming',
                  body: 'Film your go at the same drill as everyone else, and see how you compare with players your age.',
                ),
              _Section.near => const _Empty(
                  key: ValueKey('n'),
                  icon: 'pin',
                  title: 'Pitches and games near you',
                  body: 'Find pitches and players in your region. We only ever show your region, never your town.',
                ),
              _Section.opportunities => const _Empty(
                  key: ValueKey('o'),
                  icon: 'flag',
                  title: 'Opportunities come later',
                  body: 'Trials, academies and tournaments. Keep filming: your profile will be ready when this opens.',
                ),
            },
          ),
        ]),
      ),
    );
  }
}

class _Soon extends StatelessWidget {
  const _Soon();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: Tk.stoneTile, borderRadius: BorderRadius.circular(999)),
        child: const Text('Coming soon', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Tk.stone)),
      );
}

/// Empty states have a simple scene and no Pep (canvas: Empty states).
class _Empty extends StatelessWidget {
  const _Empty({super.key, required this.icon, required this.title, required this.body});

  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
        child: Column(children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: Tk.stoneTile, borderRadius: BorderRadius.circular(20)),
            alignment: Alignment.center,
            child: TIcon(icon, size: 28, color: Tk.stone),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Tk.ink)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, height: 1.45, color: Tk.muted)),
        ]),
      );
}
