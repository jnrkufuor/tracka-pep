import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
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

/// One piece of Pep's drawing and the moves it makes.
///
/// Concept: the canvas draws Pep as nested SVG groups, each with a CSS
/// animation (tracka.css: pepBreath, pepBlink, pepLook, pepScan …). Flutter
/// has no CSS, so we keep the same idea: each piece is its own layer with a
/// list of moves, outermost first, and every frame we work out where each
/// layer is from the clock. Same timings, same keyframes as the design.
/// See docs/handbook/09-mobile-and-web-apps.md, "Motion and reduce motion".
class _Layer {
  const _Layer(this.svg, [this.fx = const []]);
  final String svg;
  final List<_Fx> fx;
}

/// A move: a transform (in the 48 × 48 grid) and an opacity at time [t] seconds.
typedef _Fx = (Matrix4, double) Function(double t);

const _io = Cubic(.42, 0, .58, 1); // CSS ease-in-out
const _out = Cubic(0, 0, .58, 1); // CSS ease-out
const _in = Cubic(.42, 0, 1, 1); // CSS ease-in

/// A CSS keyframe track: [k] is (progress 0–1, value). The easing applies to
/// each step between two keyframes, as in CSS.
double _kf(List<(double, double)> k, double p, Curve c) {
  for (var i = 0; i < k.length - 1; i++) {
    final (a, va) = k[i];
    final (b, vb) = k[i + 1];
    if (p <= b) return b == a ? vb : va + (vb - va) * c.transform(((p - a) / (b - a)).clamp(0, 1));
  }
  return k.last.$2;
}

double _phase(double t, double period, [double delay = 0]) => t < delay ? 0 : ((t - delay) % period) / period;

Matrix4 _about(double ox, double oy, Matrix4 m) =>
    Matrix4.translationValues(ox, oy, 0)..multiply(m)..multiply(Matrix4.translationValues(-ox, -oy, 0));

Matrix4 _scale(double sx, [double? sy]) => Matrix4.diagonal3Values(sx, sy ?? sx, 1);

// The moves, one per keyframe in tracka.css.
(Matrix4, double) _breath(double t) {
  final s = _kf([(0, .9), (.5, 1.05), (1, .9)], _phase(t, 3.4), _io);
  return (_about(24, 24, _scale(s)), 1);
}

(Matrix4, double) _blink(double t) {
  final s = _kf([(0, 1), (.46, 1), (.49, .1), (.52, 1), (1, 1)], _phase(t, 5.5), _io);
  return (_about(24, 24, _scale(1, s)), 1);
}

(Matrix4, double) _look(double t) {
  final p = _phase(t, 6.5);
  final x = _kf([(0, 0), (.16, 0), (.22, 2.5), (.38, 2.5), (.44, -2.5), (.60, -2.5), (.66, 0), (1, 0)], p, _io);
  final y = _kf([(0, 0), (.16, 0), (.22, -1.5), (.38, -1.5), (.44, 1), (.60, 1), (.66, 0), (1, 0)], p, _io);
  return (Matrix4.translationValues(x, y, 0), 1);
}

(Matrix4, double) _wakeUp(double t) {
  final p = ((t - .2) / .9).clamp(0.0, 1.0);
  final v = _kf([(0, .12), (.6, 1.08), (1, 1)], p, const Cubic(.34, 1.56, .64, 1));
  return (_about(24, 24, _scale(1, v)), 1);
}

(Matrix4, double) _scan(double t) =>
    (Matrix4.translationValues(_kf([(0, -4), (.5, 4), (1, -4)], _phase(t, 1.6), _io), 0, 0), 1);

(Matrix4, double) _ring(double t) {
  final p = _out.transform(_phase(t, 2.4));
  return (_about(24, 26, _scale(.7 + .8 * p)), .9 * (1 - p));
}

_Fx _listen([double delay = 0]) => (t) {
      final p = _out.transform(_phase(t, 2.2, delay));
      return (_about(24, 24, _scale(1 + .45 * p)), t < delay ? 0 : .7 * (1 - p));
    };

(Matrix4, double) _spin(double t) => (_about(24, 24, Matrix4.rotationZ(_phase(t, 1.1) * 2 * math.pi)), 1);

