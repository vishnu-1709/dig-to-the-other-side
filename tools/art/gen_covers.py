"""Store covers for CrazyGames: landscape 1920x1080, portrait 800x1200, square 800x800.
Rules (CrazyGames): no borders, no text except the title, no icons/store logos.
Built from the game's own art (drill, ore colours, biome palette). Run after gen_tiles.py.
Output: store/cover_*.png
"""
import base64, io, math, os, random
from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
ART = os.path.join(ROOT, "assets", "art")
OUT = os.path.join(ROOT, "store")
os.makedirs(OUT, exist_ok=True)

ROCK = ["#8a5d38", "#c2a878", "#6f7363", "#3e3075", "#3a1a16", "#7a2c0e", "#3a4f78", "#2f6a45"]
ORE = ["#e8893a", "#ffb52e", "#ffd84a", "#7ff3ff", "#c86bff", "#fff27a", "#d6f0ff", "#e4ff5a"]


def b64png(img):
    buf = io.BytesIO(); img.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


drill = Image.open(os.path.join(ART, "drill.png"))
BODY = b64png(drill.crop((0, 0, 96, 128)))
BIT = b64png(drill.crop((96, 0, 192, 128)))
FONT = "data:font/woff2;base64," + base64.b64encode(open(os.path.join(ROOT, "assets/fonts/Fredoka-SemiBold.woff2"), "rb").read()).decode()


def planet(cx, cy, R, tunnel_to, drill_scale, rnd):
    s = []
    # outer glow
    s.append(f'<circle cx="{cx}" cy="{cy}" r="{R*1.12}" fill="url(#atmo)"/>')
    # top half rings (crust -> core), bottom half (alien -> mirror)
    for i in range(6):
        r = R * (1 - i / 6)
        s.append(f'<path d="M{cx-r},{cy} A{r},{r} 0 0 1 {cx+r},{cy} Z" fill="{ROCK[i]}"/>')
        s.append(f'<path d="M{cx-r},{cy} A{r},{r} 0 0 1 {cx+r},{cy}" fill="none" stroke="#ffffff" stroke-opacity=".12" stroke-width="3"/>')
    for i, r in [(7, R), (6, R * 0.5)]:
        s.append(f'<path d="M{cx-r},{cy} A{r},{r} 0 0 0 {cx+r},{cy} Z" fill="{ROCK[i]}"/>')
        s.append(f'<path d="M{cx-r},{cy} A{r},{r} 0 0 0 {cx+r},{cy}" fill="none" stroke="#ffffff" stroke-opacity=".12" stroke-width="3"/>')
    # glowing core
    s.append(f'<circle cx="{cx}" cy="{cy}" r="{R*0.16}" fill="url(#core)" filter="url(#glow)"/>')
    # ore glints scattered in the rings
    for _ in range(26):
        a = rnd.uniform(0, math.tau); d = rnd.uniform(0.2, 0.95) * R
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
        ring = int((1 - d / R) * 6) if y < cy else (7 if d > R * 0.5 else 6)
        col = ORE[max(0, min(7, ring))]
        k = rnd.uniform(0.6, 1.3) * R / 520
        s.append(f'<g filter="url(#glow)" transform="translate({x:.0f},{y:.0f}) scale({k:.2f}) rotate({rnd.uniform(-30,30):.0f})">'
                 f'<polygon points="0,-22 9,-8 9,10 -9,10 -9,-8" fill="{col}"/><polygon points="0,-22 2,-8 2,10 -9,10 -9,-8" fill="#fff" opacity=".35"/></g>')
    # rim
    s.append(f'<circle cx="{cx}" cy="{cy}" r="{R}" fill="none" stroke="#ffffff" stroke-opacity=".35" stroke-width="5"/>')
    # tunnel from the surface down to the drill (tunnel_to = drill centre, as in the game)
    k = drill_scale
    w = 46 * k
    top = cy - R - 30
    s.append(f'<rect x="{cx-w}" y="{top}" width="{2*w}" height="{tunnel_to-top}" rx="{w}" fill="#0b0716"/>')
    s.append(f'<rect x="{cx-w}" y="{top}" width="{2*w}" height="{tunnel_to-top}" rx="{w}" fill="none" stroke="#ffd166" stroke-opacity=".6" stroke-width="4" filter="url(#glow)"/>')
    tip = tunnel_to + 150 * k
    s.append(f'<polygon points="{cx-30*k},{tip-30*k} {cx+30*k},{tip-30*k} {cx+170*k},{tip+260*k} {cx-170*k},{tip+260*k}" fill="url(#lamp)"/>')
    # sparks + debris at the bit
    for _ in range(30):
        a = rnd.uniform(math.pi * 1.05, math.pi * 1.95); L = rnd.uniform(30, 120) * k
        x2, y2 = cx + math.cos(a) * L * 1.4, tip + math.sin(a) * L * 0.6
        col = rnd.choice(["#fff3b0", "#ffd166", "#7ff3ff", "#ffb347"])
        s.append(f'<line x1="{cx:.0f}" y1="{tip:.0f}" x2="{x2:.0f}" y2="{y2:.0f}" stroke="{col}" stroke-width="{3*k:.1f}" stroke-linecap="round" filter="url(#glow)"/>')
    for _ in range(14):
        x, y = cx + rnd.uniform(-130, 130) * k, tip + rnd.uniform(-90, 20) * k
        z = rnd.uniform(8, 18) * k
        s.append(f'<rect x="{x:.0f}" y="{y:.0f}" width="{z:.0f}" height="{z:.0f}" rx="3" fill="{rnd.choice(ROCK[:6])}" transform="rotate({rnd.randint(0,90)} {x:.0f} {y:.0f})"/>')
    # drill character (bit under body), from the game's sprite sheet
    dw, dh = 96 * k, 128 * k
    s.append(f'<image href="{BIT}" x="{cx-dw/2}" y="{tunnel_to + 30*k}" width="{dw}" height="{dh}"/>')
    s.append(f'<image href="{BODY}" x="{cx-dw/2}" y="{tunnel_to - 84*k}" width="{dw}" height="{dh}"/>')
    return "".join(s)


