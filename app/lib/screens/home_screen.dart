import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import 'upload_screen.dart';
import 'video_screen.dart';

/// Home: where you stand, what to work on next, and a big upload button.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;
    final c = s.coach;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: TColors.neon,
          onRefresh: s.refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 24), children: [
            Row(children: [
              const TrackaLogo(size: 30),
              const Spacer(),
              IconButton(
                onPressed: () => openUpload(context),
                icon: const LoopyIcon('plus', color: TColors.neon),
                tooltip: 'Upload a clip',
              ),
            ]),
            const SizedBox(height: 22),
            Eyebrow(_greeting(), color: TColors.neon),
            const SizedBox(height: 6),
            Text(me == null ? 'Hello' : 'Hey ${me.profile.firstName}', style: t.displayMedium),
            const SizedBox(height: 18),
            if (s.uploads.isNotEmpty) ...[_UploadingCard(progress: s.uploads.values.first), const SizedBox(height: 12)],
            if (c != null && c.processing > 0) ...[_ProcessingCard(count: c.processing), const SizedBox(height: 12)],
            _ScoreCard(coach: c),
            const SizedBox(height: 12),
            if (c == null || c.clipsUploaded == 0)
              _FirstClipCard(onUpload: () => openUpload(context))
            else ...[
              if (c.focus.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Eyebrow('Work on this week'),
                const SizedBox(height: 10),
                for (final f in c.focus) ...[_FocusCard(skill: f), const SizedBox(height: 10)],
              ],
              if (c.suggestedDrill != null) ...[
                const SizedBox(height: 4),
                _DrillCard(drill: c.suggestedDrill!, onRecord: () => openUpload(context, drill: c.suggestedDrill!['id'] as String)),
              ],
              if (c.trend.length >= 2) ...[
                const SizedBox(height: 22),
                const Eyebrow('Your score, week by week'),
                const SizedBox(height: 12),
                TCard(child: _TrendBars(points: c.trend)),
              ],
              if (c.recentMoments.isNotEmpty) ...[
                const SizedBox(height: 22),
                Row(children: [
                  const Eyebrow('Recent moments'),
                  const Spacer(),
                  TextButton(onPressed: () => onOpenTab(1), child: const Text('All videos')),
                ]),
                for (final m in c.recentMoments.take(5)) _MomentRow(moment: m),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }
}

Future<void> openUpload(BuildContext context, {String? drill}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => UploadScreen(drill: drill)));

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.coach});

  final CoachSummary? coach;

  @override
  Widget build(BuildContext context) {
    final c = coach;
    final analysed = c?.clipsAnalysed ?? 0;
    final needed = c?.clipsNeeded ?? 3;
    final ready = c?.overallScore != null;
    return TCard(
      neon: true,
      accent: 'star',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Eyebrow('Pep score', color: TColors.onNeon),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          KitNumber(ready ? c!.overallScore : null, size: 104, color: TColors.onNeon),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ready
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (c!.change != null && c.change != 0)
                        Text('${c.change! > 0 ? '▲' : '▼'} ${c.change!.abs()} since your last 5 clips',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (c.bestRoles.isNotEmpty)
                        Text('Your game suits: ${c.bestRoles.first.label}',
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text('${c.confidence.toLowerCase()} confidence · $analysed clips',
                          style: TextStyle(color: TColors.onNeon.withValues(alpha: 0.65), fontSize: 12.5)),
                    ])
                  : Text(
                      analysed == 0
                          ? 'Upload $needed clips and Pep gives you a score.'
                          : '$analysed of $needed clips analysed. ${needed - analysed} more for your score.',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            ),
          ),
        ]),
        if (!ready) ...[
          const SizedBox(height: 14),
          ScoreBar(analysed / needed * 100, color: TColors.onNeon),
        ],
      ]),
    );
  }
}

class _FirstClipCard extends StatelessWidget {
  const _FirstClipCard({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return TCard(
      accent: 'film',
      onTap: onUpload,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Upload your first clip', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'A match, a training session or a drill. Keep the camera on you, film in daylight, '
          'and keep it under 3 minutes.',
          style: TextStyle(color: TColors.inkSoft),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onUpload,
          icon: const LoopyIcon('upload', color: TColors.onNeon, size: 22),
          label: const Text('Upload a clip'),
        ),
      ]),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.skill});

  final Skill skill;

  @override
  Widget build(BuildContext context) {
    return TCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          KitNumber(skill.score, size: 38),
          const SizedBox(width: 14),
          Expanded(child: Text(skill.name, style: Theme.of(context).textTheme.titleLarge)),
        ]),
        const SizedBox(height: 10),
        ScoreBar(skill.score),
        const SizedBox(height: 12),
        _DrillTip(text: skill.drill),
      ]),
    );
  }
}

class _DrillTip extends StatelessWidget {
  const _DrillTip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: TColors.bg, borderRadius: BorderRadius.circular(TRadius.sm)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LoopyIcon('cone', size: 22, color: TColors.neon),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
      ]),
    );
  }
}

class _DrillCard extends StatelessWidget {
  const _DrillCard({required this.drill, required this.onRecord});

  final Map<String, dynamic> drill;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return TCard(
      accent: 'stopwatch',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Eyebrow('Record a timed drill', color: TColors.neon),
        const SizedBox(height: 8),
        Text(drill['label'] as String, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text('The fairest way to show your ${(drill['forSkill'] as String).toLowerCase()}: same test as everyone.',
            style: const TextStyle(color: TColors.inkSoft)),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: onRecord, child: const Text('Record it')),
      ]),
    );
  }
}

class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.points});

  final List<(String, int)> points;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < points.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${points[i].$2}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Container(
                  height: 80 * points[i].$2 / 100,
                  decoration: BoxDecoration(
                    color: i == points.length - 1 ? TColors.neon : TColors.surface3,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({required this.moment});

  final Moment moment;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(TRadius.sm),
      onTap: moment.videoId == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => VideoScreen(videoId: moment.videoId!, startAt: moment.atSeconds))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6, right: 12),
            decoration: BoxDecoration(color: moment.good ? TColors.neon : TColors.cherry, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(moment.text),
              Text('${moment.videoTitle ?? 'Clip'} · ${moment.atSeconds.toStringAsFixed(1)} s',
                  style: const TextStyle(color: TColors.inkFaint, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _UploadingCard extends StatelessWidget {
  const _UploadingCard({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return TCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        const LoopyIcon('upload', color: TColors.neon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Uploading… ${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ScoreBar(progress * 100, height: 6),
          ]),
        ),
      ]),
    );
  }
}

class _ProcessingCard extends StatelessWidget {
  const _ProcessingCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return TCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: TColors.violet)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(count == 1 ? 'Pep is watching your clip…' : 'Pep is watching $count clips…',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
