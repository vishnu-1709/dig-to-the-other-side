"""Generate all game art from code: per-biome tile atlases, parallax backgrounds, the drill
character, particle/glow textures. SVG -> PNG via headless Chromium (Playwright).

Run: python3 tools/art/gen_tiles.py
Outputs to assets/art/. Every texture is deterministic (fixed seeds).
"""
import math, os, random
from playwright.sync_api import sync_playwright

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "art")
os.makedirs(OUT, exist_ok=True)
T = 96  # tile px (drawn at 64 world units, so crisp at ~1.5x zoom)

# rock base, rock dark, accent, ore main, ore light, hazard, background
BIOMES = [
    dict(id="topsoil", rock="#8a5d38", dark="#5a3a22", acc="#a8784c", ore="#e8893a", ore2="#ffd0a0", haz="#ff4d4d", bg="#2a1a10", motif="pebbles"),
    dict(id="fossil",  rock="#c2a878", dark="#8a7450", acc="#e8dcc0", ore="#ffb52e", ore2="#fff0b8", haz="#ff6a3d", bg="#3a2c1a", motif="bones"),
    dict(id="ruins",   rock="#6f7363", dark="#474a3e", acc="#9aa08a", ore="#ffd84a", ore2="#fff6c0", haz="#ff3d6e", bg="#1f231c", motif="bricks"),
    dict(id="crystal", rock="#3e3075", dark="#271d52", acc="#5c4aa6", ore="#7ff3ff", ore2="#ffffff", haz="#ff5cf0", bg="#120d2e", motif="specks"),
    dict(id="magma",   rock="#3a1a16", dark="#1f0c0a", acc="#ff7a2a", ore="#c86bff", ore2="#f0d0ff", haz="#ffb020", bg="#1a0806", motif="lava"),
    dict(id="core",    rock="#7a2c0e", dark="#4a1606", acc="#ffb347", ore="#fff27a", ore2="#ffffff", haz="#ff2a2a", bg="#2a0a02", motif="veins"),
    dict(id="mirror",  rock="#3a4f78", dark="#24324f", acc="#c8d8ff", ore="#d6f0ff", ore2="#ffffff", haz="#ff4da6", bg="#0e1424", motif="sheen"),
    dict(id="alien",   rock="#2f6a45", dark="#1a3f28", acc="#8dff9a", ore="#e4ff5a", ore2="#ffffff", haz="#ff3dd2", bg="#081a10", motif="cells"),
]

DEFS = """<defs>
 <filter id="glow" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="3" result="b"/>
  <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
 <filter id="soft"><feGaussianBlur stdDeviation="6"/></filter>
 <filter id="grain" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="2" seed="5"/>
  <feColorMatrix values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 0.18 0"/><feComposite in2="SourceGraphic" operator="in"/></filter>
</defs>"""


def lighten(hexc, k):
    c = [int(hexc[i:i + 2], 16) for i in (1, 3, 5)]
    if k >= 0:
        c = [int(v + (255 - v) * k) for v in c]
    else:
        c = [int(v * (1 + k)) for v in c]
    return "#%02x%02x%02x" % tuple(max(0, min(255, v)) for v in c)


