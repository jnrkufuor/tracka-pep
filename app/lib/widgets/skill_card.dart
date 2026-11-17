import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme/theme.dart';
import 'common.dart';

/// One skill: score, where it came from, how sure Pep is, what it saw, and a drill.
class SkillCard extends StatelessWidget {
  const SkillCard({super.key, required this.skill, this.showClips = false});

  final Skill skill;
  final bool showClips;

  @override
  Widget build(BuildContext context) {
    final s = skill;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TColors.surface,
        borderRadius: BorderRadius.circular(TRadius.md),
        border: Border.all(color: TColors.lineSoft),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 56, child: KitNumber(s.score, size: 40)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill(s.sourceLabel, color: s.source == 'ai_observed' ? TColors.violet : TColors.inkSoft),
                if (s.confidence != null) ConfidencePill(s.confidence),
                if (showClips && s.clips != null) Pill('${s.clips} clips'),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        ScoreBar(s.score, color: s.source == 'ai_observed' ? TColors.violet : TColors.neon),
        if (s.explanation.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(s.explanation, style: const TextStyle(color: TColors.inkSoft, fontSize: 14)),
        ],
        if (s.drill.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: TColors.bg, borderRadius: BorderRadius.circular(TRadius.sm)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const LoopyIcon('cone', size: 22, color: TColors.neon),
              const SizedBox(width: 10),
              Expanded(child: Text(s.drill, style: const TextStyle(fontSize: 13.5))),
            ]),
          ),
        ],
      ]),
    );
  }
}
