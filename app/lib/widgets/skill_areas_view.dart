import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../theme/theme.dart';
import 'ds.dart';

/// Me › Growth: "What scouts look for", group by group (canvas: Me, and the
/// "Rating system" board). Each measured area shows its band, the measured
/// average, confidence dots and a trend; the rest say why they aren't rated.
/// No overall score anywhere.
class SkillAreasView extends StatelessWidget {
  const SkillAreasView({super.key, required this.areas, this.onOpen});

  final SkillAreas areas;

  /// Tap an area to see the signals behind it (screen comes with the Me rebuild).
  final ValueChanged<SkillItem>? onOpen;

  static Trend trendOf(String t) => switch (t) {
        'growing' => Trend.growing,
        'steady' => Trend.steady,
        'dipping' => Trend.dipping,
        _ => Trend.fresh,
      };

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Expanded(child: Text('What scouts look for', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.lab))),
        Text('vs ${areas.comparedWith}', style: const TextStyle(fontSize: 12, color: Tk.muted)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: a.main)),
        const SizedBox(width: 8),
        const Expanded(child: Text('Matters most for your position', style: TextStyle(fontSize: 12.5, color: Tk.muted))),
      ]),
      const SizedBox(height: 14),
      for (final g in areas.groups) ...[
        Panel(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // The group's name inside its card (canvas Me: "SKILLS", "BODY").
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                TIcon(_groupIcon(g.name), size: 14, color: Tk.muted),
                const SizedBox(width: 8),
                Text(g.name.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .66, color: Tk.muted)),
              ]),
            ),
            for (var i = 0; i < g.items.length; i++) ...[
              if (i > 0) const Divider(),
              RatingRow(
                name: g.items[i].name,
                keySkill: g.items[i].key,
                band: g.items[i].measured ? Band.fromName(g.items[i].band) : null,
                average: g.items[i].average,
                confidence: Confidence.fromName(g.items[i].confidence),
                trend: trendOf(g.items[i].trend),
                state: g.items[i].stateLabel,
                onTap: onOpen == null ? null : () => onOpen!(g.items[i]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
      ],
      const Text('Everything starts at "Not seen yet". It fills in as Pep sees your tests and clips.', style: TextStyle(fontSize: 12, height: 1.45, color: Tk.muted)),
      const SizedBox(height: 12),
      const InfoNote(InfoNote.measured),
    ]);
  }
}

String _groupIcon(String group) => switch (group.toLowerCase()) {
      'skills' => 'ball',
      'reading the game' => 'vision',
      'body' => 'pace',
      'attitude' => 'heart',
      _ => 'target',
    };
