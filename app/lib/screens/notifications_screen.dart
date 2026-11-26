import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'guardian_screens.dart';
import 'review_screens.dart' show TipsScreen;
import 'training_screens.dart' show WeekScreen;
import 'video_screen.dart';

/// The bell (canvas: Notifications): All, From Pep, Activity; Today, This week,
/// Earlier. Tapping one opens what it's about. Which kinds arrive is set in
/// Settings › Notifications; quiet hours hold back push messages at night.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? items;
  bool failed = false;
  String filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<AppState>().api.notifications();
      if (mounted) setState(() => items = r.items);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _readAll() async {
    final s = context.read<AppState>();
    await s.api.markRead();
    setState(() {
      for (final n in items ?? const <AppNotification>[]) {
        n.read = true;
      }
    });
    await s.loadUnread();
  }

  Future<void> _open(AppNotification n) async {
    final s = context.read<AppState>();
    if (!n.read) {
      setState(() => n.read = true);
      s.api.markRead([n.id]).then((_) => s.loadUnread()).catchError((_) {});
    }
    await openLink(Navigator.of(context), n.link ?? const {});
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)}m';
    if (d.inHours < 24) return '${d.inHours}h';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return d.inDays < 7 ? days[t.weekday - 1] : '${t.day}/${t.month}';
  }

  @override
  Widget build(BuildContext context) {
    final all = items;
    return Scaffold(
      appBar: AppBar(actions: [
        if (all != null && all.any((n) => !n.read)) TextButton(onPressed: _readAll, child: const Text('Mark all read')),
      ]),
      body: failed
          ? StateView.error(onRetry: _load)
          : all == null
              ? ListView(padding: const EdgeInsets.all(20), children: const [Skeleton(height: 60), SizedBox(height: 10), Skeleton(height: 60)])
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
                    Text('Notifications', style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 14),
                    SingleChips<String>(
                      options: const {'all': 'All', 'pep': 'From Pep', 'activity': 'Activity'},
                      value: filter,
                      onChanged: (v) => setState(() => filter = v),
                    ),
                    const SizedBox(height: 16),
                    ..._grouped(all.where((n) => filter == 'all' || n.group == filter).toList()),
                    const SizedBox(height: 14),
                    const InfoNote('Quiet hours: no notifications 9 pm to 7 am.'),
                  ]),
                ),
    );
  }

  List<Widget> _grouped(List<AppNotification> list) {
    if (list.isEmpty) {
      return const [Panel(child: Text("Nothing here yet. When Pep finishes a clip or someone gives you respect, it shows here.", style: TextStyle(color: Tk.inkSoft)))];
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String label(DateTime t) => !t.isBefore(today) ? 'Today' : now.difference(t).inDays < 7 ? 'This week' : 'Earlier';
    final out = <Widget>[];
    String? current;
    final group = <AppNotification>[];
    void flush() {
      if (group.isEmpty) return;
      out
        ..add(SectionLabel(current!))
        ..add(Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Column(children: [for (final (i, n) in group.indexed) _row(n, last: i == group.length - 1)]),
        ))
        ..add(const SizedBox(height: 16));
      group.clear();
    }

    for (final n in list) {
      final l = label(n.createdAt);
      if (l != current) {
        flush();
        current = l;
      }
      group.add(n);
    }
    flush();
    return out;
  }

  Widget _row(AppNotification n, {required bool last}) {
    final pep = n.group == 'pep';
    final a = context.accent;
    return InkWell(
      onTap: () => _open(n),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Tk.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(
            icon: pep ? 'pep' : (n.kind == 'respect' ? 'heart' : n.kind == 'guardian' ? 'shield' : n.kind == 'pitch' ? 'pin' : 'bell'),
            color: pep ? Tk.pep : Tk.stone,
            background: pep ? Tk.pepTile : Tk.stoneTile,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title, style: TextStyle(fontSize: 14.5, fontWeight: n.read ? FontWeight.w500 : FontWeight.w700, color: Tk.ink)),
              if (n.body.isNotEmpty) Text(n.body, style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_ago(n.createdAt), style: const TextStyle(fontSize: 12, color: Tk.faint)),
            if (!n.read) ...[
              const SizedBox(height: 6),
              Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: a.main)),
            ],
          ]),
        ]),
      ),
    );
  }
}

/// Open what a notification (or a tapped push) is about.
Future<void> openLink(NavigatorState nav, Map<String, dynamic> link) async {
  final id = link['id']?.toString();
  final Widget page = switch (link['screen']) {
    'video' when id != null => VideoScreen(videoId: id),
    'week' => const WeekScreen(),
    'guardian' => const GuardianScreen(),
    'tips' => const TipsScreen(),
    _ => const NotificationsScreen(),
  };
  await nav.push(MaterialPageRoute(builder: (_) => page));
}

/// The bell on Home, with a dot when something's unread.
class BellButton extends StatelessWidget {
  const BellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return IconButton(
      tooltip: s.unread > 0 ? 'Notifications, ${s.unread} new' : 'Notifications',
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
        await s.loadUnread();
      },
      icon: Stack(clipBehavior: Clip.none, children: [
        const TIcon('bell', size: 22, color: Tk.ink),
        if (s.unread > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: context.accent.main, border: Border.all(color: Tk.bg, width: 2)),
            ),
          ),
      ]),
    );
  }
}

/// Settings › Notifications.
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = s.settings;
    final minor = s.me?.profile.age != null && s.me!.profile.age! < 18;
    const kinds = [
      ('tips', 'Tips from Pep', 'When Pep spots something in your clips'),
      ('reviews', 'Reviews ready', 'When Pep finishes watching a clip'),
      ('reminders', 'Training reminders', 'On the day of a Pep session'),
      ('events', 'Events', "Games and training you've added"),
      ('respect', 'Respect on your clips', 'When players give you respect'),
    ];
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('Notifications', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(children: [
            for (final (k, t, d) in kinds)
              SwitchListTile(
                title: Text(t),
                subtitle: Text(d),
                value: st.notifications[k] ?? true,
                onChanged: (v) => s.saveSettings({
                  'notifications': {k: v},
                }),
              ),
          ]),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Quiet hours'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: SwitchListTile(
            title: const Text('No notifications 9 pm to 7 am'),
            subtitle: Text(minor ? 'Always on for under 18s' : 'They wait in the bell until morning'),
            value: minor || (s.me?.settings.quietHours ?? true),
            onChanged: minor ? null : (v) => s.saveSettings({'quietHours': v}),
          ),
        ),
        const SizedBox(height: 12),
        const InfoNote('Messages from your guardian and about your safety always come through.'),
      ]),
    );
  }
}
