import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'home_screen.dart' show openUpload;
import 'training_screens.dart' show WeekScreen;
import 'video_screen.dart';

/// Pep's reviews (canvas: Pep › Reviews, Match review, Tips, Tip drill).
///
/// A review is a story, not a score sheet: one headline, what went well, what
/// to work on (each with a time you tap to jump the video there), then tips,
/// each tied to a moment and a drill Pep picked for the kit you have. The
/// server builds it (pep/players/review.py); the app only lays it out.

String clipTime(double s) {
  final t = s.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

String clipKind(String type) => switch (type) {
      'match' => 'Match review',
      'training' => 'Training',
      'drill' => 'Drill',
      'highlight' => 'Highlight',
      _ => 'Clip',
    };

class _TimeTag extends StatelessWidget {
  const _TimeTag(this.seconds, {required this.background, this.ink = Colors.black});

  final double seconds;
  final Color background;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
        child: Text(clipTime(seconds), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ink)),
      );
}

/// The review inside a clip's page (VideoScreen), under the video.
class ReviewView extends StatelessWidget {
  const ReviewView({super.key, required this.review, required this.onSeek});

  final Review review;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final r = review;
    final planned = r.tips.where((t) => t.drill != null).map((t) => t.drill!).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const IconTile(icon: 'pep', color: Tk.pep, background: Tk.pepTile, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.title, style: const TextStyle(fontFamily: TType.display, fontSize: 18, fontWeight: FontWeight.w700, color: Tk.ink)),
            if (r.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(r.text, style: const TextStyle(fontSize: 14, height: 1.45, color: Tk.inkSoft)),
            ],
          ]),
        ),
      ]),
      if (r.wentWell.isNotEmpty) ...[
        const SizedBox(height: 20),
        const SectionLabel('What went well'),
        _Moments(moments: r.wentWell, tag: a.main, tagInk: a.on, onSeek: onSeek),
      ],
      if (r.workOn.isNotEmpty) ...[
        const SizedBox(height: 20),
        const SectionLabel('To work on'),
        _Moments(moments: r.workOn, tag: Tk.gold, tagInk: Colors.black, onSeek: onSeek),
      ],
      if (r.tips.isNotEmpty) ...[
        const SizedBox(height: 20),
        const SectionLabel('Tips'),
        for (final t in r.tips) ...[TipCard(tip: t, onSeek: onSeek), const SizedBox(height: 10)],
      ],
      if (r.areas.isNotEmpty || planned != null) ...[
        const SizedBox(height: 10),
        const SectionLabel('Where this goes'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(children: [
            for (final ar in r.areas)
              _LinkRow(
                icon: 'eye2',
                title: ar.name,
                sub: 'On Me, under ${ar.group}',
              ),
            if (planned != null)
              _LinkRow(
                icon: 'calendar',
                title: 'In your plan this week',
                sub: planned.name,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeekScreen())),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      InfoNote(r.source == 'gemini' ? InfoNote.pep : '${InfoNote.pep} These notes were written from your measurements.'),
    ]);
  }
}

class _Moments extends StatelessWidget {
  const _Moments({required this.moments, required this.tag, required this.tagInk, required this.onSeek});

  final List<ReviewMoment> moments;
  final Color tag;
  final Color tagInk;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Column(children: [
          for (final (i, m) in moments.indexed)
            Semantics(
              button: true,
              label: 'Play from ${clipTime(m.atSeconds)}',
              child: InkWell(
                onTap: () => onSeek(m.atSeconds),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: i == moments.length - 1 ? null : const Border(bottom: BorderSide(color: Tk.line)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(padding: const EdgeInsets.only(top: 1), child: _TimeTag(m.atSeconds, background: tag, ink: tagInk)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                        const SizedBox(height: 2),
                        Text(m.text, style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
                      ]),
                    ),
                    const Padding(padding: EdgeInsets.only(top: 2, left: 8), child: TIcon('play', size: 15, color: Tk.faint)),
                  ]),
                ),
              ),
            ),
        ]),
      );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.title, required this.sub, this.onTap});

  final String icon;
  final String title;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          IconTile(icon: icon, color: a.main, background: a.tile, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
              Text(sub, style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
            ]),
          ),
          if (onTap != null) const TIcon('chevron', size: 14, color: Tk.faint),
        ]),
      ),
    );
  }
}

