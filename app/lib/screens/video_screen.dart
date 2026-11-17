import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/skill_card.dart';

/// One clip: the video (yours, or "what Pep saw"), key moments, and Pep's analysis.
class VideoScreen extends StatefulWidget {
  const VideoScreen({super.key, required this.videoId, this.startAt});

  final String videoId;
  final double? startAt;

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  Video? _v;
  String? _error;
  VideoPlayerController? _player;
  bool _overlay = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = await context.read<AppState>().api.video(widget.videoId);
      if (!mounted) return;
      setState(() {
        _v = v;
        _error = null;
      });
      if (_player == null && v.videoUrl != null) await _play(v.videoUrl!, seekTo: widget.startAt);
      _poll?.cancel();
      if (v.processing) _poll = Timer(const Duration(seconds: 5), _load);
      if (!v.processing && mounted) context.read<AppState>().refresh();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _play(String url, {double? seekTo}) async {
    final old = _player;
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    await c.initialize();
    if (seekTo != null) await c.seekTo(Duration(milliseconds: (seekTo * 1000).round()));
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _player = c);
    await old?.dispose();
  }

  Future<void> _toggleOverlay() async {
    final v = _v;
    if (v?.overlayUrl == null) return;
    final at = _player?.value.position.inMilliseconds;
    setState(() => _overlay = !_overlay);
    await _play(_overlay ? v!.overlayUrl! : v!.videoUrl!, seekTo: at == null ? null : at / 1000);
  }

  void _seek(double seconds) {
    _player?.seekTo(Duration(milliseconds: (seconds * 1000).round()));
    _player?.play();
  }

  Future<void> _menu(String action) async {
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    if (action == 'rename') {
      final controller = TextEditingController(text: _v?.title);
      final title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: TColors.surface,
          title: const Text('Rename clip'),
          content: TextField(controller: controller, autofocus: true, maxLength: 120),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
          ],
        ),
      );
      if (title != null) {
        await s.renameVideo(widget.videoId, title);
        await _load();
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: TColors.surface,
          title: const Text('Delete this clip?'),
          content: const Text('The video and Pep\'s notes on it are deleted for good.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: TColors.cherry),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await s.deleteVideo(widget.videoId);
        nav.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final settings = context.watch<AppState>().settings;
    return Scaffold(
      appBar: AppBar(
        title: Text(v?.displayTitle ?? ''),
        actions: [
          if (v != null)
            PopupMenuButton<String>(
              color: TColors.surface2,
              onSelected: _menu,
              icon: const LoopyIcon('settings', size: 24),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: TColors.cherry))),
              ],
            ),
        ],
      ),
      body: v == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
              if (_player != null) _Player(controller: _player!, moments: v.analysis?.moments ?? const [], onSeek: _seek),
              if (v.overlayUrl != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _toggleOverlay,
                    icon: LoopyIcon('eye', size: 20, color: TColors.neon),
                    label: Text(_overlay ? 'Show my video' : 'Show what Pep saw'),
                  ),
                ),
              const SizedBox(height: 6),
              Text('${v.clipType} · ${DateFormat.yMMMd().add_jm().format(v.createdAt)}',
                  style: const TextStyle(color: TColors.inkFaint)),
              const SizedBox(height: 14),
              if (v.processing) const _Watching(),
              if (v.status == 'FAILED')
                TCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Pep couldn\'t score this clip', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(v.error ?? 'Something went wrong.', style: const TextStyle(color: TColors.inkSoft)),
                  ]),
                ),
              if (v.analysis != null) _AnalysisView(a: v.analysis!, settings: settings, onSeek: _seek),
            ]),
    );
  }
}

class _Player extends StatelessWidget {
  const _Player({required this.controller, required this.moments, required this.onSeek});

  final VideoPlayerController controller;
  final List<Moment> moments;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final total = controller.value.duration.inMilliseconds / 1000;
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(TRadius.md),
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: GestureDetector(
            onTap: () => controller.value.isPlaying ? controller.pause() : controller.play(),
            child: Stack(fit: StackFit.expand, children: [
              VideoPlayer(controller),
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (_, v, __) => v.isPlaying
                    ? const SizedBox.shrink()
                    : const Center(child: Icon(Icons.play_circle_fill_rounded, size: 64, color: TColors.neon)),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      // Timeline: the playhead plus a dot for every moment (neon = good, cherry = work on).
      SizedBox(
        height: 28,
        child: LayoutBuilder(builder: (context, box) {
          return ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, v, __) {
              final at = total == 0 ? 0.0 : (v.position.inMilliseconds / 1000) / total;
              return Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(color: TColors.surface2, borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                Positioned(
                  left: (box.maxWidth * at).clamp(0, box.maxWidth - 2),
                  top: 4,
                  bottom: 4,
                  child: Container(width: 2, color: TColors.ink),
                ),
                for (final m in moments)
                  if (total > 0)
                    Positioned(
                      left: (box.maxWidth * (m.atSeconds / total)).clamp(0, box.maxWidth - 16),
                      top: 6,
                      child: GestureDetector(
                        onTap: () => onSeek(m.atSeconds),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: m.good ? TColors.neon : TColors.cherry,
                            shape: BoxShape.circle,
                            border: Border.all(color: TColors.bg, width: 3),
                          ),
                        ),
                      ),
                    ),
              ]);
            },
          );
        }),
      ),
    ]);
  }
}

