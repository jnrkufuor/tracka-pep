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
        Text('What scouts look for', style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        Text('vs ${areas.comparedWith}', style: const TextStyle(fontSize: 12.5, color: Tk.faint)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: a.main)),
        const SizedBox(width: 8),
        const Expanded(child: Text('Matters most for your position', style: TextStyle(fontSize: 12.5, color: Tk.muted))),
      ]),
      const SizedBox(height: 14),
      for (final g in areas.groups) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(g.name.toUpperCase(), style: TType.eyebrow),
        ),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(children: [
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
        const SizedBox(height: 16),
      ],
      const InfoNote(InfoNote.measured),
    ]);
  }
}
