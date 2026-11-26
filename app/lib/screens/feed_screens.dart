import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'guardian_screens.dart';

/// Pitchside's Feed, a player's page, search, and posting your own clip
/// (canvas: Pitchside › Feed, Another player's profile, Search players).
///
/// Rules the server enforces and these screens follow (pep/players/pitchside.py):
/// no messages, only shirt names (never full names or towns), and Pep never
/// appears on other players' clips.

/// The vertical feed: For you / Following, one clip per screen.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.posts, this.startAt = 0});

  /// Show these posts (a player's page) instead of loading the feed.
  final List<FeedPost>? posts;
  final int startAt;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  String tab = 'for_you';
  List<FeedPost>? posts;
  bool failed = false;
  int page = 0;

  @override
  void initState() {
    super.initState();
    page = widget.startAt;
    if (widget.posts != null) {
      posts = widget.posts;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      posts = null;
      failed = false;
    });
    try {
      final r = await context.read<AppState>().api.feed(tab: tab);
      if (mounted) setState(() => posts = r.posts);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = posts;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (failed)
          StateView.error(onRetry: _load)
        else if (p == null)
          const Center(child: CircularProgressIndicator())
        else if (p.isEmpty)
          StateView(
            icon: 'clip',
            title: tab == 'following' ? 'Nothing from players you follow yet' : 'No clips yet',
            message: tab == 'following'
                ? 'Follow players from their clips or from search, and their posts show here.'
                : 'When players your age post clips, they show here.',
            actionLabel: 'Find players',
            onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
          )
        else
          PageView.builder(
            scrollDirection: Axis.vertical,
            controller: PageController(initialPage: widget.startAt),
            itemCount: p.length,
            onPageChanged: (i) => setState(() => page = i),
            itemBuilder: (_, i) => FeedPage(post: p[i], active: i == page, onChanged: () => setState(() {})),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              IconButton(tooltip: 'Back', onPressed: () => Navigator.of(context).pop(), icon: const TIcon('back', size: 20, color: Tk.ink)),
              const Spacer(),
              if (widget.posts == null)
                for (final (k, label) in const [('for_you', 'For you'), ('following', 'Following')])
                  TextButton(
                    onPressed: () {
                      if (tab == k) return;
                      setState(() => tab = k);
                      _load();
                    },
                    child: Text(label,
                        style: TextStyle(fontSize: 15.5, fontWeight: tab == k ? FontWeight.w700 : FontWeight.w500, color: tab == k ? Tk.ink : Tk.muted)),
                  ),
              const Spacer(),
              IconButton(
                tooltip: 'Search players',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
                icon: const TIcon('search', size: 20, color: Tk.ink),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// One clip in the feed. Plays only while on screen (saves data and battery).
class FeedPage extends StatefulWidget {
  const FeedPage({super.key, required this.post, required this.active, this.onChanged});

  final FeedPost post;
  final bool active;
  final VoidCallback? onChanged;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  VideoPlayerController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(FeedPage old) {
    super.didUpdateWidget(old);
    if (widget.active && _c == null) _start();
    if (!widget.active && _c != null) _stop();
  }

  Future<void> _start() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.post.videoUrl));
    _c = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      if (mounted && widget.active) await c.play();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _stop() {
    _c?.dispose();
    _c = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Future<void> _respect() async {
    final p = widget.post;
    final s = context.read<AppState>();
    setState(() {
      p.respected = !p.respected;
      p.respect += p.respected ? 1 : -1;
    });
    try {
      await s.api.respect(p.id, p.respected);
    } catch (_) {
      if (mounted) {
        setState(() {
          p.respected = !p.respected;
          p.respect += p.respected ? 1 : -1;
        });
      }
    }
  }

  Future<void> _save() async {
    final p = widget.post;
    setState(() => p.saved = !p.saved);
    try {
      await context.read<AppState>().api.savePost(p.id, p.saved);
    } catch (_) {
      if (mounted) setState(() => p.saved = !p.saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final c = _c;
    final a = context.accent;
    return Stack(fit: StackFit.expand, children: [
      GestureDetector(
        onTap: () => c == null ? null : (c.value.isPlaying ? c.pause() : c.play()),
        child: c != null && c.value.isInitialized
            ? FittedBox(fit: BoxFit.cover, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)))
            : (p.thumbnailUrl != null
                ? Image.network(p.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Tk.card))
                : const ColoredBox(color: Tk.card)),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)]),
        ),
      ),
      Positioned(
        right: 10,
        bottom: 110,
        child: Column(children: [
          _Side(icon: 'heart', label: '${p.respect}', on: p.respected, colour: a.main, onTap: p.mine ? null : _respect, semantic: 'Respect'),
          _Side(icon: 'download', label: 'Save', on: p.saved, colour: a.main, onTap: _save, semantic: 'Save'),
          _Side(icon: 'settings', label: 'More', onTap: () => showPostMenu(context, p), semantic: 'More'),
        ]),
      ),
      Positioned(
        left: 16,
        right: 80,
        bottom: 40,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: p.mine ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(id: p.author.id))),
            child: Row(children: [
              _Avatar(p.author.initials),
              const SizedBox(width: 10),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.author.shirtName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(p.author.line, style: const TextStyle(fontSize: 12.5, color: Tk.inkSoft)),
                ]),
              ),
            ]),
          ),
          if (p.caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(p.caption, style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.4)),
          ],
          if (p.challenge != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(999)),
              child: Text(p.challenge!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Tk.ink)),
            ),
          ],
        ]),
      ),
    ]);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.initials, {this.size = 40});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: context.accent.tile, border: Border.all(color: context.accent.main, width: 1.5)),
        child: Text(initials, style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w700, color: context.accent.main)),
      );
}

