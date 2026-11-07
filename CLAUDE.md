# Fill the Ocean

UI style: sunbaked-sea
Balance: follow C:\RobloxDev\library\balance\README.md; formulas come from C:\RobloxDev\shared\Lib.
Design: check C:\RobloxDev\library\design\README.md before planning features.

This file overrides the library, and the library overrides the LihFolk plugin.

## What the game is
Working title: Save the Ocean. You own the ocean; a bacon-hair drank all of it while you napped.
Starting with a spoon, you scoop water at a source, carry it and pour it back in. Every litre poured
earns money, which buys bigger tools, gadgets, buildings, vehicles and staff, until the ocean is full
again (target about 20 hours solo on the first map). Automation is allowed. Runs are saved per team:
you create a party in the lobby, play, leave, and later load the run again, but only with exactly
the same team. Each map has a fixed difficulty; clearing map 1 unlocks map 2. Story: an intro
cutscene (the bacon-hair drinks the ocean) and an ending cutscene (you smack him away). Outside a run:
an account level (permanent, capped perks) and a 3-month season pass (cosmetics, Raindrops).
Design: `docs/design/2026-11-04-fill-the-ocean-design.md`. Build plan:
`docs/plans/2026-11-05-save-the-ocean.md`. Its Phase 1 is done: the code runs one saved ocean per
team; the old multi-part run (stages, pool, lake, shares, difficulty) is gone.

## Studio
- Two places, each its own Rojo project folder:
  - `lobby/`: Place ID 99179921994084, the start place players load into. Rojo port 34872.
  - `gameplay/`: Place ID 96136704873524, where a run happens. Rojo port 34873.
- In each folder, Rojo owns code only: `src/shared` -> ReplicatedStorage.Shared, `src/server` ->
  ServerScriptService.Server, `src/client` -> StarterPlayerScripts.Client, and
  `C:\RobloxDev\shared` -> ReplicatedStorage.Kit (UI and Lib). A change in Kit changes every game.
  Both projects also map `common/` -> ReplicatedStorage.Common (save progress, run
  tickets, retries, place IDs) and declare their RemoteEvents in ReplicatedStorage.Remotes.
- The map, StarterGui and everything else built in Studio exist only in the place. Save and
  publish in Studio, or it exists nowhere.
- Nothing is generated at runtime. Baked into the places and only checked by code:
  - gameplay: the ocean model `workspace.Ocean` (`Spawn`, `Basin`, `Water`, an invisible `Source`
    over the water source and `PourPoint` marking the usual pour spot; `Map.ensure` checks them;
    players pour anywhere next to where the water will be, see
    `shared/Zones.nearFlood`), `ReplicatedStorage.ToolModels`
    (one Model per hero tool; swap placeholders for real models under the same name),
    `ReplicatedStorage.Audio` (Sounds) and `ReplicatedStorage.Vfx` (effects) named in
    `shared/Cues.luau`, SoundService SoundGroups, `StarterGui.Hud`, Lighting effects and Terrain
    Clouds.
  - lobby: `workspace.Lobby.Pads.Pad1..Pad5` (Zone part, sign with Title and Status labels; any
    pad hosts a party), `StarterGui.LobbyHud`.
- The ocean is `workspace.Ocean` at the origin: one straight beach (shore along X, sea toward -Z)
  facing a terrain seabed (y -28) that runs to the horizon; its `Water` holds 5 extra `Tile` parts
  (2048 studs each, the part size cap) that rise with it. The scenery is `workspace.Map` (terrain plus clones of `ServerStorage.MapKit`); the old map
  is kept in `ServerStorage.OldMap_Backup_2026_11_06`.
- Studio test helpers (gameplay), workspace attributes: `WaterScale` (less water needed),
  `StudioMap` (the map a Studio play test runs, default `map1`) and `StudioFill` (a fraction 0-1:
  jumps the fill). Teleports and saving need the published game / Studio API access.
- To work: `rojo serve` inside `lobby/` or `gameplay/`, then open that place in Studio >
  Plugins > Rojo > Connect (use the folder's port). Both can run at once.

## Checks
Run in each folder you changed (`lobby/`, `gameplay/`):
- `selene src` is clean.
- `rojo build -o <folder>.rbxlx` succeeds.
- `gameplay/`: `lune run tests/run` passes (Lune 0.11.1; tests cover the pure modules in
  `src/shared` and `common/`, which must not require anything or touch `game`).
- `common/`: copy `gameplay/selene.toml` in, run `selene .`, remove it (common has no own config).
