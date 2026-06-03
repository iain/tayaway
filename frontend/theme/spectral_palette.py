#!/usr/bin/env python3
"""
Spectral palette generator for Tayaway.

Tayaway colors all resolve through Tailwind's named ramps (`bg-amber-500`,
`text-stone-300`, …) plus a layer of semantic tokens in `src/style.css`. This
script rebases every one of those ramps on the OKLCH seeds from the *spectral*
terminal/editor colorscheme (https://github.com/iain/spectral), so the whole
app inherits spectral's character — a warm amber signature, a single warm
neutral hue, and an equiluminant accent band — without editing a single
component.

It does for the web app what `spectral/tools/palette.py` does for the editor:
one OKLCH source of truth, emitted into a generated file. Edit the SEEDS dict
below and run this script to regenerate `src/spectral-ramps.css`.

OKLCH triples are (L, C, H):
  L  lightness, 0=black 1=white (perceptually uniform)
  C  chroma, 0=gray; out-of-gamut chroma is reduced by bisection (L and H are
     preserved, so the hue never drifts — it just desaturates as needed)
  H  hue in degrees: 0=pink, 30=orange, 98=yellow, 135=green, 195=cyan,
     255=blue, 320=purple
"""
from __future__ import annotations

import math
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "src" / "spectral-ramps.css"

# Warm neutral hue — the heart of spectral. Every gray in the app shares this
# yellow-orange hue at very low chroma, so neutrals read as warm paper / amber
# phosphor rather than cool slate. Matches spectral's NEUTRAL_HUE.
NEUTRAL_HUE = 85.0

# --------------------------------------------------------------------------
# Seeds. Hues come straight from spectral's accent definitions; chroma is the
# ramp's peak (reached around the 500 step and tapered toward both ends by
# CHROMA_SCALE below). Families spectral doesn't define (rose, sky, …) are
# interpolated into its wheel so they sit in the same equiluminant band.
# --------------------------------------------------------------------------

# Chromatic families: hue, peak chroma.
ACCENTS: dict[str, tuple[float, float]] = {
    "amber": (75, 0.165),   # spectral signature — Tayaway's nav + accents
    "yellow": (98, 0.175),  # spectral yellow — warnings
    "orange": (50, 0.180),  # spectral orange — pending
    "red": (27, 0.205),     # spectral red — urgent / danger
    "rose": (12, 0.190),    # pinker sibling of red — primary action / focus
    "pink": (354, 0.180),
    "purple": (320, 0.165),  # spectral purple
    "violet": (300, 0.160),
    "indigo": (276, 0.160),
    "blue": (255, 0.160),    # spectral blue — info
    "sky": (230, 0.135),
    "cyan": (195, 0.125),    # spectral cyan — inflow / links
    "teal": (180, 0.130),
    "emerald": (155, 0.150),
    "green": (135, 0.190),   # spectral green — success
    "lime": (125, 0.180),
}

# Per-step lightness for the chromatic ramps, and the fraction of peak chroma
# each step carries. Chroma peaks mid-ramp and falls off toward white/black —
# the natural shape of the sRGB gamut, and what keeps tints from looking muddy.
STEPS = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]

ACCENT_L = {
    50: 0.972, 100: 0.939, 200: 0.890, 300: 0.820, 400: 0.730,
    500: 0.650, 600: 0.575, 700: 0.505, 800: 0.445, 900: 0.395, 950: 0.300,
}
CHROMA_SCALE = {
    50: 0.20, 100: 0.34, 200: 0.55, 300: 0.75, 400: 0.93,
    500: 1.00, 600: 0.98, 700: 0.90, 800: 0.80, 900: 0.70, 950: 0.50,
}

# The eye reads warm hues (amber, yellow, green) as dimmer than reds/blues at
# equal lightness, so a flat lightness ramp leaves them muddy — spectral itself
# sits its amber at L0.80 and yellow at L0.88 against red's L0.68. L_LIFT raises
# those hues into their natural brightness; LIFT_WEIGHT applies it across the
# light-to-mid steps (where the signature lives, e.g. the amber nav) and fades
# out by the 900/950 dark fills so those stay deep.
L_LIFT = {
    "amber": 0.11, "yellow": 0.16, "lime": 0.13, "green": 0.13,
    "emerald": 0.07, "orange": 0.05,
}
LIFT_WEIGHT = {
    50: 0.70, 100: 0.90, 200: 1.00, 300: 1.00, 400: 1.00,
    500: 1.00, 600: 0.80, 700: 0.55, 800: 0.30, 900: 0.12, 950: 0.00,
}

# Neutral ramps (gray/stone/slate/zinc/neutral all collapse onto one warm
# ramp). Wider lightness span than the accents — neutrals carry the page from
# near-white surfaces to near-black dark-mode fills. Chroma is tiny and leans
# into the lighter steps, the way warm paper holds more tint than deep shadow.
NEUTRAL_L = {
    50: 0.985, 100: 0.969, 200: 0.930, 300: 0.875, 400: 0.720,
    500: 0.560, 600: 0.448, 700: 0.378, 800: 0.272, 900: 0.213, 950: 0.150,
}
NEUTRAL_PEAK_C = 0.013
NEUTRAL_CHROMA_SCALE = {
    50: 1.30, 100: 1.20, 200: 1.10, 300: 1.00, 400: 0.85,
    500: 0.70, 600: 0.60, 700: 0.55, 800: 0.45, 900: 0.40, 950: 0.35,
}
NEUTRALS = ["gray", "slate", "zinc", "neutral", "stone"]

