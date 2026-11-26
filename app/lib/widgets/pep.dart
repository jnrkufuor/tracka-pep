import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/motion.dart';
import '../theme/tokens.dart';

/// Pep's 20 moods (canvas: Pep › "Pep's 20 moods").
///
/// Every face is the same Pep, the bar and the ring, with a different eye
/// or mouth and a small extra mark (a "?", a heart, a "Z"). So Pep stays
/// recognisable at 20 px in a tab bar and still shows how he feels at 96 px.
///
/// Pick the mood from the *moment*, not from the screen:
///   justHere    Home, quiet moments          watching    a clip playing or uploading
///   analysing   working on your clip         counting    timing a test, counting a challenge
///   listening   asking something personal    asking      "Want a plan? Which day works?"
///   thinking    before giving his read       reading     planning your week
///   focused     during a session or test     excited     a goal set, a new challenge
///   happy       session done, streak kept    proud       a new best
///   celebrating big moments                  respect     someone gave you respect
///   surprised   something unexpected         cheeky      a tip with a wink
///   concerned   pain logged, missed sessions sorry       streak lost, a tough result
///   calm        rest day, recovery           asleep      late at night
enum PepMood {
  justHere,
  watching,
  analysing,
  counting,
  listening,
  asking,
  thinking,
  reading,
  focused,
  excited,
  happy,
  proud,
  celebrating,
  respect,
  surprised,
  cheeky,
  concerned,
  sorry,
  calm,
  asleep,
}

