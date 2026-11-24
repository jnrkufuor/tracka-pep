import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/theme.dart';
import 'line_icons.g.dart';

// The design system's shared pieces, built once and used on every screen.
//
// Concept: a *component library*. Instead of each screen drawing its own
// card, chip or warning, screens put these together. One fix here (say, a
// chip that's too small to tap) fixes it everywhere. Each piece matches a
// board on the design canvas; the names say which.
// See docs/handbook/09-mobile-and-web-apps.md, "Component libraries".

// ───────────────────────────── icons

/// An icon from Tracka's line pack (48 x 48 grid, square ends), generated into
/// line_icons.g.dart by scripts/build_brand.py. Takes any colour; solid parts
/// (the play triangle, the ball's patch) are filled with the same colour.
/// Decorative by default: give [semanticLabel] when the icon is the only
/// thing that says what a button does.
class TIcon extends StatelessWidget {
  const TIcon(this.name, {super.key, this.size = 20, this.color, this.stroke = 4, this.semanticLabel});

  final String name;
  final double size;
  final Color? color;
  final double stroke;
  final String? semanticLabel;

  /// Every icon name the pack has (handy in tests and pickers).
  static Iterable<String> get names => linePaths.keys;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Tk.ink;
    final hex = '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final body = (linePaths[name] ?? linePaths['info']!).replaceAll('"C"', '"$hex"');
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" fill="none" stroke="$hex" '
        'stroke-width="$stroke" stroke-linecap="square" stroke-linejoin="miter">$body</svg>';
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

// ───────────────────────────── motion helpers

/// Fades its child in and lifts it 8 px, once, when it first appears.
/// Every screen's content uses this ("enterFade" on the canvas).
/// With reduce motion on, the child is simply there.
class EnterFade extends StatefulWidget {
  const EnterFade({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;

  /// Stagger lists by giving each item a little more delay (e.g. 40 ms apart).
  final Duration delay;

  @override
  State<EnterFade> createState() => _EnterFadeState();
}

class _EnterFadeState extends State<EnterFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.enter);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _c.value = 1;
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Motion.arrive);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (_, child) => Transform.translate(offset: Offset(0, 8 * (1 - curved.value)), child: child),
        child: widget.child,
      ),
    );
  }
}

/// Anything tappable that should feel pressed: shrinks to 97% while held.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: Motion.of(context, Motion.press),
          curve: Motion.arrive,
          child: widget.child,
        ),
      ),
    );
  }
}

// ───────────────────────────── containers

/// A dark card: the basic box everything sits in.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.border});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Tk.card,
        borderRadius: BorderRadius.circular(Tk.rCard),
        border: Border.all(color: border ?? Tk.line),
      ),
      child: child,
    );
    return onTap == null ? box : Pressable(onTap: onTap, child: box);
  }
}

/// A rounded square with an icon in it. Its colour says whose it is:
/// accent = you, purple = Pep, gold = watch out, stone = neutral.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.color, required this.background, this.size = 40});

  final String icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.3)),
        alignment: Alignment.center,
        child: TIcon(icon, size: size * 0.5, color: color),
      );
}

/// A small label above a section ("This week", "Skills").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.ink))),
          if (trailing != null) trailing!,
        ]),
      );
}

// ───────────────────────────── chips

/// Chips where exactly one is picked, like tabs (Pitchside: Challenges ·
/// Near you · Opportunities; Pep tips: All · Skills · ...).
/// The picked chip is filled with the main colour; NO checkmark, because
/// nothing is being "ticked", you're just choosing what to look at.
/// Tapping the picked chip again keeps it picked (never an empty choice).
class SingleChips<V> extends StatelessWidget {
  const SingleChips({super.key, required this.options, required this.value, required this.onChanged, this.scroll = true});

  final Map<V, String> options;
  final V value;
  final ValueChanged<V> onChanged;

  /// Scroll sideways when they don't fit (true), or wrap onto more lines.
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final e in options.entries)
        _Chip(label: e.value, selected: e.key == value, check: false, onTap: () => onChanged(e.key)),
    ];
    if (!scroll) return Wrap(spacing: 8, runSpacing: 8, children: chips);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(children: [for (final c in chips) Padding(padding: const EdgeInsets.only(right: 8), child: c)]),
    );
  }
}

/// Chips where you can pick several (onboarding: positions, things you're good at).
/// Here a checkmark helps: it shows what you've ticked.
class MultiChips<V> extends StatelessWidget {
  const MultiChips({super.key, required this.options, required this.values, required this.onChanged});

  final Map<V, String> options;
  final Set<V> values;
  final ValueChanged<Set<V>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in options.entries)
          _Chip(
            label: e.value,
            selected: values.contains(e.key),
            check: true,
            onTap: () {
              final next = {...values};
              next.contains(e.key) ? next.remove(e.key) : next.add(e.key);
              onChanged(next);
            },
          ),
      ]);
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.check, required this.onTap});

  final String label;
  final bool selected;
  final bool check;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.select),
          curve: Motion.change,
          height: 40, // a comfortable tap target; the row inside is centred in it
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: selected ? a.main : Tk.field,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? a.main : const Color(0xFF333333), width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (check && selected) ...[TIcon('check', size: 14, color: a.on, stroke: 5), const SizedBox(width: 6)],
            Text(label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? a.on : Tk.ink,
                )),
          ]),
        ),
      ),
    );
  }
}

