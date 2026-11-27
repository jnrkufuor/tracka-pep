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
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Tk.field, shape: BoxShape.circle),
            child: Stack(clipBehavior: Clip.none, children: [
              TIcon(icon, size: 18, color: Tk.ink),
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
  const BCta(this.label, {super.key, required this.onTap, this.ghost = false, this.height = Tk.btnMain, this.icon});

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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: ghost ? Tk.field : a.main,
              borderRadius: BorderRadius.circular(999),
              border: ghost ? Border.all(color: const Color(0xFF333333), width: 1.5) : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[TIcon(icon!, size: 16, color: fg), const SizedBox(width: 8)],
              Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: height < Tk.btnMain ? 14.5 : 15, fontWeight: FontWeight.w600, color: fg)),
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
    this.leading,
    this.round = false,
  });

  /// A round tile with an outline (Sessions: coming up) instead of a square one.
  final bool round;

  /// Something else in the tile (the colour wheel in Settings).
  final Widget? leading;

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
        if (leading != null)
          Container(
            width: tile,
            height: tile,
            alignment: Alignment.center,
            decoration: round
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: tileColor,
                    border: tileColor == null ? Border.all(color: const Color(0xFF333333), width: 2) : null,
                  )
                : BoxDecoration(color: tileColor ?? Tk.field, borderRadius: BorderRadius.circular(tile * 0.3)),
            child: leading,
          )
        else
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

/// Four main colours in one dot (Settings › Main colour).
class BColourWheel extends StatelessWidget {
  const BColourWheel({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _WheelPainter()));
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const colours = [Color(0xFFE5FF00), Color(0xFF1A8CFF), Color(0xFFFF1AA6), Color(0xFF00E5FF)];
    final r = Offset.zero & size;
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(r, -1.5708 + i * 1.5708, 1.5708, true, Paint()..color = colours[i]);
    }
  }

  @override
  bool shouldRepaint(_WheelPainter old) => false;
}

/// A page under a tab (canvas: Reviews, Your schedule, Health…): a round
/// back button with an optional note on the right, the eyebrow ("Pep"),
/// a big title and a short line, then the content, 18 apart.
class BPage extends StatelessWidget {
  const BPage({
    super.key,
    this.eyebrow,
    this.eyebrowColor,
    this.title,
    this.sub,
    this.topNote,
    required this.children,
    this.bottom,
    this.gap = 18,
  });

  final String? eyebrow;
  final Color? eyebrowColor;
  final String? title;
  final String? sub;
  final String? topNote;
  final List<Widget> children;
  final Widget? bottom;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      Row(children: [
        Semantics(
          button: true,
          label: 'Back',
          excludeSemantics: true,
          child: Pressable(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Tk.field, shape: BoxShape.circle),
              child: const TIcon('back', size: 16, color: Tk.ink),
            ),
          ),
        ),
        const Spacer(),
        if (topNote != null) Text(topNote!, style: bNote),
      ]),
      if (title != null)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (eyebrow != null) ...[
            Text(eyebrow!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: eyebrowColor ?? Tk.pep)),
            const SizedBox(height: 6),
          ],
          Text(title!, style: Theme.of(context).textTheme.headlineLarge),
          if (sub != null) ...[const SizedBox(height: 6), Text(sub!, style: bNote.copyWith(fontSize: 13))],
        ]),
      ...children,
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: EnterFade(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
                for (final (i, w) in items.indexed) ...[if (i > 0) SizedBox(height: i == 1 ? 14 : gap), w],
              ]),
            ),
          ),
          if (bottom != null) Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: bottom),
        ]),
      ),
    );
  }
}

/// A coloured block in a day (canvas: Your schedule): tinted background,
/// a 3 px edge in the thing's colour, title, time.
class BBlock extends StatelessWidget {
  const BBlock({super.key, required this.title, this.sub, required this.edge, required this.fill, this.onTap, this.done = false, this.faded = false});

  final String title;
  final String? sub;
  final Color edge;
  final Color fill;
  final VoidCallback? onTap;
  final bool done;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final box = Opacity(
      opacity: faded ? .5 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: edge, width: 3)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Tk.ink,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: Tk.muted,
                  )),
              if (sub != null && sub!.isNotEmpty) Text(sub!, style: const TextStyle(fontSize: 11.5, color: Tk.muted)),
            ]),
          ),
          if (done) TIcon('check', size: 14, color: context.accent.main, stroke: 6),
          if (onTap != null && !done) const TIcon('chevron', size: 11, color: Tk.muted),
        ]),
      ),
    );
    return onTap == null ? box : Pressable(onTap: onTap, child: box);
  }
}

/// A small ghost chip with an icon ("+ School", "Team training").
class BGhostChip extends StatelessWidget {
  const BGhostChip({super.key, required this.icon, required this.label, required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Tk.btnSmall),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFF333333), width: 1.5)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            TIcon(icon, size: 14, color: Tk.ink),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Tk.ink)),
          ]),
        ),
      );
}

/// A segmented choice in a dark pill (canvas `.seg`): the picked one fills
/// with your main colour.
class BSeg<V> extends StatelessWidget {
  const BSeg({super.key, required this.options, required this.value, required this.onChanged});

  final Map<V, String> options;
  final V value;
  final ValueChanged<V> onChanged;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(999)),
      child: Row(children: [
        for (final e in options.entries)
          Expanded(
            child: Semantics(
              button: true,
              selected: e.key == value,
              label: e.value,
              excludeSemantics: true,
              child: Pressable(
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: Motion.of(context, Motion.select),
                  curve: Motion.change,
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: e.key == value ? a.main : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(e.value,
                        maxLines: 1,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: e.key == value ? a.on : const Color(0xFFC2C6BA))),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
