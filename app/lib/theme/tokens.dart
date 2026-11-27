import 'package:material_ui/material_ui.dart';

/// Design tokens: the named values every screen is built from.
///
/// Concept: a *design token* is one decision (a colour, a size, a duration)
/// given a name and kept in one place. Screens never write `Color(0xFF...)`;
/// they ask for `Tk.pep` or `context.accent.main`. Change a token here and every
/// screen follows, so the app can't drift into fifty slightly different greys.
/// See docs/handbook/09-mobile-and-web-apps.md, "Design tokens".
///
/// Colours have JOBS, not just names (the canvas's "Colour jobs" note):
///   main colour (lime by default) = you: your progress, your main action
///   purple                        = Pep speaking (tips, AI notes)
///   gold                          = watch out (dips, warnings, safety)
///   stone                         = calm extras (neutral, offline, loading)
///   black and greys               = everything else
class Tk {
  Tk._();

  // Surfaces: pure black, then cards a step lighter.
  static const bg = Color(0xFF000000);
  static const card = Color(0xFF0E0E0E);
  static const card2 = Color(0xFF121212);
  static const field = Color(0xFF161616);
  static const line = Color(0xFF1E1E1E);
  static const lineStrong = Color(0xFF2A2A2A);

  // Text.
  static const ink = Color(0xFFF2F4EC); // chalk white
  static const inkSoft = Color(0xFFC9CDC2);
  static const muted = Color(0xFFA7AC9C);
  static const faint = Color(0xFF8C9183);
  static const lab = Color(0xFFD5D9CE); // section labels (canvas .lab)
  static const body = Color(0xFFE4E7DE); // card body text

  // Pep (purple). Pep's colour never changes, whatever main colour you pick.
  static const pep = Color(0xFFB98CFF);
  static const pepTile = Color(0xFF1D1240);

  // Watch out (gold). Also the "Below average" band.
  static const gold = Color(0xFFFFC21A);
  static const goldTile = Color(0xFF1B1505);
  static const goldInk = Color(0xFFEADFB8);

  // Calm extras (stone). Also the "Average" band.
  static const stone = Color(0xFFC8CCC2);
  static const stoneTile = Color(0xFF23251F);

  // Shapes.
  // Button heights: one scale everywhere, like iOS and Material apps.
  //   main     50  the one main action on a screen (Continue, Start training)
  //   inCard   44  buttons inside a card, or two side by side
  //   small    36  chips, filters and small pills
  // 44 is also the smallest comfortable tap target, so nothing tappable is
  // shorter than 44 except chips, which get extra space around them.
  static const btnMain = 50.0;
  static const btnInCard = 44.0;
  static const btnSmall = 36.0;

  static const rCard = 20.0;
  static const rTile = 12.0;
  static const rField = 14.0;
  static const rSheet = 26.0;
}

/// The five main colours a player can pick in Settings › Main colour.
///
/// Only the "you" colour changes. Each option is fully saturated (like Volt)
/// and keeps black text readable on it (WCAG AA or better). Purple, gold,
/// orange and red are never offered: they already mean Pep, warnings or errors.
enum MainColour {
  volt('Volt', Color(0xFFE5FF00), Color(0xFFC3D46A)),
  blue('Electric blue', Color(0xFF1A8CFF), Color(0xFF699ED3)),
  pink('Electric pink', Color(0xFFFF1AA6), Color(0xFFD369AA)),
  ice('Ice', Color(0xFF00E5FF), Color(0xFF69C9D3)),
  aqua('Aqua', Color(0xFF00FFB3), Color(0xFF69D3B4));

  const MainColour(this.label, this.main, this.soft);

  final String label;

  /// Buttons, selected chips, your progress, "Strong" and "Standout".
  final Color main;

  /// A calmer tone of the same colour: the "Above average" band.
  final Color soft;

  /// Dark tile behind your icons: the main colour at ~16% on black.
  Color get tile => Color.lerp(Tk.bg, main, 0.16)!;

  /// A faint glow for large areas: ~7% on black.
  Color get glow => Color.lerp(Tk.bg, main, 0.07)!;

  /// Text and icons drawn ON the main colour. Always black: every option was
  /// chosen so black reads well on it.
  Color get on => Tk.bg;

  /// The stored setting ("volt", "blue"...) back to a colour. Unknown or
  /// missing values fall back to Volt, so an older server can't break the app.
  static MainColour fromName(String? name) =>
      MainColour.values.firstWhere((c) => c.name == name, orElse: () => MainColour.volt);
}

/// The main colour as a [ThemeExtension], so any widget can read it with
/// `context.accent` and the whole app re-colours when the player picks another.
///
/// Concept: Flutter's [ThemeData] holds Material's own colours; a
/// ThemeExtension is how you add your own typed values to the same theme, and
/// get smooth animation between them (see [lerp]) for free.
@immutable
class Accent extends ThemeExtension<Accent> {
  const Accent(this.colour);

  final MainColour colour;

  Color get main => colour.main;
  Color get soft => colour.soft;
  Color get tile => colour.tile;
  Color get glow => colour.glow;
  Color get on => colour.on;

  @override
  Accent copyWith({MainColour? colour}) => Accent(colour ?? this.colour);

  @override
  Accent lerp(covariant Accent? other, double t) => t < 0.5 || other == null ? this : other;
}

extension AccentContext on BuildContext {
  /// The player's main colour (Volt if no theme sets one, e.g. in tests).
  Accent get accent => Theme.of(this).extension<Accent>() ?? const Accent(MainColour.volt);
}

/// Rating bands: how a measured skill compares with players of the same age group.
///
/// Never a number out of 100 and never an overall score: a band, plus the
/// measured average, how sure we are, and which way it's going.
enum Band {
  below('Below average'),
  average('Average'),
  above('Above average'),
  strong('Strong'),
  standout('Standout');

  const Band(this.label);
  final String label;

  static Band? fromName(String? name) {
    for (final b in Band.values) {
      if (b.name == name) return b;
    }
    return null;
  }

  /// Text colour of the band pill.
  Color fg(Accent a) => switch (this) {
        Band.below => Tk.gold,
        Band.average => Tk.stone,
        Band.above => a.soft,
        Band.strong => a.main,
        Band.standout => a.on,
      };

  /// Background of the band pill. Standout is solid; the rest are faint tints.
  Color bg(Accent a) => switch (this) {
        Band.below => Tk.gold.withValues(alpha: 0.12),
        Band.average => Tk.stone.withValues(alpha: 0.12),
        Band.above => a.soft.withValues(alpha: 0.14),
        Band.strong => a.main.withValues(alpha: 0.16),
        Band.standout => a.main,
      };
}

/// How sure Pep is about a rating: shown as 3 dots (filled = sure).
enum Confidence {
  low('Low confidence', 1),
  medium('Medium confidence', 2),
  high('High confidence', 3);

  const Confidence(this.label, this.dots);
  final String label;
  final int dots;

  /// Accepts the API's "LOW" / "MEDIUM" / "HIGH" (any case). Unknown → low.
  static Confidence fromName(String? name) => switch (name?.toLowerCase()) {
        'high' => Confidence.high,
        'medium' => Confidence.medium,
        _ => Confidence.low,
      };
}

/// Which way a skill is going since the last measurement.
enum Trend {
  growing('↑ Growing'),
  steady('→ Steady'),
  dipping('↓ Dipping'),
  fresh('New');

  const Trend(this.label);
  final String label;
}