def block(x, b, base, rnd, cracks=0.5):
    """Bevelled rounded block with grain, specks and optional cracks."""
    g = 3
    s = [f'<g><rect x="{x+g}" y="{g}" width="{T-2*g}" height="{T-2*g}" rx="14" fill="{base}"/>',
         f'<rect x="{x+g}" y="{g}" width="{T-2*g}" height="{T-2*g}" rx="14" fill="{base}" filter="url(#grain)"/>',
         f'<path d="M{x+g+14},{g+3} H{x+T-g-14}" stroke="{lighten(base,0.35)}" stroke-width="5" stroke-linecap="round" opacity=".9"/>',
         f'<path d="M{x+g+3},{g+14} V{T-g-14}" stroke="{lighten(base,0.22)}" stroke-width="4" stroke-linecap="round" opacity=".8"/>',
         f'<path d="M{x+g+14},{T-g-3} H{x+T-g-14}" stroke="{lighten(base,-0.45)}" stroke-width="6" stroke-linecap="round"/>',
         f'<path d="M{x+T-g-3},{g+14} V{T-g-14}" stroke="{lighten(base,-0.35)}" stroke-width="5" stroke-linecap="round"/>']
    for _ in range(rnd.randint(3, 6)):
        sx, sy = x + rnd.uniform(14, T - 14), rnd.uniform(14, T - 14)
        s.append(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{rnd.uniform(1.6,3.4):.1f}" fill="{lighten(base,-0.35)}"/>')
    if rnd.random() < cracks:
        px, py = x + rnd.uniform(25, 70), 10
        d = f"M{px:.0f},{py:.0f}"
        for _ in range(4):
            px += rnd.uniform(-12, 12); py += rnd.uniform(12, 20)
            d += f" L{px:.0f},{py:.0f}"
        s.append(f'<path d="{d}" stroke="{lighten(base,-0.5)}" stroke-width="2.5" fill="none" stroke-linejoin="round"/>')
    s.append('</g>')
    return "".join(s)


def motif(x, b, rnd):
    m, acc, dark = b["motif"], b["acc"], b["dark"]
    s = []
    if m == "pebbles":
        for _ in range(4):
            cx, cy = x + rnd.uniform(18, 78), rnd.uniform(18, 78)
            s.append(f'<ellipse cx="{cx:.0f}" cy="{cy:.0f}" rx="{rnd.uniform(4,8):.0f}" ry="{rnd.uniform(3,6):.0f}" fill="{acc}" opacity=".8"/>')
        s.append(f'<path d="M{x+10},{rnd.uniform(20,70):.0f} q20,-10 35,6 t30,-4" stroke="{dark}" stroke-width="2.5" fill="none" opacity=".7"/>')
    elif m == "bones":
        cx, cy, a = x + rnd.uniform(30, 66), rnd.uniform(30, 66), rnd.uniform(0, 180)
        s.append(f'<g transform="rotate({a:.0f} {cx:.0f} {cy:.0f})" fill="{acc}" opacity=".85"><rect x="{cx-16:.0f}" y="{cy-3:.0f}" width="32" height="6" rx="3"/>'
                 f'<circle cx="{cx-16:.0f}" cy="{cy-4:.0f}" r="4.5"/><circle cx="{cx-16:.0f}" cy="{cy+4:.0f}" r="4.5"/>'
                 f'<circle cx="{cx+16:.0f}" cy="{cy-4:.0f}" r="4.5"/><circle cx="{cx+16:.0f}" cy="{cy+4:.0f}" r="4.5"/></g>')
    elif m == "bricks":
        for row in range(3):
            y = 8 + row * 27
            off = 0 if row % 2 == 0 else 20
            for bx in range(-1, 3):
                xx = x + 8 + off + bx * 40
                if xx + 36 < x + 6 or xx > x + T - 6:
                    continue
                s.append(f'<rect x="{max(xx, x+8):.0f}" y="{y}" width="{min(36, x+T-8-max(xx, x+8)):.0f}" height="23" rx="4" fill="none" stroke="{dark}" stroke-width="2.5" opacity=".75"/>')
        s.append(f'<path d="M{x+20},{70} q12,8 28,2" stroke="#5f8a3a" stroke-width="3" fill="none" opacity=".8"/>')
    elif m == "specks":
        for _ in range(6):
            cx, cy = x + rnd.uniform(14, 82), rnd.uniform(14, 82)
            s.append(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{rnd.uniform(1,2.2):.1f}" fill="{acc}" opacity=".9"/>')
    elif m == "lava":
        px, py = x + rnd.uniform(20, 70), 6
        d = f"M{px:.0f},{py}"
        for _ in range(5):
            px += rnd.uniform(-14, 14); py += rnd.uniform(14, 18)
            d += f" L{px:.0f},{py:.0f}"
        s.append(f'<path d="{d}" stroke="{acc}" stroke-width="4" fill="none" stroke-linejoin="round" filter="url(#glow)"/>')
    elif m == "veins":
        for _ in range(2):
            px, py = x + rnd.uniform(10, 86), rnd.uniform(10, 86)
            d = f"M{px:.0f},{py:.0f}"
            for _ in range(3):
                px += rnd.uniform(-18, 18); py += rnd.uniform(-18, 18)
                d += f" L{px:.0f},{py:.0f}"
            s.append(f'<path d="{d}" stroke="{acc}" stroke-width="3" fill="none" opacity=".9" filter="url(#glow)"/>')
    elif m == "sheen":
        s.append(f'<path d="M{x+14},{80} L{x+80},{14}" stroke="{acc}" stroke-width="7" opacity=".35" stroke-linecap="round"/>')
        s.append(f'<path d="M{x+34},{82} L{x+82},{34}" stroke="{acc}" stroke-width="3" opacity=".3" stroke-linecap="round"/>')
    elif m == "cells":
        for _ in range(4):
            cx, cy, r = x + rnd.uniform(20, 76), rnd.uniform(20, 76), rnd.uniform(6, 11)
            s.append(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r:.0f}" fill="{dark}" stroke="{acc}" stroke-width="2" opacity=".75"/>'
                     f'<circle cx="{cx-r*0.3:.0f}" cy="{cy-r*0.3:.0f}" r="{r*0.25:.1f}" fill="{acc}" opacity=".6"/>')
    return "".join(s)


def ore_art(x, b, rnd):
    i = BIOMES.index(b)
    o, o2 = b["ore"], b["ore2"]
    cx, cy = x + 48, 50
    s = [f'<g filter="url(#glow)">']
    if i in (3, 6):  # crystal shards / void glass
        for k in range(4):
            bx, by = cx + rnd.uniform(-22, 22), cy + rnd.uniform(4, 26)
            h, w, a = rnd.uniform(28, 44), rnd.uniform(7, 11), rnd.uniform(-28, 28)
            s.append(f'<g transform="rotate({a:.0f} {bx:.0f} {by:.0f})"><polygon points="{bx},{by-h} {bx+w},{by-h*.72} {bx+w},{by} {bx-w},{by} {bx-w},{by-h*.72}" fill="{o}"/>'
                     f'<polygon points="{bx},{by-h} {bx+w*.2},{by-h*.72} {bx+w*.2},{by} {bx-w},{by} {bx-w},{by-h*.72}" fill="{o2}" opacity=".45"/></g>')
    elif i == 1:  # amber with a trapped bug
        s.append(f'<ellipse cx="{cx}" cy="{cy}" rx="24" ry="20" fill="{o}"/><ellipse cx="{cx-8}" cy="{cy-8}" rx="8" ry="5" fill="{o2}" opacity=".7"/>'
                 f'<ellipse cx="{cx+3}" cy="{cy+3}" rx="6" ry="3.5" fill="#5a3008" opacity=".8"/><path d="M{cx-4},{cy+1} l-6,-4 M{cx-4},{cy+5} l-6,4 M{cx+9},{cy+2} l5,-4" stroke="#5a3008" stroke-width="1.5"/>')
    elif i == 2:  # gold relic coin
        s.append(f'<circle cx="{cx}" cy="{cy}" r="22" fill="{o}" stroke="#b07a10" stroke-width="4"/><circle cx="{cx}" cy="{cy}" r="13" fill="none" stroke="#b07a10" stroke-width="2.5"/>'
                 f'<path d="M{cx},{cy-8} l7,8 l-7,8 l-7,-8z" fill="#b07a10"/><circle cx="{cx-8}" cy="{cy-9}" r="4" fill="{o2}" opacity=".8"/>')
    elif i == 7:  # star metal
        pts = " ".join(f"{cx+math.cos(a)*(22 if k%2==0 else 10):.1f},{cy+math.sin(a)*(22 if k%2==0 else 10):.1f}" for k, a in enumerate([-math.pi/2 + j*math.pi/5 for j in range(10)]))
        s.append(f'<polygon points="{pts}" fill="{o}" stroke="#7a8a10" stroke-width="2.5"/><circle cx="{cx-5}" cy="{cy-6}" r="4" fill="{o2}" opacity=".8"/>')
    elif i == 5:  # core shard: hot glowing diamond
        s.append(f'<polygon points="{cx},{cy-26} {cx+17},{cy} {cx},{cy+26} {cx-17},{cy}" fill="{o}"/><polygon points="{cx},{cy-26} {cx+4},{cy} {cx},{cy+26} {cx-17},{cy}" fill="{o2}" opacity=".5"/>')
    elif i == 4:  # obsidian shards (purple sheen)
        for k in range(3):
            bx, by = cx + (k - 1) * 15, cy + rnd.uniform(0, 12)
            s.append(f'<polygon points="{bx},{by-26} {bx+10},{by+8} {bx-9},{by+12}" fill="{o}" stroke="#2a0a40" stroke-width="2"/>')
    else:  # copper nuggets
        for k in range(3):
            bx, by, r = cx + rnd.uniform(-16, 16), cy + rnd.uniform(-12, 14), rnd.uniform(9, 13)
            s.append(f'<circle cx="{bx:.0f}" cy="{by:.0f}" r="{r:.0f}" fill="{o}" stroke="#8a4a14" stroke-width="2.5"/><circle cx="{bx-r*.35:.0f}" cy="{by-r*.35:.0f}" r="{r*.3:.1f}" fill="{o2}" opacity=".8"/>')
    s.append('</g>')
    return "".join(s)


def hazard_art(x, b):
    h = b["haz"]
    cx, cy = x + 48, 48
    return (f'<g><circle cx="{cx}" cy="{cy}" r="26" fill="{h}" opacity=".35" filter="url(#soft)"/>'
            f'<polygon points="{cx},{cy-24} {cx+24},{cy+18} {cx-24},{cy+18}" fill="{h}" stroke="#2a0008" stroke-width="4" stroke-linejoin="round" filter="url(#glow)"/>'
            f'<rect x="{cx-3}" y="{cy-10}" width="6" height="16" rx="3" fill="#2a0008"/><circle cx="{cx}" cy="{cy+12}" r="3.5" fill="#2a0008"/></g>')


def back_wall(x, b, rnd):
    d = lighten(b["bg"], 0.04)
    s = [f'<rect x="{x}" y="0" width="{T}" height="{T}" fill="{d}"/>',
         f'<rect x="{x}" y="0" width="{T}" height="{T}" fill="{d}" filter="url(#grain)"/>']
    for _ in range(3):
        s.append(f'<circle cx="{x+rnd.uniform(10,86):.0f}" cy="{rnd.uniform(10,86):.0f}" r="{rnd.uniform(6,14):.0f}" fill="{lighten(b["bg"],-0.3)}" opacity=".6"/>')
    return "".join(s)


def atlas_svg(b):
    rnd = random.Random(BIOMES.index(b) * 101 + 7)
    parts = []
    for k in range(3):   # 0-2 rock variants
        parts.append(block(k * T, b, lighten(b["rock"], (k - 1) * 0.05), rnd) + motif(k * T, b, rnd))
    parts.append(block(3 * T, b, lighten(b["rock"], -0.3), rnd, 1.0) +  # 3 hard: reinforced
                 f'<path d="M{3*T+16},{20} L{3*T+80},{76} M{3*T+80},{20} L{3*T+16},{76}" stroke="{lighten(b["rock"],-0.55)}" stroke-width="7" stroke-linecap="round" opacity=".8"/>')
    parts.append(block(4 * T, b, lighten(b["rock"], -0.15), rnd) + hazard_art(4 * T, b))   # 4 hazard
    parts.append(block(5 * T, b, b["rock"], rnd, 0.2) + ore_art(5 * T, b, rnd))             # 5 ore
    parts.append(back_wall(6 * T, b, rnd))                                                   # 6 dug back wall
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{7*T}" height="{T}">{DEFS}{"".join(parts)}</svg>', 7 * T, T


def background_svg(b):
    """Seamless 256x256 parallax tile: dark cavern with faint biome shapes."""
    rnd = random.Random(BIOMES.index(b) * 31 + 3)
    S = 256
    s = [f'<rect width="{S}" height="{S}" fill="{b["bg"]}"/>']
    for _ in range(10):
        x, y, r = rnd.uniform(0, S), rnd.uniform(0, S), rnd.uniform(14, 40)
        col = rnd.choice([b["acc"], b["rock"], b["ore"]])
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                s.append(f'<circle cx="{x+ox:.0f}" cy="{y+oy:.0f}" r="{r:.0f}" fill="{col}" opacity=".10" filter="url(#soft)"/>')
    for _ in range(14):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S)
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                s.append(f'<circle cx="{x+ox:.0f}" cy="{y+oy:.0f}" r="1.5" fill="{b["ore"]}" opacity=".35"/>')
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}">{DEFS}{"".join(s)}</svg>', S, S


