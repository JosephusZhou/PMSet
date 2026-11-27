#!/usr/bin/env python3
"""Generate PMSet owl icons (v2, more realistic): app icon (white squircle +
black owl) and two menu-bar template icons (eyes open = awake, closed = sleep).

Usage: python3 gen_owl.py [output_dir]      (needs rsvg-convert)
"""
import json, math, os, subprocess, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "./PMSet-Owl"
os.makedirs(OUT, exist_ok=True)
W = 1024


def mx(x):
    return W - x


# ---------------------------------------------------------------- silhouette
P0 = (512, 300)  # forehead dip between the ear tufts
SEGS = [  # right half, clockwise: (ctrl1, ctrl2, end)
    ((556, 296), (590, 262), (634, 190)),   # forehead -> tuft tip
    ((654, 226), (664, 262), (668, 300)),   # tuft outer edge -> head side
    ((690, 330), (712, 372), (708, 430)),   # head bulge (facial disc width)
    ((706, 470), (722, 490), (738, 540)),   # shoulder flare
    ((756, 590), (756, 660), (722, 730)),   # body
    ((696, 780), (610, 850), (512, 862)),   # belly taper to bottom centre
]


def silhouette_path():
    d = f"M{P0[0]} {P0[1]}"
    for c1, c2, e in SEGS:
        d += f" C{c1[0]} {c1[1]} {c2[0]} {c2[1]} {e[0]} {e[1]}"
    starts = [P0] + [s[2] for s in SEGS[:-1]]
    for (c1, c2, e), s in zip(reversed(SEGS), reversed(starts)):
        d += f" C{mx(c2[0])} {c2[1]} {mx(c1[0])} {c1[1]} {mx(s[0])} {s[1]}"
    return d + " Z"


def bez(p0, p1, p2, p3, t):
    u = 1 - t
    return (
        u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
        u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1],
    )


EYES = [(436, 404), (588, 404)]
WING = ((336, 520), (316, 640), (372, 780), (462, 846))  # left folded-wing edge


def wing_x_at(y):
    best = None
    for i in range(1001):
        x, yy = bez(*WING, i / 1000)
        if best is None or abs(yy - y) < best[0]:
            best = (abs(yy - y), x)
    return best[1]


def stroke(d, w, col="#fff"):
    return (
        f'<path d="{d}" stroke="{col}" stroke-width="{w}" stroke-linecap="round" '
        f'stroke-linejoin="round" fill="none"/>'
    )