// ───────────────────────────── ratings (the "Rating system" board)

/// The compact band pill: Below average · Average · Above average · Strong · Standout.
class BandPill extends StatelessWidget {
  const BandPill(this.band, {super.key});

  final Band band;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: band.bg(a), borderRadius: BorderRadius.circular(999)),
      child: Text(band.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: band.fg(a))),
    );
  }
}

/// Three dots: how sure Pep is. Filled dots use the main colour.
class ConfidenceDots extends StatelessWidget {
  const ConfidenceDots(this.confidence, {super.key, this.showLabel = true});

  final Confidence confidence;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    return Semantics(
      label: confidence.label,
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: i < confidence.dots ? a.main : const Color(0xFF3A3D36)),
          ),
        if (showLabel) ...[
          const SizedBox(width: 3),
          Text(confidence.label, style: const TextStyle(fontSize: 11.5, color: Tk.faint)),
        ],
      ]),
    );
  }
}

/// ↑ Growing · → Steady · ↓ Dipping · New. Dipping is gold (watch out), never red.
class TrendTag extends StatelessWidget {
  const TrendTag(this.trend, {super.key});

  final Trend trend;

  @override
  Widget build(BuildContext context) {
    final c = switch (trend) {
      Trend.growing => context.accent.main,
      Trend.dipping => Tk.gold,
      _ => Tk.faint,
    };
    return Text(trend.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c));
  }
}

/// One skill area on Me: name, band, the measured average, confidence and trend.
/// A skill we can't measure yet shows a calm state instead of a band.
class RatingRow extends StatelessWidget {
  const RatingRow({
    super.key,
    required this.name,
    this.band,
    this.average,
    this.confidence = Confidence.low,
    this.trend = Trend.fresh,
    this.state,
    this.keySkill = false,
    this.onTap,
  });

  final String name;
  final Band? band;

  /// The measured average in plain words ("22 wall passes in 30 s").
  final String? average;
  final Confidence confidence;
  final Trend trend;

  /// "Coming later", "Not seen yet", "Pep can't see this": used when [band] is null.
  final String? state;

  /// Key skill for this position: a small main-colour dot after the name.
  final bool keySkill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final measured = band != null;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(name,
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: measured ? FontWeight.w600 : FontWeight.w400, color: measured ? Tk.ink : Tk.muted)),
              ),
              if (keySkill)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: context.accent.main),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          if (measured) BandPill(band!) else Text(state ?? 'Not seen yet', style: const TextStyle(fontSize: 12, color: Tk.faint)),
        ]),
        if (measured) ...[
          if (average != null) ...[
            const SizedBox(height: 4),
            Text('Average: $average', style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
          ],
          const SizedBox(height: 6),
          Row(children: [ConfidenceDots(confidence), const Spacer(), TrendTag(trend)]),
        ],
      ]),
    );
    return onTap == null ? row : Pressable(onTap: onTap, child: row);
  }
}

// ───────────────────────────── notes (the "Disclaimers" note)

/// The calm stone note for AI limits:
/// "Pep is an AI and can get things wrong..." Used wherever Pep's words or
/// ratings could be taken as final.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key});

  final String text;

  /// The standard wording, so it's the same everywhere.
  static const pep = 'Pep is an AI and can get things wrong. Use its tips as a guide, '
      'and check with your coach before big changes.';
  static const measured = 'Measured from your clips by Tracka. Video can be off if the camera is far away, '
      'shaky or in poor light. Retests make it more accurate.';

  @override
  Widget build(BuildContext context) => _Note(
        text: text,
        icon: 'info',
        iconColor: Tk.muted,
        textColor: Tk.muted,
        background: Tk.card,
        border: Tk.line,
      );
}

/// The gold safety note where you train: "Stop if anything hurts."
class SafetyNote extends StatelessWidget {
  const SafetyNote(this.text, {super.key});

  final String text;

  static const training = "Stop if anything hurts. Pep can't see injuries, so rest and tell an adult or your coach.";
  static const drill = 'Warm up first. Stop if anything hurts, and tell an adult.';

  @override
  Widget build(BuildContext context) => _Note(
        text: text,
        icon: 'hurt',
        iconColor: Tk.gold,
        textColor: Tk.goldInk,
        background: Tk.goldTile,
        border: Tk.gold.withValues(alpha: 0.22),
      );
}

class _Note extends StatelessWidget {
  const _Note({
    required this.text,
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.background,
    required this.border,
  });

  final String text;
  final String icon;
  final Color iconColor;
  final Color textColor;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: TIcon(icon, size: 16, color: iconColor)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, height: 1.45, color: textColor))),
        ]),
      );
}

// ───────────────────────────── sheets and toasts