(Matrix4, double) _tick(double t) =>
    (_about(24, 24, Matrix4.rotationZ((_phase(t, 1) * 12).floor() / 12 * 2 * math.pi)), 1);

(Matrix4, double) _q(double t) {
  final v = _kf([(0, 0), (.5, 1), (1, 0)], _phase(t, 2.4), _io);
  return (Matrix4.translationValues(0, -2 * v, 0)..multiply(_about(41.5, 14.7, Matrix4.rotationZ(8 * math.pi / 180 * v))), 1);
}

_Fx _zz(double period, [double delay = 0]) => (t) {
      final v = _kf([(0, 0), (.5, 1), (1, 0)], _phase(t, period, delay), _io);
      return (Matrix4.translationValues(0, -2 * v, 0), .35 + .65 * v);
    };

(Matrix4, double) _spark(double t) {
  final v = _kf([(0, 0), (.5, 1), (1, 0)], _phase(t, 1.6), _io);
  return (_about(24, 24, _scale(.85 + .15 * v)), .25 + .75 * v);
}

(Matrix4, double) _star(double t) {
  final v = _kf([(0, 0), (.5, 1), (1, 0)], _phase(t, 3.6), _io);
  return (Matrix4.translationValues(-2 * v, -3 * v, 0)..multiply(_about(42, 7.3, Matrix4.rotationZ(25 * math.pi / 180 * v))), .85 + .15 * v);
}

_Fx _conf(double ox, double oy, double delay) => (t) {
      final p = _phase(t, 1.8, delay);
      final q = _out.transform(p);
      final o = t < delay ? 0.0 : _kf([(0, 0), (.25, 1), (1, 0)], p, _out);
      final m = Matrix4.translationValues(0, 4 - 10 * q, 0)
        ..multiply(_about(ox, oy, Matrix4.rotationZ(40 * math.pi / 180 * q)..multiply(_scale(.6 + .4 * q))));
      return (m, o);
    };

(Matrix4, double) _heart(double t) {
  final v = _kf([(0, 0), (.5, 1), (1, 0)], _phase(t, 2.2), _io);
  return (Matrix4.translationValues(0, -3 * v, 0)..multiply(_about(41, 9, _scale(1 + .12 * v))), 1);
}

(Matrix4, double) _pop(double t) =>
    (_about(41, 14.2, _scale(_kf([(0, 1), (.15, 1.25), (.3, 1), (1, 1)], _phase(t, 1.6), _io))), 1);

(Matrix4, double) _winkEye(double t) {
  final p = _phase(t, 3.4);
  final s = _kf([(0, 1), (.58, 1), (.64, .08), (.80, .08), (.86, 1), (1, 1)], p, _io);
  final o = _kf([(0, 1), (.58, 1), (.64, 0), (.80, 0), (.86, 1), (1, 1)], p, _io);
  return (_about(24, 24, _scale(1, s)), o);
}

(Matrix4, double) _winkLid(double t) =>
    (Matrix4.identity(), _kf([(0, 0), (.60, 0), (.65, 1), (.79, 1), (.84, 0), (1, 0)], _phase(t, 3.4), _io));

(Matrix4, double) _tear(double t) {
  final p = _phase(t, 2.6);
  final o = _kf([(0, 0), (.30, 0), (.45, 1), (1, 0)], p, _in);
  final y = _kf([(0, -2), (.30, -2), (1, 6)], p, _in);
  return (Matrix4.translationValues(0, y, 0), o);
}

const _bar = '<path d="M10 24 H38" stroke="C" stroke-width="3"/>';
const _ringSvg = '<circle cx="24" cy="24" r="13" stroke="C" stroke-width="6" fill="none"/>';
const _dot = '<circle cx="24" cy="24" r="6.5" fill="C"/>';

/// Pep's body (bar and ring, breathing) with an eye and its moves.
List<_Layer> _body(String eye, [List<_Fx> eyeFx = const []]) => [
      const _Layer(_bar, [_breath]),
      const _Layer(_ringSvg, [_breath]),
      _Layer(eye, [_breath, ...eyeFx]),
    ];

/// How Pep moves as a whole: 'float' (drifts up and down) or 'hop'.
enum _Whole { float, hop }