def drill_svg():
    """Drill character 'Dig-E': body (0-96) + 4 spinning bit frames (96-480), 96x128 cells."""
    W, H = 96, 128
    body = f'''
    <g transform="translate(0,0)">
      <rect x="6" y="40" width="10" height="56" rx="5" fill="#5a2a12"/><rect x="80" y="40" width="10" height="56" rx="5" fill="#5a2a12"/>
      <rect x="12" y="20" width="72" height="82" rx="26" fill="url(#hull)" stroke="#5a1d0b" stroke-width="4"/>
      <rect x="22" y="34" width="52" height="34" rx="14" fill="#1b2c48" stroke="#0d1626" stroke-width="3"/>
      <ellipse cx="38" cy="51" rx="9" ry="11" fill="#fff"/><ellipse cx="58" cy="51" rx="9" ry="11" fill="#fff"/>
      <circle cx="40" cy="54" r="5" fill="#0d1626"/><circle cx="60" cy="54" r="5" fill="#0d1626"/>
      <circle cx="42" cy="51" r="1.8" fill="#fff"/><circle cx="62" cy="51" r="1.8" fill="#fff"/>
      <path d="M26,30 q22,-10 44,0" stroke="#ffe3b0" stroke-width="4" fill="none" stroke-linecap="round" opacity=".8"/>
      <circle cx="22" cy="84" r="3" fill="#7a2a10"/><circle cx="74" cy="84" r="3" fill="#7a2a10"/>
      <rect x="40" y="6" width="16" height="18" rx="5" fill="#d8e2ea" stroke="#5a1d0b" stroke-width="3"/>
      <circle cx="48" cy="6" r="6" fill="#fff6c8" filter="url(#glow)"/>
    </g>'''
    frames = []
    for f in range(4):
        x0 = W * (f + 1)
        stripes = []
        for k in range(5):
            t0 = ((k + f * 0.25) % 5) / 5.0
            y = 8 + t0 * 96
            hw = 34 * (1 - t0 * 0.92)
            stripes.append(f'<path d="M{x0+48-hw:.1f},{y:.1f} L{x0+48+hw*0.85:.1f},{y+12:.1f}" stroke="#2c333b" stroke-width="4" stroke-linecap="round"/>')
        frames.append(f'<polygon points="{x0+12},4 {x0+84},4 {x0+48},122" fill="url(#bit)" stroke="#2c333b" stroke-width="3" stroke-linejoin="round"/>' + "".join(stripes))
    defs = DEFS.replace("</defs>", '''<linearGradient id="hull" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#c2531f"/><stop offset=".45" stop-color="#ffb347"/><stop offset=".62" stop-color="#ffd27a"/><stop offset="1" stop-color="#a33a12"/></linearGradient>
     <linearGradient id="bit" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#5d6b7a"/><stop offset=".5" stop-color="#eef4f8"/><stop offset="1" stop-color="#4a5562"/></linearGradient></defs>''')
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W*5}" height="{H}">{defs}{body}{"".join(frames)}</svg>', W * 5, H