class _Watching extends StatelessWidget {
  const _Watching();

  @override
  Widget build(BuildContext context) {
    return const TCard(
      accent: 'ball',
      child: Row(children: [
        SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: TColors.violet)),
        SizedBox(width: 16),
        Expanded(
          child: Text('Pep is watching your clip. This usually takes a minute or two. You can leave this screen.',
              style: TextStyle(fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

class _AnalysisView extends StatelessWidget {
  const _AnalysisView({required this.a, required this.settings, required this.onSeek});

  final Analysis a;
  final AppSettings settings;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = a.metrics;
    final tiles = <(String, String, String)>[
      ('Top speed', settings.speed(m['top_speed_ms']), settings.speedUnit),
      ('Distance', m['distance_m']?.toStringAsFixed(0) ?? '–', 'm'),
      ('Sprints', m['high_speed_runs']?.toStringAsFixed(0) ?? '–', ''),
      ('Touches / min', m['touches_per_min']?.toStringAsFixed(0) ?? '–', ''),
      if (m['sprint_30m_s'] != null) ('30 m sprint', m['sprint_30m_s']!.toStringAsFixed(2), 's'),
      if (m['split_10m_s'] != null) ('10 m split', m['split_10m_s']!.toStringAsFixed(2), 's'),
      if (m['agility_5105_s'] != null) ('5-10-5', m['agility_5105_s']!.toStringAsFixed(2), 's'),
      if (m['juggles_best'] != null) ('Keepy-ups', m['juggles_best']!.toStringAsFixed(0), ''),
      if (m['dives'] != null) ('Dives', m['dives']!.toStringAsFixed(0), ''),
    ];
    final roles = a.roleFit.where((r) => (r.coverage ?? 0) >= 0.35).take(3).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TCard(
        neon: true,
        accent: 'star',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            KitNumber(a.overallScore, size: 92, color: TColors.onNeon),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Eyebrow('This clip', color: TColors.onNeon),
                  const SizedBox(height: 4),
                  Text('${(a.confidence ?? 'LOW').toLowerCase()} confidence',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
          if (a.summary != null) ...[
            const SizedBox(height: 14),
            Text(a.summary!, style: const TextStyle(fontFamily: TType.display, fontSize: 18, height: 1.35, fontWeight: FontWeight.w500)),
          ],
        ]),
      ),
      const SizedBox(height: 22),
      const Eyebrow('Measured'),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.1,
        children: [
          for (final (label, value, unit) in tiles)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: TColors.surface,
                borderRadius: BorderRadius.circular(TRadius.md),
                border: Border.all(color: TColors.lineSoft),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Eyebrow(label),
                const SizedBox(height: 4),
                Text.rich(TextSpan(children: [
                  TextSpan(text: value, style: t.headlineMedium),
                  TextSpan(text: ' $unit', style: const TextStyle(color: TColors.inkFaint, fontSize: 13)),
                ])),
              ]),
            ),
        ],
      ),
      if (a.moments.isNotEmpty) ...[
        const SizedBox(height: 22),
        const Eyebrow('Moments'),
        const SizedBox(height: 6),
        for (final mo in a.moments)
          InkWell(
            onTap: () => onSeek(mo.atSeconds),
            borderRadius: BorderRadius.circular(TRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 48,
                  child: Text('${mo.atSeconds.toStringAsFixed(1)}s',
                      style: const TextStyle(fontFamily: TType.display, fontWeight: FontWeight.w700, color: TColors.inkFaint)),
                ),
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 6, right: 12),
                  decoration: BoxDecoration(color: mo.good ? TColors.neon : TColors.cherry, shape: BoxShape.circle),
                ),
                Expanded(child: Text(mo.text)),
              ]),
            ),
          ),
      ],
      const SizedBox(height: 22),
      const Eyebrow('Skills in this clip'),
      const SizedBox(height: 10),
      for (final s in a.skills) ...[SkillCard(skill: s), const SizedBox(height: 10)],
      if (roles.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Eyebrow('Roles this clip suits'),
        const SizedBox(height: 10),
        TCard(
          child: Column(children: [
            for (final r in roles) ...[
              Row(children: [
                Expanded(child: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${r.score}', style: t.titleLarge),
              ]),
              const SizedBox(height: 6),
              ScoreBar(r.score),
              const SizedBox(height: 12),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 14),
      Text(
        a.coachSource == 'gemini'
            ? 'Numbers are measured by Pep. Notes are written by Pep\'s AI coach after watching your clip.'
            : 'Numbers are measured by Pep. Notes are written from your measurements.',
        style: const TextStyle(color: TColors.inkFaint, fontSize: 12),
      ),
    ]);
  }
}