/// Each mood as layers, copied from the moods board (the same paths and the
/// same class names → moves), so the app and the design are the same Pep.
(List<_Layer>, _Whole) _mood(PepMood m) => switch (m) {
      PepMood.justHere => (
          const [
            _Layer(_bar, [_breath]),
            _Layer(_ringSvg, [_breath, _blink]),
            _Layer(_dot, [_breath, _blink, _look]),
          ],
          _Whole.float
        ),
      PepMood.watching => (
          [const _Layer('<circle cx="24" cy="26" r="15" stroke="C" stroke-width="2.5" fill="none"/>', [_ring]), ..._body('<circle cx="24" cy="24" r="6" fill="C"/>', [_scan])],
          _Whole.float
        ),
      PepMood.analysing => (
          [
            const _Layer('<circle cx="24" cy="24" r="19" stroke="C" stroke-opacity=".18" stroke-width="2.5" fill="none"/>'),
            const _Layer('<path d="M24 5 A19 19 0 0 1 43 24" stroke="C" stroke-width="2.5" stroke-linecap="round" fill="none"/>', [_spin]),
            ..._body('<circle cx="24" cy="24" r="6" fill="C"/>', [_scan]),
          ],
          _Whole.float
        ),
      PepMood.counting => (
          [
            const _Layer('<path d="M24 4.5 V8" stroke="C" stroke-width="2.6" stroke-linecap="round"/>', [_tick]),
            ..._body('<circle cx="24" cy="24" r="6" fill="C"/>', [_scan]),
          ],
          _Whole.float
        ),
      PepMood.listening => (
          [
            _Layer('<circle cx="24" cy="24" r="15" stroke="C" stroke-width="2" fill="none"/>', [_listen()]),
            _Layer('<circle cx="24" cy="24" r="15" stroke="C" stroke-width="2" fill="none"/>', [_listen(1.1)]),
            ..._body('<circle cx="21" cy="22" r="6.5" fill="C"/>'),
          ],
          _Whole.float
        ),
      PepMood.asking => (
          [
            ..._body('<circle cx="21" cy="21" r="6.5" fill="C"/>'),
            const _Layer('<path d="M38 4.5 a4 4 0 1 1 5.5 3.7 c-1.4 .6 -1.8 1.4 -1.8 2.8 M41.7 14.6 v.1" stroke="C" stroke-width="2.6" stroke-linecap="round" fill="none"/>', [_q]),
          ],
          _Whole.float
        ),
      PepMood.thinking => (
          [
            _Layer('<circle cx="41" cy="10" r="2.2" fill="C"/>', [_zz(1.4)]),
            _Layer('<circle cx="45.5" cy="4.5" r="1.6" fill="C"/>', [_zz(1.4, .25)]),
            ..._body('<circle cx="27" cy="20" r="6" fill="C"/>'),
          ],
          _Whole.float
        ),
      PepMood.reading => (
          [const _Layer('<path d="M15 6.5 H33" stroke="C" stroke-width="3" stroke-linecap="round"/>'), ..._body('<circle cx="24" cy="25" r="6" fill="C"/>', [_scan])],
          _Whole.float
        ),
      PepMood.focused => (_body('<rect x="17" y="22" width="14" height="5" rx="2.5" fill="C"/>'), _Whole.float),
      PepMood.excited => (
          [
            const _Layer('<path d="M24 2 V6 M11 6 L13.5 9.5 M37 6 L34.5 9.5" stroke="C" stroke-width="2.6" stroke-linecap="round"/>', [_spark]),
            ..._body('<circle cx="24" cy="23" r="7.5" fill="C"/>'),
          ],
          _Whole.hop
        ),
      PepMood.happy => (
          [
            const _Layer('<path d="M7 9 l2 2 M41 9 l-2 2" stroke="C" stroke-width="2.4" stroke-linecap="round"/>', [_spark]),
            ..._body('<path d="M18 26 Q24 17 30 26" stroke="C" stroke-width="5" stroke-linecap="round" fill="none"/>'),
          ],
          _Whole.hop
        ),
      PepMood.proud => (
          [
            ..._body('<path d="M18 24 Q24 17 30 24" stroke="C" stroke-width="5" stroke-linecap="round" fill="none"/>'),
            const _Layer('<path d="M42 3 l1.3 3 3 1.3 -3 1.3 -1.3 3 -1.3-3 -3-1.3 3-1.3z" fill="C"/>', [_star]),
          ],
          _Whole.float
        ),
      PepMood.celebrating => (
          [
            _Layer('<rect x="4" y="5" width="4" height="4" rx="1" fill="C"/>', [_conf(6, 7, 0)]),
            _Layer('<path d="M40 4 l3 3" stroke="C" stroke-width="2.6" stroke-linecap="round"/>', [_conf(41.5, 5.5, .2)]),
            _Layer('<rect x="42" y="16" width="3.5" height="3.5" rx="1" fill="C"/>', [_conf(43.75, 17.75, .4)]),
            _Layer('<path d="M8 17 l-3 2" stroke="C" stroke-width="2.6" stroke-linecap="round"/>', [_conf(6.5, 18, .6)]),
            _Layer('<path d="M24 1 v4" stroke="C" stroke-width="2.6" stroke-linecap="round"/>', [_conf(24, 3, .3)]),
            ..._body('<path d="M18 26 Q24 17 30 26" stroke="C" stroke-width="5" stroke-linecap="round" fill="none"/>'),
          ],
          _Whole.float
        ),
      PepMood.respect => (
          [
            ..._body(_dot),
            const _Layer('<path d="M41 13 c-5 -3.5 -6 -6.5 -4 -8.2 c1.4 -1.1 3.2 -.6 4 .8 c.8 -1.4 2.6 -1.9 4 -.8 c2 1.7 1 4.7 -4 8.2z" fill="C"/>', [_heart]),
          ],
          _Whole.float
        ),
      PepMood.surprised => (
          [..._body('<circle cx="24" cy="24" r="4" fill="C"/>'), const _Layer('<path d="M41 3 V10 M41 14 V14.2" stroke="C" stroke-width="3" stroke-linecap="round"/>', [_pop])],
          _Whole.float
        ),
      PepMood.cheeky => (
          [
            const _Layer(_bar, [_breath]),
            const _Layer(_ringSvg, [_breath]),
            const _Layer(_dot, [_breath, _winkEye]),
            const _Layer('<path d="M17 20.5 Q24 12.5 31 20.5" stroke="C" stroke-width="4.5" stroke-linecap="round" fill="none"/>', [_breath, _winkLid]),
          ],
          _Whole.float
        ),
      PepMood.concerned => (
          [..._body('<circle cx="22" cy="27" r="6" fill="C"/>'), const _Layer('<path d="M41 6 q-3 4.5 0 7 q3 -2.5 0 -7z" fill="C"/>', [_tear])],
          _Whole.float
        ),
      PepMood.sorry => (
          [
            ..._body('<path d="M18 27 Q24 33 30 27" stroke="C" stroke-width="5" stroke-linecap="round" fill="none"/>'),
            const _Layer('<path d="M33 39 q-2.5 3.5 0 5.5 q2.5 -2 0 -5.5z" fill="C"/>', [_tear]),
          ],
          _Whole.float
        ),
      PepMood.calm => (_body('<path d="M17.5 25 A6.5 6.5 0 0 0 30.5 25 Z" fill="C"/>'), _Whole.float),
      PepMood.asleep => (
          [
            const _Layer('<path d="M10 26 H38" stroke="C" stroke-width="3" opacity=".6"/>'
                '<path d="M13 26 A11 6 0 0 0 35 26" stroke="C" stroke-width="5" stroke-linecap="round" fill="none"/>'),
            _Layer('<path d="M36 6 H43 L36 13 H43" stroke="C" stroke-width="2.6" stroke-linecap="square" stroke-linejoin="miter" fill="none"/>', [_zz(2.8)]),
          ],
          _Whole.float
        ),
    };

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