# ---------------------------------------------------------------- app icon
def owl_app():
    s = []
    s.append(f'<path d="{silhouette_path()}" fill="#000"/>')

    # branch + talons (white outline separates toes from branch / belly)
    s.append(stroke("M300 900 Q512 918 724 896", 30, "#000"))
    for cx in (452, 572):
        toes = [(cx - 32, 884), (cx, 892), (cx + 32, 884)]
        for tx, ty in toes:
            s.append(stroke(f"M{cx} 854 L{tx} {ty}", 30, "#fff"))
        for tx, ty in toes:
            s.append(stroke(f"M{cx} 854 L{tx} {ty}", 19, "#000"))

    # ear-tuft feather lines
    for flip in (False, True):
        f = mx if flip else (lambda x: x)
        s.append(stroke(f"M{f(626)} 264 L{f(634)} 216", 4.5))

    # facial disc: two overlapping circles -> heart-shaped outline
    r = 92
    for cx, cy in EYES:
        s.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#fff" stroke-width="5"/>')
    for cx, cy in EYES:
        s.append(f'<circle cx="{cx}" cy="{cy}" r="{r - 2.6}" fill="#000"/>')

    # eyes: pale iris, pupil, stern slanted lid, highlight
    for i, (cx, cy) in enumerate(EYES):
        inner = 1 if i == 0 else -1  # +1: centre lies to the right
        s.append(f'<circle cx="{cx}" cy="{cy}" r="52" fill="#fff"/>')
        s.append(f'<circle cx="{cx}" cy="{cy}" r="32" fill="#000"/>')
        # lid: outer side high, inner side low
        xo, xi = cx - inner * 56, cx + inner * 56
        s.append(
            f'<path d="M{xo} {cy - 36} L{xi} {cy - 8} L{xi} {cy - 58} L{xo} {cy - 58} Z" fill="#000"/>'
        )
        s.append(f'<circle cx="{cx + 9}" cy="{cy + 3}" r="7" fill="#fff"/>')

    # hooked beak
    s.append(
        '<path d="M499 436 Q512 423 525 436 Q528 462 512 490 Q496 462 499 436 Z" fill="#fff"/>'
    )
    s.append(stroke("M512 438 L512 470", 3.5, "#000"))

    # folded wings: edge line + outward feather ticks
    for flip in (False, True):
        f = mx if flip else (lambda x: x)
        p = [(f(x), y) for x, y in WING]
        s.append(
            stroke(
                f"M{p[0][0]} {p[0][1]} C{p[1][0]} {p[1][1]} {p[2][0]} {p[2][1]} {p[3][0]} {p[3][1]}",
                7,
            )
        )
        for t in (0.28, 0.44, 0.6, 0.76):
            x, y = bez(*p, t)
            dx = 28 if flip else -28
            s.append(stroke(f"M{x:.1f} {y:.1f} L{x + dx:.1f} {y + 13:.1f}", 5.5))

    # chest: leaf-shaped streaks
    for r_i, y in enumerate(range(556, 832, 46)):
        half = 512 - wing_x_at(y) - 34
        off = 0.0 if r_i % 2 == 0 else 0.5
        L = 17 - r_i * 0.7
        wd = 13 - r_i * 0.5
        for k in range(-6, 7):
            x = 512 + (k + off) * 42
            if abs(x - 512) > half:
                continue
            s.append(
                f'<path d="M{x:.1f} {y - L:.1f} Q{x + wd:.1f} {y} {x:.1f} {y + L:.1f} '
                f'Q{x - wd:.1f} {y} {x:.1f} {y - L:.1f} Z" fill="#fff"/>'
            )
    return "\n".join(s)


def squircle(a=412, n=5.0, cx=512, cy=512, steps=240):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, sn = math.cos(t), math.sin(t)
        x = cx + a * math.copysign(abs(c) ** (2 / n), c)
        y = cy + a * math.copysign(abs(sn) ** (2 / n), sn)
        pts.append(f"{x:.1f} {y:.1f}")
    return "M" + " L".join(pts) + " Z"


def app_icon_svg():
    sq = squircle()
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <filter id="sh" x="-20%" y="-20%" width="140%" height="150%">
    <feGaussianBlur in="SourceAlpha" stdDeviation="14"/>
    <feOffset dy="10" result="b"/>
    <feFlood flood-color="#000" flood-opacity="0.28"/>
    <feComposite in2="b" operator="in"/>
    <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
