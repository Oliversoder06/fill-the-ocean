# Agent instructions: Fill the Ocean

You are implementing work in a Roblox game (Luau, Rojo). Usually the owner plans with another
assistant and hands you a plan file in `docs/plans/`; execute it exactly. Sometimes they ask for a
small change directly (see "Small tasks without a plan"). These rules apply to every task.

## Read first
- `CLAUDE.md`: what the game is, the two places (`lobby/`, `gameplay/`), what Rojo owns, the checks.
  It overrides everything below except the safety rules.
- `docs/design/2026-11-04-fill-the-ocean-design.md`: the design the plans implement.
- The plan you were given. Do one task at a time, in order, step by step.

## How to execute a plan
- Follow each task's steps in order. Where a step says "write the failing test", write it, run it,
  and confirm it FAILS before writing the code.
- Every step with a command has an `Expected:` line. Run the command and compare the real output.
  If it doesn't match, stop and fix the cause. Never change the expected output or the test.
- Use exactly the file paths, names, signatures and values the plan gives. Don't rename things.
- If the plan is wrong or impossible, stop and write down what's wrong and what you'd do instead.
  Don't silently do something else.
- Steps marked **Owner step** are done by the owner in Roblox Studio. Stop there and ask them.
- At the end of each task, list what you changed and paste the check output.

## Small tasks without a plan
1. Restate the request in one or two lines and list your assumptions. If it is ambiguous (which
   screen? server or client? should others see it?), ask before writing code.
2. Find where it lives with the code map below, and read those files fully before editing.
3. Decide which side owns it: anything that changes money, water, tools or what other players see is
   **server** (`Run.luau`); the client only shows state and sends requests.
4. If it needs anything built in Studio (UI, a part, a remote in the place), say so up front and
   mark it as an Owner step. Code alone can't create it.
5. Make the smallest change that does it, run the checks, then report: what changed, check output,
   what is NOT verified, and any Owner step left (save the place, restart `rojo serve`).

## Code map (gameplay/)
Server (`src/server/`):
- `Run.luau`: the whole run. Phases, per-player state (money, carried, stats, bought items,
  equipped), scoop/pour validation (`Act` remote), buying, rewards, publishing attributes. Most
  gameplay changes land here.
- `HeldTools.luau`: puts each player's tool model in their hand so others see it, on a `HeldGrip`
  Motor6D (hand to tool) that client `Bodies` turns to suit the carry pose.
- `Map.luau`: checks the baked stages and moves the water.

Client (`src/client/`, all started from `init.client.luau`):
- `Hud.luau`: fills `StarterGui.Hud` (wallet, waiting text, card, results, the top-right
  `Progress` panel: stopwatch, stage name, fill bar), frees the cursor while
  a window is open. Exposes helpers `Hud.find` (asserting path lookup), `Hud.set` (write only on
  change), `Hud.short` (1.2K), `Hud.money` (12,480), `Hud.currentStage`, and `Hud.walletHold`
  (money still flying in as coins; the wallet shows Money minus it).
- `Action.luau`: scoop and pour input (aim at the water + hold E / LMB / RT / touch button), one
  full sweep or pour per action, the `ActHint` text. Viewmodel and Feel read `Action.current()`.
