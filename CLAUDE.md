# Fill the Ocean

UI style: clear-tide (the lobby's pad screens, Confirm and HostBar: sunbaked-sea, owner 2026-11-14)
Balance: follow C:\RobloxDev\library\balance\README.md; formulas come from C:\RobloxDev\shared\Lib.
Design: check C:\RobloxDev\library\design\README.md before planning features.

This file overrides the library, and the library overrides the LihFolk plugin.

## What the game is
Working title: Save the Ocean. You own the ocean; a bacon-hair drank all of it while you napped.
Starting with a spoon, you scoop water at a source, carry it and pour it back in. Every litre poured
earns money, which buys bigger tools, gadgets, buildings, vehicles and staff, until the ocean is full
again (target about 20 hours solo on the first map). Everything is the team's (owner, 2026-11-10):
one wallet every coin goes into and anyone spends, the same upgrades for everyone, prices scaled
by team size (`Config.team`). Automation is allowed. Runs are saved per team:
you create a party in the lobby, play, leave, and later load the run again, but only with exactly
the same team. Each map has a fixed difficulty; clearing map 1 unlocks map 2. Story: an intro
cutscene (the bacon-hair drinks the ocean) and an ending cutscene (you smack him away). Outside a run:
an account level (permanent, capped perks) and a 3-month season pass (cosmetics, Raindrops).
Design: `docs/design/2026-11-04-fill-the-ocean-design.md`. Build plan:
`docs/plans/2026-11-05-save-the-ocean.md`. Its Phase 1 is done: the code runs one saved ocean per
team; the old multi-part run (stages, pool, lake, shares, difficulty) is gone.
Analytics (funnels, events, the session record, `lune run tools/analytics`): `docs/analytics.md`.
Its names are permanent once live: add new ones, never rename.

## Studio
- Two places, each its own Rojo project folder:
  - `lobby/`: Place ID 131785571407023, the start place players load into. Rojo port 34674.
  - `gameplay/`: Place ID 128436077571697, where a run happens. Rojo port 34675.
- In each folder, Rojo owns code only: `src/shared` -> ReplicatedStorage.Shared, `src/server` ->
  ServerScriptService.Server, `src/client` -> StarterPlayerScripts.Client, and
  `C:\RobloxDev\shared` -> ReplicatedStorage.Kit (UI and Lib). A change in Kit changes every game.
  Both projects also map `common/` -> ReplicatedStorage.Common (save progress, run
  tickets, retries, place IDs) and declare their RemoteEvents in ReplicatedStorage.Remotes.
  gameplay also maps `vendor/Animation` -> ReplicatedStorage.Animation (the owner's roblox-animation
  runtime, vendored with its LICENSE and PROVENANCE; staff bodies use it) and `src/first/Arrival`
  -> ReplicatedFirst.Arrival (puts the teleport screen you arrived behind up before the place
  loads). lobby maps gameplay's
  `shared/Config`, `Water` and `Admins` into ServerStorage.GameplayShared (server only).
- The map, StarterGui and everything else built in Studio exist only in the place. Save and
  publish in Studio, or it exists nowhere.
- Nothing is generated at runtime. Baked into the places and only checked by code:
  - gameplay: the ocean model `workspace.Ocean` (`Spawn`, `Basin`, `Water`, an invisible `Source`
    over the water source and `PourPoint` marking the usual pour spot, and `PourDecal`, a flat part
    on the seabed with a Decal that client/Channels fades out as the ocean fills; `Map.ensure` checks them;
    players pour anywhere next to where the water will be, see
    `shared/Zones.nearFlood`; a `Tap` with an Attachment `Hose` for the Garden Hose, as in every
    area), each area's `Areas.<Name>.Channel` from its `Pour` to the ocean (`Path`: parts named
    1..N in order, a wave follows them; `Water`: parts whose Textures trickle; server/Map),
    each area's `Areas.<Name>.Walls` (a Persistent Model of invisible walls 1500 studs high in a
    closed loop round the area on the ridge tops, sea front and outer mountains, above the gate
    tunnels; server/Map clears them when the gate opens),
    `ReplicatedStorage.ToolModels`
    (one Model per hero tool, and `Gadgets.<Model>` per gadget; swap placeholders for real models
    under the same name), `workspace.Map.Town.ToolShack`'s ProximityPrompt `Prompt` (sells the Water Gun),
    `workspace.Map.Town.FireStation` (`Prompt` sells vehicles, `CallPrompt` and part `VehicleSpawn`
    bring one out, the next owned one on each call), `ReplicatedStorage.Vehicles.<Model>` (VehicleSeat `Seat` with a `DrivePrompt`),
    hydrants (`Map.Roads.TruckRefillBay1/2`, `Areas.<Name>.Hydrant`; server/Map),
    `workspace.Map.Beach.Stage_Ocean_LifeguardTower`'s ProximityPrompt `Prompt` (hires staff),
    `ReplicatedStorage.Staff.<Model>` (R15 staff rigs with a PrimaryPart; client/Staff walks copies),
    `workspace.Map.Revive.M1..M8` (Models: cove decorations shown once their milestone revives
    them, client/Milestones), `ReplicatedStorage.Story.BaconHair` (a Model, placeholder; the
    milestone sightings put a copy far out at sea, facing the beach along its pivot's front),
    the intro's story models in `ReplicatedStorage.Story` (client/Intro): `BaconRig` (the real
    bacon-hair R6 rig at normal size with its Animator, facing -Z, pivot at its feet; he strolls
    onto the beach), `SandPile` (a damp-sand ball he plays with, sunk into the sand), `BaconFat` (a
    stand-in for the fat ball until
    `art/models/story/BaconHairFat.glb` is imported: the rig x20 with a `Belly` ball, a Motor6D `Neck`
    in the model's own axes and an Attachment `Mouth`; pivot at its feet), `Straw` and `Puddle`
    (cylinders along X), `StarterGui.Cutscene`, `Lighting.IntroBlur`, `Audio.Intro*` and
    `Audio.EndSmack` (the ending's slap),
    `ReplicatedStorage.Audio` (Sounds) and `ReplicatedStorage.Vfx` (effects, `ChannelWave` included) named in
    `shared/Cues.luau`, SoundService SoundGroups, `StarterGui.Hud`, Lighting effects and Terrain
    Clouds, and `ReplicatedStorage.Transition` (a copy of the lobby's teleport screen, for Studio
    tests with `StudioTransition`).
  - lobby: `workspace.Lobby.Pads.Pad1..Pad5` (Zone part, `Walls` model with four invisible
    CanCollide walls around it (touching them joins; members stay on until Leave), sign with Title
    and Status labels and `Art`, a capture of the gameplay map (`art/lobby/Map1Thumb.png`); any pad
    hosts a party), `StarterGui.LobbyHud` (`PadScreen` with `CreateParty`
    and `SavedRuns` side by side on one screen, over `PadCover` (its full-screen dark cover, faded in
    with `Lighting.PadBlur`); `Confirm` over everything (UIScale `Scale`,
    `DesignSize`); `HostBar` with `StartButton` and `LeaveButton`; `Admin.ResetProfile` for admins),
    `ReplicatedStorage.Transition` (the teleport screen, a ScreenGui: `Fresh` (`Black`, `Water` with
    `Band` and `Foam`, `Pool` with `Arc1..4` and `Hole`), `Return.Body` (`Edge`/`EdgeFoam`,
    `Top`/`TopFoam`, `Rays`, `Bubbles`, `Card` with UIScale `Scale`, `DesignSize`, `Logo`, `MapName`,
    `FillBar.Fill`/`Label`, `Status`) and Sounds `Flood`, `Drain`, `Wave`, `Splash`; common/Transition),
    the lobby's feel (named in `lobby/src/shared/LobbyCues.luau`): `ReplicatedStorage.Audio`
    (SoundGroups `Music`, `Sfx`, `Ambience`, `Footsteps` and copies of gameplay's sounds, plus
    `MusicLobby` and `UiClick`), `ReplicatedStorage.Vfx` (`ScoopSplash`, `Sparkle`, `PadBubbles`),
    `ReplicatedStorage.Scenery` (`Gull`: parts, `WingL` / `WingR` each with a `Hinge` Attachment,
    facing -Z; `BaconFat`: the fat bacon-hair at 1.6x gameplay's, anchored, no joints, pivot at his
    feet where he stands out at sea, with `Belly`, `Head.Mouth` and `Straw`), a `Ripple` Texture on
    every pad's `Water`, `LobbyHud.Countdown` (TextLabel with UIScale `Pop`), the `Footstep`
    attribute (`"wood"`) on the boardwalk's Plastic `Path` boards, and the terrain's
    `WaterWaveSize` 0.2 / `WaterWaveSpeed` 12.
- The ocean is `workspace.Ocean` at the origin: one straight beach (shore along X, sea toward -Z)
  facing a terrain seabed (y -28) that runs to the horizon; its `Water` holds 5 extra `Tile` parts
  (2048 studs each, the part size cap; unturned, edges on the 4-stud grid). They stay hidden and
  mark where the ocean's Roblox terrain water goes; code writes that water as the ocean fills
  (`shared/Zones`). The scenery is `workspace.Map` (terrain plus clones of `ServerStorage.MapKit`); the old map
  is kept in `ServerStorage.OldMap_Backup_2026_11_06`.
- Studio test helpers (gameplay), workspace attributes: `WaterScale` (less water needed),
  `StudioMap` (the map a Studio play test runs, default `map1`) and `StudioMoney` (coins put into the
  team's wallet) and `StudioFill` (a fraction 0-1:
  jumps the fill) and `StudioGolden` (true: starts a golden spring now) and `StudioIntro` (true: the
  run opens on the intro, whatever the save) and `StudioIntroAt` / `StudioEndingAt` (seconds: the
  intro or the ending holds on that frame, for framing shots; `StudioFill` 1 plays the real ending)
  and `StudioTransition` (`"fresh"` or `"return"`: you arrive behind that teleport screen, as from
  the lobby) and `StudioEcho` (both places; false: silences the `[Telemetry]` lines Studio prints for each
  analytics event instead of sending it).
  Teleports and saving need the published game / Studio API access.
- To work: `rojo serve` inside `lobby/` or `gameplay/`, then open that place in Studio >
  Plugins > Rojo > Connect (use the folder's port). Both can run at once.

## Checks
Run in each folder you changed (`lobby/`, `gameplay/`):
- `selene src` is clean.
- `rojo build -o <folder>.rbxlx` succeeds.
- `gameplay/`: `lune run tests/run` passes (Lune 0.11.1; tests cover the pure modules in
  `src/shared` and `common/`, which must not require anything or touch `game`).
- `common/`: copy `gameplay/selene.toml` in, run `selene .`, remove it (common has no own config).