const _view = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-2 -2 52 52" fill="none">';

/// The SVG for a mood in a colour, standing still (for tests and the web Lab).
String pepSvg(PepMood mood, {Color color = Tk.pep}) =>
    '$_view${_mood(mood).$1.map((l) => l.svg).join().replaceAll('"C"', '"${_hex(color)}"')}</svg>';

/// Pep's face, alive: he floats (or hops when excited or happy), breathes,
/// and each mood has its own move — he blinks and glances around when he's
/// just here, his eye scans while he watches, dots pulse while he thinks, a
/// Z drifts while he sleeps. Timings are the design's (tracka.css).
///
/// Everything stops when the phone or Tracka asks for less motion; Pep then
/// stands still at full size, the same picture as [pepSvg].
class PepFace extends StatefulWidget {
  const PepFace(this.mood, {super.key, this.size = 40, this.color = Tk.pep, this.breathe = true, this.wake = false});

  /// Open his eye when he appears (canvas "Bottom tabs": the Pep tab wakes
  /// up when you open it; pepWake, 0.9 s with a little overshoot).
  final bool wake;

  final PepMood mood;
  final double size;
  final Color color;

  /// False draws Pep still (the moods sheet in tests, tiny icons).
  final bool breathe;

  /// Off in tests (test/flutter_test_config.dart): Pep never stops moving,
  /// and tests that wait for every animation to finish would wait forever.
  static bool breathing = true;