/// One tip: the moment it came from, what to do, and a drill (or "See the moment").
/// [onSeek] is set inside the clip's page; from Pep › Tips the tip opens the clip.
class TipCard extends StatelessWidget {
  const TipCard({super.key, required this.tip, this.onSeek, this.showClip = false});

  final ReviewTip tip;
  final ValueChanged<double>? onSeek;
  final bool showClip;

  void _seeMoment(BuildContext context) {
    final at = tip.atSeconds;
    if (onSeek != null && at != null) {
      onSeek!(at);
    } else if (tip.videoId != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: tip.videoId!, startAt: at)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final drill = tip.drill;
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (showClip)
          SizedBox(
            height: 110,
            child: Stack(fit: StackFit.expand, children: [
              if (tip.thumbnailUrl != null)
                Image.network(tip.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Tk.card2))
              else
                const ColoredBox(color: Tk.card2),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x1A000000), Color(0xF2111111)],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 10,
                child: Row(children: [
                  if (tip.atSeconds != null) ...[_TimeTag(tip.atSeconds!, background: Tk.pep), const SizedBox(width: 6)],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(999)),
                    child: Text(tip.group, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Tk.ink)),
                  ),
                ]),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (showClip && (tip.videoTitle ?? '').isNotEmpty) ...[
              Text(tip.videoTitle!, style: const TextStyle(fontSize: 12.5, color: Tk.faint)),
              const SizedBox(height: 6),
            ],
            if (!showClip)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  if (tip.atSeconds != null) ...[_TimeTag(tip.atSeconds!, background: Tk.pep), const SizedBox(width: 8)],
                  Text(tip.areaName, style: const TextStyle(fontSize: 12, color: Tk.pep, fontWeight: FontWeight.w600)),
                ]),
              ),
            Text(tip.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Tk.ink)),
            const SizedBox(height: 3),
            Text(tip.text, style: const TextStyle(fontSize: 13.5, height: 1.45, color: Tk.inkSoft)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: drill != null ? () => showTipDrill(context, tip) : () => _seeMoment(context),
                child: Text(drill != null ? 'Try the drill · ${drill.minutes} min' : 'See the moment'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The drill behind a tip (canvas: Tip drill): why, how, kit, and the safety line.
Future<void> showTipDrill(BuildContext context, ReviewTip tip) {
  final d = tip.drill!;
  const kitNames = {'ball': 'a ball', 'wall': 'a wall', 'cones': 'cones', 'friends': 'friends', 'space': 'space to run', 'gym': 'a gym'};
  final needs = [for (final n in d.needs) if (kitNames[n] != null) kitNames[n]!];
  return showEditSheet<void>(
    context,
    title: d.name,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(['${d.minutes} min', ...needs].join(' · '), style: const TextStyle(fontSize: 13, color: Tk.muted)),
      const SizedBox(height: 14),
      Panel(
        color: Tk.pepTile,
        border: Tk.pepTile,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const TIcon('pep', size: 20, color: Tk.pep),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Why', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Tk.pep)),
              const SizedBox(height: 2),
              Text(tip.text, style: const TextStyle(fontSize: 14, height: 1.45, color: Tk.ink)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      const SectionLabel('How'),
      Text(d.how, style: const TextStyle(fontSize: 14.5, height: 1.5, color: Tk.ink)),
      const SizedBox(height: 16),
      const SafetyNote(SafetyNote.drill),
      const SizedBox(height: 8),
    ]),
  );
}

/// Pep › Reviews: clips Pep is watching, then ready reviews, newest first.
class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final watching = s.videos.where((v) => v.processing).toList();
    final ready = s.videos.where((v) => v.status == 'READY').toList();
    return Scaffold(
      appBar: AppBar(),
      body: ready.isEmpty && watching.isEmpty
          ? StateView(
              icon: 'clip',
              title: 'No reviews yet',
              message: "Send a clip and you'll get what went well and what to work on, with a time for each.",
              actionLabel: 'Add a clip',
              onAction: () => openUpload(context),
            )
          : RefreshIndicator(
              onRefresh: s.refresh,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
                const Text('PEP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tk.pep, letterSpacing: 0.8)),
                const SizedBox(height: 4),
                Text('Reviews', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 4),
                const Text("Send me a clip and I'll tell you what went well and what to work on.",
                    style: TextStyle(fontSize: 13, color: Tk.muted)),
                const SizedBox(height: 18),
                for (final v in watching) ...[
                  Panel(
                    child: Row(children: [
                      const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Tk.pep)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Pep is watching ${v.displayTitle}',
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                          const Text("Usually ready in a few minutes. You can leave this screen.",
                              style: TextStyle(fontSize: 12.5, color: Tk.muted)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
                if (ready.isNotEmpty) ...[const SizedBox(height: 4), const SectionLabel('Ready')],
                for (final v in ready) ...[_ReviewRow(v), const SizedBox(height: 10)],
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () => openUpload(context),
                  icon: const TIcon('camera', size: 18, color: Tk.ink),
                  label: const Text('Send Pep a clip'),
                ),
                const SizedBox(height: 14),
                const InfoNote(InfoNote.pep),
              ]),
            ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.v);

  final Video v;

  @override
  Widget build(BuildContext context) => Panel(
        padding: EdgeInsets.zero,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: v.id))),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(Tk.rCard)),
              child: SizedBox(
                width: 96,
                child: v.thumbnailUrl == null
                    ? const ColoredBox(color: Tk.card2, child: Center(child: TIcon('play', size: 16, color: Tk.faint)))
                    : Image.network(v.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Tk.card2)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(clipKind(v.clipType).toUpperCase(),
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Tk.pep, letterSpacing: 0.6)),
                  const SizedBox(height: 4),
                  Text(v.displayTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
                  if (v.reviewNote != null) ...[
                    const SizedBox(height: 2),
                    Text(v.reviewNote!, style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      );
}

/// Pep › Tips: every tip from your clips, newest first, filtered by skill group.
class TipsScreen extends StatefulWidget {
  const TipsScreen({super.key});

  @override
  State<TipsScreen> createState() => _TipsScreenState();
}

class _TipsScreenState extends State<TipsScreen> {
  late Future<List<ReviewTip>> _tips = context.read<AppState>().api.tips();
  String _group = 'All';

  void _reload() => setState(() => _tips = context.read<AppState>().api.tips());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: FutureBuilder<List<ReviewTip>>(
        future: _tips,
        builder: (context, snap) {
          if (snap.hasError) return StateView.error(onRetry: _reload);
          if (!snap.hasData) {
            return ListView(padding: const EdgeInsets.all(20), children: const [
              Skeleton(height: 28, width: 200),
              SizedBox(height: 20),
              Skeleton(height: 220),
              SizedBox(height: 12),
              Skeleton(height: 220),
            ]);
          }
          final all = snap.data!;
          if (all.isEmpty) {
            return StateView(
              icon: 'target',
              title: 'No tips yet',
              message: 'Each tip comes from a moment in one of your clips. Send a clip to get your first.',
              actionLabel: 'Add a clip',
              onAction: () => openUpload(context),
            );
          }
          final groups = ['All', ...{for (final t in all) t.group}];
          final shown = _group == 'All' ? all : all.where((t) => t.group == _group).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
            const Text('PEP', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tk.pep, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Text('Tips from your clips', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 4),
            const Text('Each tip comes from a moment in one of your clips.', style: TextStyle(fontSize: 13, color: Tk.muted)),
            const SizedBox(height: 16),
            if (groups.length > 2) ...[
              SingleChips<String>(
                options: {for (final g in groups) g: g},
                value: _group,
                onChanged: (g) => setState(() => _group = g),
              ),
              const SizedBox(height: 16),
            ],
            for (final t in shown) ...[TipCard(tip: t, showClip: true), const SizedBox(height: 12)],
            const SizedBox(height: 4),
            const InfoNote(InfoNote.pep),
          ]);
        },
      ),
    );
  }
}
