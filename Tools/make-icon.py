"""Nightshift app icon – pure-Python rasteriser (no PIL on the build host).

A crescent moon with a pair of beamed eighth notes, in the web UI's
night-shift accent on black.

The mark is not placed by eye: it is drawn in unit space, measured with a
low-resolution pass, and then scaled and shifted so it sits optically centred
and fills a fixed share of the canvas. Balance is computed, not guessed.
"""
import math, os, pathlib, struct, sys, zlib

S = 1024                  # output size
MEASURE = 256             # resolution of the measuring pass
COVERAGE = 0.74           # share of the canvas the mark spans
OPTICAL_LIFT = 0.000      # pure centring: see the note in __main__

# --- palette (matches static/style.css) --------------------------------
BG_TOP    = (0x00, 0x00, 0x00)
BG_BOTTOM = (0x15, 0x15, 0x19)
DEFAULT_INK = "FFB03A"           # --accent of the night shift theme

# The alternate app icons, keyed by the name iOS switches on. The primary icon
# is the accent orange and lives in the asset catalog, so it is not listed.
ALTERNATES = {
    "Indigo": "5856D6",
    "Blue":   "0A84FF",
    "Teal":   "30B0C7",
    "Green":  "34C759",
    "Red":    "FF3B30",
    "Pink":   "FF375F",
    "Purple": "AF52DE",
}
ALTERNATE_SIZES = {"@2x": 120, "@3x": 180}   # 60 pt icon on iPhone


def _rgb(hex_value):
    v = int(hex_value, 16)
    return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)


def _shade(rgb, amount):
    """Positive lightens towards white, negative deepens towards black."""
    if amount >= 0:
        return tuple(int(c + (255 - c) * amount) for c in rgb)
    return tuple(int(c * (1 + amount)) for c in rgb)


def ink_pair(hex_value):
    """Top and bottom colour of the mark's subtle vertical gradient."""
    base = _rgb(hex_value)
    return _shade(base, 0.14), _shade(base, -0.08)


# --- shape primitives: all return a signed distance in unit space -------

def sd_disc(x, y, cx, cy, r):
    return math.hypot(x - cx, y - cy) - r


def sd_ellipse(x, y, cx, cy, rx, ry, angle):
    dx, dy = x - cx, y - cy
    c, s = math.cos(-angle), math.sin(-angle)
    ex, ey = (dx * c - dy * s) / rx, (dx * s + dy * c) / ry
    return (math.hypot(ex, ey) - 1.0) * min(rx, ry)


def sd_capsule(x, y, x1, y1, x2, y2, w):
    """Thick line segment with round caps – stems and the beam."""
    vx, vy = x2 - x1, y2 - y1
    wx, wy = x - x1, y - y1
    denom = vx * vx + vy * vy
    t = 0.0 if denom == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / denom))
    return math.hypot(wx - vx * t, wy - vy * t) - w / 2


# --- the mark, in unit space -------------------------------------------
# Crescent: a disc with a second disc taken out of it.
MOON = (0.400, 0.600, 0.288)
BITE = (0.532, 0.470, 0.276)

# Two beamed eighth notes, defined around their own centre so the group can be
# moved and resized as one. Placed relative to the moon: the closer and smaller
# the group, the more the mark reads as one shape instead of two.
NOTE_OFFSET = (0.256, -0.138)     # from the moon's centre
NOTE_SCALE = 0.92
HEAD_TILT = -0.32
_HEAD_RX, _HEAD_RY = 0.068, 0.054
_STEM_W, _BEAM_W = 0.027, 0.054
_HEAD_1, _HEAD_2 = (-0.094, 0.114), (0.092, 0.066)
_STEM_1_TOP, _STEM_2_TOP = (-0.037, -0.094), (0.149, -0.142)


def _place(point):
    return (MOON[0] + NOTE_OFFSET[0] + point[0] * NOTE_SCALE,
            MOON[1] + NOTE_OFFSET[1] + point[1] * NOTE_SCALE)


