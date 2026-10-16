# Process audit: from five islands to a living sea (Oct 5 – Oct 16, 2026)

This file is an honest log of how the project got from the "CV-first" release (commit `547ef97`,
Oct 5) to the world that is live today: what was built, what broke, how each problem was found and
how it was fixed, with the numbers that were actually measured. The earlier phases (Oct 1 – Oct 5)
are summarized in the [README](../README.md#end-to-end-process) and in `Documentation/REVISAO_*.md`.

Everything here can be checked in the repository: the scripts named below, the test scripts in
`Tests/` that produced each number, and the screenshots in `docs/images/process/`.

---

## 0. How the work was done

- **Direction and decisions: me.** I chose every model, every biome, every creature, and approved or
  rejected each result after watching the recorded videos and screenshots. Many Meshy models were
  generated more than once until they looked right.
- **3D models: Meshy.ai.** Islands, biome landmarks, cities, colossi, the Kraken, buoys and props.
  Some came with Meshy's auto-rig; the Kraken maw did not and was rigged in Blender (below).
- **Code: Claude Code as a tool**, connected to Godot and Blender through MCP. During this phase I
  ran several sessions in parallel (world/biomes, creatures and animation, sound, sky, web build),
  each in its own area of the project, coordinated by a main session.
- **Verification rule:** nothing was called done without proof from the engine itself. Every change
  was checked with a headless Godot run (no script errors), and visual changes with scripted
  screenshots or videos recorded with Godot's Movie Maker in the same renderer used on the web.
- **Hard rules kept from the brief:**
  - the original Meshy GLBs are never decimated in place; lighter copies are generated for the web;
  - nothing from Nintendo (models, textures, music, sounds) enters the project or the site;
    references stay on my machine;
  - no publish, commit or deploy without my explicit go-ahead.

---

## 1. Four biomes on an 800 m planet

**Goal:** the sea should never feel empty. From any point you can sail to, something new should be
on the horizon.

- `Scripts/WorldDecor.gd` splits the sphere into four equal sectors with their own art direction:
  - **North:** ruins and living runes;
  - **East:** driftwood and merchants;
  - **South:** abyss, volcano and the ghost sea;
  - **West:** corals and the turtle.
- Placement follows hard rules:
  - 230 m clear around each of the five portfolio islands;
  - a 40 m corridor along the sailing route;
  - 180 m clear around each colossus's path.
- `Tests/biome_layout_dump.gd` lists every item with its distance to the islands and to the route,
  and flags anything that breaks a rule.
- My reference was a 2D chart with 49 positions. Read literally on a sphere it needed a scale of at
  least 1.35, covered only ~39% of the planet and forced four portfolio islands to move. I chose to
  keep the islands and spread the chart's items over the four sectors.
- **Filling holes:** a last pass (`_fill_horizon_holes`) samples the open sea and adds an item
  wherever nothing would be visible.
  - The last full check covered the whole planet: 100% of sampled points with the larger
    landmarks, 99% with the current sizes, and one remaining ~20 m blind cell.

<p align="center">
  <img src="images/process/north-runestone-citadel.jpg" width="49%" alt="North: Runestone Citadel">
  <img src="images/process/east-driftwood-merchant.jpg" width="49%" alt="East: Driftwood Merchant">
  <img src="images/process/west-coral-paradise.jpg" width="49%" alt="West: Coral Paradise">
  <img src="images/process/south-basalt-caldera.jpg" width="49%" alt="South: basalt caldera with smoke and lava">
</p>

<p align="center">
  <img src="images/process/world-map-layout.jpg" width="90%" alt="World map: four sectors, routes, islands and every item">
</p>

---

## 2. Colossi, sea life and the Kraken

- **Colossi:** a timber whale, a granite crab, an obsidian giant and a stone turtle carrying an
  island. Each one circles its own sector slowly (`Scripts/SeaBeasts.gd`, the turtle in
  `WorldDecor.gd`). They leave a wake, push ripples on the water and are tied into the calm-water
  system, so the ship floats correctly next to them.
- **Animation:**
  - **Rigged in Meshy:** the colossi used Meshy's rig and were animated in Blender (headless, from
    scripts: `Tools/animate_meshy_rigs_blender.py`, `Tools/rig_creatures_blender.py`).
  - **Body and shell:** stiff "shrimp" motion was rejected more than once. The crab and turtle
    shells are now rigid; only legs, flippers and tails bend.
  - **Kraken maw:** the new model had no rig. `Tools/rig_kraken_maw_blender.py` finds the 9 fangs by
    clustering the vertex angles, builds one bone per fang, weights them by height and angle, and
    adds a looping "Gnash" bite that runs around the ring.