class _Side extends StatelessWidget {
  const _Side({required this.icon, required this.label, required this.semantic, this.onTap, this.on = false, this.colour = Tk.ink});

  final String icon;
  final String label;
  final String semantic;
  final VoidCallback? onTap;
  final bool on;
  final Color colour;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic,
        selected: on,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Column(children: [
              TIcon(icon, size: 26, color: on ? colour : Colors.white),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

/// Report, block, or delete your own post. Reporting hides the clip for you at once.
Future<void> showPostMenu(BuildContext context, FeedPost p) {
  final s = context.read<AppState>();
  return showEditSheet<void>(
    context,
    title: p.mine ? 'Your post' : 'This clip',
    child: Builder(
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (p.mine)
          OutlinedButton(
            onPressed: () async {
              await s.api.deletePost(p.id);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) showToast(context, 'Taken down', detail: 'The clip is still in your library.', aboveTabs: false);
            },
            child: const Text('Take it down'),
          )
        else ...[
          const SectionLabel('Report it'),
          for (final (k, t) in const [
            ('unsafe', 'Someone could get hurt'),
            ('bullying', 'Bullying or mean'),
            ('not_football', 'Not football'),
            ('fake', 'Fake or not theirs'),
            ('other', 'Something else'),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t),
              onTap: () async {
                await s.api.report(p.id, k);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) showToast(context, 'Thanks for telling us', detail: "You won't see this clip again.", aboveTabs: false);
              },
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              await s.api.block(p.author.id, true);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) showToast(context, 'Blocked ${p.author.shirtName}', detail: "You won't see each other.", aboveTabs: false);
            },
            child: Text('Block ${p.author.shirtName}'),
          ),
        ],
      ]),
    ),
  );
}

