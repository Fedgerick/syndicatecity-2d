# SyndicateCity — Game Design Specification

**Version:** 0.7 (v7 build)
**Engine:** Godot 4.5 stable, gl_compatibility, 2D UI + 3D world hybrid
**Tagline:** *SimCity + GTA, in one game. Build a city. Walk its streets. Commit crimes.*

---

## 1. Vision

A single-player, real-time city-builder with full player agency. Two pillars fused:

- **City simulation** (SimCity): zones grow when placed near roads. Population, tax income, day/night cycle, demand bars, budget, growth ticks.
- **Free-roam player** (GTA): the player character walks the streets, drives vehicles, enters buildings, shoots, gets a wanted meter, triggers missions, and changes the city by their actions (or doesn't).

The city is **both a thing you build and a place you live in.** Most city-builders abstract the player out; most sandbox games abstract the city out. SyndicateCity puts them on the same map, same time, same camera.

Target feel: 30-minute sessions where the player builds 10 zones, drives a red sedan into a lake, gets chased by police, abandons the chase, walks into a bank, robs it, escapes, and finds a new city block has burned down while they were running.

---

## 2. Pillars (design priorities)

When in doubt, optimize for these in order:

1. **Cause and effect are visible.** Every action has a visible response within 1 second (audio + visual + UI).
2. **You can always do something.** The city never idles. Even with 0 zones placed, NPCs walk, cars drive, day/night cycles, and random events spawn.
3. **Risk ↔ reward is real.** $5000 heist → 5 wanted stars → 30-second escape timer. Busted = -$200 (or GAME OVER on hard).
4. **The city grows whether you play it or not.** Population, tax income, day count advance even if the player stands still.
5. **No modal menus block gameplay.** Pause (P), menu (B), help (H), stats (TAB) all overlay the world. Only GAME OVER / WIN halts the simulation.

---

## 3. World

### Grid

- **32×32 cell** grid, 2m cell size → **64m × 64m** playable area.
- World coordinates: `x, z ∈ [-32, +32]` (centered on origin). `y` is up.
- Cell hash: `(x, z) → cell_color: int, cell_density: int, custom_road: bool`.
- Each cell can be: empty, road, building (with color 0–5 → res/com/ind densities, etc).

### Rendering

- **3D world**, isometric perspective (camera at yaw 35°, pitch -50°, dist 90 by default).
- **2D UI overlay** via CanvasLayer — minimap, HUD, hints, menus.
- gl_compatibility driver — works on low-end hardware.
- All buildings are procedural (no assets). Tree, lamp, car, NPC, road strip, building block — every mesh is built from BoxMesh / SphereMesh / CylinderMesh / PlaneMesh at runtime.

### Biomes

- **City core:** flat grass with buildings, roads, lamps.
- **River:** south edge, animated water plane.
- **Hills:** east edge, two terrain bumps with grass on top.
- **Trees:** 30 procedural trees scattered through the city.

### Time

- **60 sim-seconds = 1 day.** Time-of-day `_t` is in `[0, 1)`.
  - `:00–:25` night → `:25–:30` dawn → `:30–:70` day → `:70–:75` dusk → `:75–:00` night.
- Sun position, sky color, ambient light, lamp emission, NPC speed, building window glow all keyed off `_t`.
- Time speed: 0.25x .. 8x, adjustable with +/- keys.

---

## 4. Player

### Character

- Single-player, no multiplayer.
- Mesh: capsule body + sphere head. Procedural.
- Default position: `(0, 0.7, 0)` (center of map).
- Health: 100 max. **HP regenerates at +5/sec when health > 50 and wanted = 0.**
- Ammo: 30 max. Reloads at stores only (no infinite-ammo exploits).

### Controls

| Input | Action |
|---|---|
| WASD / arrows | Walk |
| Mouse | Aim/look (third-person) / place zones (overview) |
| F | Enter/exit vehicle |
| E | Enter building |
| Esc | Exit building / vehicle / quit on GAME OVER |
| Space (on foot, select tool) | Shoot |
| 1/2/3/4/5/0 | Tool: res / com / ind / road / bulldoze / select |
| Click | Apply tool |
| C / V | Third-person / overview camera |
| T | Top-down toggle |
| B | Store menu |
| M | Next mission |
| H | Help toggle OR start heist (when near bank) |
| TAB | Stats overlay |
| P | Pause |
| G | Cheat: +1 wanted (debug) |
| +/- | Time speed |
| F5/F9 | Save / Load |
| R | Restart / respawn |

### Movement physics

- Player speed: 6 m/s on foot, up to 22 m/s in vehicle.
- Collision with buildings: slide-along-axis.
- Vehicle: same physics, with hit-against-NPC/Car/Pickup.

---

## 5. Economy & budget

### Starting state

- $20,000 starting cash.
- Population: 1,250 starting residents.

### Income

- **Daily tax income**: `population × tax_rate × income_per_capita`. With 1,250 × 4% × 0.5 = ~$25/day at start.
- **Mission rewards**: $250 (M3) to $5,000 (M4).
- **Pickups**: $50..$250 each.
- **Event resolve**: $300.
- **Robbery / Heist**: $5,000 per heist.

### Expenses

- **Daily expenses**: $5 × day_count (rises over time).
- **Busted penalty**: -$200 (normal), -$500 (hard).
- **Death penalty**: -$500 (respawn on hard).
- **Store purchases**: variable ($150–$1,000).

### Demand bars

3 bars, 0..100 each:
- **Residential demand**: how much the city wants new homes. Falls as R zones fill.
- **Commercial demand**: same for shops.
- **Industrial demand**: same for factories.

Placement of zones pushes that demand down (already satisfied). New building types raise it.

### Growth

- Each day, if a zone cell has road-adjacency AND population > 1000 AND budget > $10,000:
  - With probability 10%, density 1 → 2 (visible floor added).
  - With probability 5%, density 2 → 3.
- Building color subtly darkens with density.

### Future

- Loans from bank (interest rate).
- Bond issuance.
- Tax revolt (raise taxes too high → buildings abandoned).
- Welfare / education / healthcare policies.

---

## 6. Vehicles

### Parked cars (4 corners, enterable)

- Red, blue, yellow, green sedans.
- Press F within 4m of any one to enter.
- Driver seat view (third-person when driving).
- WASD steers + accelerates.
- Exit with F or Esc.

### Traffic cars (12)

- Random colors, drive on road paths.
- AI: lerp along path, smooth turn.
- Get out of player's way when blocked (or ram into them).

### Vehicle damage

- Bullets damage vehicles (smoky red overlay at 80%+ damage).
- Police ramming damages the player based on police speed.

### Future

- Helicopter (next session, parked on a helipad near the bank).
- Boat (river edge).
- Smog Upgrade (already in store: 1000 → max vehicle speed 22 m/s).

---

## 7. NPCs (12)

### Behavior

- Each NPC has a `path: Array[Vector3]` (two endpoints on road networks) and walks between them at 0.3..1.0 m/s.
- Speed multiplier: 1.0 during day (1 if `_t ∈ (0.3, 0.75)`, else 0.35 at night).
- Day-night cycle changes speed, not destinations.
- Mesh: capsule body, sphere head, random colored shirt.

### Future

- NPC names (random pool).
- Dialogue on T key when near an NPC.
- NPCs run from player when wanted > 0.
- Gang NPCs that fight each other.

---

## 8. Police (2 units)

### Behavior

- Patrol roads when wanted = 0. Idle near police station.
- When wanted > 0: chase player.
- Speed: 12 m/s base, +4 m/s per wanted star.
- Smooth turn (4 rad/s slew rate).
- Lightbar: red/blue alternating flash at 5 Hz.
- Siren: two-tone 700 Hz beep every 0.6s.

### Damage model

- Police ramming at speed > 8 m/s damages player: `clamp(speed * 1.5, 8, 30)` HP per hit.
- I-frame at 0.8s after hit.
- Police don't damage NPCs or each other.

### Spawn

- 2 base units.
- Heist mission spawns 3 extra units (5 total).
- Difficulty affects max units (3 in easy, 5 in hard).

---

## 9. Wanted meter (0..5 stars)

### Earn

- Shooting near an NPC: +1.
- Shooting a police car: +2.
- Running a red light (future): +1.
- Heist mission: instant 5.
- Robbing a bank: instant 5.

### Decay

- -1 star every 8 sim-seconds.
- **2x faster decay while inside a building** (hiding).
- Bail bond (store, $500): instant -2 stars.

### Effects

- Stars > 0: police chase.
- Stars >= 3: police chase speed +8 m/s, 3 extra units spawn at 4+.
- Stars == 5 for 12s on a mission: mission fails.

### Bust

- Police touches player at low speed: busted.
- -$200 (normal), -$500 (hard).
- Player respawned at police station cell.
- Wanted reset to 0.

### Death

- HP <= 0 on NORMAL/HARD: GAME OVER.
- HP <= 0 on EASY: auto-respawn at hospital with full HP and ammo.
- Death from police ram is the main cause.

---

## 10. Missions

4 story missions, total earnings $7,750. Press M to advance.

### M1: Bust the Burglar ($1,500)

- Yellow burglar figure spawns at random road cell.
- Walk within 1.5m to arrest.
- Wanted: 0..2 stars OK; if wanted hits 5 for 12s, mission fails.
- Completes when burglar mesh is touched.

### M2: Chase the Bank Robber ($1,000)

- Red robber figure spawns and runs away.
- Wanted +1 when you get close.
- Catch within 60s or mission fails.
- Police assist.

### M3: Tax Bonus ($250)

- 5 yellow money pickups spawn on roads.
- Walk within 1.5m to collect.
- Each pickup adds $50..$250 to budget.
- Time limit: 90s.

### M4: The Big Heist ($5,000)

- Press H when standing within 4m of the bank (visible corner building).
- Wanted → 5 instantly. 3 extra police units spawn.
- 30-second timer. Survive without being caught.
- +$5000 on success.

### Future missions

- Drug Run (collect 3-6 ammo pickups while avoiding police).
- Bounty Hunt (find and kill a specific NPC).
- Territory War (claim 5 buildings by standing inside them for 10s each).
- Heist Variants (jewel store, armored car).

---

## 11. Mission system (technical)

### Lifecycle

- All missions in `missions: Array[Dictionary]`.
- `current_mission: Dictionary` is the active one.
- `completed_missions: Array[String]` is the IDs.
- Pressing M calls `_next_mission()` which picks the next uncompleted.

### Per-mission state

```
{
  "id": "collect_bonus",
  "title": "Tax Bonus",
  "objective": "Collect 5 money pickups on the streets",
  "reward": 250,
  "wanted_threshold": 2,  # can fail if wanted exceeds
  "spawn_count": 5,
  "time_limit": 90.0,
  "fail_timer": 0.0  # accumulated time above wanted threshold
}
```

### Failure conditions

- Time limit expires.
- Wanted >= wanted_threshold for 12s straight.
- Player dies / GAME OVERs mid-mission.

### Success

- `objective complete` → +reward → announcement → next mission unlocked.

### Future

- Random side missions from NPCs.
- Mission 5: Helicopter Getaway (escape to the helipad).
- Mission 6: Bunker Heist (multi-stage).
- Story branching (heist success/failure affects ending).

---

## 12. Buildings

### Types

- **Empty cell** — grass.
- **Road** — asphalt strip, 0.05m raised.
- **Residential zone** — brown/green tower, 1-3 floors based on density (1-3).
- **Commercial zone** — yellow/blue low-rise with windows.
- **Civic** — large white building (only one, the police station/hospital combo).
- **Bank** — red corner building, Big Heist target.

### Density

- Starts at 1 on placement.
- Increases when road-adjacent + population > 1000 + budget > $10,000.
- Max density 3 (visible floor height).

### Interiors (rich, 4 types)

When player presses E near a building:

- **Apartment** (1/4 buildings): bed + table + couch.
- **Shop** (1/4): counter + 3 shelves.
- **Office** (1/4): desk + chair + monitor.
- **Vault** (1/4): safe + 9 gold bars (this is the bank interior).

Interior lighting dimmed, player can shoot inside (limited ammo), can walk out any time with E or Esc.

---

## 13. Random city events

Every 20s, an event spawns at a random road cell:

- **Mugging** — red marker, 25s lifetime. Walk within 4m to resolve. +$300.
- **Car Theft** — yellow marker, 25s. +$300.
- **Fire** — orange marker, 25s. +$300.

If timer expires: EVENT FAILED (no reward, no penalty). Marker disappears.

### Future

- More types: gang war, hostage, robbery, parade.
- Side quests given by NPCs (press T near pedestrian → quest log).
- Multi-stage events (chained).

---

## 14. Store (B key)

| Item | Cost | Effect |
|---|---|---|
| 1. Health Pack | $200 | +50 HP |
| 2. Ammo Crate | $150 | +30 ammo |
| 3. Bail Bond | $500 | wanted -2 |
| 4. Smog Upgrade | $1000 | vehicle max speed → 22 m/s |
| 0. Close | — | close menu |

Only available when player has $ in their pocket. Cannot buy if item grayed out (insufficient funds).

---

## 15. Difficulty

| Mode | Wanted gain | Bust damage | Death behavior |
|---|---|---|---|
| Easy | × 0.5 | none | auto-respawn, +ammo, +$1000 floor |
| Normal | × 1.0 | none | -$200 on bust, GAME OVER on death |
| Hard | × 1.5 | -30 HP | -$500 on bust, GAME OVER on death, tougher AI |

Press 1/2/3 on main menu, or pass `--easy` / `--hard` on cmdline.

---

## 16. Save / Load

- Single slot: `user://city_save.json`.
- F5 = save, F9 = load.
- v3 schema: day count, budget, population, time, wanted, player pos, buildings list, roads list, stats (kills, money, distance, missions failed), completed missions, current mission idx, health, ammo, difficulty, total play time, total deaths.
- Save is full-state, restore is destructive (current city wiped first).

---

## 17. UI surfaces

### Main menu (CanvasLayer 10)

- Title "SYNDICATE CITY" (yellow, 72pt).
- "SimCity + GTA" subtitle.
- Instructions block.
- Difficulty hint (1/2/3).
- "Press ENTER or click to start."
- Dismissed by ENTER, click, or `--start` cmdline flag.

### Context hint banner (CanvasLayer 4)

- Top of screen.
- Shows current mission, driving/hiding state, wanted level, event timer.
- Color shifts: white → yellow → red with urgency.

### HUD (CanvasLayer 3)

- Top-left: AMMO / HP / SPD / DAY.
- Top-right: $ Budget, Population, Wanted stars.
- Bottom: tool selector (1/2/3/4/5/0).
- Bottom-left: minimap.

### Minimap (CanvasLayer 5)

- 256×256 image bottom-left.
- Roads in dark gray, buildings in zone colors.
- Player in yellow.
- Police in blue with flashing border.
- Vehicle in bright yellow.
- Event marker in pulsing red.

### Mission overlay (CanvasLayer 6)

- Title + objective + reward + timer.

### Stats overlay (CanvasLayer 6)

- TAB toggles.
- Kills, money, distance walked, missions done/failed, total play time, deaths.

### Announcement (CanvasLayer 8)

- Yellow banner, 3s duration, fades out.
- Used for: mission start, mission complete, wanted up, low HP, store purchase, event spawn, NPC dialogue (future).

### Buy menu (CanvasLayer 7)

- B opens. Click 1/2/3/4 to buy, 0 to close.

### Random event marker (CanvasLayer 9)

- 3D marker plus HUD label with countdown.

### Damage flash (CanvasLayer 11)

- Red overlay, 0.2s duration on hit.

### Final / GAME OVER (CanvasLayers 12, 13)

- Black/dark card with score, stats, restart prompt.

---

## 18. Audio

All audio is procedural (sine-wave beeps via `AudioStreamGenerator`):

- Pickup: 880 Hz, 80ms.
- Crash: 180 Hz, 150ms.
- Enter building: 660 Hz, 60ms.
- Police siren: 700 Hz two-tone, repeats every 0.6s.
- Mission complete: 660 + 880 Hz chord.
- Gunshot: 110 Hz low-freq thump.
- Damage hit: 110 Hz warning beep.
- Out-of-ammo: 110 Hz, 100ms.

### Future

- Replace beeps with streamed WAV/MP3 samples (real gunshots, real crashes).
- Music: ambient city drone + chase music during wanted.
- Adaptive audio: more sirens at higher wanted levels.

---

## 19. Camera

### Modes

- **Overview** (default): isometric 35° yaw, -50° pitch, 90m dist.
- **Third-person** (C): follows player at 35° yaw, -25° pitch, 12m dist.
- **Top-down** (T): 0° pitch, 90m dist.
- Mouse drag rotates overview yaw by 0.5°/px.

### Future

- First-person when in building (was a v3 idea; deferred).
- Cinematic camera for cutscenes / mission intros.
- Picture mode (free camera, no time advance).

---

## 20. Tech architecture

- **Single-file GDScript**: `main.gd` (~2,900 lines). All logic in one file. Simple to reason about, single source of truth.
- **No external assets**: all meshes, audio, UI built at runtime.
- **Single scene**: `main.tscn` with `main.gd` as root script.
- **Procedural grid**: cells stored in `placed_buildings: Array[Vector3i]` and dicts `cell_color`, `cell_density`, `custom_roads`.

### Subsystems (each has its own update tick):

| Tick | System | File location |
|---|---|---|
| _process | Time-of-day advance, sun position, sky color | line ~179 |
| _process | Sim daily tick (tax income, expenses) | line ~192 |
| _process | Player movement + collision | _update_player |
| _process | Vehicle driving + hit detection | _update_vehicle |
| _process | NPC walking | _update_npcs |
| _process | Police chase | _update_police |
| _process | Bullet physics + collision | _update_bullets |
| _process | Pickup animation + collection | _update_pickups |
| _process | Mission state machine | _update_mission |
| _process | Heist escape timer | _update_heist |
| _process | Random event spawn/resolution | _update_random_events |
| _process | HUD refresh | _refresh_hud |
| _process | Minimap redraw | _update_minimap |
| _process | Context hint update | _update_context_hint |
| _process | Player status (HP, i-frames) | _update_player_status |
| _process | Damage flash decay | inline in _process |
| _process | Wanted decay | _update_wanted |
| _process | Total play time + game-complete check | inline |

### Performance budget

- Target: 60 fps at 1280×720 on integrated graphics.
- ~297 buildings, 12 NPCs, 12 traffic cars, 2 police, 4 parked cars, 12 lamps, 30 trees.
- Each frame: ~10K vertices drawn. Well within budget.

### Future

- Split into multiple files (`player.gd`, `world.gd`, `police.gd`, etc).
- Use GDScript's static typing more aggressively.
- Add a profiler pass to find hot frames.

---

## 21. Roadmap

### v8 (next session)

- [x] **Neon storefront glow / night window emission** — commercial zones glow magenta/cyan at night, lamps flicker warmly.
- [ ] Helicopter vehicle (spawn on helipad, fly with WASD + Space/Shift)
- [ ] NPC dialogue (T key near pedestrian, dialogue trees)
- [ ] Side quests from NPCs (3-5 chain quests)
- [ ] Heist variants (jewel store, armored car)
- [ ] Save thumbnails (PNG preview in load dialog)
- [ ] Settings menu (volume, keybinds, screen size)

### v9

- [ ] Weather (rain, snow, fog) affecting NPC behavior
- [ ] Day/night affects business open/closed (shops open only during day)
- [ ] Real gunshots + crashes (replace beeps)
- [ ] Adaptive music
- [ ] Multi-floor interiors (stairs between floors)

### v10

- [ ] Multiplayer co-op (city-build with friends)
- [ ] Procedural city names (New San Fierro, Vice City, etc.)
- [ ] Bigger map (64×64 cells, multiple districts)
- [ ] Subway / metro system
- [ ] Cinematic story campaign (8 missions, true ending)

---

## 22. Anti-goals (what this game is NOT)

- **Not a roguelike.** Permadeath is per-run (R restarts) but you don't lose unlocks between runs.
- **Not multiplayer.** Single-player only. Co-op is a long-term maybe.
- **Not pixel art / not 3D AAA.** Procedural gl_compatibility. Embracing the constraints.
- **Not a city builder first.** The simulation runs even when the player does nothing, but the player's actions are what drives the fun loop. Cities don't need to be "optimal".
- **Not realistic.** Police AI is forgiving. Cars don't have engine failures. NPCs don't have schedules.

---

## 23. Inspiration

- **SimCity 2000 / 3000** — zone adjacency, demand, growth, day/night, civic structures.
- **GTA 1 / 2 / Vice City** — top-down free roam, wanted meter, on-foot + car + enter buildings.
- **Cities: Skylines** — road-first zone growth (zone must touch road to develop).
- **Satisfactory** — procedural everything, no asset pipeline.
- **Dwarf Fortress** — emergent simulation, every system ticks every frame.
- **Elite Dangerous** — single-player with deep systems but you can always do *something*.

---

## 24. Open questions

- Should buildings have "owners" (NPCs tied to buildings)?
- Should the player have a house they can fast-travel to?
- Multi-district: how big before the single-frame render chokes?
- Should random events ever spawn hostile NPCs that shoot back?
- Should the player be able to buy property / claim territory?
- Weather: how does rain affect NPC behavior? Fire spread?
- Multiplayer: how does the world sim stay consistent across clients?

These are intentionally deferred — each one needs user playtesting to know if it's a feature or noise.

---

*End of spec.*