# Agent instructions: Fill the Ocean

You are implementing work in a Roblox game (Luau, Rojo). Usually the owner plans with another
assistant and hands you a plan file in `docs/plans/`; execute it exactly. Sometimes they ask for a
small change directly (see "Small tasks without a plan"). These rules apply to every task.

## Read first
- `CLAUDE.md`: what the game is, the two places (`lobby/`, `gameplay/`), what Rojo owns, the checks.
  It overrides everything below except the safety rules.
- `docs/design/2026-11-04-fill-the-ocean-design.md`: the design (Save the Ocean).
- `docs/plans/2026-11-05-save-the-ocean.md`: the build plan. Do one task at a time, in order.
- Phase 1 of that plan is done: the code map below describes the code as it is (one saved ocean
  per team).

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
- `Run.luau`: the whole run. Loads and autosaves the team's run (`common/RunSave`, `RunStore`),
  phases, per-player state (money, carried, stats, bought levels, equipped), scoop/pour validation
  (`Act` remote), buying, publishing attributes. Most gameplay changes land here.
- `HeldTools.luau`: puts each player's tool model in their hand so others see it, on a `HeldGrip`
  Motor6D (hand to tool) that client `Bodies` turns to suit the carry pose.
- `Map.luau`: checks the baked ocean model and moves the water.
- `Mechanics.luau`: area mechanics (steam vents and their knockback, snow, the drifting cloud, the
  rocks in front of the deeper pools, the golden spring); `Run` starts it with hooks and asks it for
  `rocksBroken` and `goldenId` when it credits a scoop.
- `Vehicles.luau`: vehicles (Fire Truck, Tanker, Snowcat Tanker, Water Bomber): the Fire Station's
  `CallPrompt` brings the best owned one out (`Vehicle_<UserId>`), owner-only `DrivePrompt`, driver
  network ownership, collision groups, hydrant fill, truck hose spray, bomber skim and drop; `Run`
  starts it with the same hooks as `Mechanics` and calls `leave` / `stop`.
- `Buildings.luau`: the team's buildings on `workspace.Map.Plots.PlotN` (`Build` remote, TAB levels
  via `Buy`, output on a tick split between everyone present, clogs, aqueduct flow); `Run` starts it
  with hooks. 3f's Plumber hook: `Buildings.setPlumber(scale, keepClear)`, `Buildings.unclog(plot)`.
- `Staff.luau`: each player's staff (Helper, Lifeguard, Firefighter, Plumber; hired at the Lifeguard
  Tower, a cove shop): `Staff` remote (assign), output from rates on a tick (D4: owner present and
  playing) at half the post's hand pay, 2x while the owner works that area (`state.workArea`, set in
  `onAct`), Lifeguard walk bonus (`state.nearLifeguard`), Plumbers into `Buildings.setPlumber`.
- `Payroll.luau`: ticked pay (buildings' `share`, staff's `owe`) paid in batches; `Run` calls
  `Payroll.payNow()` before a join or leave, at the run's end and on close.

Client (`src/client/`, all started from `init.client.luau`):
- `Hud.luau`: fills `StarterGui.Hud` (wallet, waiting text, card, the top-right `Progress`
  panel: stopwatch, map name, fill bar), frees the cursor while
  a window is open. Exposes helpers `Hud.find` (asserting path lookup), `Hud.set` (write only on
  change), `Hud.short` (1.2K), `Hud.money` (12,480), `Hud.ocean`, and `Hud.walletHold`
  (money still flying in as coins; the wallet shows Money minus it).
- `Action.luau`: scoop and pour input (aim at the water + hold E / LMB / RT / touch button), one
  full sweep or pour per action, the `ActHint` text. Viewmodel and Feel read `Action.current()`.