HEAD_RX, HEAD_RY = _HEAD_RX * NOTE_SCALE, _HEAD_RY * NOTE_SCALE
STEM_W, BEAM_W = _STEM_W * NOTE_SCALE, _BEAM_W * NOTE_SCALE
HEAD_1, HEAD_2 = _place(_HEAD_1), _place(_HEAD_2)
STEM_1_TOP, STEM_2_TOP = _place(_STEM_1_TOP), _place(_STEM_2_TOP)


def mark_distance(x, y):
    """Signed distance to the whole mark (negative = inside)."""
    moon = max(sd_disc(x, y, *MOON), -sd_disc(x, y, *BITE))

    stem_1 = (HEAD_1[0] + HEAD_RX - STEM_W / 2, HEAD_1[1])
    stem_2 = (HEAD_2[0] + HEAD_RX - STEM_W / 2, HEAD_2[1])
    note = min(
        sd_ellipse(x, y, HEAD_1[0], HEAD_1[1], HEAD_RX, HEAD_RY, HEAD_TILT),
        sd_ellipse(x, y, HEAD_2[0], HEAD_2[1], HEAD_RX, HEAD_RY, HEAD_TILT),
        sd_capsule(x, y, stem_1[0], stem_1[1], STEM_1_TOP[0], STEM_1_TOP[1], STEM_W),
        sd_capsule(x, y, stem_2[0], stem_2[1], STEM_2_TOP[0], STEM_2_TOP[1], STEM_W),
        sd_capsule(x, y, STEM_1_TOP[0], STEM_1_TOP[1] + BEAM_W / 4,
                   STEM_2_TOP[0], STEM_2_TOP[1] + BEAM_W / 4, BEAM_W),
    )
    return min(moon, note)


def measure():
    """Bounding box and centre of mass of the mark, in unit coordinates."""
    x0, y0, x1, y1 = 1.0, 1.0, 0.0, 0.0
    sx = sy = mass = 0.0
    for j in range(MEASURE):
        v = (j + 0.5) / MEASURE
        for i in range(MEASURE):
            u = (i + 0.5) / MEASURE
            if mark_distance(u, v) <= 0:
                x0, y0 = min(x0, u), min(y0, v)
                x1, y1 = max(x1, u), max(y1, v)
                sx, sy, mass = sx + u, sy + v, mass + 1
    return (x0, y0, x1, y1), (sx / mass, sy / mass)


def render(scale, ox, oy, ink_top, ink_bottom, size=S,
           transparent=False, mark_scale=1.0):
    """Rasterise the mark. `transparent` yields RGBA on a clear background –
    Android's adaptive icon draws the mark over its own background layer.
    `mark_scale` shrinks the mark inside the canvas, for the safe zone that
    adaptive icons crop to."""
    S = size
    stride = 4 if transparent else 3
    px = bytearray(S * S * stride)
    if mark_scale != 1.0:
        ox = 0.5 - (0.5 - ox) * mark_scale
        oy = (0.5 - OPTICAL_LIFT) - ((0.5 - OPTICAL_LIFT) - oy) * mark_scale
        scale *= mark_scale
    for y in range(S):
        fy = (y + 0.5) / S
        t = fy
        bg = (BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t,
              BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t,
              BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
        ink = (ink_top[0] + (ink_bottom[0] - ink_top[0]) * t,
               ink_top[1] + (ink_bottom[1] - ink_top[1]) * t,
               ink_top[2] + (ink_bottom[2] - ink_top[2]) * t)
        row = y * S * stride
        uy = (fy - oy) / scale
        for x in range(S):
            fx = (x + 0.5) / S
            ux = (fx - ox) / scale
            # distance in unit space -> pixels, for a 1 px soft edge
            d = mark_distance(ux, uy) * scale * S
            a = min(1.0, max(0.0, 0.5 - d))
            i = row + x * stride
            if transparent:
                px[i] = int(ink[0] + .5)
                px[i + 1] = int(ink[1] + .5)
                px[i + 2] = int(ink[2] + .5)
                px[i + 3] = int(a * 255 + .5)
            elif a <= 0.0:
                px[i], px[i + 1], px[i + 2] = (int(bg[0] + .5), int(bg[1] + .5),
                                               int(bg[2] + .5))
            else:
                px[i] = int(bg[0] + (ink[0] - bg[0]) * a + .5)
                px[i + 1] = int(bg[1] + (ink[1] - bg[1]) * a + .5)
                px[i + 2] = int(bg[2] + (ink[2] - bg[2]) * a + .5)
    return bytes(px)


def write_png(path, w, h, pixels, alpha=False):
    stride = 4 if alpha else 3
    raw = b"".join(b"\x00" + pixels[y * w * stride:(y + 1) * w * stride]
                   for y in range(h))
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8,
                                      6 if alpha else 2, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(raw, 9))
    out += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(out)