- `Feel.luau`: sounds and splashes for scoop and pour (own and other players'), from `Cues`.
- `Payout.luau`: when Money goes up, coins burst from the pour, land around you and fly into the
  wallet with rising ticks, plus a "+amount" pop (`Vfx.Coin`, `Vfx.MoneyPop`, `Cues.coins`).
- `Shop.luau`: the shop window: one tile per upgrade track in the Tool and Boosts panels, and a
  detail panel with the Buy button. Opens through `Window`. The `UpgradesButton` (right edge)
  squishes while Tab / gamepad Y / mouse / touch is held and opens or closes the shop on release.
- `Admin.luau`: the admin window (F2), only for user ids in `shared/Admins.luau`: one button per
  stage (`Hud.Admin.Body.Stages.Stage<i>`) jumps the run there (`Admin` remote).
- `Purchase.luau`: the purchase moment: sting, coins fly from your money into the tile, a "BOUGHT!"
  stamp (`StarterGui.Hud.Templates`), Buy-button shake when you can't buy, new-tool swing-up
  sparkles and speed-upgrade whoosh/FOV kick when the shop closes (`Cues.purchase`).
- `Footsteps.luau`: your steps on each dip of the camera bob (`CameraFeel.onStep`), others' every
  `Steps.STRIDE` studs; sound by floor (`shared/Steps`), heavier while carrying; dust puffs on dry
  floors (`Footsteps.dust`, `Vfx.StepDust`); mutes Roblox's default "Running" sound (`Cues.steps`).
- `Bodies.luau`: third-person bodies (others, and yours for its shadow). After the default
  animations each frame it sets joint `Transform`s: arms reach for the tool by IK in a carry pose
  per tool (hand / hang / hug / overhead), others' scoops and pours (from `ActKind`/`ActAt`), a
  walk bounce and twist synced to the animated legs, lean, heavy-load waddle, landing crouch,
  head look (`Look`), and drips from full tools (`Vfx.Drips`). Sends your camera pitch (`Look`).
- `Ambience.luau`: a looping bed per stage plus a cicada heat layer; filling the basin fades the
  heat out and the bed up (`Cues.ambience`, `Cues.ambienceMix`).
- `Music.luau`: a track per stage, a faster final-push track (last 5% of the last stage) and a
  calm track for waiting/results (`Cues.musicTrack`); crossfades, ducks under stage cards and
  purchases (`Music.duck`), plays through `SoundService.Music`.
- `Window.luau`: the shared window open/close (frame pops in, then parts marked `Reveal` pop in
  layer by layer; timing in `shared/Reveal.luau`).
- `Hotbar.luau`: the one tool slot (1 / gamepad X / click to equip or unequip) and the fill bar
  (springs with `Ease.pop`).
- `Viewmodel.luau`: first-person tool (sweep / pour poses), held by a copy of the player's own right
  hand and forearm, with walk wobble and turn sway. `CameraFeel.luau`: first-person camera bob and
  tilt (`CameraFeel.walk()` shares the walk cycle). `Mood.luau`: lighting.

Shared (`src/shared/`, pure unless noted):
- `Config.luau`: every run number: stages and the six upgrade tracks (`Config.tracks`: tool,
  pickup, hold, quick, walk, tip), each level with its price and unlock stage. Balance changes go
  here; check them with `lune run tools/simulate`.
- `Ladder.luau`: `stats(config, levels)` (what a player's levels add up to, including `sweeps`),
  `offer(config, levels, trackId, stage)` (next level and `"buy"` / `"locked"` / `"max"`),
  `baseSweeps`, `tripSeconds`.
- `Boosts.luau`: fill-milestone boosts (`Config.boosts`): `crossed(milestones, before, after)` and
  `apply(config, stats, id)` (stats with the boost on; the server keeps bought stats separate).
- `Cues.luau`: every feel number (sounds, volumes, pitches, splash sizes). Tune feel here.
- `Water.luau`, `Rewards.luau`, `ToolView.luau`, `Session.luau`, `Ease.luau`, `CoinBurst.luau`,
  `Reveal.luau`, `Steps.luau`, `BodyPose.luau` (carry styles per tool, arm IK, walk/lean/look
  numbers for `Bodies`):
  maths, all Lune-tested (`Cues` too).
- `Zones.luau`, `ToolModels.luau`: touch the place (not pure, not tested).

## Server ↔ client contract
The server publishes state as attributes; the client only reads them.
- `ReplicatedStorage` attributes: `Phase` (`waiting`, `playing`, `card`, `saving`, `results`),
  `Stage` (1-3), `Current`, `Target`, `Fill`, `Waiting`, `ReturnAt`, `Difficulty`,
  `RunStartedAt` / `RunEndedAt` (server time, for the stopwatch), `Boost` (running boost id or
  `""`) and `BoostEndsAt` (server time). `Sweeps` is published with the boost applied.
- Player attributes: `Money`, `Carried`, `Capacity`, `WalkSpeed`, `ActSeconds`, `Sweeps`,
  `ToolName`, `ToolModel`, `ToolTier`, `Equipped`, `Hold`, `CoinBonus`, `Share`, and
  `Level_<trackId>` per upgrade track (`Level_tool`, `Level_walk`, ...); `ActKind` + `ActAt`
  (server time) when an action is accepted, and `Look` (pitch in whole degrees) for other clients.
- Remotes (`ReplicatedStorage.Remotes`, declared in `default.project.json`): `Buy` (track id),
  `Equip` (boolean), `Act` (`"scoop"` or `"pour"`, sent when an action starts; the server credits
  a scoop ActSeconds later and a pour at once), `Look` (camera pitch in degrees, range-checked and
  rate-limited), `Admin` (stage index; the server checks `shared/Admins` and only jumps while
  Phase is `playing`), `Card` and `Results` (server to client).
- A new attribute: set it in `Run.luau`'s `publish`. A new remote: add it to
  `default.project.json` AND to the `remote(...)` list in `Run.start`, validate its arguments, and
  tell the owner to restart `rojo serve` (a running Rojo does not reload the project file; the
  server errors "missing remote" until then).

## UI
- All UI is built in Studio under `StarterGui.Hud` (Wallet, Hotbar, Shop, Card, Waiting, Results,
  Admin).
  Code never builds new UI (it only clones hidden templates like `Results.RowTemplate`); it finds
  elements by name with `Hud.find` and fills them. Renaming or removing an
  element breaks the client with "Hud is missing ...". New UI elements are an Owner step.
- Look: style `sunbaked-sea` (`C:\RobloxDev\library\ui\styles\sunbaked-sea\style.md`). Colours,
  fonts, image ids, 9-slice settings and motion come from the theme module
  `ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"]` (`C:\RobloxDev\shared\UI\Themes\sunbaked-sea.luau`).
  Never hard-code a colour or image id in game code; read it from the theme.
- The look: a dry cracked-sand frame, quiet flat dark-sea panels (built in Studio, not images),
  tiles coloured by category (Tool orange, Boosts teal, locked slate), navy outlines,
  Montserrat Heavy titles, Nunito Heavy body text, white text with a navy outline (thin on small
  text). No corner stickers or sparkles; the angry sun is the one decoration. Tintable images
  (tile, tag, tab, big button) are white; colour them with `ImageColor3` from the theme.
- Windows (anything the player clicks in) must be listed in `Hud.luau`'s `windows` table, so the
  first-person cursor is freed while they are open. While no window is open the mouse icon is
  hidden and `StarterGui.Cursor` (its own ScreenGui, IgnoreGuiInset so it sits on the true
  screen centre; no script inside, `Hud.luau` shows and hides it) marks the aim.
- Windows open and close through `client/Window.luau`. To make a part pop in, give it a number
  attribute `Reveal` (whole part = layer: 1 panels, 2 tags, 3 items, 4 decorations; fraction =
  place in the layer; equal values appear together) and exactly one UIScale child. Decorations
  (4 and up) also swing in by `Reveal.SPIN` degrees and finish with the last item. Never mark a
  child of a UIListLayout/UIGridLayout (its scale moves its siblings); mark what is inside it.
- Tool icons are not drawn yet; slots use the `unknown` image or the tool's 3D model.

## Gotchas (each one has cost time)
- After changing anything in Studio (StarterGui, the map), the owner must **save the place**, or the
  change is lost.
- Uploading images with Open Cloud as `Decal` returns a **decal id**. `ImageLabel.Image` needs the
  image id inside it (load the decal with `InsertService:LoadAsset` and read `Decal.Texture`).
- `ContentProvider:PreloadAsync` reports `Failure` for fresh images when run from a plugin or the
  command bar, even when they work. Check `ImageLabel.IsLoaded` in a play test instead.
- The game is locked first person: `MouseBehavior` is forced to `LockCenter` every frame. To free
  the cursor, override it after the camera runs (see `HudCursor` in `Hud.luau`). Setting
  `GuiButton.Modal` left `MouseBehavior` at `LockCenter` in testing, so don't rely on it.
- Tab opens the shop, so Roblox's player list is disabled in `Shop.luau`. The Board that used to
  show shares is gone.
- Never trust the client: `Equip`, `Buy` and `Act` are all re-checked on the server.

## Hard rules (never break these)
- **Never edit, delete, skip, weaken or special-case a test** to make it pass. If a test looks wrong,
  stop and tell the owner. New tests the plan asks for are fine.
- **No silent error swallowing:** no empty `pcall`, no ignoring errors. Fail loudly with a clear message.
- **No new dependency** (package, tool, plugin) without asking the owner first.
- **Surgical changes:** only change what the task needs. Don't refactor or reformat other code.
  Put new code next to related code, not at the end of a file.
- **Don't touch** `lobby/` unless the plan says so. Don't touch `C:\RobloxDev\shared` (it affects
  every game) unless the plan says so.
- Don't commit or push unless the owner asks.
- Never wait more than 2 minutes on one command. If it hangs, stop it and say so.

## Checks (run inside `gameplay/` after every task that touches it, and show the output)
- `selene src`: must print `0 errors`, `0 warnings`.
- `rojo build -o gameplay.rbxlx`: must succeed.
- `lune run tests/run`: must end with `N passed, 0 failed`.
Say "done" only after all three pass. Also say what you could NOT verify (for example, anything that
needs a Studio play test).

## Roblox rules for this codebase
- Rojo owns code only. The map, terrain and scenery live in the Studio place; the owner saves and
  publishes it in Studio.
- `gameplay/src/shared/` modules that tests cover (Config, Ladder, Water, Rewards, ToolView, Session) must stay
  **pure**: no `require` of other modules, no `game`, no Roblox types, so Lune can run them.
  Lune tests live in `gameplay/tests/*.spec.luau` and are listed in `gameplay/tests/run.luau`.
- Server-authoritative: the server owns money, water, purchases. Validate every remote argument
  (type and allowed values) and rate-limit anything a client can spam.
- `FindFirstChild` results must be nil-checked before use (or use `Zones.part`, which asserts).
- Never yield (`WaitForChild`, `task.wait`) inside `RenderStepped` / `BindToRenderStep` callbacks.
- Write Roblox properties only when the value changes in per-frame code.
- Filling is never automatic: water only moves while the player holds the act input aimed at the
  water; each sweep or pour, once started, always plays out in full.
- For Roblox API facts, check the LihFolk vault:
  `C:\Users\lexru\.claude\plugins\cache\lihfolk\lihfolk\2.5.0\LihFolk Vault V2\` (search it by keyword).
- The owner's taste and numbers: `C:\RobloxDev\library` (rules in `LIBRARY-RULES.md`).
  Order of authority: this game's `CLAUDE.md` > the library > the LihFolk vault.

## Style
- Luau, tabs, existing naming (PascalCase modules, camelCase locals, UPPER_CASE constants).
- Short comments that say why, not what.
