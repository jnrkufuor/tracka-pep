import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';
import '../widgets/common.dart';

/// The splash (canvas: Onboarding › Splash). Nothing moves: the mark fades in,
/// then "Tracka" fades in just after (about 0.7 s), while the app checks for a
/// saved login. Always Volt, whatever main colour the player picked: the logo
/// is the brand, not a setting. With reduce motion on, it simply appears.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mark over the first ~70% of the time, the word from ~30% to the end.
    final mark = CurvedAnimation(parent: _c, curve: const Interval(0, 0.7, curve: Curves.easeOut));
    final word = CurvedAnimation(parent: _c, curve: const Interval(0.3, 1, curve: Curves.easeOut));
    return Scaffold(
      backgroundColor: Tk.bg,
      body: Semantics(
        label: 'Tracka',
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FadeTransition(opacity: mark, child: const TrackaMark(size: 132, color: TColors.neon)),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: word,
              child: const Text('Tracka',
                  style: TextStyle(fontFamily: TType.display, fontSize: 46, fontWeight: FontWeight.w800, letterSpacing: -1.6, color: Tk.ink)),
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }
}