- **Sea life** (`Scripts/SeaLife.gd`, `Scripts/SeaShadows.gd`, `Scripts/Seagulls.gd`):
  - rare dolphin pods that overtake the ship;
  - flying fish and seagull flocks;
  - shadows of animals under the hull.
- **The Kraken** (`Scripts/KrakenEvent.gd`): a rare encounter in open sea.
  - The tentacles rise in groups (1, 3, 2, 1) around a whirlpool and slam the water near the ship,
    pushing it.
  - The rigged maw gnashes in the center.
  - The tentacles sit 14% of their height under the water, so their base never shows.
- **Ghost ship** (`Scripts/GhostShip.gd`): appears only in the southern ghost sea, crosses the bow
  and chases the ship if you get close.

<p align="center">
  <img src="images/process/east-timber-whale.jpg" width="49%" alt="Timber whale colossus">
  <img src="images/process/west-turtle-colossus.jpg" width="49%" alt="Stone turtle carrying an island">
  <img src="images/process/south-abyssal-behemoth.jpg" width="49%" alt="Granite crab colossus">
  <img src="images/process/south-obsidian-giant.jpg" width="49%" alt="Obsidian and bone giant">
</p>

---

## 3. Weather, sky and sound

- **Weather** (`Scripts/Weather.gd`, `StormCell.gd`, `Cyclone.gd`, `CycloneRide.gd`, `Thunder.gd`):
  - local storms that drift through empty sea, with rain, rough water and lightning;
  - cyclones that pull the ship in, lift it and drop it somewhere else in open sea.
- **Where the ideas came from:** the Wind Waker sea was studied from a reference video captured on
  noclip.website (`Documentation/Plano_Clima_Eventos_Mar.md`). Meshes, shaders, numbers and code
  were made for this project.
- **Sky:** clouds on camera-facing cards baked from Blender volumes (`Scripts/SkyClouds.gd`), a
  stars pass and a sun flare that hides when something solid blocks the sun.
- **Sound:**
  - recordings from Freesound, cut into short loops and one-shots by `Tools/cut_game_sfx.sh`;
  - a few effects synthesized by `Tools/make_sfx.py`.
  - Every CC-BY sound is credited in `Config/sfx_credits.json`. The raw recordings (up to 330 MB
    each) stay out of Git; only the cuts the game uses are versioned.

<p align="center">
  <img src="images/process/north-runes-at-night.jpg" width="49%" alt="Runes glowing at night">
  <img src="images/process/south-leviathan-jaw-arch.jpg" width="49%" alt="Leviathan jaw arch in the south">
</p>

---

## 4. Problems found and how they were fixed

Each row was found by a test or by me watching a recording, not assumed.