/// The drawing for each mood, on a 48 × 48 grid, in Pep's colour `C`.
/// Copied from the moods board so the app and the design are the same picture.
String _svg(PepMood m) {
  const bar = '<path d="M10 24 H38" stroke="C" stroke-width="3"/>';
  const ring = '<circle cx="24" cy="24" r="13" stroke="C" stroke-width="6" fill="none"/>';
  String face(String inner) => '$bar$ring$inner';
  final body = switch (m) {
    PepMood.justHere => face('<circle cx="24" cy="24" r="6.5" fill="C"/>'),
    PepMood.watching => '<circle cx="24" cy="26" r="15" stroke="C" stroke-width="2.5" stroke-opacity=".5" fill="none"/>'
        '${face('<circle cx="24" cy="24" r="6" fill="C"/>')}',
    PepMood.analysing => '<circle cx="24" cy="24" r="19" stroke="C" stroke-opacity=".18" stroke-width="2.5" fill="none"/>'
        '<path d="M24 5 A19 19 0 0 1 43 24" stroke="C" stroke-width="2.5" stroke-linecap="round" fill="none"/>'
        '${face('<circle cx="24" cy="24" r="6" fill="C"/>')}',
    PepMood.counting => '<path d="M24 4.5 V8" stroke="C" stroke-width="2.6" stroke-linecap="round"/>'
        '${face('<circle cx="24" cy="24" r="6" fill="C"/>')}',
    PepMood.listening => '<circle cx="24" cy="24" r="18" stroke="C" stroke-width="2" stroke-opacity=".35" fill="none"/>'
        '${face('<circle cx="21" cy="22" r="6.5" fill="C"/>')}',
    PepMood.asking => '${face('<circle cx="21" cy="21" r="6.5" fill="C"/>')}'
        '<path d="M38 4.5 a4 4 0 1 1 5.5 3.7 c-1.4 .6 -1.8 1.4 -1.8 2.8 M41.7 14.6 v.1" stroke="C" stroke-width="2.6" stroke-linecap="round" fill="none"/>',
    PepMood.thinking => '<circle cx="41" cy="10" r="2.2" fill="C"/><circle cx="45.5" cy="4.5" r="1.6" fill="C"/>'
        '${face('<circle cx="27" cy="20" r="6" fill="C"/>')}',
    PepMood.reading => '<path d="M15 6.5 H33" stroke="C" stroke-width="3" stroke-linecap="round"/>'
        '${face('<circle cx="24" cy="25" r="6" fill="C"/>')}',
    PepMood.focused => face('<rect x="17" y="22" width="14" height="5" rx="2.5" fill="C"/>'),
    PepMood.excited => '<path d="M24 2 V6 M11 6 L13.5 9.5 M37 6 L34.5 9.5" stroke="C" stroke-width="2.6" stroke-linecap="round"/>'
        '${face('<circle cx="24" cy="23" r="7.5" fill="C"/>')}',
    PepMood.happy => '<path d="M7 9 l2 2 M41 9 l-2 2" stroke="C" stroke-width="2.4" stroke-linecap="round"/>'
        '${face('<path d="M18 26 Q24 17 30 26" stroke="C" stroke-width="5" stroke-linecap="round" fill="none"/>')}',
    PepMood.proud => '${face('<path d="M18 24 Q24 17 30 24" stroke="C" stroke-width="5" stroke-linecap="round" fill="none"/>')}'
        '<path d="M42 3 l1.3 3 3 1.3 -3 1.3 -1.3 3 -1.3-3 -3-1.3 3-1.3z" fill="C"/>',
    PepMood.celebrating => '<rect x="4" y="5" width="4" height="4" rx="1" fill="C"/><path d="M40 4 l3 3" stroke="C" stroke-width="2.6" stroke-linecap="round"/>'
        '<rect x="42" y="16" width="3.5" height="3.5" rx="1" fill="C"/><path d="M8 17 l-3 2" stroke="C" stroke-width="2.6" stroke-linecap="round"/>'
        '<path d="M24 1 v4" stroke="C" stroke-width="2.6" stroke-linecap="round"/>'
        '${face('<path d="M18 26 Q24 17 30 26" stroke="C" stroke-width="5" stroke-linecap="round" fill="none"/>')}',
    PepMood.respect => '${face('<circle cx="24" cy="24" r="6.5" fill="C"/>')}'
        '<path d="M41 13 c-5 -3.5 -6 -6.5 -4 -8.2 c1.4 -1.1 3.2 -.6 4 .8 c.8 -1.4 2.6 -1.9 4 -.8 c2 1.7 1 4.7 -4 8.2z" fill="C"/>',
    PepMood.surprised => '${face('<circle cx="24" cy="24" r="4" fill="C"/>')}'
        '<path d="M41 3 V10 M41 14 V14.2" stroke="C" stroke-width="3" stroke-linecap="round"/>',
    PepMood.cheeky => face('<circle cx="24" cy="24" r="6.5" fill="C"/>'
        '<path d="M17 20.5 Q24 12.5 31 20.5" stroke="C" stroke-width="4.5" stroke-linecap="round" fill="none"/>'),
    PepMood.concerned => '${face('<circle cx="22" cy="27" r="6" fill="C"/>')}'
        '<path d="M41 6 q-3 4.5 0 7 q3 -2.5 0 -7z" fill="C"/>',
    PepMood.sorry => '${face('<path d="M18 27 Q24 33 30 27" stroke="C" stroke-width="5" stroke-linecap="round" fill="none"/>')}'
        '<path d="M33 39 q-2.5 3.5 0 5.5 q2.5 -2 0 -5.5z" fill="C"/>',
    PepMood.calm => face('<path d="M17.5 25 A6.5 6.5 0 0 0 30.5 25 Z" fill="C"/>'),
    PepMood.asleep => '<path d="M10 26 H38" stroke="C" stroke-width="3" opacity=".6"/>'
        '<path d="M13 26 A11 6 0 0 0 35 26" stroke="C" stroke-width="5" stroke-linecap="round" fill="none"/>'
        '<path d="M36 6 H43 L36 13 H43" stroke="C" stroke-width="2.6" stroke-linecap="square" stroke-linejoin="miter" fill="none"/>',
  };
  return body;
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// The SVG for a mood in a colour (exposed for tests and for the web Lab).
String pepSvg(PepMood mood, {Color color = Tk.pep}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 -2 52 52" fill="none">'
    '${_svg(mood).replaceAll('"C"', '"${_hex(color)}"')}</svg>';

/// Pep's face. He breathes gently (scale 1 → 1.04 over 3 s) unless the phone
/// or Tracka asks for less motion, so he feels alive without moving much.
class PepFace extends StatefulWidget {
  const PepFace(this.mood, {super.key, this.size = 40, this.color = Tk.pep, this.breathe = true});

  final PepMood mood;
  final double size;
  final Color color;
  final bool breathe;

  /// Off in tests (test/flutter_test_config.dart): a breath never ends, and
  /// tests that wait for every animation to finish would wait forever.
  static bool breathing = true;

  @override
  State<PepFace> createState() => _PepFaceState();
}

class _PepFaceState extends State<PepFace> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.breathe && PepFace.breathing && !Motion.reduced(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pic = SvgPicture.string(
      pepSvg(widget.mood, color: widget.color),
      width: widget.size,
      height: widget.size,
      semanticsLabel: 'Pep',
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.scale(scale: 1 + 0.04 * Curves.easeInOut.transform(_c.value), child: child),
      child: pic,
    );
  }
}

/// Pep in his purple tile (the same shape as [IconTile]), for cards and lists.
class PepTile extends StatelessWidget {
  const PepTile(this.mood, {super.key, this.size = 40});

  final PepMood mood;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Tk.pepTile, borderRadius: BorderRadius.circular(size * 0.3)),
        child: PepFace(mood, size: size * 0.62),
      );
}

/// Pep's mood for the time of day, when nothing else is going on.
PepMood pepIdleMood([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  return h >= 22 || h < 6 ? PepMood.asleep : PepMood.justHere;
}

/// Pep saying something, with his face beside it (the canvas's "pepnote").
/// Used where Pep explains a step: why your age matters, how he'll coach you.
class PepNote extends StatelessWidget {
  const PepNote({super.key, required this.mood, required this.child, this.title});

  final PepMood mood;
  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Tk.pepTile, borderRadius: BorderRadius.circular(Tk.rCard)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PepFace(mood, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) ...[
                Text(title!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Tk.pep)),
                const SizedBox(height: 4),
              ],
              DefaultTextStyle.merge(style: const TextStyle(fontSize: 14, height: 1.45, color: Tk.ink), child: child),
            ]),
          ),
        ]),
      );
}