- `Feel.luau`: sounds and splashes for scoop and pour (own and other players'), from `Cues`.
- `Payout.luau`: when Money goes up, coins burst from the pour, land around you and fly into the
  wallet with rising ticks, plus a "+amount" pop (`Vfx.Coin`, `Vfx.MoneyPop`, `Cues.coins`).
- `Shop.luau`: the shop window: one tile per upgrade track in the Tool and Boosts panels, and a
  detail panel with the Buy button. Opens through `Window`. The `UpgradesButton` (right edge)
  squishes while Tab / gamepad Y / mouse / touch is held and opens or closes the shop on release.
- `Admin.luau`: the admin window (F2), only for user ids in `shared/Admins.luau`: buttons jump the
  ocean's fill (`Hud.Admin.Body.Fill0` / `Fill50` / `Fill95` / `Fill100`, `Admin` remote).
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
- `Ambience.luau`: a looping ocean bed plus a cicada heat layer; filling the ocean fades the
  heat out and the bed up (`Cues.ambience`, `Cues.ambienceMix`).
- `Music.luau`: the map's track, a faster final-push track (last 5% of the ocean) and a calm
  track for waiting (`Cues.musicTrack`); crossfades, ducks under cards and purchases
  (`Music.duck`), plays through `SoundService.Music`.
- `Window.luau`: the shared window open/close (frame pops in, then parts marked `Reveal` pop in
  layer by layer; timing in `shared/Reveal.luau`).
- `Hotbar.luau`: the tool slot (1 / gamepad X / click to equip or unequip), one slot per owned
  hotbar gadget (`Hotbar.Gadgets.<itemId>`; 2 / 3 / 4, gamepad DPadRight) and the fill bar (springs
  with `Ease.pop`) for only what is in hand, its model at the left end: the tool's water, the Water
  Gun's water, the jetpack's fuel, the vehicle's tank (driving or by its hose); the Garden Hose
  shows `Hotbar.Status` text instead (clipped? flowing L/s).
- `Guide.luau`: the first-minute tutorial (new saves, until the first purchase): `Hud.Guide`
  objective at the top centre, yellow ground chevrons toward the step's place (clones of
  `Vfx.GuideChevron`, maths in `shared/GuideTrail`) and a click hand (clone of
  `Hud.Templates.ClickHand`) tapping the button to press. `Guide.pointTo(position?)` leads the
  chevrons anywhere once the tutorial isn't showing (nil hides them).
- `Jetpack.luau`: with the Jetpack Tank out, holding jump asks the server to fly (`Gadget "fly"`).
- `Vehicles.luau`: drives your own vehicle while seated (sets its `Drive` / `Turn` constraints from
  the VehicleSeat's throttle and steer; bomber up/down on E/Q, R1/L1, touch), `driving` (seated in
  your own: CameraFeel goes third person, Viewmodel hides), `hoseReady` (on foot by
  your truck with water: Action sprays it) and `gauge` (Hotbar shows the tank).
- `Mechanics.luau`: steam vent puffs and bursts (vent attributes), the golden spring's glow.
- `Buildings.luau`: the build picker (`Hud.BuildPicker`, options cloned from
  `Hud.Templates.BuildOption`) opened by a plot's prompt; scrolls flowing aqueducts' water.
- `Staff.luau`: staff bodies: from each player's `Staff` attribute, clones of
  `ReplicatedStorage.Staff.<Model>` (anchored root, `workspace.StaffBodies`) walk their loop
  (Source/Pour, Fire Station/refill bay, plots), posed by the animation runtime's `AnimPlayer` with
  `shared/StaffClips` (baked once per model); at most 30, nearest first, none past 250 studs.
- `Viewmodel.luau`: first-person tool or hotbar gadget (`ToolModels.Gadgets.<model>`; sweep / pour
  poses), held by a copy of the player's own right
  hand and forearm, with walk wobble and turn sway. `CameraFeel.luau`: first-person camera bob and
  tilt (`CameraFeel.walk()` shares the walk cycle); third person (Classic, zoom 20-30) while
  driving your own vehicle, and `Hud`'s cursor code frees the mouse then. `Mood.luau`: lighting.

Shared (`src/shared/`, pure unless noted):
- `Config.luau`: every run number: the one ocean (`Config.ocean`: flat `coinsPerLitre`, the fill
  curve `firstPercent` and `growth`, and `standInOpens`, the fill points that open areas 2 and 3
  until Phase 2 builds the gates) and the upgrade tracks (`Config.tracks`: tool, pickup, hold,
  quick, walk, tip), each level with its price and the `area` that opens it. Balance changes go
  here; check them with `lune run tools/simulate`.