| Problem | How it showed up | Root cause | Fix |
|---|---|---|---|
| Models looked washed out, almost white (whale, turtle) | My note after a colossus video | Exponential fog at 0.0022/m with a light sky color: at ~170 m about 31% of an object's color was fog. Ruled out first: sun flare, glow and material settings | Base fog 0.0022 → 0.0007; storms still thicken it (`FOG_BASE` in `main_world.gd`). Before/after below |
| Stone looked like polished metal | Material dump (`Tests/bright_material_probe.gd`) | Meshy exports `metallic = 1` multiplied by a metallic texture | At load, metallic 0.08 and specular ≤ 0.3 on world models (`_tame_meshy_metal`); the ship keeps its own |
| Cannon aim dots vanished while sailing | `Tests/aim_probe.gd` | The transparent ocean patch was drawn over other transparent effects | `render_priority` on the aim line, the Kraken whirlpool and splashes |
| Kraken splashes rendered as white squares | Frame sheet of the encounter (below) | The particle had no texture | Radial gradient texture |
| Turtle's rear flippers above the water | My note with a screenshot | Meshy weighted the shell rim to the rear flippers, plus a 6° pitch | Rigid rim, 3° pitch, waterline measured in Blender (`TURTLE_WATER_Z`) |
| One world load failed to compile | Headless load | A GDScript type-inference error in `WorldDecor.gd` | Explicit type (`var daylight: float`) |
| Some WAVs did not import | Import log | 24-bit PCM | Converted to 16-bit |
| Two sessions in one Blender | A rig export picked up another session's objects | Both sessions drove the same interactive Blender | Rule: my scripts run in headless Blender only; the rig was redone cleanly |
| The 49-position chart, read literally, covered only 39% of the planet | Layout study | Flat chart coordinates taken literally on a sphere | Decision above (keep islands, spread by sector) |
| Licensing risk | My review | A fan remake of a Nintendo track was on the playlist | Removed from the playlist and from the site |

<p align="center">
  <img src="images/process/fog-before-vs-none.jpg" width="49%" alt="Old fog (left) vs no fog (right)">
  <img src="images/process/fog-after-vs-none.jpg" width="49%" alt="New fog (left) vs no fog (right)">
</p>
<p align="center"><sub>Left of each pair: the fog in the game. Right: fog off, for reference. First pair is the old density, second is the new one.</sub></p>

<p align="center">
  <img src="images/process/kraken-event.jpg" width="90%" alt="Kraken encounter frame sheet, with the square splash bug in the last row">
</p>
<p align="center"><sub>Kraken encounter frames recorded during testing. The white squares in the last row are the splash bug from the table above.</sub></p>

---

## 5. Web and mobile: from a 397 MB package to 77 MiB on a phone

The original Meshy models are huge: up to 6.7 million triangles and ~200 MB per file. With them,
the world used **~4.4 GB of video memory** on my PC (`Tests/stress_sail.gd`). That can never run on
a phone, so the site uses generated copies.

**5.1 Web variants.**
- `Tools/make_web_variants.py` runs Blender headless: it welds, decimates and resizes textures into
  `Assets/WebDesktop` and `Assets/WebMobile`. The originals stay untouched as the source.
- Budgets are set per model type (portfolio islands get the most).
- `Tools/compare_web_variants.py` renders original vs desktop vs mobile side by side, so every
  model was checked by eye.

<p align="center">
  <img src="images/process/web-variant-sheet.jpg" width="60%" alt="Original vs desktop vs mobile variants">
</p>

**5.2 What the first mobile build actually contained.**
- The first export of this phase was **397 MB**. Listing the files inside the package showed what
  had leaked in:
  - raw sound recordings the game never plays (one of 331 MB);
  - 4K textures left over from the original models;
  - three copies of each portfolio island, two of them used only by measuring tools.
- The build now keeps only what the game references.
- Texture sizes depend on how close you see the model:
  - near-view models (islands, sloop, title plates) at 1024 on mobile and 2048 on desktop;
  - everything else at 512 on mobile and 1024 on desktop;
  - sky and clouds unchanged on desktop, 1024 on mobile.
- Music was already streamed by the browser instead of living in the package.

**5.3 Proximity loading.**
- The main package now carries the islands, the sloop, the sea, the creatures and the interface.
- The models of each sector live in their own pack: `world-north.pck`, `world-east.pck`,
  `world-south.pck`, `world-west.pck`.
- How it works:
  1. The build measures every model once: its bounds, its collision outline and whether it has an
     idle animation. It saves this in `Config/world_kinds.json` (`Tests/bake_world_kinds.gd`).
  2. When the world opens, the full map is laid out from those measurements, with collisions,
     lights and effects already in place, even before a single sector model has arrived.
  3. `Scripts/AssetPacks.gd` downloads the packs in the background, the ship's sector first, and
     keeps them in the browser for the next visit. Each model appears as soon as its pack arrives.
