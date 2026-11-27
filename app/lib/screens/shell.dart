import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import '../widgets/pep.dart';
import '../widgets/tour.dart';
import 'home_screen.dart';
import 'pep_screen.dart';
import 'pitchside_screen.dart';
import 'profile_screen.dart';
import 'training_screens.dart' show WeekScreen, showEventSheet;
import 'upload_screen.dart';
import 'video_screen.dart';

/// The tabs: Home, Pitchside, + (add a clip), Pep, Me.
///
/// Each tab keeps its scroll position when you switch away (IndexedStack keeps
/// all four alive). The + in the middle is not a tab: it opens "add a clip"
/// on top of whatever you were doing. The active tab takes the player's main
/// colour (`context.accent`), so it changes with Settings › Main colour.
class Shell extends StatefulWidget {
  const Shell({super.key, this.initialTab});

  /// Which tab to open on (tests and screen pictures); normally Home.
  final int? initialTab;

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> with SingleTickerProviderStateMixin {
  late int index = (widget.initialTab ?? int.tryParse(AppConfig.param('tab') ?? '') ?? 0).clamp(0, 3);

  @override
  void initState() {
    super.initState();
    final video = AppConfig.param('video'); // screenshot mode only
    if (video != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: video))));
    }
  }

  /// Each tab fades in when you open it (canvas: every screen's content
  /// arrives with a 0.35 s fade).
  late final AnimationController _fade = AnimationController(vsync: this, duration: Motion.enter, value: 1);

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void go(int i) {
    if (i == index) return;
    setState(() => index = i);
    if (Motion.reduced(context)) return;
    _fade.forward(from: 0);
  }

  /// The + button (canvas: The + button): what do you want to do?
  void _add() => showPlusSheet(context);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scaffold = Scaffold(
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
        child: IndexedStack(index: index, children: [
          // TickerMode: hidden tabs stay alive (they keep their scroll) but stop
          // animating, so Pep on a tab you can't see doesn't use the phone's time.
          for (final (i, tab) in [HomeScreen(onOpenTab: go), const PitchsideScreen(), const PepScreen(), const ProfileScreen()].indexed)
            TickerMode(enabled: i == index, child: tab),
        ]),
      ),
      bottomNavigationBar: TabBarT(index: index, onTab: go, onAdd: _add),
    );
    if (!s.tourPending) return scaffold;
    if (index != 0) WidgetsBinding.instance.addPostFrameCallback((_) => go(0));
    return Stack(children: [scaffold, Positioned.fill(child: TourOverlay(onDone: s.endTour))]);
  }
}

/// The bottom bar from the canvas ("Bottom tabs" board): four labelled tabs and
/// a main-colour + button in the middle.
class TabBarT extends StatelessWidget {
  const TabBarT({super.key, required this.index, required this.onTab, required this.onAdd});

  final int index;
  final ValueChanged<int> onTab;
  final VoidCallback onAdd;

  static const _tabs = [('home', 'Home'), ('clip', 'Pitchside'), ('pep', 'Pep'), ('you', 'Me')];

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    Widget tab(int i) {
      final on = index == i;
      // Pep's tab is purple when open (Pep's colour); the others use your main colour.
      // Canvas "Bottom tabs": white when not open; open = your main colour (Pep: purple).
      final colour = !on ? Colors.white : (i == 2 ? Tk.pep : a.main);
      return Expanded(
        child: KeyedSubtree(
          key: i == 2 ? TourKeys.pepTab : null,
          child: Semantics(
          selected: on,
          button: true,
          label: _tabs[i].$2,
          excludeSemantics: true,
          child: Pressable(
            onTap: () => onTab(i),
            child: ConstrainedBox(
              // At least 52 tall for the thumb; taller when the text is big, so labels never get cut.
              constraints: const BoxConstraints(minHeight: 52),
              child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                // Pep's own tab (canvas "Bottom tabs"): asleep with a drifting Z
                // while you're elsewhere; he wakes up when you open his tab.
                if (i == 2)
                  PepFace(on ? PepMood.justHere : PepMood.asleep, key: ValueKey(on), size: 22, color: colour, wake: on)
                else
                  TIcon(_tabs[i].$1, size: 20, color: colour, stroke: 3),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: Motion.of(context, Motion.select),
                  style: TextStyle(fontFamily: TType.text, fontSize: 10, letterSpacing: .2, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: colour),
                  child: Text(_tabs[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          ),
        ),
        ),
      );
    }

    return Container(
      color: Tk.card2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(children: [
            tab(0),
            tab(1),
            Expanded(
              // heightFactor 1: as tall as the button, not the whole screen. A plain
              // Center grows to fill all the height the bottom bar is offered.
              child: Center(
                heightFactor: 1,
                child: Semantics(
                  button: true,
                  label: 'Add a clip',
                  excludeSemantics: true,
                  child: Pressable(
                    key: TourKeys.plus,
                    onTap: onAdd,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: a.main, borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: TIcon('plus', size: 20, color: a.on, stroke: 7),
                    ),
                  ),
                ),
              ),
            ),
            tab(2),
            tab(3),
          ]),
        ),
      ),
    );
  }
}


/// What do you want to do? Film a clip, this week's challenge, an event, or log a session.
Future<void> showPlusSheet(BuildContext context) {
  final s = context.read<AppState>();
  Widget row(BuildContext ctx, String icon, String title, String sub, Future<void> Function() go) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: IconTile(icon: icon, color: ctx.accent.main, background: ctx.accent.tile, size: 40),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub),
        onTap: () async {
          Navigator.of(ctx).pop();
          await go();
        },
      );
  return showEditSheet<void>(
    context,
    title: 'What do you want to do?',
    child: Builder(
      builder: (ctx) => Column(children: [
        row(ctx, 'camera', 'Film a clip', 'Pep watches it and sends you tips',
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen()))),
        row(ctx, 'trophy', "Try this week's challenge", 'Film your go. It stays private unless you post it', () async {
          try {
            final c = await s.api.challenges();
            if (context.mounted) {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengeRecordScreen(challenge: c.thisWeek)));
            }
          } catch (_) {}
        }),
        row(ctx, 'calendar', 'Create an event', 'A match, a casual game or training', () => showEventSheet(context)),
        row(ctx, 'check', 'Log a session', 'Something you did without filming', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WeekScreen()))),
      ]),
    ),
  );
}