def simple_svgs():
    out = {}
    out["glow"] = ('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><defs><radialGradient id="g">'
                   '<stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".35" stop-color="#fff" stop-opacity=".45"/>'
                   '<stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs><rect width="128" height="128" fill="url(#g)"/></svg>', 128, 128)
    out["headlight"] = ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="384"><defs><radialGradient id="g" cx="50%" cy="0%" r="100%">'
                        '<stop offset="0" stop-color="#fff" stop-opacity=".8"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>'
                        '<filter id="b"><feGaussianBlur stdDeviation="10"/></filter></defs>'
                        '<polygon points="108,0 148,0 246,384 10,384" fill="url(#g)" filter="url(#b)"/></svg>', 256, 384)
    out["chunk"] = ('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect x="1" y="1" width="14" height="14" rx="3" fill="#fff"/>'
                    '<rect x="1" y="9" width="14" height="6" rx="3" fill="#000" opacity=".25"/></svg>', 16, 16)
    out["spark"] = ('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><defs><radialGradient id="g"><stop offset="0" stop-color="#fff"/>'
                    '<stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient></defs><circle cx="8" cy="8" r="8" fill="url(#g)"/></svg>', 16, 16)
    out["coin"] = ('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><circle cx="24" cy="24" r="20" fill="#ffd166" stroke="#a5651a" stroke-width="4"/>'
                   '<circle cx="24" cy="24" r="12" fill="none" stroke="#e0a030" stroke-width="3"/><circle cx="17" cy="16" r="4" fill="#fff6d0"/></svg>', 48, 48)
    return out


def render(page, svg, w, h, path):
    page.set_viewport_size({"width": w, "height": h})
    page.set_content(f"<html><body style='margin:0;background:transparent'>{svg}</body></html>")
    page.screenshot(path=path, omit_background=True, clip={"x": 0, "y": 0, "width": w, "height": h})


if __name__ == "__main__":
    with sync_playwright() as p:
        br = p.chromium.launch()
        pg = br.new_page()
        for b in BIOMES:
            i = BIOMES.index(b)
            render(pg, *atlas_svg(b), os.path.join(OUT, f"tiles_{i}.png"))
            render(pg, *background_svg(b), os.path.join(OUT, f"bg_{i}.png"))
        render(pg, *drill_svg(), os.path.join(OUT, "drill.png"))
        for name, (svg, w, h) in simple_svgs().items():
            render(pg, svg, w, h, os.path.join(OUT, f"{name}.png"))
        br.close()
    total = 0
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".png"):
            sz = os.path.getsize(os.path.join(OUT, f)); total += sz
            print(f"{f:<16}{sz/1024:7.1f} KB")
    print(f"TOTAL {total/1024:.1f} KB")
