"""Economy pacing simulator for Dig to the Other Side.

Models a reasonable player: steers onto some ore, dodges most hazards, and between runs
buys the cheapest affordable upgrade until broke. Mirrors the rules in scenes/shaft.gd:
hard blocks take 2x, hazards cost fuel (reduced by Heat Shield), magnet grabs ore in the
same row, auto-miners earn coins over time, runs restart at the deepest biome reached.

Run: python3 tools/balance_sim.py   (exit 1 if pacing misses targets in data/biomes.json)
"""
import json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load():
    up = json.loads((ROOT / "data/upgrades.json").read_text())
    bio = json.loads((ROOT / "data/biomes.json").read_text())
    return {k: v for k, v in up.items() if not k.startswith("_")}, bio["config"], bio["biomes"]


def simulate(up=None, cfg=None, biomes=None):
    if up is None:
        up, cfg, biomes = load()
    keys = list(up)
    lv = {k: 0 for k in keys}

    def cost(k):
        return up[k]["base_cost"] * up[k]["growth"] ** lv[k]

    def mult(k):
        u = up[k]
        return u["effect"] * lv[k] if u.get("additive") else u["effect"] ** lv[k]

    starts, acc = [], 0
    for b in biomes:
        starts.append(acc); acc += b["rows"]
    total_rows = acc
    coins, t, runs, reached, best = 0.0, 0.0, 0, 0, 0
    entered = {0: 0.0}
    steer = cfg["steer_collect"]
    while best < total_rows and t < 3 * 3600:
        runs += 1
        fuel = cfg["base_fuel_s"] * mult("fuel")
        power, cm = mult("drill"), mult("ore")
        radius = mult("magnet")
        row, bi = starts[reached], reached
        run_t = 0.0
        while fuel > 0 and row < total_rows:
            b = biomes[bi]
            if lv["drill"] < b["min_drill"]:
                break
            dt = b["hardness"] * (1 + cfg["hard_p"]) / power
            fuel -= dt * b.get("fuel_drain", 1.0)
            fuel -= b["hazard_p"] * cfg["hazard_hit_rate"] * cfg["hazard_fuel_s"] * mult("shield")
            if fuel < 0:
                break
            run_t += dt
            row += 1
            density = min(steer + cfg["ore_p"] * 2 * radius, cfg["ore_p"] * 9)
            coins += (density * b["ore_value"] + b["rock_value"]) * cm
            if bi + 1 < len(biomes) and row >= starts[bi + 1]:
                bi += 1
                if bi > reached:
                    reached = bi
                    entered[bi] = t + run_t
        best = max(best, row)
        run_t += cfg["run_overhead_s"]
        t += run_t
        # auto-miners earn during the whole run (online rate)
        coins += lv["miners"] * cfg["miner_rate"] * biomes[reached]["ore_value"] * run_t
        while True:
            k = min((k for k in keys if lv[k] < up[k]["max"]), key=cost, default=None)
            if k is None or cost(k) > coins:
                break
            coins -= cost(k); lv[k] += 1
            t += cfg["seconds_per_purchase"]
    entered[len(biomes)] = t
    rows = [(b["name"], (entered.get(i + 1, t) - entered.get(i, t)) / 60) for i, b in enumerate(biomes)]
    avg_run = t / max(runs, 1)
    return rows, t / 60, runs, lv, avg_run


def main():
    up, cfg, biomes = load()
    rows, total, runs, lv, avg_run = simulate(up, cfg, biomes)
    ok = True
    print(f"{'Biome':<16}{'minutes':>8}   target")
    for (name, m), b in zip(rows, biomes):
        lo, hi = b["target_min"]
        flag = "" if lo <= m <= hi else "  <-- off target"
        ok &= not flag
        print(f"{name:<16}{m:8.1f}   {lo}-{hi}{flag}")
    lo, hi = cfg["target_total_min"]
    flag = "" if lo <= total <= hi else "  <-- off target"
    ok &= not flag
    print(f"{'TOTAL':<16}{total:8.1f}   {lo}-{hi}{flag}")
    print(f"runs: {runs}   avg run: {avg_run:.0f} s   final levels: {lv}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
