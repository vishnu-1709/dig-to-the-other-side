"""Synthesize all game audio as small mono OGG files (no recordings, no licenses needed).

Melodic samples are recorded at C4 (261.63 Hz); the game pitches them per note.
Bass is recorded at C2, pad at C3. Run: python3 tools/audio/gen_audio.py
"""
import os, subprocess, tempfile, wave
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(42)
C4, C3, C2 = 261.63, 130.81, 65.41


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(n, a=0.005, d=0.3, curve=4.0):
    x = np.arange(n) / SR
    e = np.minimum(1.0, x / max(a, 1e-4)) * np.exp(-curve * np.maximum(0, x - a) / d)
    return e


def fade_out(y, ms=20):
    k = int(SR * ms / 1000)
    y[-k:] *= np.linspace(1, 0, k)
    return y


def save(name, y, quality=3):
    y = np.asarray(y, dtype=np.float64)
    peak = np.max(np.abs(y)) or 1.0
    y = fade_out(y / peak * 0.85)
    pcm = (y * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
        path = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
    os.unlink(tmp.name)
    print(f"{name:<16}{os.path.getsize(path)/1024:6.1f} KB")


def karplus(freq, dur, damp=0.996):
    n = int(SR * dur); p = int(SR / freq)
    buf = rng.uniform(-1, 1, p); out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = damp * 0.5 * (buf[i % p] + buf[(i + 1) % p])
    return out


# ---------- biome instruments (all at C4) ----------
def pluck():          # Topsoil: bright pluck
    return karplus(C4, 0.9, 0.995)

def marimba():        # Fossil Beds: wooden mallet
    x = t(0.8)
    return (np.sin(2*np.pi*C4*x) + 0.35*np.sin(2*np.pi*C4*4*x)*np.exp(-x*30) + 0.15*np.sin(2*np.pi*C4*10*x)*np.exp(-x*60)) * env(len(x), 0.002, 0.25)

def flute():          # Lost Ruins: breathy flute
    x = t(0.9)
    vib = np.sin(2*np.pi*5*x) * 0.004
    tone = np.sin(2*np.pi*C4*x*(1+vib)) + 0.2*np.sin(2*np.pi*C4*2*x)
    breath = np.convolve(rng.normal(0, 1, len(x)), np.ones(8)/8, "same") * 0.08
    e = np.minimum(1, x/0.06) * np.exp(-np.maximum(0, x-0.25)*4)
    return (tone + breath) * e

def glass_bell():     # Crystal Caves: inharmonic bell
    x = t(1.4)
    ratios, amps = [1, 2.76, 5.4, 8.93], [1, 0.5, 0.3, 0.15]
    return sum(a*np.sin(2*np.pi*C4*r*x)*np.exp(-x*(1.5+r)) for r, a in zip(ratios, amps)) * np.minimum(1, x/0.002)

def low_synth():      # Magma Rivers: warm saw
    x = t(0.8)
    saw = sum(((-1)**(k+1))/k*np.sin(2*np.pi*C4*k*x) for k in range(1, 12))
    return saw * env(len(x), 0.01, 0.35)

def drone_pulse():    # The Core: square pulse
    x = t(0.7)
    sq = np.sign(np.sin(2*np.pi*C4*x)) * 0.5 + 0.5*np.sin(2*np.pi*C4*x)
    return np.convolve(sq, np.ones(6)/6, "same") * env(len(x), 0.004, 0.3)

def ethereal():       # Mirror Mantle: detuned sines with slow attack
    x = t(1.4)
    y = sum(np.sin(2*np.pi*C4*d*x) for d in (0.997, 1.0, 1.003)) + 0.3*np.sin(2*np.pi*C4*2*x)
    return y * np.minimum(1, x/0.08) * np.exp(-np.maximum(0, x-0.1)*2.2)

def alien_fm():       # Alien Crust: FM with a strange ratio
    x = t(1.0)
    mod = np.sin(2*np.pi*C4*1.414*x) * 3.0 * np.exp(-x*3)
    return np.sin(2*np.pi*C4*x + mod) * env(len(x), 0.003, 0.4)

# ---------- shared rhythm section ----------
def kick():
    x = t(0.35)
    f = 50 + 120*np.exp(-x*35)
    return np.sin(2*np.pi*np.cumsum(f)/SR) * np.exp(-x*9)

def snare():
    x = t(0.25)
    noise = rng.normal(0, 1, len(x)) * np.exp(-x*22)
    return noise*0.7 + np.sin(2*np.pi*190*x)*np.exp(-x*30)*0.6

def hat():
    x = t(0.08)
    n = rng.normal(0, 1, len(x)); n = n - np.convolve(n, np.ones(4)/4, "same")
    return n * np.exp(-x*70)

def bass():           # C2
    x = t(0.6)
    y = np.sin(2*np.pi*C2*x) + 0.4*np.sin(2*np.pi*C2*2*x) + 0.15*np.sin(2*np.pi*C2*3*x)
    return y * env(len(x), 0.005, 0.3, 3)

def pad():            # C3, soft and long
    x = t(2.4)
    y = sum(np.sin(2*np.pi*C3*d*x) + 0.25*np.sin(2*np.pi*C3*2*d*x) for d in (0.995, 1.0, 1.005))
    return y * np.minimum(1, x/0.4) * np.exp(-np.maximum(0, x-0.8)*1.4)

# ---------- event sounds ----------
def click():
    x = t(0.06)
    return np.sin(2*np.pi*1400*x) * np.exp(-x*80)

def fuel_out():
    x = t(0.7)
    f = 420*np.exp(-x*2.2)
    return np.sign(np.sin(2*np.pi*np.cumsum(f)/SR)) * 0.4 * np.exp(-x*3)

def biome_enter():
    x = t(1.2)
    f = 200 + 900*x
    whoosh = np.convolve(rng.normal(0, 1, len(x)), np.ones(20)/20, "same") * np.sin(np.pi*x/1.2)
    return whoosh*0.8 + 0.4*np.sin(2*np.pi*np.cumsum(f)/SR)*np.sin(np.pi*x/1.2)

def coin():
    x = t(0.25)
    y = np.where(x < 0.06, np.sin(2*np.pi*988*x), np.sin(2*np.pi*1319*x))
    return y * np.exp(-x*12)

def magnet():
    x = t(0.2)
    f = 500 + 1400 * (x / 0.2) ** 1.5
    tone = np.sin(2*np.pi*np.cumsum(f)/SR)
    shimmer = np.sin(2*np.pi*np.cumsum(f*2.01)/SR) * 0.3
    return (tone + shimmer) * np.minimum(1, x/0.01) * np.exp(-x*9)

def upgrade():
    x = t(0.45)
    notes = [523.25, 659.25, 783.99]
    y = np.zeros(len(x))
    for i, f in enumerate(notes):
        s = int(i*0.08*SR); seg = x[:len(x)-s]
        y[s:] += np.sin(2*np.pi*f*seg) * np.exp(-seg*8)
    return y


if __name__ == "__main__":
    for name, fn in [("inst_0", pluck), ("inst_1", marimba), ("inst_2", flute), ("inst_3", glass_bell),
                     ("inst_4", low_synth), ("inst_5", drone_pulse), ("inst_6", ethereal), ("inst_7", alien_fm),
                     ("kick", kick), ("snare", snare), ("hat", hat), ("bass", bass), ("pad", pad),
                     ("click", click), ("fuel_out", fuel_out), ("biome_enter", biome_enter),
                     ("coin", coin), ("upgrade", upgrade), ("magnet", magnet)]:
        save(name, fn())
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".ogg"))
    print(f"TOTAL {total/1024:.1f} KB")
