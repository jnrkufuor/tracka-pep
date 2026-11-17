import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart' show openUpload;
import 'video_screen.dart';

/// Your library: every clip you've uploaded, newest first, with Pep's score.
class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Your videos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openUpload(context),
        backgroundColor: TColors.neon,
        foregroundColor: TColors.onNeon,
        icon: const LoopyIcon('upload', color: TColors.onNeon, size: 22),
        label: const Text('Upload', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: TColors.neon,
        onRefresh: s.refresh,
        child: s.videos.isEmpty
            ? ListView(children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: EmptyState(
                    icon: 'film',
                    title: 'No clips yet',
                    message: 'Your clips live here, with Pep\'s notes on each one. Only you can see them.',
                    action: FilledButton(onPressed: () => openUpload(context), child: const Text('Upload a clip')),
                  ),
                ),
              ])
            : LayoutBuilder(builder: (context, box) {
                final cols = box.maxWidth > 900 ? 4 : (box.maxWidth > 600 ? 3 : 2);
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: s.videos.length,
                  itemBuilder: (_, i) => VideoTile(video: s.videos[i]),
                );
              }),
      ),
    );
  }
}

class VideoTile extends StatelessWidget {
  const VideoTile({super.key, required this.video});

  final Video video;

  @override
  Widget build(BuildContext context) {
    final v = video;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: v.id))),
      child: Container(
        decoration: BoxDecoration(
          color: TColors.surface,
          borderRadius: BorderRadius.circular(TRadius.md),
          border: Border.all(color: TColors.lineSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              if (v.thumbnailUrl != null)
                Image.network(v.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _ThumbFallback())
              else
                const _ThumbFallback(),
              Positioned(left: 8, top: 8, child: _StatusBadge(video: v)),
              if (v.overallScore != null)
                Positioned(
                  right: 10,
                  bottom: 6,
                  child: KitNumber(v.overallScore, size: 36, color: TColors.neon),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${v.clipType} · ${DateFormat.MMMd().format(v.createdAt)}',
                  style: const TextStyle(color: TColors.inkFaint, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: TColors.surface2, child: Center(child: LoopyIcon('film', size: 40, color: TColors.inkFaint)));
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.video});

  final Video video;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (video.status) {
      'READY' => (null, TColors.neon),
      'FAILED' => ('Couldn\'t read', TColors.cherry),
      _ => ('Pep is watching', TColors.violet),
    };
    if (label == null) return const SizedBox.shrink();
    return Pill(label, color: color, background: TColors.bg.withValues(alpha: 0.85));
  }
}
