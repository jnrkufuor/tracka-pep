import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'feed_screens.dart' show showPostSheet;
import 'home_screen.dart' show openUpload;
import 'review_screens.dart' show ReviewView;

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

  /// Rename: a sheet that saves as you go (no Save button).
  Future<void> _rename() async {
    final s = context.read<AppState>();
    var title = _v?.title ?? '';
    await showEditSheet<void>(
      context,
      title: 'Rename clip',
      child: TextFormField(
        initialValue: title,
        autofocus: true,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Title', hintText: 'Sunday match, 2nd half'),
        onChanged: (v) => title = v,
      ),
    );
    if (title.trim() != (_v?.title ?? '')) {
      await s.renameVideo(widget.videoId, title.trim());
      await _load();
    }
  }

  Future<void> _delete() async {
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final ok = await showEditSheet<bool>(
      context,
      title: 'Delete this clip?',
      child: Builder(
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text("The video and Pep's notes on it are deleted for good.", style: TextStyle(fontSize: 14.5, color: Tk.inkSoft)),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Tk.gold, side: const BorderSide(color: Color(0x66FFC21A))),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete it'),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep it')),
        ]),
      ),
    );
    if (ok == true) {
      await s.deleteVideo(widget.videoId);
      nav.pop();
    }
  }

  Future<void> _more(Video v) => showEditSheet<void>(
        context,
        title: v.displayTitle,
        child: Builder(
          builder: (ctx) => Column(children: [
            if (v.status == 'READY')
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const TIcon('share', size: 20, color: Tk.ink),
                title: const Text('Post on Pitchside'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showPostSheet(context, widget.videoId);
                },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const TIcon('pencil', size: 20, color: Tk.ink),
              title: const Text('Rename'),
              onTap: () {
                Navigator.of(ctx).pop();
                _rename();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const TIcon('trash', size: 20, color: Tk.gold),
              title: const Text('Delete', style: TextStyle(color: Tk.gold)),
              onTap: () {
                Navigator.of(ctx).pop();
                _delete();
              },
            ),
          ]),
        ),
      );

  static const _kinds = {'match': 'Match', 'training': 'Training', 'drill': 'Test or drill', 'highlight': 'Highlight'};

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final settings = context.watch<AppState>().settings;
    return Scaffold(
      appBar: AppBar(
        title: Text(v?.displayTitle ?? ''),
        actions: [
          if (v != null) IconButton(tooltip: 'More', onPressed: () => _more(v), icon: const TIcon('settings', size: 21, color: Tk.ink)),
        ],
      ),
      body: v == null
          ? (_error == null ? const Center(child: CircularProgressIndicator()) : StateView.error(onRetry: _load))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
              if (_player != null) _Player(controller: _player!, moments: v.analysis?.moments ?? const [], onSeek: _seek),
              if (v.overlayUrl != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _toggleOverlay,
                    icon: TIcon('eye2', size: 18, color: context.accent.main),
                    label: Text(_overlay ? 'Show my video' : 'Show what Pep saw'),
                  ),
                ),
              const SizedBox(height: 6),
              Text('${_kinds[v.clipType] ?? 'Clip'} · ${DateFormat.yMMMd().add_jm().format(v.createdAt)}',
                  style: const TextStyle(fontSize: 13, color: Tk.faint)),
              const SizedBox(height: 14),
              if (v.processing) const _Watching(),
              if (v.status == 'FAILED')
                StateView(
                  icon: 'camera',
                  kind: StateKind.watchOut,
                  title: "Pep couldn't read this clip",
                  message: v.error ?? 'Something went wrong.',
                  actionLabel: 'Film it again',
                  onAction: () => openUpload(context),
                ),
              if (v.review != null) ...[
                ReviewView(review: v.review!, onSeek: _seek),
                const SizedBox(height: 22),
              ] else if (v.analysis?.summary != null) ...[
                Text(v.analysis!.summary!, style: const TextStyle(fontSize: 15, height: 1.45, color: Tk.ink)),
                const SizedBox(height: 16),
              ],
              if (v.analysis != null) _Measured(a: v.analysis!, settings: settings),
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
        borderRadius: BorderRadius.circular(Tk.rCard),
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
                    : Center(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x99000000)),
                          alignment: Alignment.center,
                          child: const TIcon('play', size: 22, color: Colors.white),
                        ),
                      ),
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
                    decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                Positioned(
                  left: (box.maxWidth * at).clamp(0, box.maxWidth - 2),
                  top: 4,
                  bottom: 4,
                  child: Container(width: 2, color: Tk.ink),
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
                            color: m.good ? context.accent.main : Tk.gold,
                            shape: BoxShape.circle,
                            border: Border.all(color: Tk.bg, width: 3),
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
  Widget build(BuildContext context) => const Panel(
        child: Row(children: [
          SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Tk.pep)),
          SizedBox(width: 14),
          Expanded(
            child: Text('Pep is watching your clip. This usually takes a minute or two. You can leave this screen.',
                style: TextStyle(fontSize: 14.5, color: Tk.ink)),
          ),
        ]),
      );
}

class _Measured extends StatelessWidget {
  const _Measured({required this.a, required this.settings});

  final Analysis a;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final m = a.metrics;
    final tiles = <(String, String, String)>[
      if (m['top_speed_ms'] != null) ('Top speed', settings.speed(m['top_speed_ms']), settings.speedUnit),
      if (m['distance_m'] != null) ('Distance', m['distance_m']!.toStringAsFixed(0), 'm'),
      if (m['high_speed_runs'] != null) ('Sprints', m['high_speed_runs']!.toStringAsFixed(0), ''),
      if (m['touches_per_min'] != null) ('Touches a minute', m['touches_per_min']!.toStringAsFixed(0), ''),
      if (m['sprint_30m_s'] != null) ('30 m sprint', m['sprint_30m_s']!.toStringAsFixed(2), 's'),
      if (m['split_10m_s'] != null) ('10 m split', m['split_10m_s']!.toStringAsFixed(2), 's'),
      if (m['agility_5105_s'] != null) ('5-10-5', m['agility_5105_s']!.toStringAsFixed(2), 's'),
      if (m['juggles_best'] != null) ('Keepy-ups', m['juggles_best']!.toStringAsFixed(0), ''),
      if (m['dives'] != null) ('Dives', m['dives']!.toStringAsFixed(0), ''),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('What Pep measured', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
        children: [
          for (final (label, value, unit) in tiles)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: Tk.muted))),
                Text('$value${unit.isEmpty ? '' : ' $unit'}',
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
              ]),
            ),
          const SizedBox(height: 8),
          const InfoNote(InfoNote.measured),
        ],
      ),
    );
  }
}
