# Pep Lab design

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

## The logo
`scripts/build_brand.py` redraws Tracka's mark as clean vectors (head
circle, kicking "7" body, ball) traced from the original PNG. Outputs in
`web/assets/brand/`:
- `mark-neon.svg`, `mark-ink.svg`, `mark-white.svg`: the mark alone;
- `app-icon.svg`: neon tile with the dark mark, now **58% of the tile's
  height** (the old icon was about 74%), so it has more breathing room;
- `favicon.svg`.

The same SVGs work in the Flutter app (`flutter_svg`) and in slides.