def stars(W, H, rnd, n):
    return "".join(f'<circle cx="{rnd.uniform(0,W):.0f}" cy="{rnd.uniform(0,H):.0f}" r="{rnd.uniform(0.8,2.6):.1f}" fill="#fff" opacity="{rnd.uniform(.3,.9):.2f}"/>' for _ in range(n))


DEFS = """<defs>
 <radialGradient id="space" cx="60%" cy="45%" r="80%"><stop offset="0" stop-color="#2b1f63"/><stop offset="1" stop-color="#06041a"/></radialGradient>
 <radialGradient id="atmo"><stop offset=".85" stop-color="#7f6bff" stop-opacity=".45"/><stop offset="1" stop-color="#7f6bff" stop-opacity="0"/></radialGradient>
 <radialGradient id="core"><stop offset="0" stop-color="#ffffff"/><stop offset=".4" stop-color="#fff27a"/><stop offset="1" stop-color="#ff5a1f"/></radialGradient>
 <radialGradient id="lamp" cx="50%" cy="0%" r="100%"><stop offset="0" stop-color="#fff6c8" stop-opacity=".55"/><stop offset="1" stop-color="#fff6c8" stop-opacity="0"/></radialGradient>
 <filter id="glow" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
</defs>"""


def title_html(lines, size, x, y, align):
    spans = "<br>".join(lines)
    return (f'<div style="position:absolute;left:{x}px;top:{y}px;width:max-content;text-align:{align};font-family:F;'
            f'font-size:{size}px;line-height:.98;color:#fff;letter-spacing:1px;'
            f'-webkit-text-stroke:{size*0.09:.0f}px #120d2e;paint-order:stroke fill;'
            f'text-shadow:0 {size*0.08:.0f}px 0 #ff9f43, 0 {size*0.16:.0f}px {size*0.2:.0f}px rgba(0,0,0,.6)">{spans}</div>')


def page(W, H, svg, title):
    return f"""<html><head><style>@font-face{{font-family:F;src:url({FONT}) format('woff2');}}
    body{{margin:0;width:{W}px;height:{H}px;overflow:hidden;position:relative}}</style></head>
    <body><svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" style="position:absolute;left:0;top:0">{DEFS}
    <rect width="{W}" height="{H}" fill="url(#space)"/>{svg}</svg>{title}</body></html>"""


def landscape():
    rnd = random.Random(1); W, H = 1920, 1080
    svg = stars(W, H, rnd, 160) + planet(1380, 560, 440, 560 - 440 * 0.5, 1.6, rnd)
    return W, H, page(W, H, svg, title_html(["DIG TO", "THE OTHER", "SIDE"], 150, 90, 250, "left"))


def portrait():
    rnd = random.Random(2); W, H = 800, 1200
    svg = stars(W, H, rnd, 90) + planet(400, 770, 340, 770 - 340 * 0.5, 1.2, rnd)
    return W, H, page(W, H, svg, title_html(["DIG TO THE", "OTHER SIDE"], 92, 0, 70, "center").replace("left:0px", "left:0;right:0;margin:auto"))


def square():
    rnd = random.Random(3); W, H = 800, 800
    svg = stars(W, H, rnd, 70) + planet(400, 520, 255, 520 - 255 * 0.5, 0.95, rnd)
    return W, H, page(W, H, svg, title_html(["DIG TO THE", "OTHER SIDE"], 78, 0, 40, "center").replace("left:0px", "left:0;right:0;margin:auto"))


if __name__ == "__main__":
    with sync_playwright() as p:
        br = p.chromium.launch()
        for name, fn in [("landscape_1920x1080", landscape), ("portrait_800x1200", portrait), ("square_800x800", square)]:
            W, H, html = fn()
            pg = br.new_page(viewport={"width": W, "height": H})
            pg.set_content(html)
            pg.wait_for_timeout(300)
            path = os.path.join(OUT, f"cover_{name}.png")
            pg.screenshot(path=path)
            print(path, os.path.getsize(path) // 1024, "KB")
            pg.close()
        br.close()
