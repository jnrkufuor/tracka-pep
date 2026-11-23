import 'package:flutter/material.dart';

import '../config.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'home_screen.dart';
import 'pep_screen.dart';
import 'pitchside_screen.dart';
import 'profile_screen.dart';
import 'upload_screen.dart';
import 'video_screen.dart';

/// The tabs: Home, Pitchside, + (add a clip), Pep, Me.
///
/// Each tab keeps its scroll position when you switch away (IndexedStack keeps
/// all four alive). The + in the middle is not a tab: it opens "add a clip"
/// on top of whatever you were doing. The active tab takes the player's main
/// colour (`context.accent`), so it changes with Settings › Main colour.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int index = (int.tryParse(AppConfig.param('tab') ?? '') ?? 0).clamp(0, 3);

  @override
  void initState() {
    super.initState();
    final video = AppConfig.param('video'); // screenshot mode only
    if (video != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: video))));
    }
  }

  void go(int i) => setState(() => index = i);

  void _add() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: index, children: [
        HomeScreen(onOpenTab: go),
        const PitchsideScreen(),
        const PepScreen(),
        const ProfileScreen(),
      ]),
      bottomNavigationBar: TabBarT(index: index, onTab: go, onAdd: _add),
    );
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
      final colour = !on ? Tk.faint : (i == 2 ? Tk.pep : a.main);
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          label: _tabs[i].$2,
          excludeSemantics: true,
          child: Pressable(
            onTap: () => onTab(i),
            child: SizedBox(
              height: 52,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                TIcon(_tabs[i].$1, size: 21, color: colour, stroke: 3),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: Motion.of(context, Motion.select),
                  style: TextStyle(fontFamily: TType.text, fontSize: 10.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: colour),
                  child: Text(_tabs[i].$2),
                ),
              ]),
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
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(children: [
            tab(0),
            tab(1),
            Expanded(
              child: Center(
                child: Semantics(
                  button: true,
                  label: 'Add a clip',
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: onAdd,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(color: a.main, borderRadius: BorderRadius.circular(13)),
                      alignment: Alignment.center,
                      child: TIcon('plus', size: 20, color: a.on, stroke: 6),
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