- `Ladder.luau`: `stats(config, levels)` (what a player's levels add up to, including `sweeps`),
  `openAreas(config, fill)` (areas open at a fill fraction), `offer(config, levels, trackId,
  openAreas)` (next level and `"buy"` / `"locked"` / `"max"`), `baseSweeps`, `tripSeconds`.
- `Boosts.luau`: fill-milestone boosts (`Config.boosts`): `crossed(milestones, before, after)` and
  `apply(config, stats, id)` (stats with the boost on; the server keeps bought stats separate).
- `Cues.luau`: every feel number (sounds, volumes, pitches, splash sizes). Tune feel here.
- `Water.luau` (the fill curve: `fill`, `litresAt`; `pourAmount`, `scoopAmount`), `ToolView.luau`, `Session.luau`, `Ease.luau`, `CoinBurst.luau`,
  `Reveal.luau`, `Steps.luau`, `Gadgets.luau` (jetpack fuel), `AreaRules.luau` (vent timing, ice hits, deep pools, snow, rock tool,
  golden spring), `BodyPose.luau` (carry styles per tool, arm IK, walk/lean/look
  numbers for `Bodies`), `BuildingRules.luau` (building pay, output, clogs, the build check),
  `GuideTrail.luau` (where the guide's ground chevrons sit and which show):
  maths, all Lune-tested (`Cues` too).
- `VehicleRules.luau` (pure, tested): `best` owned vehicle, `fill`, `spray`, `plausible` (could it
  have got there from its last fill), `skims` (bomber over a pool), `payArea` (refill bays pay the
  vehicle's own area). Numbers in `Config.vehicle`; `Water.share` splits a tank's value.
- `Zones.luau`, `ToolModels.luau`: touch the place (not pure, not tested).
- `StaffRules.luau` (pure, tested): staff `targets` / `post` / `nextPost` (where each job may work),
  `rate`, `payPerLitre`, `bonus` (2x), `plumber`, `walkFactor`, the `Staff` attribute's
  `encode` / `decode`. Numbers in `Config.staff`.
- `StaffClips.luau` (pure data, tested): the staff's clips and gaits for the animation runtime, and
  `overlay` (the carry hold over the walk). `tests/StaffClips.spec` bakes and lints them on R15.

Vendored (`vendor/Animation` -> `ReplicatedStorage.Animation`): the owner's roblox-animation
runtime (pure core + `Roblox/` AnimPlayer etc.; `vendor/LICENSE`, `vendor/PROVENANCE.md`). Outside
`src`, so `selene src` doesn't lint it; don't edit it here, update it from the skill.

Common (`common/`, mapped to `ReplicatedStorage.Common` in both places):
- `RunSave.luau` (pure): a team's saved run (its `buildings` levels and `plots`; per player `assign`,
  staff id -> area id), its key, and the exact-team check (`sameTeam`).
- `Items.luau` (pure): things bought once at an area's stand (`Config.items`) and levelled in TAB:
  `canBuy`, `nextLevel`, the worn backpack and its `capacityBonus` (plus the Jetpack Tank's),
  `standPick` (an area's stand or a cove shop in `Config.stands`; never a building), `gadgetStat`,
  `slots` (hotbar gadgets), `reachable` (Cloud Catcher needs the Jetpack Tank), `teamOwned`,
  `buildingOffer` / `buildingStat` (the team's building levels).
- `RunStore.luau`: loads and saves runs (DataStore) and locks a run to one server (MemoryStore).
- `Maps.luau` (pure): the maps, their difficulty numbers and what unlocks them.
- `Progress.luau` (pure) / `PlayerData.luau`: a player's Raindrops, saved-run keys and cleared maps.
- `RunTicket.luau`: the lobby's ticket for a reserved server (`mapId`, run key, members).
- `SessionRules.luau` (pure): lobby pad rules (create, join, load only with the same team).
- `Places.luau`: the two place IDs. `Retry.luau`: retries DataStore, MemoryStore and Teleport
  calls, warning on every failure.

## Server ↔ client contract
The server publishes state as attributes; the client only reads them.
- `ReplicatedStorage` attributes: `Phase` (`loading`, `intro`, `playing`, `ending`, `done`),
  `MapId`, `MapName`, `Current`, `Target`, `Fill`, `Waiting`, `RunStartedAt` (server time) and
  `PlaySeconds` (time played on this save before this session), for the stopwatch, `Boost`
  (running boost id or `""`) and `BoostEndsAt` (server time), `RocksBroken` (`"1,3"`), `Golden`
  (area id of the golden spring, 0 for none) and `GoldenEndsAt`; vent parts carry `VentState`
  (`warn` / `burst`) and `VentAt`. `Sweeps` is published with the
  boost applied. `BuildingLevel_<id>` (the team's upgrades per building, nil until built); a placed
  building (`Plots.PlotN.Building`) carries `Clogged`; `Town.Aqueduct_<side>` carries `Flowing`.
- Player attributes: `Money`, `Carried`, `Capacity`, `WalkSpeed`, `ActSeconds`, `Sweeps`,
  `ToolName`, `ToolModel`, `ToolTier`, `Equipped`, `Hold`, `CoinBonus`, and
  `Level_<trackId>` per upgrade track (`Level_tool`, `Level_walk`, ...); `Owned` (item ids,
  `"backpackTank,bigTank"`), `ItemLevel_<itemId>` per item and `Backpack` (the worn pack's model or
  `""`); `Capacity` includes the pack and the Jetpack Tank; `Gadget` (the hotbar gadget out instead
  of the tool, an item id or `""`), `HoseArea` (area id the Garden Hose is clipped to, 0 for none),
  `Spraying`, `Flying` and `Fuel` (jetpack seconds left, only once owned), `IceHits` (hits on the
  current Glacier ice block); `ActKind` + `ActAt`
  (server time) when an action is accepted, and `Look` (pitch in whole degrees) for other clients.
  Vehicles (server/Vehicles): `Vehicle` (item id out or `""`), `Tank`, `TankMax` (whole litres),
  `Filling`, `VehicleSpraying`; the vehicle model carries `Owner` (UserId), `ItemId`, `Speed`, `Flies`.
  Staff (server/Staff): `Staff` (`"helper:2@2,firefighter:1@0"`: id:hires@post, post 0 = nowhere).
- Remotes (`ReplicatedStorage.Remotes`, declared in `default.project.json`): `Buy` (track id, or an owned item's id to level it,
  or a built building's id to level it for the team),
  `Build` (plot number, building id; server checks plot empty, area open, price, reach, rate),
  `Staff` (`"assign", itemId, areaId`: an owned staff's post, checked against
  `StaffRules.targets`; rate-limited),
  `Equip` (boolean for the tool, or an owned hotbar gadget's id), `Act` (`"scoop"` or `"pour"`, sent
  when an action starts; the server credits a scoop ActSeconds later and a pour at once; with the
  Water Gun out a pour reaches its range), `Gadget` (`"clip"`, `"spray", on`, `"fly", on`;
  rate-limited, water and fuel follow the server's clock), `Vehicle` (`"spray", on`: the truck's hose
  while on foot within reach of your own truck by the water; rate-limited), `Look` (camera pitch in degrees, range-checked and
  rate-limited), `Admin` (a fill fraction 0-1; the server checks `shared/Admins` and only jumps
  while Phase is `playing`), `Card` (server to client).
- A new attribute: set it in `Run.luau`'s `publish`. A new remote: add it to
  `default.project.json` AND to the `remote(...)` list in `Run.start`, validate its arguments, and
  tell the owner to restart `rojo serve` (a running Rojo does not reload the project file; the
  server errors "missing remote" until then).

## UI
- All UI is built in Studio under `StarterGui.Hud` (Wallet, Hotbar, Shop, Card, Waiting, Progress,
  Admin, BuildPicker).
  Code never builds new UI (it only clones hidden templates like `Hud.Templates`); it finds
  elements by name with `Hud.find` and fills them. Renaming or removing an
  element breaks the client with "Hud is missing ...". New UI elements are an Owner step.
- Look: style `sunbaked-sea` (`C:\RobloxDev\library\ui\styles\sunbaked-sea\style.md`). Colours,
  fonts, image ids, 9-slice settings and motion come from the theme module
  `ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"]` (`C:\RobloxDev\shared\UI\Themes\sunbaked-sea.luau`).
  Never hard-code a colour or image id in game code; read it from the theme.
- The look: a dry cracked-sand frame, quiet flat dark-sea panels (built in Studio, not images),
  tiles coloured by category (Tool orange, Boosts teal, locked slate), navy outlines,
  Montserrat Heavy titles, Nunito Heavy body text, white text with a navy outline (thin on small
  text). No corner stickers or sparkles. Tintable images
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
- Tab opens the shop, so Roblox's player list is disabled in `Shop.luau`.
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
- `gameplay/src/shared/` and `common/` modules that tests cover (Config, Ladder, Water, ToolView,
  Session, RunSave, Maps, Progress, SessionRules) must stay
  **pure**: no `require` of other modules, no `game`, no Roblox types, so Lune can run them.
  Lune tests live in `gameplay/tests/*.spec.luau` and are listed in `gameplay/tests/run.luau`.
- Server-authoritative: the server owns money, water, purchases. Validate every remote argument
  (type and allowed values) and rate-limit anything a client can spam.
- `FindFirstChild` results must be nil-checked before use (or use `Zones.part`, which asserts).
- Never yield (`WaitForChild`, `task.wait`) inside `RenderStepped` / `BindToRenderStep` callbacks.
- Write Roblox properties only when the value changes in per-frame code.
- Filling may be automatic (staff, vehicles, machines; owner, 2026-11-05). A player's own scoop
  or pour still only happens while they hold the act input aimed at the water, and each sweep or
  pour, once started, always plays out in full.
- Saves: only the gameplay server writes a run (`UpdateAsync`, never after a failed load), a run is
  open in one server at a time (`RunStore.lock`), and only its exact team may load it
  (`RunSave.sameTeam`, checked in the lobby and again in the gameplay server).
- For Roblox API facts, check the LihFolk vault:
  `C:\Users\lexru\.claude\plugins\cache\lihfolk\lihfolk\2.5.0\LihFolk Vault V2\` (search it by keyword).
- The owner's taste and numbers: `C:\RobloxDev\library` (rules in `LIBRARY-RULES.md`).
  Order of authority: this game's `CLAUDE.md` > the library > the LihFolk vault.

## Style
- Luau, tabs, existing naming (PascalCase modules, camelCase locals, UPPER_CASE constants).
- Short comments that say why, not what.