/// Another player's page: no messages, ever. Follow and respect only.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.id});

  final String id;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  PlayerPage? p;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await context.read<AppState>().api.player(widget.id);
      if (mounted) setState(() => p = v);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _follow() async {
    final v = p!;
    await context.read<AppState>().api.follow(v.player.id, !v.player.following);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final v = p;
    if (failed) {
      return Scaffold(
        appBar: AppBar(),
        body: StateView(icon: 'users', title: "Can't show this player", message: 'They may have made their profile private.', actionLabel: 'Back', onAction: () => Navigator.of(context).pop()),
      );
    }
    if (v == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    Widget stat(int n, String label) => Expanded(
          child: Column(children: [
            Text('$n', style: const TextStyle(fontFamily: TType.display, fontSize: 20, fontWeight: FontWeight.w800, color: Tk.ink)),
            Text(label, style: const TextStyle(fontSize: 12, color: Tk.muted)),
          ]),
        );
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Row(children: [
          _Avatar(v.player.initials, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.player.shirtName, style: const TextStyle(fontFamily: TType.display, fontSize: 20, fontWeight: FontWeight.w800, color: Tk.ink)),
              Text([v.player.line, if (v.level != null) v.level!].join(' · '), style: const TextStyle(fontSize: 13, color: Tk.muted)),
              if (v.style != null) Text('Style: ${v.style}', style: const TextStyle(fontSize: 13, color: Tk.inkSoft)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: v.player.following
              ? OutlinedButton(onPressed: _follow, child: const Text('Following'))
              : FilledButton(onPressed: _follow, child: const Text('Follow')),
        ),
        const SizedBox(height: 16),
        Row(children: [stat(v.clips, 'Clips'), stat(v.respect, 'Respect'), stat(v.followers, 'Followers')]),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.7,
          children: [
            for (final (i, post) in v.posts.indexed)
              InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FeedScreen(posts: v.posts, startAt: i))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: post.thumbnailUrl != null
                      ? Image.network(post.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Tk.card2))
                      : const ColoredBox(color: Tk.card2, child: Center(child: TIcon('play', size: 18, color: Tk.faint))),
                ),
              ),
          ],
        ),
        if (v.player.under18) ...[
          const SizedBox(height: 14),
          const InfoNote('Under 18. No messages. Contact goes through their guardian.'),
        ],
      ]),
    );
  }
}

/// Search players: only players who chose to be seen show up.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  ({List<FeedAuthor> players, List<FeedAuthor> nearYou})? r;
  String q = '';

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String text) async {
    q = text;
    try {
      final v = await context.read<AppState>().api.searchPlayers(text);
      if (mounted && q == text) setState(() => r = v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final v = r;
    Widget row(FeedAuthor a) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _Avatar(a.initials),
          title: Text(a.shirtName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(a.line),
          trailing: Text(a.following ? 'Following' : '', style: const TextStyle(color: Tk.muted, fontSize: 12.5)),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(id: a.id))),
        );
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Search by shirt name', border: InputBorder.none, filled: false),
          onChanged: _search,
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        if (v != null && q.trim().isNotEmpty) ...[
          const SectionLabel('Players'),
          if (v.players.isEmpty) const Text('Nobody by that name.', style: TextStyle(color: Tk.muted)),
          for (final a in v.players) row(a),
          const SizedBox(height: 14),
        ],
        if (v != null && v.nearYou.isNotEmpty) ...[
          const SectionLabel('Players your age near you'),
          for (final a in v.nearYou) row(a),
        ],
        const SizedBox(height: 14),
        const InfoNote('Only players who chose to be seen show up here.'),
      ]),
    );
  }
}

/// Post one of your clips on Pitchside (creating something new: it has a button).
Future<void> showPostSheet(BuildContext context, String videoId) async {
  final s = context.read<AppState>();
  final f = await s.api.feed().then((r) => r.canPost).catchError((_) => false);
  if (!context.mounted) return;
  if (!f) {
    if (s.me?.needsGuardian ?? false) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuardianScreen()));
    } else {
      await showAskGuardian(context, 'post');
    }
    return;
  }
  var caption = '';
  await showEditSheet<void>(
    context,
    title: 'Post on Pitchside',
    child: Builder(
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          maxLength: 200,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Say something about it', hintText: 'Took me weeks.'),
          onChanged: (v) => caption = v,
        ),
        const InfoNote("Players see your shirt name, position, age group and region. Pep's notes on this clip stay with you."),
        const SizedBox(height: 10),
        // Shown before anyone posts (Google Play asks apps used by children for this).
        const SafetyNote(SafetyNote.online, icon: 'lock'),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () async {
            try {
              await s.api.post(videoId, caption: caption);
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (context.mounted) showToast(context, 'Posted', detail: 'Players can see it on Pitchside.', aboveTabs: false);
            } catch (e) {
              if (ctx.mounted) showToast(ctx, "Couldn't post it", detail: '$e', ok: false, aboveTabs: false);
            }
          },
          child: const Text('Post'),
        ),
      ]),
    ),
  );
}
