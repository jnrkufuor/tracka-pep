import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';
import 'loopy_icons.g.dart' show trackaMarkSvgBody;

/// The Tracka mark (a player striking a ball), in any colour. Defaults to the
/// player's main colour. The paths come from scripts/build_brand.py.
class TrackaMark extends StatelessWidget {
  const TrackaMark({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.accent.main;
    final hex = '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 185 196" fill="$hex">$trackaMarkSvgBody</svg>',
      height: size,
      semanticsLabel: 'Tracka',
    );
  }
}

/// The lockup: the mark in your main colour, then "Tracka" (capital T, as on the splash).
class TrackaLogo extends StatelessWidget {
  const TrackaLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        TrackaMark(size: size),
        SizedBox(width: size * 0.3),
        Text('Tracka', style: TextStyle(fontFamily: TType.display, fontWeight: FontWeight.w800, fontSize: size * 0.72, letterSpacing: -0.5, color: Tk.ink)),
      ]);
}
