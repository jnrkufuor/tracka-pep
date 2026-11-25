import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../util/local_video.dart';
import '../widgets/common.dart';
import '../widgets/profile_fields.dart' show FieldLabel, Segmented;
import 'uploads_screen.dart';

/// Upload a clip: pick it, say what it is, tap yourself (and the cones, for a drill), send it to Pep.
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key, this.drill});

  final String? drill;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  XFile? _file;
  VideoPlayerController? _video;
  final _title = TextEditingController();
  String _clipType = 'match';
  String? _drill;
  Offset? _target; // where you are, as a share of the frame (0..1)
  double _targetAt = 0;
  final List<Offset> _cones = [];
  double _conesAt = 0;
  double? _progress;

  @override
  void initState() {
    super.initState();
    if (widget.drill != null) {
      _clipType = 'drill';
      _drill = widget.drill;
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    _title.dispose();
    super.dispose();
  }

  Drill? get _drillInfo => context.read<AppState>().meta?.drills[_drill];
  bool get _needsCones => _clipType == 'drill' && (_drillInfo?.needsCalibration ?? false);
  int get _conesNeeded => _drillInfo?.cones.length ?? 0;

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickVideo(source: source, maxDuration: const Duration(minutes: 3));
    if (file == null) return;
    final old = _video;
    final controller = localVideoController(file.path);
    await controller.initialize();
    await controller.setLooping(true);
    setState(() {
      _file = file;
      _video = controller;
      _target = null;
      _cones.clear();
    });
    await old?.dispose();
  }

  void _tap(TapUpDetails d, Size size) {
    final v = _video;
    if (v == null) return;
    v.pause();
    final p = Offset((d.localPosition.dx / size.width).clamp(0, 1), (d.localPosition.dy / size.height).clamp(0, 1));
    final seconds = v.value.position.inMilliseconds / 1000;
    setState(() {
      if (_needsCones && _cones.length < _conesNeeded) {
        _cones.add(p);
        _conesAt = seconds;
      } else {
        _target = p;
        _targetAt = seconds;
      }
    });
  }

  String get _hint {
    if (_needsCones && _cones.length < _conesNeeded) {
      final c = _drillInfo!.cones[_cones.length];
      return 'Pause on a clear frame, then tap cone ${_cones.length + 1} of $_conesNeeded: '
          '${c[0].toStringAsFixed(0)} m along, ${c[1].toStringAsFixed(0)} m across.';
    }
    return _target == null
        ? 'Pause where you\'re clearly in shot and tap yourself, so Pep follows the right player.'
        : 'Got you. Tap again to move the marker.';
  }

  bool get _ready => _file != null && (!_needsCones || _cones.length == _conesNeeded) && (_clipType != 'drill' || _drill != null);

  Future<void> _upload() async {
    final s = context.read<AppState>();
    final nav = Navigator.of(context);
    final meta = <String, dynamic>{
      'title': _title.text.trim(),
      'clipType': _clipType,
      if (_clipType == 'drill') 'drill': _drill,
      if (_target != null) 'target': {'x': _target!.dx, 'y': _target!.dy},
      if (_target != null) 'targetAtSeconds': _targetAt,
      if (_needsCones)
        'calibration': {
          'atSeconds': _conesAt,
          'imagePoints': [for (final c in _cones) {'x': c.dx, 'y': c.dy}],
          'worldPointsM': _drillInfo!.cones,
        },
    };
    setState(() => _progress = 0);
    _video?.pause();
    try {
      // Saved to the queue first; it sends now, on Wi-Fi, or when you're back online.
      await s.upload(_file!, meta);
      nav.pushReplacement(MaterialPageRoute(builder: (_) => const UploadsScreen()));
    } catch (e) {
      if (mounted) {
        setState(() => _progress = null);
        showSnack(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = context.watch<AppState>().meta;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New clip')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
          if (_video == null) ...[
            TCard(
              accent: 'upload',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pick a clip', style: t.headlineMedium),
                const SizedBox(height: 8),
                const Text('3 seconds to 3 minutes. Daylight, camera on you, and the whole of you in shot works best.',
                    style: TextStyle(color: TColors.inkSoft)),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const LoopyIcon('film', color: TColors.onNeon, size: 22),
                  label: const Text(kIsWeb ? 'Choose a video' : 'From your gallery'),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.camera),
                    icon: const LoopyIcon('play', size: 20),
                    label: const Text('Record now'),
                  ),
                ],
              ]),
            ),
          ] else ...[
            _Preview(video: _video!, target: _target, cones: _cones, hint: _hint, onTap: _tap),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => _pick(ImageSource.gallery), child: const Text('Choose another')),
            ),
          ],
          const SizedBox(height: 12),
          const FieldLabel('What kind of clip'),
          Segmented<String>(
            options: const {'match': 'Match', 'training': 'Training', 'drill': 'Drill', 'highlight': 'Highlight'},
            value: _clipType,
            onChanged: (v) => setState(() {
              _clipType = v;
              _cones.clear();
              if (v == 'drill') _drill ??= meta?.drills.keys.first;
            }),
          ),
          if (_clipType == 'highlight')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Highlights are great to keep, but Pep trusts their scores less: they only show your best moments.',
                  style: TextStyle(color: TColors.inkFaint, fontSize: 12.5)),
            ),
          if (_clipType == 'drill' && meta != null) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _drill,
              isExpanded: true,
              dropdownColor: TColors.surface2,
              decoration: const InputDecoration(labelText: 'Which drill'),
              items: [for (final d in meta.drills.values) DropdownMenuItem(value: d.id, child: Text(d.label))],
              onChanged: (v) => setState(() {
                _drill = v;
                _cones.clear();
              }),
            ),
            if (_drillInfo != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: TColors.surface, borderRadius: BorderRadius.circular(TRadius.md)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const LoopyIcon('cone', color: TColors.neon, size: 24),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_drillInfo!.how, style: const TextStyle(fontSize: 13.5))),
                ]),
              ),
            ],
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Title (optional)', hintText: 'e.g. Sunday league vs Hearts U17'),
          ),
          const SizedBox(height: 8),
          if (_progress != null) ...[
            const Text('Saving your clip…', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ScoreBar(_progress! * 100),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _ready && _progress == null ? _upload : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: const Text('Send to Pep'),
          ),
        ]),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.video, required this.target, required this.cones, required this.hint, required this.onTap});

  final VideoPlayerController video;
  final Offset? target;
  final List<Offset> cones;
  final String hint;
  final void Function(TapUpDetails, Size) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(TRadius.md),
        child: AspectRatio(
          aspectRatio: video.value.aspectRatio,
          child: LayoutBuilder(builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            Widget pin(Offset p, {String? label}) => Positioned(
                  left: p.dx * size.width - 13,
                  top: p.dy * size.height - 13,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: label == null ? Colors.transparent : TColors.neon,
                      border: Border.all(color: TColors.neon, width: 3),
                      boxShadow: [BoxShadow(color: TColors.neon.withValues(alpha: 0.35), blurRadius: 10, spreadRadius: 3)],
                    ),
                    child: label == null
                        ? null
                        : Text(label, style: const TextStyle(color: TColors.onNeon, fontWeight: FontWeight.w700, fontSize: 11)),
                  ),
                );
            return GestureDetector(
              onTapUp: (d) => onTap(d, size),
              child: Stack(children: [
                Positioned.fill(child: VideoPlayer(video)),
                for (var i = 0; i < cones.length; i++) pin(cones[i], label: '${i + 1}'),
                if (target != null) pin(target!),
              ]),
            );
          }),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        ValueListenableBuilder(
          valueListenable: video,
          builder: (_, v, __) => IconButton(
            onPressed: () => v.isPlaying ? video.pause() : video.play(),
            icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: TColors.neon),
          ),
        ),
        Expanded(
          child: VideoProgressIndicator(
            video,
            allowScrubbing: true,
            colors: const VideoProgressColors(playedColor: TColors.neon, bufferedColor: TColors.surface3, backgroundColor: TColors.surface2),
          ),
        ),
      ]),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: TColors.surface, borderRadius: BorderRadius.circular(TRadius.sm)),
        child: Row(children: [
          const LoopyIcon('target', size: 22, color: TColors.neon),
          const SizedBox(width: 10),
          Expanded(child: Text(hint, style: const TextStyle(fontSize: 13.5))),
        ]),
      ),
    ]);
  }
}
