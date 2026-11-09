"""Procedurally generate a Crystal Caves gameplay frame as SVG (code-only art test)."""
import math, random

random.seed(7)
W, H, T = 720, 1280, 60          # canvas, tile size
COLS, ROWS = W // T, H // T + 1
out = []
add = out.append

# ---------- palette (Crystal Caves) ----------
ROCK = [(46, 38, 92), (54, 44, 104), (40, 33, 82), (60, 50, 112)]
DEEP = "#120d2e"
CRYS = ["#7ff3ff", "#b48cff", "#ff8de8"]

def rgb(c, k=1.0):
    return "rgb(%d,%d,%d)" % tuple(max(0, min(255, int(v * k))) for v in c)

# ---------- tunnel path carved by the drill ----------
def tunnel_x(y):
    return 300 + 110 * math.cos((y - 820) / 240.0) + 14 * math.sin(y / 70.0)

DRILL_Y = 820
def carved(cx, cy):
    if cy > DRILL_Y + 10:
        return False
    return abs(cx - tunnel_x(cy)) < 74

add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
add('''<defs>
 <radialGradient id="bgGlow" cx="50%" cy="40%" r="70%">
  <stop offset="0" stop-color="#2b1f63"/><stop offset="1" stop-color="#07051a"/></radialGradient>
 <filter id="glow" x="-100%" y="-100%" width="300%" height="300%">
  <feGaussianBlur stdDeviation="7" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
 <filter id="soft"><feGaussianBlur stdDeviation="18"/></filter>
 <filter id="grain"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="3"/>
  <feColorMatrix values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 0.06 0"/><feComposite in2="SourceGraphic" operator="in"/></filter>
 <linearGradient id="crysG" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#ffffff"/><stop offset=".35" stop-color="#7ff3ff"/><stop offset="1" stop-color="#3a5bd9"/></linearGradient>
 <linearGradient id="crysP" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#fff0ff"/><stop offset=".4" stop-color="#c79bff"/><stop offset="1" stop-color="#5a2fb8"/></linearGradient>
 <linearGradient id="hull" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#b8461f"/><stop offset=".45" stop-color="#ffb347"/><stop offset=".6" stop-color="#ffd27a"/><stop offset="1" stop-color="#9c3412"/></linearGradient>
 <linearGradient id="bit" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#5d6b7a"/><stop offset=".5" stop-color="#e9f1f7"/><stop offset="1" stop-color="#4a5562"/></linearGradient>
 <radialGradient id="lamp" cx="50%" cy="0%" r="100%">
  <stop offset="0" stop-color="#fff6c8" stop-opacity=".55"/><stop offset="1" stop-color="#fff6c8" stop-opacity="0"/></radialGradient>
 <radialGradient id="vign" cx="50%" cy="50%" r="75%">
  <stop offset=".6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".65"/></radialGradient>
</defs>''')

# ---------- background: deep cavern with parallax crystal silhouettes ----------
add(f'<rect width="{W}" height="{H}" fill="url(#bgGlow)"/>')
for layer, (alpha, scale) in enumerate([(0.25, 2.2), (0.45, 1.4)]):
    for i in range(9):
        x = random.uniform(-40, W + 40); y = random.uniform(0, H)
        h = random.uniform(80, 220) * scale / 2; w = h * 0.28
        col = random.choice(["#6a4dff", "#3fb6ff", "#b25cff"])
        add(f'<polygon points="{x},{y-h} {x+w},{y} {x},{y+h*0.25} {x-w},{y}" fill="{col}" opacity="{alpha*0.6}" filter="url(#soft)"/>')

# ---------- tunnel back wall (darker, recessed) ----------
pts_l = [(tunnel_x(y) - 96, y) for y in range(-20, DRILL_Y + 1, 20)]
bot = [(tunnel_x(DRILL_Y) + 96*math.cos(a), DRILL_Y + 60*math.sin(a)) for a in [math.pi - i*math.pi/8 for i in range(1,8)]]
pts_l = pts_l + [(x, y) for x, y in bot][::-1][::-1]
pts_r = [(tunnel_x(y) + 96, y) for y in range(DRILL_Y, -21, -20)]
poly = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts_l + pts_r)
add(f'<polygon points="{poly}" fill="{DEEP}"/>')
add(f'<polygon points="{poly}" fill="#3a2a8a" opacity=".35" filter="url(#soft)"/>')

# ---------- rock blocks with bevels, cracks, specks ----------
ore_tiles = set()
for _ in range(7):
    cx, cy = random.randrange(COLS), random.randrange(2, ROWS)
    for _ in range(random.randint(4, 7)):
        ore_tiles.add((cx, cy))
        cx += random.choice([-1, 0, 1]); cy += random.choice([0, 1])

