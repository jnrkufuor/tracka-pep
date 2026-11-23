import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

  static const _tabs = [(_Icon.home, 'Home'), (_Icon.pitchside, 'Pitchside'), (_Icon.pep, 'Pep'), (_Icon.me, 'Me')];

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
                SvgPicture.string(_tabs[i].$1.svg, width: 21, height: 21, colorFilter: ColorFilter.mode(colour, BlendMode.srcIn)),
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
                      child: Icon(Icons.add_rounded, size: 26, color: a.on),
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

/// Tab icons from the chosen icon pack (square line ends, 48-unit grid).
/// TODO(design-system): move these into scripts/build_brand.py with the rest
/// of the pack so web and app share one source.
enum _Icon {
  home('<path d="M9 22 L24 9 L39 22 V39 H9 Z M20 39 V29 H28 V39" stroke-width="3" stroke-linecap="square" fill="none" stroke="#000"/>'),
  pitchside('<rect x="7" y="11" width="34" height="26" rx="4" stroke="#000" stroke-width="3" fill="none"/><path d="M21 18 L30 24 L21 30 Z" fill="#000"/>'),
  pep('<path d="M10 24 H38" stroke="#000" stroke-width="3"/><circle cx="24" cy="24" r="13" stroke="#000" stroke-width="6" fill="none"/><circle cx="24" cy="24" r="6.5" fill="#000"/>'),
  me('<circle cx="24" cy="16" r="7" stroke="#000" stroke-width="3" fill="none"/><path d="M10 40 C10 31 16 27 24 27 C32 27 38 31 38 40" stroke="#000" stroke-width="3" fill="none" stroke-linecap="square"/>');

  const _Icon(this.body);
  final String body;
  String get svg => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">$body</svg>';
}
