"""Record CrazyGames preview videos (no sound) from the web build in ?demo mode.
Landscape 1920x1080 and portrait 1080x1620, ~18 s each, cut from three biomes.
Usage: python3 tests/record_preview.py build/web out_dir
"""
import functools, http.server, os, subprocess, sys, threading, time
from playwright.sync_api import sync_playwright

site, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=site)
handler.log_message = lambda *a: None
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 8061), handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()

BIOMES = [3, 4, 7]
CLIP_S = 6.0
FORMATS = {"landscape": ((1280, 720), "1920:1080"), "portrait": ((720, 1080), "1080:1620")}

with sync_playwright() as p:
    b = p.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
    for fmt, (vp, scale) in FORMATS.items():
        parts = []
        for bi in BIOMES:
            raw = os.path.join(out, f"raw_{fmt}_{bi}")
            ctx = b.new_context(viewport={"width": vp[0], "height": vp[1]}, record_video_dir=raw,
                                record_video_size={"width": vp[0], "height": vp[1]})
            pg = ctx.new_page()
            t0 = time.time()
            booted = [None]
            pg.on("console", lambda m: booted.__setitem__(0, booted[0] or (time.time() if "RUN_START" in m.text else None)))
            pg.goto(f"http://127.0.0.1:8061/index.html?biome={bi}&demo")
            while booted[0] is None and time.time() - t0 < 40:
                pg.wait_for_timeout(200)
            start = (booted[0] or time.time()) - t0 + 0.6
            pg.wait_for_timeout(int((CLIP_S + 1.0) * 1000))
            video = pg.video.path()
            ctx.close()
            clip = os.path.join(out, f"clip_{fmt}_{bi}.mp4")
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{start:.2f}", "-i", video, "-t", str(CLIP_S),
                            "-vf", f"scale={scale}:flags=lanczos,fps=30", "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                            "-preset", "veryfast", "-crf", "20", clip], check=True)
            parts.append(clip)
        lst = os.path.join(out, f"list_{fmt}.txt")
        open(lst, "w").write("".join(f"file '{os.path.abspath(c)}'\n" for c in parts))
        final = os.path.join(out, f"preview_{fmt}.mp4")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
        print(final, os.path.getsize(final) // 1024, "KB")
    b.close()
srv.shutdown()