def placed_geometry(scale, ox, oy):
    """The mark's geometry after centring, in unit coordinates.

    The SwiftUI version of the mark (launch screen) draws from these numbers,
    so artwork and icon are the same shape by construction.
    """
    def pt(p):
        return (p[0] * scale + ox, p[1] * scale + oy)

    stem_1 = (HEAD_1[0] + HEAD_RX - STEM_W / 2, HEAD_1[1])
    stem_2 = (HEAD_2[0] + HEAD_RX - STEM_W / 2, HEAD_2[1])
    return {
        "moon": (pt((MOON[0], MOON[1])), MOON[2] * scale),
        "bite": (pt((BITE[0], BITE[1])), BITE[2] * scale),
        "head1": pt(HEAD_1), "head2": pt(HEAD_2),
        "headRX": HEAD_RX * scale, "headRY": HEAD_RY * scale,
        "headTilt": HEAD_TILT,
        "stem1": (pt(stem_1), pt(STEM_1_TOP)),
        "stem2": (pt(stem_2), pt(STEM_2_TOP)),
        "beam": (pt((STEM_1_TOP[0], STEM_1_TOP[1] + BEAM_W / 4)),
                 pt((STEM_2_TOP[0], STEM_2_TOP[1] + BEAM_W / 4))),
        "stemW": STEM_W * scale, "beamW": BEAM_W * scale,
    }


def write_svg(path, g):
    """The mark as SVG, drawn with `currentColor` so a page can tint it.

    The crescent is a disc with the bite masked out — the same construction the
    rasteriser and both apps use, expressed in SVG's own vocabulary.
    """
    def pct(v):
        return round(v * 100, 4)

    (mx, my), mr = g["moon"]
    (bx, by), br = g["bite"]
    heads = "".join(
        '\n    <ellipse cx="%s" cy="%s" rx="%s" ry="%s" transform="rotate(%s %s %s)"/>'
        % (pct(h[0]), pct(h[1]), pct(g["headRX"]), pct(g["headRY"]),
           round(math.degrees(g["headTilt"]), 3), pct(h[0]), pct(h[1]))
        for h in (g["head1"], g["head2"]))
    lines = "".join(
        '\n    <line x1="%s" y1="%s" x2="%s" y2="%s" stroke="currentColor" '
        'stroke-width="%s" stroke-linecap="round"/>'
        % (pct(a[0]), pct(a[1]), pct(b[0]), pct(b[1]), pct(w))
        for a, b, w in ((g["stem1"][0], g["stem1"][1], g["stemW"]),
                        (g["stem2"][0], g["stem2"][1], g["stemW"]),
                        (g["beam"][0], g["beam"][1], g["beamW"])))

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Nightshift">
  <mask id="bite">
    <rect width="100" height="100" fill="white"/>
    <circle cx="{pct(bx)}" cy="{pct(by)}" r="{pct(br)}" fill="black"/>
  </mask>
  <g fill="currentColor">
    <circle cx="{pct(mx)}" cy="{pct(my)}" r="{pct(mr)}" mask="url(#bite)"/>{heads}{lines}
  </g>
