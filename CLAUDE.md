# Fill the Ocean

UI style: sunbaked-sea
Balance: follow C:\RobloxDev\library\balance\README.md; formulas come from C:\RobloxDev\shared\Lib.
Design: check C:\RobloxDev\library\design\README.md before planning features.

This file overrides the library, and the library overrides the LihFolk plugin.

## What the game is
The evil sun has evaporated all the water on Earth, and up to 10 friends refill it, starting with a
spoon. Core loop: scoop water at a source, carry it, and pour it in. Every litre poured earns money,
which buys bigger tools and faster trips until the body of water is full. Filling is always manual: one
hold prompt fills the tool, one empties it. Hook: the upgrade ladder is the joke. It runs from spoon to cup to bucket to
bathtub to cargo ship, all the way up to scooping with the Moon, and every purchase makes the next
trip noticeably faster. A run: about 33 minutes in a private server, pool (5 min), then lake
(9 min), then ocean (19 min), with a cutscene of the sun draining each one. Tools and money carry
over between stages, each stage adds new tools, and each stage pays more per litre. The water needed
scales with player count, so a run lasts the same at any group size. Nothing carries over between
runs except unlocked difficulties and the reward currency. Rewards: paid only at the end of the run,
from a pot of 100 per player. Half is split evenly, and the other half is split by share of the
water poured. Twist: when the ocean finally fills, the sun throws a tantrum and blows up the Earth.
Beating a run unlocks the next difficulty, where the sun is angrier.

## Studio
- Two places, each its own Rojo project folder:
  - `lobby/`: Place ID 99179921994084, the start place players load into. Rojo port 34872.
  - `gameplay/`: Place ID 96136704873524, where a run happens. Rojo port 34873.
- In each folder, Rojo owns code only: `src/shared` -> ReplicatedStorage.Shared, `src/server` ->
  ServerScriptService.Server, `src/client` -> StarterPlayerScripts.Client, and
  `C:\RobloxDev\shared` -> ReplicatedStorage.Kit (UI and Lib). A change in Kit changes every game.
  Both projects also map `common/` -> ReplicatedStorage.Common (difficulty, save progress, run
  tickets, retries, place IDs) and declare their RemoteEvents in ReplicatedStorage.Remotes.
- The map, StarterGui and everything else built in Studio exist only in the place. Save and
  publish in Studio, or it exists nowhere.
- Nothing is generated at runtime. Baked into the places and only checked by code:
  - gameplay: `workspace.Stages` (Pool, Lake, Ocean, with ScoopPrompt/PourPrompt),
    `ReplicatedStorage.ToolModels` (one Model per hero tool; swap placeholders for real models
    under the same name), `StarterGui.Hud`, Lighting effects and Terrain Clouds.
  - lobby: `workspace.Lobby.Pads.Pad1..Pad5` (Zone part, Difficulty attribute, sign with Title
    and Status labels), `StarterGui.LobbyHud`.
- Lake and Ocean are terrain bowls (natural shoreline); their `Basin` part is invisible and only
  marks the water's base. The Pool is a tiled tank.
- Studio test helpers (gameplay): workspace attributes `WaterScale` (shorter runs),
  `StudioFillStage` (fill the current stage), `StudioDifficulty` (1-5). Teleports and saving
  need the published game / Studio API access.
- To work: `rojo serve` inside `lobby/` or `gameplay/`, then open that place in Studio >
  Plugins > Rojo > Connect (use the folder's port). Both can run at once.

## Checks
Run in each folder you changed (`lobby/`, `gameplay/`):
- `selene src` is clean.
- `rojo build -o <folder>.rbxlx` succeeds.
- `gameplay/`: `lune run tests/run` passes (Lune 0.11.1; tests cover the pure modules in
  `src/shared` and `common/` (Difficulty, Progress), which must not require anything or touch `game`).
- `common/`: copy `gameplay/selene.toml` in, run `selene .`, remove it (common has no own config).
