"""Headless-browser smoke test for the web build.

Serves build/web, opens it in Chromium (software WebGL), waits for the game's
BOOT_OK console line, collects console errors + FPS lines, takes screenshots
(landscape + portrait), and writes report/report.md. Exit 1 on failure.
Usage: python3 tests/smoke_test.py build/web report
"""
import functools, http.server, os, sys, threading, time
from playwright.sync_api import sync_playwright

site, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=site)
handler.log_message = lambda *a: None
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 8060), handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()

lines, errors = [], []
results = {}
with sync_playwright() as p:
    b = p.chromium.launch(args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
    for name, vp in [("landscape", (1280, 720)), ("portrait", (390, 844))]:
        pg = b.new_page(viewport={"width": vp[0], "height": vp[1]})
        pg.on("console", lambda m, n=name: lines.append((n, m.type, m.text)))
        pg.on("pageerror", lambda e, n=name: errors.append((n, str(e))))
        t0 = time.time()
        pg.goto("http://127.0.0.1:8060/index.html")
        boot = None
        while time.time() - t0 < 60:
            if any(n == name and "BOOT_OK" in t for n, _, t in lines):
                boot = time.time() - t0
                break
            pg.wait_for_timeout(200)
        results[name] = boot
        pg.wait_for_timeout(1500)
        pg.screenshot(path=f"{out}/{name}_1_hub.png")
        pg.focus("canvas")
        pg.keyboard.press("Enter")
        pg.wait_for_timeout(5000)
        for k in ["ArrowLeft", "ArrowLeft", "ArrowRight"]:
            pg.keyboard.press(k)
            pg.wait_for_timeout(400)
        pg.screenshot(path=f"{out}/{name}_2_run.png")
        t1 = time.time()
        while time.time() - t1 < 45 and not any(n == name and "RUN_END" in t for n, _, t in lines):
            pg.wait_for_timeout(300)
        pg.wait_for_timeout(1500)
        pg.screenshot(path=f"{out}/{name}_3_result.png")
        pg.keyboard.press("Enter")
        pg.wait_for_timeout(800)
        results[name + "_run_end"] = time.time() - t1 if any(n == name and "RUN_END" in t for n, _, t in lines) else None
        pg.close()
    # one screenshot mid-run in every biome via the ?biome=N preview
    for bi in range(8):
        pg = b.new_page(viewport={"width": 1280, "height": 720} if bi % 2 == 0 else {"width": 390, "height": 844})
        pg.on("console", lambda m, n=f"biome{bi}": lines.append((n, m.type, m.text)))
        pg.on("pageerror", lambda e, n=f"biome{bi}": errors.append((n, str(e))))
        pg.goto(f"http://127.0.0.1:8060/index.html?biome={bi}")
        t0 = time.time()
        while time.time() - t0 < 30 and not any(n == f"biome{bi}" and "BOOT_OK" in t for n, _, t in lines):
            pg.wait_for_timeout(200)
        pg.wait_for_timeout(800)
        if bi == 0:
            pg.screenshot(path=f"{out}/hub_preview.png")
        pg.focus("canvas")
        pg.keyboard.press("Enter")
        pg.wait_for_timeout(3500)
        pg.keyboard.press("ArrowLeft")
        pg.wait_for_timeout(700)
        pg.screenshot(path=f"{out}/biome_{bi}.png")
        pg.close()
    b.close()
srv.shutdown()

fps = [t for _, _, t in lines if t.startswith("FPS")]
cerr = [f"{n}: {t}" for n, ty, t in lines if ty == "error"] + [f"{n}: {e}" for n, e in errors]
ok = all(v is not None for v in results.values())
with open(f"{out}/report.md", "w") as f:
    f.write("# Smoke test\n\n")
    for k, v in results.items():
        f.write(f"- {k}: boot {'FAILED' if v is None else f'{v:.1f} s'}\n")
    f.write(f"- FPS samples (software WebGL, not real-device speed): {', '.join(fps[-6:]) or 'none'}\n")
    f.write(f"- console errors: {len(cerr)}\n")
    for e in cerr[:30]:
        f.write(f"  - {e}\n")
    f.write("\n## Console\n\n```\n" + "\n".join(f"[{n}] {ty}: {t}" for n, ty, t in lines[:200]) + "\n```\n")
print(open(f"{out}/report.md").read())
sys.exit(0 if ok else 1)