</svg>
"""
    pathlib.Path(path).write_text(svg)
    print("written", path)


def print_swift(g):
    def p(v):
        return "CGPoint(x: %.4f, y: %.4f)" % v
    print("    static let moonCentre = %s" % p(g["moon"][0]))
    print("    static let moonRadius: CGFloat = %.4f" % g["moon"][1])
    print("    static let biteCentre = %s" % p(g["bite"][0]))
    print("    static let biteRadius: CGFloat = %.4f" % g["bite"][1])
    print("    static let head1 = %s" % p(g["head1"]))
    print("    static let head2 = %s" % p(g["head2"]))
    print("    static let headRX: CGFloat = %.4f" % g["headRX"])
    print("    static let headRY: CGFloat = %.4f" % g["headRY"])
    print("    static let headTilt: CGFloat = %.4f" % g["headTilt"])
    print("    static let stem1 = (%s, %s)" % (p(g["stem1"][0]), p(g["stem1"][1])))
    print("    static let stem2 = (%s, %s)" % (p(g["stem2"][0]), p(g["stem2"][1])))
    print("    static let beam = (%s, %s)" % (p(g["beam"][0]), p(g["beam"][1])))
    print("    static let stemWidth: CGFloat = %.4f" % g["stemW"])
    print("    static let beamWidth: CGFloat = %.4f" % g["beamW"])


if __name__ == "__main__":
    (x0, y0, x1, y1), (cmx, cmy) = measure()
    scale = COVERAGE / max(x1 - x0, y1 - y0)
    # Centre on the bounding box. Blending in the centre of mass was worse in
    # practice: the moon far outweighs the notes, so the mark drifted up and to
    # the right until the beam nearly touched the corner while the bottom kept a
    # fat margin. Even margins read better than a weighted centre here.
    cx = (x0 + x1) / 2
    cy = (y0 + y1) / 2
    ox = 0.5 - cx * scale
    oy = (0.5 - OPTICAL_LIFT) - cy * scale
    if "--svg" in sys.argv:
        write_svg(sys.argv[sys.argv.index("--svg") + 1],
                  placed_geometry(scale, ox, oy))
        raise SystemExit(0)

    if "--swift" in sys.argv:
        print_swift(placed_geometry(scale, ox, oy))
        raise SystemExit(0)

    if "--alternates" in sys.argv:
        out_dir = sys.argv[sys.argv.index("--alternates") + 1]
        os.makedirs(out_dir, exist_ok=True)
        for name, hex_value in ALTERNATES.items():
            top, bottom = ink_pair(hex_value)
            for suffix, size in ALTERNATE_SIZES.items():
                path = os.path.join(out_dir, "icon-%s%s.png"
                                    % (name.lower(), suffix))
                write_png(path, size, size,
                          render(scale, ox, oy, top, bottom, size))
                print("written", path)
        raise SystemExit(0)

    if "--android" in sys.argv:
        out_dir = sys.argv[sys.argv.index("--android") + 1]
        top, bottom = ink_pair(DEFAULT_INK)
        # Legacy launcher icon, plus the foreground layer of the adaptive icon.
        # Adaptive foregrounds are 108 dp with only the middle 72 dp guaranteed
        # visible, hence the shrink — 0.66 leaves a comfortable ring around it.
        for density, launcher, adaptive in (("mdpi", 48, 108), ("hdpi", 72, 162),
                                            ("xhdpi", 96, 216), ("xxhdpi", 144, 324),
                                            ("xxxhdpi", 192, 432)):
            folder = os.path.join(out_dir, "mipmap-" + density)
            os.makedirs(folder, exist_ok=True)
            square = render(scale, ox, oy, top, bottom, launcher)
            for name in ("ic_launcher.png", "ic_launcher_round.png"):
                write_png(os.path.join(folder, name), launcher, launcher, square)
            write_png(os.path.join(folder, "ic_launcher_foreground.png"),
                      adaptive, adaptive,
                      render(scale, ox, oy, top, bottom, adaptive,
                             transparent=True, mark_scale=0.66),
                      alpha=True)
            print("written", folder)
        raise SystemExit(0)

    print("bbox %.3f,%.3f – %.3f,%.3f  mass %.3f,%.3f  scale %.3f"
          % (x0, y0, x1, y1, cmx, cmy, scale))
    top, bottom = ink_pair(DEFAULT_INK)
    write_png(sys.argv[1], S, S, render(scale, ox, oy, top, bottom))
    print("written", sys.argv[1])
