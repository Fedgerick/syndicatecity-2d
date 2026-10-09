# SyndicateCity 2D

**SimCity + GTA**, in one game. Build a city, walk its streets, commit crimes.

Built with **Godot 4.5** (gl_compatibility, 2D UI + 3D world hybrid).

## How to launch

Double-click `launch.bat`, or run `install_shortcut.bat` once to drop a desktop icon.

Optional cmdline flags after `--`:
- `--time=0.5` — start sim time at noon (0.5 = noon)
- `--topdown` — start in top-down camera
- `--start` — skip the main menu (for headless testing / screenshots)
- `--easy` / `--hard` — set difficulty without going through the menu
- `--capture` — render one frame to PNG and quit (used by `capture.bat` / `showcase.bat`)

## Controls

### Movement
- **WASD** or **arrow keys** — walk
- **Mouse** — place/remove zones
- **F** — enter / exit vehicle
- **E** — enter building
- **Esc** — exit building / vehicle / quit on game over

### Camera
- **C** — third-person
- **V** — overview
- **T** — top-down
- **Mouse drag** — rotate overview

### Building
- **1 / 2 / 3** — Residential / Commercial / Industrial zone
- **4** — Road
- **5** — Bulldoze
- **0 / Space** — Select tool
- **Click** — apply current tool at hover cell

### Combat
- **Space** (select mode, near a vehicle OR on foot) — shoot
- **G** — increase wanted level (for testing)

### Other
- **M** — advance to next mission
- **B** — open Store
- **TAB** — toggle stats overlay
- **P** — pause / resume
- **H** — start heist (when near the bank)
- **+ / -** — speed up / slow down time (0.25x .. 8x)
- **[** / **]** — lower / raise residential tax rate (0%..20%)
- **N** — cycle weather (CLEAR → RAIN → STORM)
- **F5** — save city
- **F9** — load city
- **R** — restart (or respawn after GAME OVER for $500)

## Difficulty

Press **1** / **2** / **3** on the main menu (or `--easy` / `--hard`).

- **Easy** — wanted gain halved, cheap bail, full ammo on death, auto-respawn at hospital.
- **Normal** — standard.
- **Hard** — wanted gain x1.5, $500 bail, -30 HP when busted, GAME OVER on death.

## Missions

Five story missions, $8,150 total earnings:

1. **Bust the Burglar** — Find and arrest the burglar (red capsule in the residential zone, $500).
2. **Bank Robbery in Progress** — Drive within 5m of the robber's getaway car ($1500).
3. **Tax Bonus** — Collect 5 yellow money pickups on the map ($750).
4. **The Big Heist** — Press H near the bank to start, escape the police for 30 seconds ($5000).
5. **Pizza Run** — Walk to the pizza shop (red building at grid 15,15), pick up the order, and deliver it to the green marker within 90 sim-seconds ($400). Failure costs $50. Press M to skip the pickup (no penalty).

Press **M** to advance between missions. Each mission has its own wanted threshold and objectives. M can also skip a stuck active mission (fails the delivery, but completes the others).

## Game systems

- **Wanted meter** — 0..5 stars. Decays 1 star every 8 seconds (2x faster inside buildings).
- **Police** — 2 patrol cars. Chase you when wanted > 0. Ramming deals damage proportional to speed.
- **Wanted decay** — go inside a building to hide.
- **NPCs** — 12 pedestrians walking road networks. Faster during day, slower at night.
- **Vehicles** — 4 parked cars (4 corners) + 12 traffic cars on roads.
- **Buildings** — 297 zoned cells + 12 rich interiors (apartment / shop / office / vault based on grid hash).
- **Day/night** — 60-sim-second days. Streetlamps turn on at night. Commercial zones glow with neon storefront lighting at night; residential/industrial windows emit warm light.
- **Vehicle lights** — Traffic, parked, and police cars get 2 white headlights at the front and 2 red tail lights at the rear. They auto-toggle with the day/night cycle, so the city has moving points of light at night.
- **Dynamic weather** — 3 states (CLEAR / RAIN / STORM) that auto-cycle every 90 sim-seconds. Rain = 240 falling blue streak particles + greyer overcast sky + dimmer ambient. Storm = rain + wind drift on rain + noticeably darker. Press N to cycle manually. Cmdline: `--rain` or `--storm` to force a starting state. Saved/loaded.
- **City health warnings** — Banners surface SimCity failure modes so the simulation has a visible feedback loop: BUDGET CRISIS (3+ days deficit, red), POPULATION EXODUS (down 15% from peak, orange), NEED WORKERS (industry outpacing residential, yellow), UNEMPLOYMENT (residential without jobs, blue). Each warning names the cause and the fix.
- **Random events** — every 20 seconds a mugging/car-theft/fire spawns. Get within 4m to resolve for $300. Each event spawns a ring of **traffic cones** (orange, pulsing at 3 Hz) around the site — the city responds with a roadblock.
- **Traffic cones** — 20 pre-built orange cones (emissive, pulse at night). Spawn at random events as roadblocks, and police set up a roadblock (4 cones across the nearest road) when wanted ≥ 3. Cones auto-clear when the event is resolved or wanted drops. Recycle after 60s.
- **Store** — Health Pack ($200), Ammo Crate ($150), Bail Bond ($500), Smog Upgrade ($1000).
- **Stats** — kills, money, distance walked, missions done.
- **Save/Load** — F5 saves full game state (version 3), F9 loads.

## What's not yet verified

This host has **no active Windows desktop session** (no explorer/dwm, qwinsta empty).
Godot's display server keeps the engine ticking but does not draw to a visible window.
`capture.bat` / `--capture` work because they quit before display timeout.

If you double-click `launch.bat` from your own desktop (where the display server is
alive), all of the above should work as a real game.

## Repo structure

- `main.gd` — entire game (~2,800 lines, single file by design)
- `main.tscn` — root scene
- `project.godot` — Godot project config (gl_compatibility, 1280x720)
- `launch.bat` — local desktop launcher
- `install_shortcut.bat` — desktop-icon installer
- `capture.bat` — single-frame screenshot helper
- `showcase.bat` — 4-view (noon/dusk/night/topdown) renderer
- `screenshots/` — rendered gameplay images
- `user://city_save.json` — saved game state (Godot user data dir)

Built over multiple nights, single-developer (AI-assisted) project. Most recent push: 2026-10-06.