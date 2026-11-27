import 'package:material_ui/material_ui.dart';

import '../theme/theme.dart';
import 'ds.dart';
import 'pep.dart';

/// The canvas's building blocks, one widget each, with the board's numbers.
///
/// Concept: a design system is a small set of parts used everywhere. The
/// canvas builds every screen from the same few (tracka.css): `.lab`
/// section labels, `.note` small grey text, `.pepnote` Pep's purple notes,
/// `.cta` the big round button, cards #111 with a #222 edge, dashed boxes
/// for "nothing here yet". Copying those parts exactly is what makes the app
/// look like the design; each screen then only arranges them.
/// See docs/handbook/09-mobile-and-web-apps.md, "Design systems".

/// Small grey text (canvas `.note`).
const bNote = TextStyle(fontSize: 12, height: 1.45, color: Tk.muted);

/// A screen's title block: eyebrow (main colour or Pep purple) over a big title.
class BHead extends StatelessWidget {
  const BHead({super.key, this.eyebrow, required this.title, this.eyebrowColor, this.size = 30, this.sub});

  final String? eyebrow;
  final String title;
  final Color? eyebrowColor;
  final double size;
  final String? sub;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (eyebrow != null)
          Text(eyebrow!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: eyebrowColor ?? context.accent.main)),
        if (eyebrow != null) const SizedBox(height: 4),
        Text(title, style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: size, height: 1.1)),
        if (sub != null) ...[const SizedBox(height: 3), Text(sub!, style: bNote.copyWith(fontSize: 13))],
      ]);
}

/// A section label with an optional note or link on the right (canvas `.lab`).
class BLab extends StatelessWidget {
  const BLab(this.text, {super.key, this.note, this.link, this.onLink});

  final String text;
  final String? note;
  final String? link;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.lab))),
          if (note != null) Flexible(child: Text(note!, textAlign: TextAlign.right, style: bNote)),
          if (link != null)
            Pressable(
              onTap: onLink,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(link!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Tk.muted)),
                const SizedBox(width: 4),
                const TIcon('chevron', size: 12, color: Tk.muted),
              ]),
            ),
        ]),
      );
}

/// A card (#111, #222 edge, corners 20).
class BCard extends StatelessWidget {
  const BCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Panel(padding: padding, onTap: onTap, child: child);
}

/// A dashed box: something that will fill in later.
class BDashed extends StatelessWidget {
  const BDashed({super.key, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 18)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashPainter(),
        child: Padding(padding: padding, child: SizedBox(width: double.infinity, child: child)),
      );
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(20)).deflate(.75);
    final path = Path()..addRRect(r);
    final paint = Paint()
      ..color = const Color(0xFF2E2E2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => false;
}

/// Pep's note (canvas `.pepnote`): his face beside a bold line and his words.
class BPepNote extends StatelessWidget {
  const BPepNote({super.key, required this.mood, this.title, required this.text, this.onTap, this.chip});

  final PepMood mood;
  final String? title;
  final String text;
  final VoidCallback? onTap;
  final String? chip;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFF160C33), borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: PepFace(mood, size: 24)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) ...[
              Text(title!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFEDE4FF))),
              const SizedBox(height: 2),
            ],
            Text(text, style: const TextStyle(fontSize: 13, height: 1.45, color: Color(0xFFD9CCF7))),
            if (chip != null) ...[
              const SizedBox(height: 8),
              BChip(chip!, color: Tk.pep, background: Tk.pepTile),
            ],
          ]),
        ),
      ]),
    );
    return onTap == null ? box : Pressable(onTap: onTap, child: box);
  }
}

/// A small rounded label (canvas `.chip`).
class BChip extends StatelessWidget {
  const BChip(this.text, {super.key, required this.color, required this.background, this.caps = false});

  final String text;
  final Color color;
  final Color background;
  final bool caps;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: caps ? 9 : 10, vertical: caps ? 3 : 5),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
        child: Text(caps ? text.toUpperCase() : text,
            style: TextStyle(fontSize: caps ? 10.5 : 12, fontWeight: caps ? FontWeight.w700 : FontWeight.w600, letterSpacing: caps ? .6 : 0, color: color)),
      );
}

/// The round 44 px button at the top of a screen (customise, bell, share).
class BRoundButton extends StatelessWidget {
  const BRoundButton({super.key, required this.icon, required this.label, required this.onTap, this.dot = false});

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Tk.field, shape: BoxShape.circle),
            child: Stack(clipBehavior: Clip.none, children: [
              TIcon(icon, size: 20, color: Tk.ink),
              if (dot)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: context.accent.main, border: Border.all(color: Tk.field, width: 2)),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// The big round button (canvas `.cta`): main colour, or ghost.
class BCta extends StatelessWidget {
  const BCta(this.label, {super.key, required this.onTap, this.ghost = false, this.height = 56, this.icon});

  final String label;
  final VoidCallback? onTap;
  final bool ghost;
  final double height;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final fg = ghost ? Tk.ink : a.on;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Pressable(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? .4 : 1,
          child: Container(
            constraints: BoxConstraints(minHeight: height),
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: ghost ? Tk.field : a.main,
              borderRadius: BorderRadius.circular(999),
              border: ghost ? Border.all(color: const Color(0xFF333333), width: 1.5) : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[TIcon(icon!, size: 18, color: fg), const SizedBox(width: 8)],
              Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: ghost ? FontWeight.w600 : FontWeight.w700, color: fg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A list row: a coloured tile, a title and a note, and something on the right.
class BRow extends StatelessWidget {
  const BRow({
    super.key,
    required this.icon,
    required this.title,
    this.sub,
    this.tile = 38,
    this.iconColor,
    this.tileColor,
    this.trailing,
    this.onTap,
    this.divider = true,
    this.titleSize = 14.5,
  });

  final String icon;
  final String title;
  final String? sub;
  final double tile;
  final Color? iconColor;
  final Color? tileColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: divider ? const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.line))) : null,
      child: Row(children: [
        IconTile(icon: icon, color: iconColor ?? Tk.ink, background: tileColor ?? Tk.field, size: tile),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w600, color: Tk.ink)),
            if (sub != null) ...[const SizedBox(height: 2), Text(sub!, style: bNote)],
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
    return onTap == null ? row : Pressable(onTap: onTap, child: row);
  }
}

/// A picture tile: photo (or a dark placeholder), dark fade at the bottom.
class BThumb extends StatelessWidget {
  const BThumb({super.key, this.url, required this.height, this.radius = 14, this.children = const []});

  final String? url;
  final double height;
  final double radius;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(fit: StackFit.expand, children: [
            if (url != null)
              Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1A1D16)))
            else
              const DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1F2618), Color(0xFF0E120B)])),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [.4, 1], colors: [Color(0x0D000000), Color(0xCC000000)]),
              ),
            ),
            ...children,
          ]),
        ),
      );
}