# Spectral's signature amber — the exact OKLCH of its Ruby-symbol / directory
# color (#F9AD26). Bright enough to glow on both warm-paper and OLED-black, so
# the navbar wears it mode-independently. `strong` is the pressed/active shade,
# `soft` the hover shade — same hue, lightness stepped either side of the base.
SIGNATURE = {
    "": (0.80, 0.16, 75),         # base — bg-nav
    "-strong": (0.705, 0.155, 75),  # nav-active
    "-soft": (0.88, 0.135, 75),    # nav-hover
}


# --------------------------------------------------------------------------
# OKLCH → sRGB (Björn Ottosson), with bisection gamut-mapping. Lifted from
# spectral/tools/palette.py so both projects clamp identically.
# --------------------------------------------------------------------------

def oklab_to_linear_srgb(L: float, a: float, b: float) -> tuple[float, float, float]:
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_**3, m_**3, s_**3
    return (
        +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )


def in_gamut(rgb_linear: tuple[float, float, float]) -> bool:
    return all(-1e-6 <= c <= 1 + 1e-6 for c in rgb_linear)


def gamut_chroma(L: float, C: float, H: float) -> float:
    """Largest chroma <= C that stays inside sRGB at this L and H."""
    h_rad = math.radians(H)

    def at(c: float) -> tuple[float, float, float]:
        return oklab_to_linear_srgb(L, c * math.cos(h_rad), c * math.sin(h_rad))

    if in_gamut(at(C)):
        return C
    lo, hi = 0.0, C
    for _ in range(24):
        mid = (lo + hi) / 2
        if in_gamut(at(mid)):
            lo = mid
        else:
            hi = mid
    return lo


def _num(x: float, places: int) -> str:
    """Round to `places` decimals and drop trailing zeros (prettier-clean)."""
    return f"{round(x, places):.{places}f}".rstrip("0").rstrip(".")


def oklch_css(L: float, C: float, H: float) -> str:
    """A CSS `oklch()` literal, chroma reduced into sRGB so no browser clamps
    it differently. Hue is dropped when chroma rounds to zero (pure gray)."""
    c = gamut_chroma(L, C, H)
    if round(c, 4) == 0:
        return f"oklch({_num(L, 3)} 0 0)"
    return f"oklch({_num(L, 3)} {_num(c, 4)} {_num(H, 3)})"


# --------------------------------------------------------------------------
# Emit
# --------------------------------------------------------------------------

def ramp(name: str, hue: float, peak_c: float, l_by_step: dict, scale: dict,
         lift: float = 0.0) -> list[str]:
    lines = []
    for step in STEPS:
        L = min(0.995, l_by_step[step] + lift * LIFT_WEIGHT[step])
        C = peak_c * scale[step]
        lines.append(f"  --color-{name}-{step}: {oklch_css(L, C, hue)};")
    return lines


def main() -> None:
    out = [
        "/* GENERATED by theme/spectral_palette.py — do not hand-edit.",
        " *",
        " * Tailwind's named color ramps, rebased on the OKLCH seeds from the",
        " * spectral colorscheme: a warm amber signature, one warm neutral hue,",
        " * and an equiluminant accent band. Overriding the ramps here recolors",
        " * every `*-amber-500` / `*-stone-300` utility across the app at once;",
        " * the semantic tokens in style.css then resolve through these. */",
        "",
        "@theme {",
        "  /* Warm neutrals — gray/slate/zinc/neutral/stone all share spectral's",
        f"   * yellow-orange neutral hue ({NEUTRAL_HUE:g}deg) at a whisper of chroma. */",
    ]
    for name in NEUTRALS:
        out += ramp(name, NEUTRAL_HUE, NEUTRAL_PEAK_C, NEUTRAL_L, NEUTRAL_CHROMA_SCALE)
        out.append("")

    out.append("  /* Accents — spectral's wheel, in one equiluminant band. */")
    for name, (hue, peak_c) in ACCENTS.items():
        out += ramp(name, hue, peak_c, ACCENT_L, CHROMA_SCALE, L_LIFT.get(name, 0.0))
        out.append("")

    out.append("  /* Signature — spectral's amber (#F9AD26), promoted to the nav. */")
    for suffix, (L, C, H) in SIGNATURE.items():
        out.append(f"  --color-signature{suffix}: {oklch_css(L, C, H)};")

    if out[-1] == "":
        out.pop()
    out.append("}")
    out.append("")

    OUT.write_text("\n".join(out))
    n = len(NEUTRALS) + len(ACCENTS)
    print(f"wrote {OUT.relative_to(OUT.parents[2])} — {n} ramps x {len(STEPS)} steps")


if __name__ == "__main__":
    main()