- I did not add unloading of far sectors. Measured memory was already low (below), and unloading
  would only add hitches when sailing back.

<p align="center">
  <img src="images/process/sector-pack-before-after.jpg" width="90%" alt="Sector model missing right after opening, then in place after its pack arrived">
</p>
<p align="center"><sub>Exported package, run outside the editor: right after opening (left) and after the North pack arrived (right).</sub></p>

**5.4 Bugs found only by testing the real build.**
- **The map was different on the web.** The volcano's lava rivers drew from the same random
  generator as the item layout. The search for a river path uses up a different amount of random
  numbers depending on the mesh, and the lighter web volcano has a slightly different surface.
  Every item placed after it moved.
  - Fix: the lava has its own random generator.
  - Check: desktop and web layouts compared item by item are now identical.
- **The packs never mounted in the browser.**
  - The download was set to use a thread, and the web build has none: the request never finished.
  - After that fix, the file `HTTPRequest` should have saved to browser storage was never written.
  - Now the game receives the pack in memory, writes it itself, then mounts it.
  - On the live site, with the browser tab in the background (~1.5 fps), one pack took minutes:
    Godot's `HTTPRequest` reads one chunk per frame. In the browser the download is now a native
    `fetch`, which runs at network speed whatever the frame rate. All four packs then arrived in
    under 30 s even at 1.5 fps.
  - Verified in the browser at phone size: all four packs load, and a second visit loads them from
    cache with no new download.
- **The "Explore in 3D" button still showed old sizes.** It now shows the real package size,
  written by the build.

**5.5 Measured results (this machine, local server):**

| | Before the first frame | Downloaded in the background |
|---|---|---|
| Mobile | **77.1 MiB** (was 397 MB at the start of this phase; 63.5 MiB before the quality pass below) | 4 packs, 7.8–12.4 MiB each |
| Desktop | **222.3 MiB** (139.7 MiB before the quality pass) | 4 packs, 51.5–76.7 MiB each, served in ≤20 MiB parts |

- **Sizes are what crosses the network on a cold load.** Checked with response headers on the live
  site: the package and pack parts are served without `Content-Encoding`, with `Content-Length`
  equal to the file size. Gzip saves only ~2% on them, because the textures are already compressed.
  On top of the package, the browser also downloads the engine (`index.wasm`, 7.1 MB with Brotli),
  `index.js` and the fonts (~1.5 MB).
- **Quality pass (Oct 16).** Testing the live site, I found the web models crude: faceted, low
  detail, and desktop textures halved. The fixes:
  - triangle budgets raised (cities 300k desktop / 70k mobile, landmarks 150k / 35k);
  - rigged colossi no longer decimated on desktop;
  - smooth-by-angle shading after decimation;
  - every model texture at 2048 on desktop.
  - The download grew as a result; that is the trade-off.
**5.6 Time until the boat answers the helm (cold load, measured).** `https://dotpdf.dev/?medir`
- **What the mode does:** it opens the 3D world straight away and throttles the boat up by itself. It
  marks the moment the hull passes 0.5 m/s, then hands the controls back. Times, bytes that really
  crossed the network, FPS, device and network all show on screen.
- **Run 1, Oct 16:**
  - **Device:** desktop PC (RTX 3060 Ti, 16 cores, 32 GB) emulating a phone in the built-in browser
    of the Claude app. Pixel 8 user agent, 375×812 viewport @1.5, mobile package, Medium graphics.
  - **Not a real phone.** The GPU and CPU are far stronger than a phone's.
  - **Network:** home connection. The browser reports "4g · 10 Mbps", but Chrome caps that estimate;
    the package actually arrived at ~170 Mbps (77 MiB in 3.9 s).
  - **Cache:** cold, with Cache Storage and IndexedDB cleared. 125.5 MiB transferred in total, which
    matches package + engine + the four sector packs, so nothing came from the cache.

