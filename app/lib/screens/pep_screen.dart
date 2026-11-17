import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/skill_card.dart';
import 'home_screen.dart' show openUpload;

/// Pep, your coach: every skill across your recent clips, your best roles,
/// the standard drills, and how scoring works.
class PepScreen extends StatelessWidget {
  const PepScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final c = s.coach;
    final drills = s.meta?.drills.values.toList() ?? const [];
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: TColors.neon,
          onRefresh: s.refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [
            const Eyebrow('Your AI coach', color: TColors.neon),
            const SizedBox(height: 6),
            Text('Pep', style: t.displayLarge),
            const SizedBox(height: 8),
            const Text(
              'Pep watches your clips, measures what you do, and compares you with players your age. '
              'The more clips, the surer it gets.',
              style: TextStyle(color: TColors.inkSoft),
            ),
            const SizedBox(height: 10),
            const Tape(),
            const SizedBox(height: 22),
            if (c == null || c.skills.isEmpty)
              TCard(
                accent: 'ai',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Nothing to show yet', style: t.titleLarge),
                  const SizedBox(height: 6),
                  const Text('Once Pep has watched a clip, your skills show up here with a drill for each.',
                      style: TextStyle(color: TColors.inkSoft)),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: () => openUpload(context), child: const Text('Upload a clip')),
                ]),
              )
            else ...[
              Row(children: [
                const Eyebrow('Your skills'),
                const Spacer(),
                ConfidencePill(c.confidence, suffix: ' confidence'),
              ]),
              const SizedBox(height: 4),
              Text('Average of your newest clips (up to 5 per skill).',
                  style: TextStyle(color: TColors.inkFaint.withValues(alpha: 0.9), fontSize: 12.5)),
              const SizedBox(height: 12),
              for (final sk in c.skills) ...[SkillCard(skill: sk, showClips: true), const SizedBox(height: 10)],
              if (c.bestRoles.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Eyebrow('Roles your game suits'),
                const SizedBox(height: 10),
                TCard(
                  accent: 'player',
                  child: Column(children: [
                    for (final r in c.bestRoles) ...[
                      Row(children: [
                        Expanded(child: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                        KitNumber(r.score, size: 30),
                      ]),
                      const SizedBox(height: 6),
                      ScoreBar(r.score),
                      const SizedBox(height: 14),
                    ],
                  ]),
                ),
              ],
            ],
            const SizedBox(height: 22),
            const Eyebrow('Timed drills'),
            const SizedBox(height: 6),
            const Text('The same test for everyone, so they\'re the fairest numbers you can show.',
                style: TextStyle(color: TColors.inkSoft)),
            const SizedBox(height: 12),
            for (final d in drills) ...[
              TCard(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    LoopyIcon(d.needsCalibration ? 'stopwatch' : 'ball', color: TColors.neon),
                    const SizedBox(width: 10),
                    Expanded(child: Text(d.label, style: t.titleLarge)),
                  ]),
                  const SizedBox(height: 8),
                  Text(d.how, style: const TextStyle(color: TColors.inkSoft, fontSize: 13.5)),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => openUpload(context, drill: d.id), child: const Text('Record this drill')),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 14),
            const _HowPepWorks(),
          ]),
        ),
      ),
    );
  }
}

class _HowPepWorks extends StatelessWidget {
  const _HowPepWorks();

  @override
  Widget build(BuildContext context) {
    const points = [
      ('target', 'It follows you', 'Tap yourself when you upload so Pep follows the right player.'),
      ('ruler', 'It measures', 'Speed, sprints, touches and body shape, using your height as its ruler.'),
      ('pulse', 'It compares fairly', 'Scores are against players your age. 62 is typical; 80+ is excellent.'),
      ('lock', 'It\'s honest', 'Every score says how sure Pep is. Drills are surest; highlights least.'),
      ('ai', 'It explains', 'The AI coach writes notes from watching your clip, but never sets the numbers.'),
    ];
    return TCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('How Pep scores you', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        for (final (icon, title, text) in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LoopyIcon(icon, size: 24, color: TColors.neon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(text, style: const TextStyle(color: TColors.inkSoft, fontSize: 13.5)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