for r in range(ROWS):
    for c in range(COLS):
        x, y = c * T, r * T
        if carved(x + T/2, y + T/2):
            continue
        base = random.choice(ROCK)
        depth_k = (0.85 + 0.25 * (r / ROWS)) * (1.12 if (r // 3) % 2 else 0.92)
        k = random.uniform(.9, 1.1) * depth_k
        g = 3
        add(f'<rect x="{x+g}" y="{y+g}" width="{T-2*g}" height="{T-2*g}" rx="9" fill="{rgb(base,k)}"/>')
        # bevel: light top-left, dark bottom-right
        add(f'<path d="M{x+g+9},{y+g+2} H{x+T-g-9} M{x+g+2},{y+g+9} V{y+T-g-9}" stroke="{rgb(base,k*1.6)}" stroke-width="3" stroke-linecap="round" opacity=".8"/>')
        add(f'<path d="M{x+g+9},{y+T-g-2} H{x+T-g-9} M{x+T-g-2},{y+g+9} V{y+T-g-9}" stroke="{rgb(base,k*0.45)}" stroke-width="4" stroke-linecap="round" opacity=".9"/>')
        # specks
        for _ in range(random.randint(2, 5)):
            sx, sy = x + random.uniform(10, T-10), y + random.uniform(10, T-10)
            add(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="{random.uniform(1.2,2.6):.1f}" fill="{rgb(base,k*0.6)}"/>')
        # occasional crack
        if random.random() < .18:
            px, py = x + random.uniform(15, 45), y + 8
            d = f"M{px:.0f},{py:.0f}"
            for _ in range(3):
                px += random.uniform(-9, 9); py += random.uniform(10, 16)
                d += f" L{px:.0f},{py:.0f}"
            add(f'<path d="{d}" stroke="{rgb(base,k*0.4)}" stroke-width="2" fill="none"/>')
        # crystal ore growing out of the block
        if (c, r) in ore_tiles:
            grad = random.choice(["crysG", "crysP"])
            add('<g filter="url(#glow)">')
            for _ in range(random.randint(3, 4)):
                bx = x + random.uniform(16, T-16); by = y + random.uniform(T*.55, T-10)
                h = random.uniform(26, 50); w = h * random.uniform(.22, .32)
                ang = random.uniform(-30, 30)
                add(f'<g transform="rotate({ang:.0f} {bx:.1f} {by:.1f})">'
                    f'<polygon points="{bx:.1f},{by-h:.1f} {bx+w:.1f},{by-h*.7:.1f} {bx+w:.1f},{by:.1f} {bx-w:.1f},{by:.1f} {bx-w:.1f},{by-h*.7:.1f}" fill="url(#{grad})"/>'
                    f'<polygon points="{bx:.1f},{by-h:.1f} {bx+w*.15:.1f},{by-h*.7:.1f} {bx+w*.15:.1f},{by:.1f} {bx-w:.1f},{by:.1f} {bx-w:.1f},{by-h*.7:.1f}" fill="#fff" opacity=".28"/></g>')
            add('</g>')

for side in (-1, 1):
    d = "M" + " L".join(f"{tunnel_x(y)+side*74:.1f},{y}" for y in range(-20, DRILL_Y-20, 10))
    add(f'<path d="{d}" stroke="#8f6bff" stroke-width="5" fill="none" opacity=".55" filter="url(#glow)"/>')
# ---------- loose crystal pickups floating in tunnel ----------
for i in range(5):
    yy = DRILL_Y - 140 - i * 120
    xx = tunnel_x(yy) + random.uniform(-30, 30)
    col = random.choice(CRYS)
    add(f'<g filter="url(#glow)"><polygon points="{xx},{yy-14} {xx+9},{yy} {xx},{yy+14} {xx-9},{yy}" fill="{col}"/></g>')

# ---------- drill ----------
dx, dy = tunnel_x(DRILL_Y), DRILL_Y
slope = (tunnel_x(DRILL_Y + 2) - tunnel_x(DRILL_Y - 2)) / 4
ang = -math.degrees(math.atan(slope))
add(f'<g transform="rotate({ang:.1f} {dx:.1f} {dy:.1f})">')
# headlight cone
add(f'<polygon points="{dx-30},{dy+60} {dx+30},{dy+60} {dx+130},{dy+330} {dx-130},{dy+330}" fill="url(#lamp)"/>')
# exhaust trail
for i in range(7):
    add(f'<circle cx="{dx + random.uniform(-14,14):.1f}" cy="{dy-80-i*26}" r="{10+i*3}" fill="#c9b8ff" opacity="{0.22 - i*0.028:.2f}"/>')
# body
add(f'<rect x="{dx-34}" y="{dy-70}" width="68" height="92" rx="16" fill="url(#hull)" stroke="#5a1d0b" stroke-width="3"/>')
add(f'<rect x="{dx-22}" y="{dy-56}" width="44" height="26" rx="8" fill="#1b2c48" stroke="#5a1d0b" stroke-width="2"/>')
add(f'<rect x="{dx-17}" y="{dy-52}" width="14" height="8" rx="3" fill="#8fd8ff" opacity=".8"/>')
for sx in (-34, 34):
    add(f'<rect x="{dx+sx-(8 if sx<0 else 0)}" y="{dy-44}" width="8" height="52" rx="3" fill="#7a2a10"/>')
add(f'<circle cx="{dx}" cy="{dy-6}" r="6" fill="#fff6c8" filter="url(#glow)"/>')
# drill bit cone with spiral bands
add(f'<polygon points="{dx-30},{dy+22} {dx+30},{dy+22} {dx},{dy+86}" fill="url(#bit)" stroke="#2c333b" stroke-width="2"/>')
for i in range(4):
    t0 = 0.12 + i * 0.22
    y0 = dy + 22 + 64 * t0; hw = 30 * (1 - t0)
    add(f'<path d="M{dx-hw:.1f},{y0:.1f} L{dx+hw*0.8:.1f},{y0+10:.1f}" stroke="#2c333b" stroke-width="3" stroke-linecap="round"/>')
add('</g>')

# ---------- sparks & debris at the bit ----------
bx, by = dx, dy + 80
add('<g filter="url(#glow)">')
for _ in range(22):
    a = random.uniform(math.pi * 0.05, math.pi * 0.95) + math.pi
    L = random.uniform(14, 46)
    x2, y2 = bx + math.cos(a) * L * 1.6, by + math.sin(a) * L * -0.3 + random.uniform(-20, 25)
    col = random.choice(["#fff3b0", "#ffd166", "#7ff3ff"])
    add(f'<line x1="{bx:.0f}" y1="{by:.0f}" x2="{x2:.0f}" y2="{y2:.0f}" stroke="{col}" stroke-width="2.2" stroke-linecap="round" opacity=".9"/>')
add('</g>')
for _ in range(10):
    rx, ry = bx + random.uniform(-70, 70), by + random.uniform(-30, 20)
    s = random.uniform(5, 11)
    add(f'<rect x="{rx:.0f}" y="{ry:.0f}" width="{s:.0f}" height="{s:.0f}" rx="2" fill="{rgb(ROCK[1],1.1)}" transform="rotate({random.randint(0,90)} {rx:.0f} {ry:.0f})"/>')

# ---------- pickup popups ----------
for (px, py, txt, col) in [(dx + 70, dy - 30, "+48", "#7ff3ff"), (dx - 120, dy - 150, "+120", "#d6a8ff")]:
    add(f'<text x="{px:.0f}" y="{py:.0f}" font-family="Arial Rounded MT Bold, Arial Black, sans-serif" font-size="30" font-weight="900" fill="{col}" stroke="#120d2e" stroke-width="6" paint-order="stroke" filter="url(#glow)">{txt}</text>')
# music note hint
add(f'<text x="{dx+90:.0f}" y="{dy+40:.0f}" font-size="34" fill="#ffffff" opacity=".85" filter="url(#glow)">&#9834;</text>')

# ---------- grain + vignette ----------
add(f'<rect width="{W}" height="{H}" fill="#fff" filter="url(#grain)" opacity=".5"/>')
add(f'<rect width="{W}" height="{H}" fill="url(#vign)"/>')

# ---------- HUD ----------
add(f'''<g font-family="Arial Rounded MT Bold, Arial Black, sans-serif" font-weight="900">
 <rect x="24" y="24" width="{W-48}" height="96" rx="24" fill="#0b0820" opacity=".72"/>
 <text x="48" y="64" font-size="22" fill="#b9a9ff">CRYSTAL CAVES</text>
 <text x="48" y="100" font-size="30" fill="#fff">1,284 <tspan font-size="20" fill="#9a8fd0">/ 12,742 km</tspan></text>
 <circle cx="{W-180}" cy="72" r="18" fill="#ffd166" stroke="#a5651a" stroke-width="4"/>
 <text x="{W-152}" y="83" font-size="32" fill="#ffd166">8,950</text>
 <rect x="24" y="{H-70}" width="{W-48}" height="22" rx="11" fill="#0b0820" opacity=".75"/>
 <rect x="30" y="{H-65}" width="{(W-60)*0.62:.0f}" height="12" rx="6" fill="#ff9f43"/>
 <text x="36" y="{H-82}" font-size="20" fill="#ffcf9a">FUEL</text>
 <rect x="{W-44}" y="140" width="16" height="{H-260}" rx="8" fill="#0b0820" opacity=".7"/>
 <rect x="{W-41}" y="143" width="10" height="{(H-266)*0.10:.0f}" rx="5" fill="#7ff3ff"/>
</g>''')

add('</svg>')
open("crystal_caves.svg", "w").write("\n".join(out))
print("ok", len(out))