/// Opens an edit screen as a sheet on pure black: grabber, round close button,
/// big title, and changes save as you make them (no Save / Cancel buttons).
/// Swipe down or tap the close button to go back.
Future<T?> showEditSheet<T>(BuildContext context, {required String title, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Tk.bg,
    barrierColor: Colors.black,
    sheetAnimationStyle: Motion.reduced(context)
        ? const AnimationStyle(duration: Duration.zero, reverseDuration: Duration.zero)
        : const AnimationStyle(duration: Motion.sheet, reverseDuration: Motion.select),
    builder: (ctx) => EditSheet(title: title, child: child),
  );
}

class EditSheet extends StatelessWidget {
  const EditSheet({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Its own ScaffoldMessenger + Scaffold, so a toast shown from inside the
    // sheet appears on the sheet (not hidden behind it).
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _sheet(context),
      ),
    );
  }

  Widget _sheet(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 1,
      minChildSize: 0.5,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: [
          Center(
            child: Container(width: 40, height: 5, decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(9))),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineLarge)),
            Semantics(
              button: true,
              label: 'Close',
              child: Pressable(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: Tk.field, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const TIcon('close', size: 18, color: Tk.ink),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

/// A toast at the BOTTOM of the screen, above the tabs, for 4 seconds.
/// Use for "Saved", "Ama said yes", "Upload stopped". Never for errors that
/// need a decision: those get a [StateView] or a sheet.
/// [ok] false = something didn't work: a gold "watch out" icon instead of a check.
void showToast(BuildContext context, String title,
    {String? detail, String? actionLabel, VoidCallback? onAction, bool aboveTabs = true, bool ok = true}) {
  final a = context.accent;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: Motion.toastStay,
      margin: EdgeInsets.fromLTRB(12, 0, 12, aboveTabs ? 96 : 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      content: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: ok ? a.tile : Tk.goldTile, borderRadius: BorderRadius.circular(11)),
          alignment: Alignment.center,
          child: ok ? TIcon('check', size: 18, color: a.main, stroke: 5) : const TIcon('info', size: 18, color: Tk.gold),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.ink)),
            if (detail != null) Text(detail, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: Tk.muted)),
          ]),
        ),
      ]),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ));
}

// ───────────────────────────── failsafe states (the "Failsafe states" boards)

/// What a player sees when something went wrong or isn't ready:
/// say what happened in plain words, say their work is safe, give ONE next step.
class StateView extends StatelessWidget {
  const StateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.kind = StateKind.neutral,
    this.secondaryLabel,
    this.onSecondary,
    this.extra,
  });

  /// A line-pack icon name (see [TIcon]).
  final String icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final StateKind kind;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Optional detail under the message (e.g. "why Pep couldn't read the clip").
  final Widget? extra;

  /// "That didn't work": something failed on our side. Work is safe; try again.
  factory StateView.error({required VoidCallback onRetry, VoidCallback? onReport}) => StateView(
        icon: 'info',
        kind: StateKind.watchOut,
        title: "That didn't work",
        message: 'Something went wrong on our side. Your clips and progress are safe. Try again in a moment.',
        actionLabel: 'Try again',
        onAction: onRetry,
        secondaryLabel: onReport == null ? null : 'Report a problem',
        onSecondary: onReport,
      );

  /// You're offline and there's nothing saved to show here.
  factory StateView.offline({required VoidCallback onRetry}) => StateView(
        icon: 'nosignal',
        title: "You're offline",
        message: "This needs the internet. Everything you've done is saved, and clips upload when you're back.",
        actionLabel: 'Try again',
        onAction: onRetry,
      );

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (kind) {
      StateKind.neutral => (Tk.stone, Tk.stoneTile),
      StateKind.watchOut => (Tk.gold, Tk.goldTile),
      StateKind.pep => (Tk.pep, Tk.pepTile),
      StateKind.you => (context.accent.main, context.accent.tile),
    };
    return LayoutBuilder(
      builder: (ctx, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight - 56),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
              alignment: Alignment.center,
              child: TIcon(icon, size: 34, color: fg),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.headlineMedium),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, height: 1.5, color: Tk.muted)),
            ),
            if (extra != null) ...[const SizedBox(height: 20), extra!],
            const SizedBox(height: 28),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: onAction, child: Text(actionLabel))),
            if (secondaryLabel != null) TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ]),
        ),
      ),
    );
  }
}

enum StateKind { neutral, watchOut, pep, you }

/// The quiet banner at the top of a screen while offline. The screen keeps
/// showing what's saved underneath.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF262626))),
        child: const Row(children: [
          TIcon('nosignal', size: 16, color: Tk.stone),
          SizedBox(width: 10),
          Expanded(
            child: Text("You're offline. Showing what's saved. Clips upload when you're back.",
                style: TextStyle(fontSize: 13, color: Tk.inkSoft, height: 1.4)),
          ),
        ]),
      );
}

/// A grey shape where content will appear while it loads. Pulses slowly;
/// with reduce motion it stays still.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width = double.infinity, required this.height, this.radius = 12});

  final double width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: FadeTransition(
          opacity: Tween(begin: 1.0, end: 0.55).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(widget.radius)),
          ),
        ),
      );
}
