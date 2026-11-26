import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';
import 'ds.dart';

/// Tap where you play on a pitch (canvas: Onboarding › Player profile, and
/// Edit profile). The first tap is your MAIN position; more taps add
/// positions you can also play (up to 4 in all). Tap an extra one to make it
/// your main; tap your main again to clear it.
///
/// Positions use the API's codes (GK, CB, CDM, CM, CAM...), so they go straight
/// into PATCH /v1/me as `positions`, main first.
class PitchPicker extends StatelessWidget {
  const PitchPicker({super.key, required this.positions, required this.onChanged, this.max = 4});

  /// Main first, then the others.
  final List<String> positions;
  final ValueChanged<List<String>> onChanged;
  final int max;

  /// (code, label, x 0..1, y 0..1): attack at the top, goalkeeper at the bottom.
  static const spots = [
    ('ST', 'ST', 0.50, 0.11),
    ('LW', 'LW', 0.15, 0.22),
    ('RW', 'RW', 0.85, 0.22),
    ('CAM', 'AM', 0.50, 0.32),
    ('LM', 'LM', 0.15, 0.45),
    ('CM', 'CM', 0.50, 0.46),
    ('RM', 'RM', 0.85, 0.45),
    ('CDM', 'DM', 0.50, 0.60),
    ('LB', 'LB', 0.15, 0.70),
    ('RB', 'RB', 0.85, 0.70),
    ('CB', 'CB', 0.50, 0.77),
    ('GK', 'GK', 0.50, 0.91),
  ];

  static String nameOf(String code) => switch (code) {
        'GK' => 'Goalkeeper',
        'CB' => 'Centre-back',
        'LB' => 'Left-back',
        'RB' => 'Right-back',
        'CDM' => 'Defensive midfielder',
        'CM' => 'Central midfielder',
        'CAM' => 'Attacking midfielder',
        'LM' => 'Left midfielder',
        'RM' => 'Right midfielder',
        'LW' => 'Left winger',
        'RW' => 'Right winger',
        'CF' => 'Centre-forward',
        'ST' => 'Striker',
        _ => code,
      };

  void _tap(String code) {
    final list = [...positions];
    if (list.isNotEmpty && list.first == code) {
      list.removeAt(0); // clear the main; the next one (if any) becomes main
    } else if (list.contains(code)) {
      list
        ..remove(code)
        ..insert(0, code); // make it the main
    } else if (list.length < max) {
      list.add(code);
    } else {
      return;
    }
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(
        aspectRatio: 0.78,
        child: LayoutBuilder(builder: (context, box) {
          const dot = 46.0;
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
            for (final s in spots)
              Positioned(
                left: s.$3 * box.maxWidth - dot / 2,
                top: s.$4 * box.maxHeight - dot / 2,
                child: Semantics(
                  button: true,
                  selected: positions.contains(s.$1),
                  label: '${nameOf(s.$1)}${positions.isNotEmpty && positions.first == s.$1 ? ', main position' : positions.contains(s.$1) ? ', also play' : ''}',
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: () => _tap(s.$1),
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.select),
                      width: dot,
                      height: dot,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: positions.isNotEmpty && positions.first == s.$1
                            ? a.main
                            : positions.contains(s.$1)
                                ? a.tile
                                : const Color(0xFF101010),
                        border: Border.all(
                          color: positions.contains(s.$1) ? a.main : const Color(0xFF3A3A3A),
                          width: 1.5,
                        ),
                      ),
                      child: Text(s.$2,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: positions.isNotEmpty && positions.first == s.$1
                                ? a.on
                                : positions.contains(s.$1)
                                    ? a.main
                                    : Tk.inkSoft,
                          )),
                    ),
                  ),
                ),
              ),
          ]);
        }),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (positions.isEmpty)
          const Text('Tap your main position', style: TextStyle(fontSize: 13.5, color: Tk.muted))
        else ...[
          _Tag('Main · ${nameOf(positions.first)}', main: true),
          for (final p in positions.skip(1)) _Tag('Also · ${nameOf(p)}'),
        ],
      ]),
    ]);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.main = false});

  final String text;
  final bool main;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: main ? a.tile : Tk.field, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: main ? a.main : Tk.inkSoft)),
    );
  }
}

/// Pitch lines: outline, halfway line, centre circle, both boxes. Quiet grey on black.
class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
    canvas.drawRRect(r, Paint()..color = const Color(0xFF0B140C));
    final line = Paint()
      ..color = const Color(0xFF26382A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final w = size.width, h = size.height;
    canvas.drawRRect(r.deflate(8), line);
    canvas.drawLine(Offset(8, h / 2), Offset(w - 8, h / 2), line);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.13, line);
    canvas.drawRect(Rect.fromCenter(center: Offset(w / 2, 8 + h * 0.07), width: w * 0.5, height: h * 0.14), line);
    canvas.drawRect(Rect.fromCenter(center: Offset(w / 2, h - 8 - h * 0.07), width: w * 0.5, height: h * 0.14), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
