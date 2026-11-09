"""Economy pacing simulator for Dig to the Other Side.

Simulates a reasonable player (buys the cheapest of fuel/drill/ore between runs)
and reports minutes spent in each biome. Run: python3 tools/balance_sim.py
Exit code 1 if pacing misses the targets in data/biomes.json.
"""
import json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
UP = json.loads((ROOT / "data/upgrades.json").read_text())
BIO = json.loads((ROOT / "data/biomes.json").read_text())
CFG, BIOMES = BIO["config"], BIO["biomes"]


def cost(key, lvl):
    u = UP[key]
    return u["base_cost"] * u["growth"] ** lvl


def simulate(verbose=False):
    lv = {"fuel": 0, "drill": 0, "ore": 0}
    coins, t = 0.0, 0.0
    start_rows = [sum(b["rows"] for b in BIOMES[:i]) for i in range(len(BIOMES))]
    reached = 0                       # deepest biome index entered
    best_row = 0
    entered = {0: 0.0}
    runs = 0
    while best_row < sum(b["rows"] for b in BIOMES) and t < 4 * 3600:
        runs += 1
        fuel = CFG["base_fuel_s"] * UP["fuel"]["effect"] ** lv["fuel"]
        power = UP["drill"]["effect"] ** lv["drill"]
        mult = UP["ore"]["effect"] ** lv["ore"]
        row = start_rows[reached]     # elevator: start at deepest biome reached
        bi = reached
        earned = 0.0
        while fuel > 0:
            b = BIOMES[bi]
            if lv["drill"] < b["min_drill"]:
                break                 # hit a wall this drill can't break
            dt = b["hardness"] / power
            if dt > fuel:
                break
            fuel -= dt
            t += dt
            row += 1
            earned += (b["ore_density"] * b["ore_value"] + b["rock_value"]) * mult
            if bi + 1 < len(BIOMES) and row >= start_rows[bi + 1]:
                bi += 1
                if bi > reached:
                    reached = bi
                    entered[bi] = t
            if row >= start_rows[-1] + BIOMES[-1]["rows"]:
                break
        best_row = max(best_row, row)
        coins += earned
        t += CFG["run_overhead_s"]
        # shop: buy cheapest available upgrade until broke
        while True:
            k = min(lv, key=lambda k: cost(k, lv[k]))
            c = cost(k, lv[k])
            if c > coins:
                break
            coins -= c
            lv[k] += 1
            t += CFG["seconds_per_purchase"]
    entered[len(BIOMES)] = t
    rows = []
    for i, b in enumerate(BIOMES):
        end = entered.get(i + 1, t)
        rows.append((b["name"], (end - entered.get(i, t)) / 60))
    return rows, t / 60, runs, lv


def main():
    rows, total, runs, lv = simulate()
    ok = True
    print(f"{'Biome':<16}{'minutes':>8}   target")
    for (name, m), b in zip(rows, BIOMES):
        lo, hi = b["target_min"]
        flag = "" if lo <= m <= hi else "  <-- off target"
        ok &= not flag
        print(f"{name:<16}{m:8.1f}   {lo}-{hi}{flag}")
    lo, hi = CFG["target_total_min"]
    flag = "" if lo <= total <= hi else "  <-- off target"
    ok &= not flag
    print(f"{'TOTAL':<16}{total:8.1f}   {lo}-{hi}{flag}")
    print(f"runs: {runs}   final levels: {lv}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
