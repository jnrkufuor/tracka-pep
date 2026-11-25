import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'home_screen.dart' show openUpload;
import 'video_screen.dart';

/// Your clips: every clip, newest first, as a grid you can filter by kind.
/// Only you can see them until you post one on Pitchside. No scores here:
/// open a clip for Pep's review.
class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<VideosScreen> {
  String kind = 'all';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final shown = s.videos.where((v) => kind == 'all' || v.clipType == kind).toList();
    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(tooltip: 'Add a clip', onPressed: () => openUpload(context), icon: const TIcon('plus', size: 22, color: Tk.ink)),
      ]),
      body: RefreshIndicator(
        onRefresh: s.refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
          Text('Your clips', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 4),
          const Text('Only you can see these until you post them.', style: TextStyle(fontSize: 13, color: Tk.muted)),
          const SizedBox(height: 14),
          SingleChips<String>(
            options: const {'all': 'All', 'match': 'Matches', 'training': 'Training', 'drill': 'Tests and drills', 'highlight': 'Highlights'},
            value: kind,
            onChanged: (v) => setState(() => kind = v),
          ),
          const SizedBox(height: 14),
          if (shown.isEmpty)
            StateView(
              icon: 'clip',
              title: s.videos.isEmpty ? 'No clips yet' : 'None of these yet',
              message: 'Film a match, a drill or a challenge. Pep watches it and tells you what went well.',
              actionLabel: 'Add a clip',
              onAction: () => openUpload(context),
            )
          else
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.72,
              children: [for (final v in shown) ClipTile(video: v)],
            ),
        ]),
      ),
    );
  }
}

class ClipTile extends StatelessWidget {
  const ClipTile({super.key, required this.video});

  final Video video;

  @override
  Widget build(BuildContext context) {
    final v = video;
    final (label, colour) = v.processing
        ? ('Pep is watching', Tk.pep)
        : v.status == 'FAILED'
            ? ("Couldn't read it", Tk.gold)
            : ('Analysed', Tk.inkSoft);
    return Semantics(
      button: true,
      label: '${v.displayTitle}, $label',
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: v.id))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(fit: StackFit.expand, children: [
            if (v.thumbnailUrl != null)
              Image.network(v.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Tk.card2))
            else
              const ColoredBox(color: Tk.card2, child: Center(child: TIcon('play', size: 18, color: Tk.faint))),
            const DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)])),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(label, style: TextStyle(fontSize: 10.5, color: colour)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