  @override
  State<PepFace> createState() => _PepFaceState();
}

class _PepFaceState extends State<PepFace> with SingleTickerProviderStateMixin {
  final _t = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((d) => _t.value = d.inMicroseconds / 1e6);

  bool get _alive => widget.breathe && PepFace.breathing && !Motion.reduced(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PepFace old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (_alive && !_ticker.isActive) _ticker.start();
    if (!_alive && _ticker.isActive) {
      _ticker.stop();
      _t.value = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    var (layers, whole) = _mood(widget.mood);
    if (widget.wake && widget.mood == PepMood.justHere) {
      // The ring and the eye open after the breath, before blinking starts.
      layers = [
        for (final (i, l) in layers.indexed) i == 0 ? l : _Layer(l.svg, [l.fx.first, _wakeUp, ...l.fx.skip(1)]),
      ];
    }
    final hex = _hex(widget.color);
    final k = size / 52; // grid units → pixels (the view box is 52 wide)
    final pics = [
      for (final l in layers)
        SvgPicture.string('$_view${l.svg.replaceAll('"C"', '"$hex"')}</svg>', width: size, height: size),
    ];
    if (!_alive) {
      return Semantics(label: 'Pep', image: true, child: SizedBox.square(dimension: size, child: Stack(children: pics)));
    }
    return Semantics(
      label: 'Pep',
      image: true,
      // RepaintBoundary: Pep redraws 60 times a second; this keeps that redraw
      // to his own square instead of the whole screen around him.
      child: RepaintBoundary(child: ValueListenableBuilder<double>(
        valueListenable: _t,
        builder: (_, t, __) {
          final dy = whole == _Whole.hop
              ? -.14 * size * _kf([(0, 0), (.3, 1), (.5, 0), (1, 0)], _phase(t, 1.6), const Cubic(.34, 1.56, .64, 1))
              : -.08 * size * _kf([(0, 0), (.5, 1), (1, 0)], _phase(t, 4.6), _io);
          return Transform.translate(
            offset: Offset(0, dy),
            child: SizedBox.square(
              dimension: size,
              child: Stack(children: [
                for (var i = 0; i < layers.length; i++) _place(layers[i], pics[i], t, k),
              ]),
            ),
          );
        },
      )),
    );
  }

  /// One layer at time [t]: its moves composed outermost first, moved from the
  /// grid into pixels.
  Widget _place(_Layer l, Widget pic, double t, double k) {
    if (l.fx.isEmpty) return pic;
    var m = Matrix4.identity();
    var o = 1.0;
    for (final f in l.fx) {
      final (fm, fo) = f(t);
      m.multiply(fm);
      o *= fo;
    }
    final px = Matrix4.diagonal3Values(k, k, 1)..multiply(Matrix4.translationValues(2, 2, 0));
    final back = Matrix4.translationValues(-2, -2, 0)..multiply(Matrix4.diagonal3Values(1 / k, 1 / k, 1));
    final mm = px..multiply(m)..multiply(back);
    final moved = Transform(transform: mm, child: pic);
    // Only fade when the move asks for it: a see-through layer costs the phone
    // an extra drawing pass every frame.
    return o >= .999 ? moved : Opacity(opacity: o.clamp(0.0, 1.0), child: moved);
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
