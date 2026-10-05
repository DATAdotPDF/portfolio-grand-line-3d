# Recon: Wind Waker HD × Sea of Thieves (2026-10-03)

Static analysis only (file listings, headers, metadata). Nothing extracted to disk, no executable
touched, no game launched. Complements [Estudo_Mar_Vento_Barco.md](Estudo_Mar_Vento_Barco.md), whose
rule is still the rule: **public ideas and techniques only, no assets copied.**

## The Legend of Zelda: The Wind Waker HD

| Item | Value |
|---|---|
| Path | `References/ISOs/The Legend of Zelda - The Wind Waker HD/…/` (gitignored by `/References/`) |
| Platform | Wii U, loose dump (`code/ content/ meta/`), 1.7 GB |
| Title | `WUP-P-BCZE`, title id `0005000010143500` (USA), title version 0 (no update), SDK 20911 |
| Code | `code/cking.rpx` (PowerPC RPX, native) |
| Emulator | Cemu: **not installed** on this PC |
| Anti-cheat | none (offline console game) |

Content formats (804 `.szs` files, all Yaz0):

- `Yaz0 → SARC → BFRES` (Wii U models/textures) + `room.dzr` / `stage.dzs` (actor and stage placement,
  same format as the GameCube original) + `baseLight.bin` and `event_list.dat`.
- `Common/Stage/` (1 GB): one `<name>_Stage.szs` + `<name>_Room<N>.szs` per area. The Great Sea is
  `sea_E_Stage.szs` + `sea_E_Room<N>.szs` (one room per chart square, e.g. Room44 = 9.5 MB).
- `Common/Pack/*.pack`: SARCs of permanent objects. The boat is `Ship.szs` (King of Red Lions),
  the sail is `Ho.szs`, the pirate ship is `Kaizokusen.szs`.
- `Common/Shaders/*.sharcfb`: compiled GX2 shaders (`wii_pipeline`, `particle`, `render_buffer`).
- Audio: `.bfstm` (115 streams) + `.aw` (67 banks) + one `.bfsar`.

Usual community routes: Cemu graphic packs (resolution, FPS, free camera), Switch Toolbox (opens BFRES),
the GameCube-era tools for `.dzr/.dzs`, and the decomp of the GameCube original (`zeldaret/tww`) to
read sea and boat logic as source code.

## Sea of Thieves

| Item | Value |
|---|---|
| Path | `D:\Steam\steamapps\common\Sea of Thieves` |
| Version | `2.152.3728.4` (`Athena/Binaries/Win64/Version.txt`), project name "Athena" |
| Engine | Unreal Engine 4 (heavily modified by Rare), D3D12, x64 |
| Content | 2731 `.pak` files (135 GB) under `Athena/Content/Paks`, **each with a `.sig`** (signed paks), pak format v3, index not encrypted |
| Anti-cheat | **EasyAntiCheat**, plus Epic Online Services (`EOSSDK`) and an online sandbox id in `ClientConfiguration.json` |
| Loaders | none |

**Verdict: don't mod it.** The game is online-only with EAC, and the signed paks mean the client
rejects altered content. UE4SS, `~mods` paks and DLL injection are all ruled out (risk of a ban and a
breach of the terms of service). Only legitimate routes:
- play and observe (record clips, measure by eye);
- Rare's public talks: the SIGGRAPH 2018 talk, already summarised in the study doc.

## What this means for the portfolio

- **Wind Waker:** the most useful source of *logic* (wind, sail, boat speed, the grid of squares) is
  the GameCube decomp: source code that can be read to learn from, without copying assets. That still
  needs the user to OK it, because the study's rule says "no reverse engineering". Reading a public
  decomp is a grey area, so it's the user's call.
- **Watch Godot:** the dump's `meta/*.tga` files were already imported by the editor (`.import` files
  next to them, cache in `.godot/imported`). The export already excludes `References/*`, so nothing
  leaks into the build. A `.gdignore` in `References/` would stop the import entirely.
- Nothing from the dumps goes into `Assets/`. Models keep coming from Meshy, sounds from our own sources.
