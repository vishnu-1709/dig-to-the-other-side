# Dig to the Other Side — project rules

2D mining incremental for CrazyGames (first) and Poki (later), built in Godot 4 (latest stable).
The player drills through a 12,742 km planet and breaks out on the far side. Every ore plays a
musical note quantized to the beat. Revenue = ad revenue share, so playtime and return visits matter most.

Full design: see the "Dig to the Other Side — Build Plan" doc. This file is the build contract.

## Hard limits (a build that breaks one of these is a failed build)
- Compressed (brotli) web download < 8 MB total. Target: engine 4–6 MB, content < 2 MB.
- Playable within 3 s of load. No title gate, no text tutorial, no login.
- 60 FPS desktop; 50+ FPS on a low-end Android phone.
- Works with touch, mouse and keyboard. Landscape AND portrait from one layout.
- Ads only through the Portal autoload (CrazyGames / Poki SDK). No other ad networks or outside links.
- Only original or openly licensed assets. No real brands or characters.

## Godot web export settings
- Renderer: Compatibility (GL) for all platforms. No Forward+/Mobile features.
- Web export: single-threaded (thread support OFF), release template, VRAM compression for desktop + mobile.
- GDScript only (no C#). No GDExtension.
- Custom stripped export template once the feature set is stable (drop 3D, unused modules).
- Audio: OGG Vorbis, mono, short loops. Schedule note sounds slightly ahead on the beat clock (web audio latency).

## Architecture
| Path | Role |
| --- | --- |
| `scenes/main.tscn` | Surface hub + responsive layout (shop left / stats right in landscape; pull-up shop in portrait) |
| `scenes/shaft.tscn` | One dig run: chunked TileMap block grid, drill, hazards, camera |
| `scripts/autoload/game.gd` | Single source of truth: coins, upgrade levels, depth, deepest biome, prestige |
| `scripts/autoload/save.gd` | Local storage save every 10 s + on exit/hide; versioned format with migration |
| `scripts/autoload/music.gd` | Beat clock, stem layering by combo, note quantizing, key per biome |
| `scripts/autoload/portal.gd` | One API: `rewarded(reason) -> bool`, `midgame()`, `gameplay_start/stop()`, `banner(show)`. Backends: crazygames, poki, fake (dev) |
| `scenes/fx.gd` | Additive glow (ores, hazards, headlight) + particle pools; cosmetic only |
| `scenes/planet_map.gd` | Hub planet cross-section with the record-depth tunnel |
| `scripts/ui_theme.gd` | `UiTheme.build()` — font, panels, button/label variations |
| `tools/art/gen_tiles.py`, `tools/audio/gen_audio.py` | Regenerate all art / audio from code |
| `data/*.json` | ALL tuning numbers. Never hard-code costs, values, hardness, cooldowns in scripts |
| `tools/balance_sim.py` | Pacing simulator; must exit 0 before any economy change is committed |
| `tests/` | Headless-browser smoke test (load time, FPS, console errors, size) |

## Game rules (current design)
- Run: hold to drill down, drag/keys to steer. Fuel runs out -> auto-return to surface, bank coins, shop.
- Runs start at the top of the deepest biome reached (elevator), not at the surface.
- Upgrade cost = base_cost * growth^level (data/upgrades.json). Effects multiply per level.
- Biomes in data/biomes.json; pacing target 30–45 min to the far side (sim 42 min / 37 runs; bot 32 min / 33 runs).
- Fuel Tank capped at 16 levels so runs stay ~1 min (natural ad breaks).
- Hazard blocks cost fuel (Heat Shield reduces); Magnet grabs ore in the same row; Core drains fuel 1.5x.
- Offline earnings from auto-miners, capped at 4 h; rewarded ad claims x3.
- Prestige ("Reforge") after the breakthrough: reset for Core Shards, +5% coins each, permanent.

## Testing shortcuts
- `?reset` wipes the save. `?biome=N` (0-7) previews biome N with fitting upgrades and never saves.
- CI runs: unit test, 8-run bot, full-game bot to the breakthrough (~32 game-min), web export,
  size check, browser smoke test with screenshots pushed to the `ci-report` branch.

## Ads
- Rewarded: offline x3, end-of-run double, +10 s fuel near rare ore (1/run), 3-min overclock.
- Midgame: first entry to a new biome (max once per 3 min), after a Reforge. Never mid-run.
  Never in a new player's first 2 minutes.
- Pause game + mute audio during ads. If an ad fails, give a smaller fallback reward.

## Working rules
- One feature per change. Export, run the smoke test and the balance sim, then commit.
- Gray-box first: no final art until the loop is fun with coloured squares.
- Keep the shaft chunked: only ~2 screens of rows alive; free rows above the camera.
- Particles capped on mobile. No full-screen shaders that run every frame on mobile.
- Commit messages: `area: what changed` (e.g. `shaft: chunked row generation`).
