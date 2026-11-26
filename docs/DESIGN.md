# Tracka design (app and Lab)

## Player app: design system v2 (November 2026)

The player app is built from the design canvas ("Tracka player app:
screen concepts v2"). The sections further down describe the first version
and apply only to the Lab (staff console).

- **Colours have jobs** (`app/lib/theme/tokens.dart`, class `Tk`):
  - **main colour** = you: your buttons, progress, "Strong" and "Standout".
    Volt `#E5FF00` by default; players can pick Electric blue `#1A8CFF`,
    Electric pink `#FF1AA6`, Ice `#00E5FF` or Aqua `#00FFB3` in Settings ›
    Main colour (`MainColour`, saved as the `mainColour` setting);
  - **purple** `#B98CFF` = Pep speaking; **gold** `#FFC21A` = watch out;
    **stone** `#C8CCC2` = calm extras; pure black `#000` behind everything.
  - Never offered as a main colour: purple, gold/orange, red, plain green.
    There is **no red** anywhere in the app.
- **Type**: Bricolage Grotesque ExtraBold for headings and big numbers,
  Figtree for text (both SIL Open Font License, in `app/assets/fonts`).
- **Ratings**: no overall score and no numbers out of 100. Each measured
  skill gets a band (Below average · Average · Above average · Strong ·
  Standout), its measured average, confidence dots and a trend tag.
- **Motion** (`app/lib/theme/motion.dart`): short and quick, and
  everything still works with reduce motion on (phone setting or
  Settings › Accessibility). Per-screen list: the "Motion, screen by
  screen" board.
- **Components** (`app/lib/widgets/ds.dart`): chips (single-choice chips
  have no checkmark), band pill, confidence dots, trend tag, AI note
  (stone) and safety note (gold), edit sheets on pure black (grabber,
  close button, saves as you go), toasts at the bottom, failsafe
  `StateView`, offline banner, loading skeletons.
- **Icons**: the "Line, burst, play" pack (48 x 48, square ends, a few
  solid shapes). Defined in `scripts/build_brand.py` (`LINE_ICONS`),
  generated to `web/assets/icons/line/` and `app/lib/widgets/line_icons.g.dart`,
  drawn in the app with `TIcon('name')`. Add an icon in the script, run it.
- **Tabs**: Home, Pitchside, + (add a clip), Pep, Me. The splash fades
  the mark in, then "Tracka".


**Brief:** YesBut's design language, turned to *night-match* mode. A darker,
sportier Tracka, still with the neon.

## What carries over from YesBut
- **Type**: Bricolage Grotesque Bold for headlines (tight tracking, big
  sizes) and Google Sans Flex for text. Fonts are in `web/assets/fonts`
  (SIL Open Font License).
- **Shapes**: big soft radii (14 / 22 / 30 / 40 px), pill buttons and
  chips, one loud colour card per screen.
- **Icons**: the hand-drawn "loopy" single-line set (40 × 40 grid, round
  caps, deliberately wobbly curves), extended with sport icons: ball,
  stopwatch, bolt, cone, whistle, player, pulse, star, target, ruler.
- **Microcopy**: plain, direct, second person ("Pep couldn't score this
  clip").
- **Motion**: short eased transitions, bars that grow in, and
  `prefers-reduced-motion` respected.

## What's new (sport, dark)
- **Palette** (`web/app.css :root`):
  - pitch at night `#0A0B09`, surfaces `#121410 / #191C16 / #22261E`
  - chalk white `#F2F4EC`, soft `#A7AC9C`, faint `#6E7366`
  - **Tracka neon `#E5FF00`**: the floodlight. Primary actions, the score
    card, highlights.
  - accents re-tuned for dark: cherry `#FF4858` (LOW / failed / work-on),
    sunflower `#FFD100` (MEDIUM), violet `#8C73FF` (running / AI-observed).
- **Kit-number scores**: big tabular numerals skewed −9°, like a shirt
  number in motion.
- **Tape stripes**: a skewed dashed neon bar under hero titles, like
  pitch-side tape.
- **Uppercase eyebrows** with wide letter-spacing, like broadcast graphics.
- **Mobile**: the nav becomes a floating bottom pill (thumb reach).

## In the Flutter app
The app uses **only design system v2** (top of this file). The v1 pieces
(`TColors`, `TRadius`, loopy icons, kit-number scores, tape stripes, score
bars, `common.dart`, `skill_card.dart`) were removed in November 2026; the
Lab keeps v1 on the web.
- tokens: `app/lib/theme/tokens.dart` (`Tk`, `MainColour`, `Band`, `Confidence`);
- components: `app/lib/widgets/ds.dart`; brand: `app/lib/widgets/brand.dart`
  (`TrackaMark`, `TrackaLogo`: the mark in your main colour, then "Tracka");
- icons: the line pack, `TIcon('name')` (`line_icons.g.dart`, generated);
- accessibility: text size on top of the phone's (`textSize`), higher
  contrast (`highContrast`: a colour filter that lifts every grey, black stays
  black), less motion (`reduceMotion` plus the phone's setting).

## The logo
`scripts/build_brand.py` redraws Tracka's mark as clean vectors (head
circle, kicking "7" body, ball) traced from the original PNG. Outputs in
`web/assets/brand/`:
- `mark-neon.svg`, `mark-ink.svg`, `mark-white.svg`: the mark alone;
- `app-icon.svg`: neon tile with the dark mark, now **58% of the tile's
  height** (the old icon was about 74%), so it has more breathing room;
- `favicon.svg`.

The same SVGs work in the Flutter app (`flutter_svg`) and in slides.