| Since the click | Time |
|---|---|
| Game package downloaded (77.1 MiB) | 4.2 s |
| Engine ready | 4.4 s |
| Islands built | 9.0 s |
| First smooth frames | 18.0 s |
| **Boat answers the helm** | **18.0 s** |
| Four sector packs downloaded | 20.2 s |
| Every sector model in place | 20.7 s |
| FPS in the 5 s after the helm | 39 |

- **Where the time goes:** on a fast connection, most of the time is first-frame shader compilation
  (9 → 18 s), not the download.
- **On a real 4G line (estimate, not measured):** downloading the ~86 MB needed before the helm alone
  would take ~35 s at 20 Mbps, or ~70 s at 10 Mbps.
- **Run 2, Oct 16, real phone:**
  - **Device:** Samsung Galaxy A55 (SM-A556E), Android 16, Samsung Xclipse 530 GPU (Vulkan, through
    ANGLE), 8 cores, 8 GB.
  - **Viewport:** 384×832 @1.5, mobile package. The page picked Medium graphics because the phone
    counts as "strong" (8 GB, 8 cores).
  - **Network:** Wi-Fi. The browser reports "4g · 9.7 Mbps", a capped estimate; the package actually
    arrived in 5.1 s.
  - **Cache:** cold. 126.7 MB transferred in total, 85.0 MB of it before the helm.

| Since the click | PC emulating a phone | Galaxy A55 |
|---|---|---|
| Game package downloaded | 4.2 s | 5.1 s |
| Engine ready | 4.4 s | 5.9 s |
| Islands built | 9.0 s | 17.0 s |
| First smooth frames | 18.0 s | 25.2 s |
| **Boat answers the helm** | **18.0 s** | **25.2 s** |
| Four sector packs downloaded | 20.2 s | 30.3 s |
| Every sector model in place | 20.7 s | 35.1 s |
| FPS in the 5 s after the helm | 39 | **7** |

- **The 7 fps is a real problem, and it is reported as measured.** Two caveats:
  - On the phone, the 5 s window right after the helm overlaps the sector packs being downloaded and
    attached (until 35.1 s), so it is a worst case.
  - The game also lowers the graphics tier by itself after a few slow seconds.
- **Next fixes, in order:**
  1. Measure FPS again after every sector model is in place.
  2. Start phones on the Low tier.
  3. Spread the model attaching over more frames.
  4. Revisit the mobile model budgets that grew in the quality pass.

- Every file in the site is under Cloudflare's 25 MiB static-asset limit.
- The mobile package at the Low graphics tier, run on this PC (not on a phone): a steady 30 fps
  with ~240 MB of video memory (`Tests/stress_sail.gd -- low`).

<p align="center">
  <img src="images/process/mobile-web-test.jpg" width="260" alt="Mobile-size browser test of the built site">
</p>

---

## 6. What is not in Git, and why

- **Not versioned:**
  - original Meshy exports (`Assets/**/*.glb` outside `Assets/Optimized`);
  - rigged creatures and the ghost ship (16–75 MB per file);
  - raw Freesound recordings;
  - the generated web variants;
  - build output.
- **Versioned:**
  - all code, shaders and tools;
  - every `.import` setting;
  - the optimized islands and sloop;
  - the sound cuts the game plays;
  - the measurements in `Config/world_kinds.json`.
- **What this means for a fresh clone:** the portfolio islands and the sloop work, but biome
  landmarks and creatures need the original files. The web build always regenerates its variants
  from the originals.

## 7. How to reproduce the checks

```powershell
# Layout rules (headless)
Godot.exe --headless --path . --script res://Tests/biome_layout_dump.gd
# Memory and fps while sailing past every island and sector ("-- low" = mobile tier)
Godot.exe --path . --resolution 1280x720 --script res://Tests/stress_sail.gd -- low
# Full site build: variants, sector packs, chunked packages
pwsh Web/build.ps1
# The exported mobile package with its sector packs, outside the editor (run inside Builds/WebMobile)
Godot.exe --main-pack index.pck --script <project>/Tests/packs_probe.gd -- --packs=<project>/Builds/WebMobile/packs --out=<folder>
```