</defs>
<path d="{sq}" fill="#fff" filter="url(#sh)"/>
<path d="{sq}" fill="none" stroke="#000" stroke-opacity="0.10" stroke-width="2"/>
<g transform="translate(512 512) scale(0.86) translate(-512 -546)">
{owl_app()}
</g>
</svg>
"""


# ---------------------------------------------------------------- menu bar
def menubar_svg(awake):
    holes = []
    for cx, cy in EYES:
        if awake:
            st = os.environ.get("EYE_STYLE", "B")
            if st == "ring":
                holes.append(f'<circle cx="{cx}" cy="{cy}" r="64" fill="#000"/>')
                holes.append(f'<circle cx="{cx}" cy="{cy + 3}" r="33" fill="#fff"/>')
            elif st == "A":  # thin ring, big pupil
                holes.append(f'<circle cx="{cx}" cy="{cy}" r="58" fill="#000"/>')
                holes.append(f'<circle cx="{cx}" cy="{cy + 3}" r="43" fill="#fff"/>')
            elif st == "B":  # thin ring, big pupil, catchlight
                holes.append(f'<circle cx="{cx}" cy="{cy}" r="60" fill="#000"/>')
                holes.append(f'<circle cx="{cx}" cy="{cy + 3}" r="43" fill="#fff"/>')
                holes.append(f'<circle cx="{cx + 14}" cy="{cy - 7}" r="12" fill="#000"/>')
            elif st == "D":  # soft oval eyes
                holes.append(f'<ellipse cx="{cx}" cy="{cy + 2}" rx="46" ry="60" fill="#000"/>')
                holes.append(f'<ellipse cx="{cx}" cy="{cy + 12}" rx="31" ry="40" fill="#fff"/>')
                holes.append(f'<circle cx="{cx + 11}" cy="{cy - 4}" r="10" fill="#000"/>')
        else:
            holes.append(
                stroke(f"M{cx - 56} {cy - 6} Q{cx} {cy + 48} {cx + 56} {cy - 6}", 27, "#000")
            )
    holes.append('<path d="M497 448 L527 448 L512 486 Z" fill="#000"/>')  # beak notch
    for flip in (False, True):  # wing edges
        f = mx if flip else (lambda x: x)
        p = [(f(x), y) for x, y in WING]
        pts = [bez(*p, i / 40 * 0.84) for i in range(41)]  # stop short of the bottom edge
        holes.append(
            stroke("M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts), 14, "#000")
        )
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
    <rect width="1024" height="1024" fill="#fff"/>
    {''.join(holes)}
  </mask>
</defs>
<g transform="translate(512 512) scale(1.32) translate(-512 -526)">
  <path d="{silhouette_path()}" fill="#000" mask="url(#m)"/>
</g>
</svg>
"""


# ---------------------------------------------------------------- export
def rsvg(svg, png, px):
    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), svg, "-o", png], check=True)


def write(path, text):
    with open(path, "w") as fh:
        fh.write(text)


write(f"{OUT}/AppIcon.svg", app_icon_svg())
write(f"{OUT}/MenuBarIcon-Awake.svg", menubar_svg(True))   # lid closed, NO sleep -> eyes open
write(f"{OUT}/MenuBarIcon-Sleep.svg", menubar_svg(False))  # lid closed, sleep    -> eyes closed
rsvg(f"{OUT}/AppIcon.svg", f"{OUT}/AppIcon-1024.png", 1024)

aset = f"{OUT}/Assets.xcassets/AppIcon.appiconset"
os.makedirs(aset, exist_ok=True)
images = []
for pt in (16, 32, 128, 256, 512):
    for sc in (1, 2):
        name = f"icon_{pt}x{pt}{'@2x' if sc == 2 else ''}.png"
        rsvg(f"{OUT}/AppIcon.svg", f"{aset}/{name}", pt * sc)
        images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{sc}x", "filename": name})
write(f"{aset}/Contents.json", json.dumps({"images": images, "info": {"version": 1, "author": "xcode"}}, indent=2))

for key, svg in (("MenuBarAwake", "MenuBarIcon-Awake.svg"), ("MenuBarSleep", "MenuBarIcon-Sleep.svg")):
    d = f"{OUT}/Assets.xcassets/{key}.imageset"
    os.makedirs(d, exist_ok=True)
    imgs = []
    for sc in (1, 2, 3):
        name = f"{key}{'@%dx' % sc if sc > 1 else ''}.png"
        rsvg(f"{OUT}/{svg}", f"{d}/{name}", 18 * sc)
        imgs.append({"idiom": "universal", "filename": name, "scale": f"{sc}x"})
    write(
        f"{d}/Contents.json",
        json.dumps(
            {
                "images": imgs,
                "info": {"version": 1, "author": "xcode"},
                "properties": {"template-rendering-intent": "template"},
            },
            indent=2,
        ),
    )
print("ok", OUT)
