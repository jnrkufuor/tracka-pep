"""
Builds Tracka's brand files from one source of truth: this script.

    python scripts/build_brand.py        -> web/assets/brand/*.svg, web/assets/icons/*.svg, web/assets/icons.js

Why generate instead of hand-editing SVG files? The logo appears in many
sizes and colours (app icon, favicon, dark and light marks), and the icons
are used both by the web UI (icons.js) and as standalone SVGs (for the
Flutter app or slides). One definition, many outputs, never out of sync.

THE MARK
  Redrawn as clean vector shapes from the original tracka_logo.png: a head
  (circle), a body sweeping like a "7" mid-kick, and the ball (circle).
  In the app icon the mark is a little smaller than in the old icon
  (about 58% of the tile's height instead of ~74%), so it breathes.

THE LINE ICONS (design system v2, the app's icons)
  The "Line, burst, play" pack picked on the design canvas: 48 x 48 grid,
  square line ends, sharp corners, a few solid shapes (play, burst, ball).
  Paths use "C" where a solid fill takes the icon's colour.
  Outputs: web/assets/icons/line/<name>.svg and app/lib/widgets/line_icons.g.dart
  (drawn by the TIcon widget in app/lib/widgets/ds.dart).

THE ICONS (older)
  Tracka's "loopy" set: the same hand-drawn, single-line style as YesBut
  (40 x 40 grid, round caps, slightly wobbly Bezier curves on purpose),
  extended with sport icons: ball, stopwatch, bolt, cone, whistle...
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "web" / "assets"

NEON = "#E5FF00"
INK = "#0A0B09"

# ---------------------------------------------------------------- the mark (viewBox 0 0 185 196)
MARK_W, MARK_H = 185, 196
MARK = [
    '<circle cx="124.9" cy="22.6" r="22.6"/>',
    '<circle cx="146.6" cy="148.8" r="23"/>',
    '<path d="M46.5 72.6C78 56.6 128 47.5 180.6 66.6Q184.2 68 184 72.2L182.4 88.4Q181.8 92.4 177.4 93'
    "C138 97 80 130 19.4 191.4Q15.6 195 12.2 192.4L3.2 183.4Q0.2 180 3.4 176.4C42 135 84 106 115.4 88.6"
    'Q120.4 85.6 118.2 81.2Q116.8 78.8 112.6 79C92 79 72 82.6 56.8 89.6Q53.2 91 51.2 88L45 78.4Q43.4 74.6 46.5 72.6Z"/>',
]


def mark_svg(color: str) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {MARK_W} {MARK_H}" fill="{color}">'
        + "".join(MARK)
        + "</svg>\n"
    )


def tile_svg(size: int = 512, mark_share: float = 0.58, radius_share: float = 0.225) -> str:
    """App icon: neon tile, dark mark. mark_share = mark height / tile height."""
    scale = size * mark_share / MARK_H
    w, h = MARK_W * scale, MARK_H * scale
    # Optical centring: the mark's weight sits low-left, so nudge it right and up a touch.
    x, y = (size - w) / 2 + size * 0.015, (size - h) / 2 - size * 0.01
    r = size * radius_share
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}">'
        f'<rect width="{size}" height="{size}" rx="{r:.1f}" fill="{NEON}"/>'
        f'<g transform="translate({x:.2f} {y:.2f}) scale({scale:.5f})" fill="{INK}">{"".join(MARK)}</g>'
        "</svg>\n"
    )


# ---------------------------------------------------------------- loopy icons (40 x 40)
ICONS: dict[str, list[str]] = {
    # from YesBut, unchanged
    "upload": [
        "M12 27.4 C7.4 27.6 5.6 23.2 8.2 20.6 C9.2 19.6 10.6 19.4 11.6 19.8 C11.6 14.2 17.6 11.4 21.6 14 C23.2 15 24.2 16.6 24.4 18.2 C27.4 16.8 31.6 18.6 31.8 22.6 C32 25.8 29.6 27.6 27 27.4",
        "M20.2 34.6 C20.4 30 19.8 25.2 20.4 20.6 C19.2 21.8 17.4 23.4 15.8 25 M20.4 20.6 C21.8 22 23.4 23.6 24.8 25.2",
    ],
    "check": [
        "M27.8 9.2 C24.2 6.4 17 5.8 12 9.4 C6.4 13.4 5.6 22.6 9.8 28.2 C14 33.8 23.4 35 29 30.2 C33.6 26.2 34.4 19.2 31.8 14.4",
        "M13.4 20.6 C15.4 22 17 23.8 18.4 25.6 C21.8 20 25.6 14.6 30.6 9.4 C32 8 33.4 8.6 32.4 10",
    ],
    "eye": [
        "M4.6 20.4 C10 12.4 16 10.2 20.4 10.4 C27 10.6 32 15.2 35.4 20.2 C31.4 26.4 26 29.8 20 29.6 C13.6 29.4 8.6 25.8 4.6 20.4",
        "M20.2 24.6 C16.8 24.6 15.6 21.4 17 19 C18.4 16.8 21.8 16.8 23 19.2 C24 21.2 22.6 22.8 21 22.2 C19.8 21.6 20.2 20.2 21 19.8",
    ],
    "flag": [
        "M11 35 C10.6 26 11 16 11.2 6.4 C15.6 4.8 19.4 8.6 23.4 7.4 C26.6 6.4 28.2 5 31 6.2 C30.6 10.6 30.8 15 31.2 19.4 C27.6 21.4 24.2 18.6 20.6 19.6 C17.4 20.4 14.6 22.4 11.2 21.2",
    ],
    "search": [
        "M18 29 C11.4 29.2 7.4 24.2 7.8 18.4 C8.2 12.4 13.2 8 19 8.4 C25 8.8 29 13.8 28.6 19.6 C28.4 23 26.6 25.8 24 27.4",
        "M25.4 26.4 C27.8 28.8 30.2 31.4 33 34",
    ],
    "back": [
        "M33 20.6 C26 20.2 18 20.8 9.4 20.4",
        "M17 12.4 C14.4 15 12 17.6 9.4 20.4 C12 23.2 14.4 25.8 17.2 28.6",
    ],
    "refresh": [
        "M30.6 15.4 C28.4 10.6 23.8 8 19.4 8.4 C12.6 9 8.2 14.8 8.6 21 C9 27.2 14.4 32 20.6 31.6 C25.4 31.2 29 28.2 30.6 24",
        "M31.6 8.6 C31.4 11 31.2 13.4 31 15.8 C28.6 15.6 26.2 15.4 23.8 15.2",
    ],
    "ai": [
        "M17 6 C17.8 12.6 13.8 17 8 18 C14 19.4 17.2 23.6 17.4 30 C18.4 23.4 22.6 19.6 28 18.2 C22.4 17 18.2 13 17 6",
        "M29 27 C29.6 29.6 31 31 33.6 31.6 C31 32.2 29.6 33.6 29 36.2 C28.4 33.6 27 32.2 24.4 31.6",
    ],
    # new: sport
    "ball": [
        "M20 6.4 C28 6 34 12.2 33.8 20.2 C33.6 28 27.6 34 19.8 33.8 C12 33.6 6.2 27.6 6.4 19.8 C6.6 12.4 12.4 6.6 20 6.4",
        "M20.2 15 C21.8 16 23.2 17.2 24.6 18.4 C24 20.2 23.4 22 22.8 23.8 C21 23.8 19 23.8 17.2 23.8 C16.6 22 16 20.2 15.4 18.4 C16.8 17.2 18.4 16 20.2 15",
        "M20.2 15 C20 12.2 20.2 9.4 20.2 6.6",
        "M24.6 18.4 C27.4 17.4 30.4 16.4 33.2 15.4",
        "M22.8 23.8 C24.4 26.4 26 29 27.4 31.4",
        "M17.2 23.8 C15.6 26.4 14 29 12.6 31.4",
        "M15.4 18.4 C12.6 17.4 9.8 16.4 6.8 15.6",
    ],
    "stopwatch": [
        "M20.2 33.6 C13.8 33.8 9 28.8 9.2 22.6 C9.4 16.6 14.4 11.8 20.4 12 C26.4 12.2 31.2 17.2 31 23.2 C30.8 29 26 33.4 20.2 33.6",
        "M16.6 6.6 C19 6.4 21.2 6.6 23.6 6.4",
        "M20.2 6.6 C20.2 8.4 20.2 10.2 20.4 12",
        "M20.4 22.8 C21.8 20.4 23.2 18.2 24.8 16",
        "M28.6 12.6 C29.6 11.6 30.6 10.6 31.6 9.6",
    ],
    "bolt": [
        "M22.6 5.6 C19.4 11 16 16.4 12.4 21.8 C15.4 21.8 18.2 21.6 21 21.8 C19.8 25.8 18.6 29.8 17.4 34.4 C21.4 28.6 25.2 22.8 28.8 17.2 C25.8 17.4 23 17.2 20.2 17.4 C21 13.4 21.8 9.4 22.6 5.6",
    ],
    "cone": [
        "M20 7 C17.4 15 14.8 23 12.2 30.8 C17.4 31.2 22.6 31 27.8 30.8 C25.2 23 22.6 15 20 7",
        "M8.4 31 C16 31.4 24 30.8 31.6 31.2 C31.8 32.4 31.6 33.4 31.4 34.2 C24 34.4 16 34 8.6 34.2 C8.4 33.2 8.4 32 8.4 31",
        "M15.8 20.6 C18.6 20.4 21.4 20.6 24.2 20.4",
    ],
    "whistle": [
        "M8 18.4 C8.2 13.6 12.2 11 16.4 11.4 C22 11.6 28 11.2 33.6 11.6 C33.8 13.6 33.6 15.4 33.4 17 C30 17.2 27 17 24.6 17.4 C25.6 22.4 21.6 27.4 16.2 27.2 C11.6 27 8 23.4 8 18.4",
        "M16.4 21.6 C14.2 21.6 13.4 19 15 17.8 C16.4 16.8 18.4 17.8 18 19.6",
        "M33.4 11.6 C34.6 9.4 34.4 7 32.6 5.6",
    ],
    "player": [
        "M24.4 9.6 C22.6 9.8 21.4 8.4 21.6 6.8 C21.8 5.2 23.4 4.2 25 4.6 C26.4 5 27 6.6 26.4 8 C26 9 25.2 9.6 24.4 9.6",
        "M22.8 13 C20.6 17 19 20.6 17.4 23.8 C20.4 25.4 22.8 27 24.6 29.4 C24.4 31.4 24 33.4 23.4 35",
        "M17.4 23.8 C15.4 26.6 13.2 29.6 10 31.4",
        "M14.2 15.4 C16.8 13.8 19.8 12.6 22.8 13 C25.2 15 27.4 17 30.2 17.6",
    ],
    "pulse": [
        "M5.4 21 C9 21 11.6 21.2 13.6 20.8 C15 17.6 16.4 13.4 17.6 9.6 C19.2 16 20.6 24.4 22.4 30.6 C23.8 26.6 25 23.4 26.2 20.6 C28.8 20.8 31.4 20.6 34.6 20.8"
    ],
    "star": [
        "M20.2 6.2 C21.6 10 23 13.4 24.4 16.4 C28 16.6 31.4 16.8 34.4 17.2 C31.8 19.8 29.2 22.2 26.6 24.4 C27.4 28 28.2 31.4 28.8 34.2 C25.8 32.2 22.8 30.4 20 28.8 C17 30.6 14 32.4 11.2 34.2 C11.8 31 12.6 27.6 13.4 24.2 C10.8 22 8.2 19.6 5.6 17.2 C9 16.8 12.4 16.6 15.8 16.4 C17.2 13 18.6 9.8 20.2 6.2",
    ],
    "play": [
        "M13.4 9.2 C13.2 16.4 13.4 23.6 13.6 30.8 C19.4 27.4 25 23.8 30.4 20.2 C24.8 16.4 19 12.8 13.4 9.2"
    ],
    "target": [
        "M20 6.6 C27.6 6.4 33.6 12.4 33.4 20 C33.2 27.4 27.4 33.4 20 33.4 C12.6 33.4 6.6 27.4 6.6 20 C6.6 12.8 12.6 6.8 20 6.6",
        "M20 13.4 C23.8 13.2 26.8 16.4 26.6 20 C26.4 23.6 23.6 26.6 20 26.6 C16.4 26.6 13.4 23.8 13.4 20.2 C13.4 16.4 16.6 13.6 20 13.4",
        "M20.2 20.6 C19.6 20.6 19.4 19.8 19.8 19.6 C20.2 19.4 20.8 19.8 20.4 20.2",
    ],
    "ruler": [
        "M6.4 25.6 C15 17 23.6 8.6 26.6 6.6 C29 9 31.4 11.4 33.6 13.6 C25 22.2 16.4 30.6 13.6 33.6 C11.2 31 8.8 28.4 6.4 25.6",
        "M12.8 21.6 C13.8 22.6 14.6 23.4 15.6 24.4",
        "M17 17.4 C17.6 18 18.2 18.6 18.8 19.2",
        "M21.2 13.2 C22.2 14.2 23 15 24 16",
        "M25.4 9.2 C26 9.8 26.6 10.4 27.2 11",
    ],
    # new: app navigation and actions
    "home": [
        "M6.6 19.4 C11 15.4 15.4 11.4 20 7.4 C24.6 11.4 29 15.4 33.4 19.4",
        "M10.4 16.6 C10.2 22 10.6 27.6 10.4 33 C16.8 33.4 23.2 33.2 29.6 33 C29.4 27.6 29.8 22 29.6 16.6",
        "M17 33 C17 29.6 16.8 26.6 17.2 24 C19 23.8 21 23.8 22.8 24 C23.2 26.8 23 29.8 23 33",
    ],
    "film": [
        "M7.4 9.6 C15.8 9.2 24.2 9.6 32.6 9.4 C32.8 16.4 32.4 23.6 32.6 30.6 C24.2 31 15.8 30.6 7.4 30.8 C7 23.8 7.6 16.6 7.4 9.6",
        "M17 15.6 C17 18.6 16.8 21.6 17 24.6 C19.8 23 22.4 21.6 25 20 C22.4 18.6 19.8 17 17 15.6",
        "M12 9.6 C12.2 7.6 12 6.4 12.2 5",
        "M28 9.6 C28.2 7.6 28 6.4 28.2 5",
    ],
    "trophy": [
        "M12.4 7.4 C17.4 7.2 22.6 7.6 27.6 7.4 C28 13.6 27.8 19.6 20.2 22.6 C12.4 19.8 12 13.6 12.4 7.4",
        "M12.6 10.6 C8.4 10 6.6 12.6 7.6 15.6 C8.6 18 11 18.6 13.4 18",
        "M27.4 10.6 C31.6 10 33.4 12.6 32.4 15.6 C31.4 18 29 18.6 26.6 18",
        "M20.2 22.6 C20 25.4 20.2 27.6 20 30",
        "M13.6 33.2 C17.8 31 22.4 31 26.6 33.2",
    ],
    "user": [
        "M20.2 20.4 C16.4 20.6 13.8 17.6 14 14 C14.2 10.4 17 7.8 20.4 8 C23.8 8.2 26.4 11 26.2 14.4 C26 17.8 23.6 20.2 20.2 20.4",
        "M8.6 33.2 C9.4 27.4 14 23.8 20 23.8 C26 23.8 30.8 27.6 31.6 33.2",
    ],
    "settings": [
        "M6.4 13 C12 12.6 17 13.2 21.6 12.8 C21.8 9.4 26.6 8.8 27.6 11.8 C28.4 14.4 25.4 16.2 23.4 14.6 C22.4 13.8 23.2 12.6 24.4 12.8 C28 13.2 30.6 12.8 33.6 12.8",
        "M6.4 27.4 C8.4 27.2 9.8 27.4 11.4 27.2 C11.8 24 16.6 23.6 17.2 26.6 C17.8 29.4 14.6 30.8 12.8 29 C12 28.2 12.8 27 14 27.2 C20.6 27.6 27 26.8 33.6 27",
    ],
    "trash": [
        "M8 11.4 C16 11 24 11.6 32 11.2",
        "M16 11.2 C16 8.4 17 7.4 20 7.4 C23 7.4 24 8.4 24 11.2",
        "M10.8 11.6 C11.4 18.8 11.6 26 12.4 33 C17.4 33.4 22.6 33.2 27.6 33 C28.4 26 28.6 18.8 29.2 11.6",
        "M17 17 C17.2 21 17 25 17.2 28",
        "M23 17 C22.8 21 23 25 22.8 28",
    ],
    "pencil": [
        "M9.4 30.6 C10 28 10.6 25.6 11.2 23.2 C17 17.4 22.8 11.6 28.6 6.2 C30.6 7.8 32.4 9.6 33.8 11.4 C28 17.2 22.2 23 16.4 28.8 C14 29.4 11.8 30 9.4 30.6",
        "M25.2 9.6 C27 11.2 28.6 12.8 30.4 14.6",
        "M7 34 C15 33.6 23.4 34 31.6 33.6",
    ],
    "plus": ["M20 8.4 C20.2 16 19.8 24 20.2 31.6", "M8.4 20.2 C16 20 24 20.4 31.6 20"],
    "logout": [
        "M18.4 8.4 C14.6 8.2 11 8.4 8.4 8.6 C8.2 16.2 8.6 23.8 8.4 31.4 C11.2 31.6 14.8 31.4 18.6 31.6",
        "M15.6 20.2 C21.6 20 27.6 20.4 33.2 20",
        "M27.4 14 C29.4 16 31.4 18 33.2 20 C31.4 22 29.4 24 27.4 26",
    ],
    "lock": [
        "M10 18.6 C16.6 18.2 23.4 18.8 30 18.4 C30.4 23.4 30 28.4 30.2 33.4 C23.4 33.8 16.8 33.4 10 33.6 C9.8 28.6 10.2 23.6 10 18.6",
        "M14 18.4 C13.6 13.6 15.4 8.6 20 8.6 C24.6 8.6 26.4 13.4 26 18.4",
        "M20 24.2 C20.2 25.8 20 27 20.2 28.4",
    ],
}


# ---------------------------------------------------------------- line icons (48 x 48), design system v2
LINE_ICONS: dict[str, str] = {
    "accel": '<path d="M14 24 H42 M33 15 L42 24 L33 33"/><path d="M4 16 H14 M4 32 H14"/>',
    "agility": '<path d="M10 40 L22 28 L14 20 L28 8"/><path d="M19 8 H28 V17"/>',
    "back": '<path d="M30 12 L18 24 L30 36"/>',
    "ball": '<circle cx="24" cy="24" r="16"/><polygon points="24,17 30.7,21.8 28.1,29.7 19.9,29.7 17.3,21.8" fill="C" stroke="none"/>',
    "bell": '<path d="M12 34 V22 A12 12 0 0 1 36 22 V34 L40 38 H8 Z"/><path d="M20 42 H28"/>',
    "burst": '<polygon points="24.0,4.0 27.9,15.9 39.6,11.4 32.6,21.8 43.4,28.3 31.0,29.4 32.6,41.9 24.0,32.7 15.4,41.9 17.0,29.4 4.6,28.3 15.4,21.8 8.4,11.4 20.1,15.9" fill="C" stroke="none"/>',
    "calendar": '<rect x="8" y="11" width="32" height="29"/><path d="M8 19 H40 M16 6 V14 M32 6 V14"/>',
    "camera": '<rect x="6" y="14" width="36" height="26"/><path d="M17 14 L20 8 H28 L31 14"/><circle cx="24" cy="27" r="7"/>',
    "chart": '<path d="M6 38 L18 26 L26 32 L40 16"/><path d="M31 16 H40 V25"/>',
    "check": '<path d="M10 25 L20 35 L38 13"/>',
    "chevron": '<path d="M18 12 L30 24 L18 36"/>',
    "clip": '<rect x="7" y="11" width="34" height="26" rx="4"/><path d="M21 18 L30 24 L21 30 Z" fill="C" stroke="none"/>',
    "clock": '<circle cx="24" cy="24" r="16"/><path d="M24 15 V24 H32"/>',
    "close": '<path d="M12 12 L36 36 M36 12 L12 36"/>',
    "compare": '<path d="M6 24 L19 14 V34 Z M42 24 L29 14 V34 Z" fill="C" stroke="none"/>',
    "cone": '<path d="M24 8 L35 38 H13 Z"/><path d="M8 40 H40 M18.5 23 H29.5"/>',
    "cover": '<rect x="6" y="9" width="36" height="30"/><path d="M6 33 L18 22 L27 30 L33 25 L42 32"/>',
    "crop": '<path d="M14 4 V34 H44 M4 14 H34 V44"/>',
    "doc": '<path d="M12 6 H30 L38 14 V42 H12 Z"/><path d="M18 22 H32 M18 30 H32"/>',
    "download": '<path d="M24 6 V30 M14 20 L24 30 L34 20 M8 40 H40"/>',
    "eye2": '<path d="M5 24 C11 14 17 11 24 11 S37 14 43 24 C37 34 31 37 24 37 S11 34 5 24 Z"/><circle cx="24" cy="24" r="5" fill="C" stroke="none"/>',
    "flag": '<path d="M10 42 V6 M10 8 H36 L30 16 L36 24 H10"/>',
    "globe": '<circle cx="24" cy="24" r="17"/><path d="M7 24 H41 M24 7 C16 16 16 32 24 41 M24 7 C32 16 32 32 24 41"/>',
    "heart": '<path d="M24 40 C10 30 6 23 6 17 A9 9 0 0 1 24 13 A9 9 0 0 1 42 17 C42 23 38 30 24 40 Z"/>',
    "help": '<path d="M16 17 A8 8 0 1 1 26 24.5 C24.5 25.3 24 26.5 24 28.5 V30"/><circle cx="24" cy="37" r="3" fill="C" stroke="none"/>',
    "home": '<path d="M9 22 L24 9 L39 22 V39 H9 Z"/><path d="M20 39 V29 H28 V39"/>',
    "hurt": '<rect x="8" y="17" width="32" height="14" rx="7" transform="rotate(-45 24 24)"/>',
    "info": '<circle cx="24" cy="24" r="17"/><rect x="22" y="14" width="4" height="4" fill="C" stroke="none"/><path d="M24 22 V34"/>',
    "jump": '<path d="M24 36 V8 M14 18 L24 8 L34 18"/><path d="M10 42 H38"/>',
    "lock": '<rect x="10" y="22" width="28" height="20"/><path d="M16 22 V16 A8 8 0 0 1 32 16 V22"/>',
    "longpass": '<path d="M6 38 C12 14 28 10 40 18"/><path d="M31 14 L40 18 L37 27"/>',
    "mind": '<circle cx="24" cy="24" r="16"/><path d="M24 14 V24 L31 29"/>',
    "nosignal": '<path d="M8 40 H14 V34 M20 40 V26 M28 40 V18 M36 40 V10"/><path d="M6 6 L42 42"/>',
    "pace": '<path d="M27 5 L11 27 H22 L19 43 L37 19 H26 Z" fill="C" stroke="none"/>',
    "mail": '<path d="M6 12 H42 V38 H6 Z"/><path d="M6 13 L24 27 L42 13"/>',
    "pass": '<path d="M6 24 H40 M31 15 L40 24 L31 33"/>',
    "pencil": '<path d="M10 38 L12 30 L32 10 L38 16 L18 36 Z M28 14 L34 20"/>',
    "pep": '<path d="M10 24 H38" stroke-width="3"/><circle cx="24" cy="24" r="13" stroke-width="6"/><circle cx="24" cy="24" r="6.5" fill="C" stroke="none"/>',
    "pin": '<path d="M24 42 C16 32 11 25 11 19 A13 13 0 0 1 37 19 C37 25 32 32 24 42 Z"/><circle cx="24" cy="19" r="4" fill="C" stroke="none"/>',
    "play": '<path d="M16 10 L38 24 L16 38 Z" fill="C" stroke="none"/>',
    "plus": '<path d="M24 9 V39 M9 24 H39"/>',
    "search": '<circle cx="21" cy="21" r="11"/><path d="M29 29 L40 40"/>',
    "settings": '<path d="M6 14 H42 M6 34 H42"/><rect x="12" y="9" width="9" height="10" fill="C" stroke="none"/><rect x="27" y="29" width="9" height="10" fill="C" stroke="none"/>',
    "share": '<path d="M24 30 V6 M14 16 L24 6 L34 16"/><path d="M10 24 V40 H38 V24"/>',
    "shield": '<path d="M24 6 L39 12 V24 C39 32 32 38 24 42 C16 38 9 32 9 24 V12 Z"/>',
    "signout": '<path d="M20 8 H8 V40 H20 M28 14 L38 24 L28 34 M38 24 H18"/>',
    "slowmo": '<circle cx="24" cy="27" r="14"/><path d="M24 27 V19 M20 7 H28 M24 7 V13"/>',
    "spot": '<circle cx="24" cy="24" r="16"/><circle cx="24" cy="24" r="5" fill="C" stroke="none"/>',
    "stamina": '<circle cx="24" cy="27" r="14"/><path d="M24 27 V19 M20 7 H28 M24 7 V13"/>',
    "star": '<polygon points="24,6 29.3,17.8 42,19.1 32.5,27.7 35.2,40.3 24,33.8 12.8,40.3 15.5,27.7 6,19.1 18.7,17.8" fill="C" stroke="none"/>',
    "streak": '<path d="M24 6 C30 14 36 19 36 28 A12 12 0 0 1 12 28 C12 22 15 19 18 16 C18 21 20 23 22 24 C22 18 21 12 24 6 Z"/>',
    "strength": '<path d="M14 24 H34"/><rect x="6" y="15" width="8" height="18"/><rect x="34" y="15" width="8" height="18"/>',
    "tackle": '<path d="M8 36 L22 22 M22 22 L40 22"/><circle cx="34" cy="34" r="6"/>',
    "target": '<circle cx="24" cy="24" r="16"/><circle cx="24" cy="24" r="10"/><circle cx="24" cy="24" r="4"/>',
    "text": '<path d="M10 10 H38 M24 10 V40"/>',
    "trash": '<path d="M8 12 H40 M18 12 V6 H30 V12 M12 12 L14 42 H34 L36 12"/>',
    "trim": '<path d="M14 8 H8 V40 H14 M34 8 H40 V40 H34"/><path d="M20 24 H28"/>',
    "trophy": '<path d="M15 9 H33 V19 A9 9 0 0 1 15 19 Z"/><path d="M15 13 H9 A6 6 0 0 0 15 21 M33 13 H39 A6 6 0 0 1 33 21 M24 28 V35 M16 39 H32"/>',
    "up": '<path d="M12 36 L34 14 M17 14 H34 V31"/>',
    "upload": '<path d="M24 34 V8 M14 18 L24 8 L34 18 M8 40 H40"/>',
    "users": '<circle cx="18" cy="17" r="6"/><path d="M6 38 A12 12 0 0 1 30 38"/><circle cx="33" cy="19" r="5"/><path d="M33 29 A10 10 0 0 1 42 38"/>',
    "vision": '<path d="M5 24 C11 14 17 11 24 11 S37 14 43 24 C37 34 31 37 24 37 S11 34 5 24 Z"/><circle cx="24" cy="24" r="5" fill="C" stroke="none"/>',
    "you": '<circle cx="24" cy="17" r="7"/><path d="M10 40 A14 13 0 0 1 38 40"/>',
}


def line_svg(body: str, color: str = "currentColor", stroke: float = 4) -> str:
    """One line icon as a standalone SVG ("C" fills become the icon colour)."""
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" fill="none" '
        f'stroke="{color}" stroke-width="{stroke}" stroke-linecap="square" stroke-linejoin="miter">'
        + body.replace('"C"', f'"{color}"')
        + "</svg>\n"
    )


def icon_svg(paths: list[str], color: str = "currentColor", stroke: float = 2.4) -> str:
    body = "".join(f'<path d="{d}"/>' for d in paths)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40" fill="none" '
        f'stroke="{color}" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round">{body}</svg>\n'
    )


def main() -> None:
    (OUT / "brand").mkdir(parents=True, exist_ok=True)
    (OUT / "icons").mkdir(parents=True, exist_ok=True)
    (OUT / "brand" / "mark-neon.svg").write_text(mark_svg(NEON))
    (OUT / "brand" / "mark-ink.svg").write_text(mark_svg(INK))
    (OUT / "brand" / "mark-white.svg").write_text(mark_svg("#FFFFFF"))
    (OUT / "brand" / "app-icon.svg").write_text(tile_svg())
    (OUT / "brand" / "favicon.svg").write_text(tile_svg(64, mark_share=0.64, radius_share=0.24))
    for name, paths in ICONS.items():
        (OUT / "icons" / f"{name}.svg").write_text(icon_svg(paths))
    # The web UI draws icons from this file, so they can take any colour via CSS (currentColor).
    (OUT / "icons.js").write_text(
        "// Generated by scripts/build_brand.py. Edit the script, not this file.\n"
        f"export const ICONS = {json.dumps(ICONS, indent=0)};\n"
        f"export const MARK = {json.dumps(''.join(MARK))};\n"
    )
    # The Flutter app gets the same marks and icons.
    app = ROOT / "app"
    (app / "assets" / "brand").mkdir(parents=True, exist_ok=True)
    (app / "assets" / "brand" / "mark-neon.svg").write_text(mark_svg(NEON))
    (app / "assets" / "brand" / "mark-ink.svg").write_text(mark_svg(INK))
    (app / "assets" / "brand" / "app-icon.svg").write_text(tile_svg())
    dart = [
        "// Generated by scripts/build_brand.py. Edit the script, not this file.",
        "// Tracka's loopy icons: hand-drawn single-line paths on a 40 x 40 grid.",
        "",
        "const Map<String, List<String>> loopyPaths = {",
    ]
    for name, paths in ICONS.items():
        dart.append(f"  '{name}': [")
        dart += [f"    '{d}'," for d in paths]
        dart.append("  ],")
    dart += ["};", "", f"const String trackaMarkSvgBody = '{''.join(MARK)}';", ""]
    (app / "lib" / "widgets" / "loopy_icons.g.dart").write_text("\n".join(dart))
    # Line icons (design system v2): standalone SVGs for the web, and a Dart map for the app.
    (OUT / "icons" / "line").mkdir(parents=True, exist_ok=True)
    for name, body in LINE_ICONS.items():
        (OUT / "icons" / "line" / f"{name}.svg").write_text(line_svg(body))
    line_dart = [
        "// Generated by scripts/build_brand.py. Edit the script, not this file.",
        '// Tracka\'s line icons (design system v2): 48 x 48, square ends. "C" = fill in the icon colour.',
        "",
        "const Map<String, String> linePaths = {",
    ]
    # Raw single-quoted Dart strings: the SVG bodies only use double quotes.
    assert all("'" not in b for b in LINE_ICONS.values())
    line_dart += [f"  '{name}': r'{body}'," for name, body in LINE_ICONS.items()]
    line_dart += ["};", ""]
    (app / "lib" / "widgets" / "line_icons.g.dart").write_text("\n".join(line_dart))
    print(f"wrote {len(ICONS)} loopy icons, {len(LINE_ICONS)} line icons and brand files to {OUT} and {app}")


if __name__ == "__main__":
    main()
