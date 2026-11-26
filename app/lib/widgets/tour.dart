import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';
import 'ds.dart';

/// Pep's tour ("Show me around"), canvas: Pep's tour 1 to 4.
///
/// Four short notes over the real Home screen, each pointing at the thing it
/// explains: the screen dims except a cut-out around that thing (a
/// "coach mark"). The things are found with GlobalKeys ([TourKeys]) placed on
/// the real widgets, so the tour never drifts out of step with the layout.
/// If a target isn't on screen (the player hid that card), the note shows
/// in the middle with no cut-out. Fades only, nothing slides.
class TourKeys {
  static final road = GlobalKey(debugLabel: 'tour-road');
  static final progress = GlobalKey(debugLabel: 'tour-progress');
  static final plus = GlobalKey(debugLabel: 'tour-plus');
  static final pepTab = GlobalKey(debugLabel: 'tour-pep');
}

class TourStep {
  const TourStep(this.target, this.title, this.body);

  final GlobalKey target;
  final String title;
  final String body;
}

List<TourStep> get tourSteps => [
      TourStep(TourKeys.road, 'Your goal and your week',
          'I built your first week around your football. Ticks fill in as you go, and your goal stays up here.'),
      TourStep(TourKeys.progress, 'Start here',
          'Do your baseline tests first, so I know where you are now. Then I can show you how you grow.'),
      TourStep(TourKeys.plus, 'Film anything with +', "Any game or drill, even 20 seconds. I'll watch it and send you tips."),
      TourStep(TourKeys.pepTab, 'Find me here',
          "Your plan, tests and tips live in the Pep tab. Tap me any time you're not sure what to do."),
    ];

class TourOverlay extends StatefulWidget {
  const TourOverlay({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  int step = 0;
  Rect? hole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final me = context.findRenderObject() as RenderBox?;
    final box = tourSteps[step].target.currentContext?.findRenderObject() as RenderBox?;
    Rect? r;
    if (me != null && box != null && box.attached && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero, ancestor: me);
      r = (topLeft & box.size).inflate(6);
      if (r.top < 0 || r.bottom > me.size.height) r = null; // scrolled away
    }
    setState(() => hole = r);
  }

  void _next() {
    if (step == tourSteps.length - 1) {
      widget.onDone();
      return;
    }
    setState(() {
      step++;
      hole = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    final s = tourSteps[step];
    final last = step == tourSteps.length - 1;
    return LayoutBuilder(builder: (context, box) {
      final h = hole;
      final below = h == null || h.center.dy < box.maxHeight / 2;
      final card = Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 440),
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Tk.card, borderRadius: BorderRadius.circular(Tk.rCard), border: Border.all(color: Tk.pep.withValues(alpha: 0.5))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const TIcon('pep', size: 20, color: Tk.pep),
            const SizedBox(width: 8),
            Flexible(
              child: Text("Pep's tour · ${step + 1} of ${tourSteps.length}",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Tk.pep)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(s.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Tk.ink)),
          const SizedBox(height: 4),
          Text(s.body, style: const TextStyle(fontSize: 14, height: 1.45, color: Tk.inkSoft)),
          const SizedBox(height: 12),
          Row(children: [
            if (!last)
              Flexible(
                child: TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: widget.onDone, child: const Text('Skip tour')),
              ),
            const Spacer(),
            Flexible(
              child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: _next, child: Text(last ? 'Got it' : 'Next')),
            ),
          ]),
        ]),
      );
      return Material(
        type: MaterialType.transparency,
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {}, // the screen underneath isn't tappable during the tour
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.select),
                child: CustomPaint(key: ValueKey('$step-$h'), painter: _Dim(h), size: Size.infinite),
              ),
            ),
          ),
          if (h == null)
            Center(child: card)
          else if (below)
            Positioned(left: 0, right: 0, top: (h.bottom + 12).clamp(0, box.maxHeight - 240), child: card)
          else
            Positioned(left: 0, right: 0, bottom: (box.maxHeight - h.top + 12).clamp(0, box.maxHeight - 240), child: card),
        ]),
      );
    });
  }
}

class _Dim extends CustomPainter {
  _Dim(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    final path = hole == null
        ? all
        : Path.combine(PathOperation.difference, all, Path()..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(18))));
    canvas.drawPath(path, Paint()..color = const Color(0xCC000000));
    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!, const Radius.circular(18)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Tk.pep,
      );
    }
  }

  @override
  bool shouldRepaint(_Dim old) => old.hole != hole;
}
