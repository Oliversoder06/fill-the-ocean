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
  phases, the team's economy (`team`: one wallet, track levels, items, staff posts; `earn` / `spend`,
  prices through `Items.price` for the save's team size, `announce` to teammates), per-player state
  (carried, earned, stats from the team's levels, equipped, gadget, hose), scoop/pour validation
  (`Act` remote), buying, publishing attributes. Most gameplay changes land here.
- `HeldTools.luau`: puts each player's tool model in their hand so others see it, on a `HeldGrip`
  Motor6D (hand to tool) that client `Bodies` turns to suit the carry pose.
- `Map.luau`: checks the baked ocean model and moves the water.
- `Mechanics.luau`: area mechanics (steam vents and their knockback, snow, the drifting cloud, the
  rocks in front of the deeper pools, the golden spring); `Run` starts it with hooks and asks it for
  `rocksBroken` and `goldenId` when it credits a scoop.
- `Vehicles.luau`: vehicles (Fire Truck, Tanker, Snowcat Tanker, Water Bomber): the Fire Station's
  `CallPrompt` brings one of the team's vehicles out for the caller (`Vehicle_<UserId>`, one per
  player): the best first, each call while one is
  out swaps it for the next one down (`Items.nextOwned`), caller-only `DrivePrompt`, driver
  network ownership, collision groups, hydrant fill, truck hose spray, bomber skim and drop; `Run`
  starts it with the same hooks as `Mechanics` and calls `leave` / `stop`.
- `Buildings.luau`: the team's buildings on `workspace.Map.Plots.PlotN` (`Build` remote, TAB levels
  via `Buy`, output on a tick paid into the team's wallet, clogs, aqueduct flow); `Run` starts it
  with hooks. 3f's Plumber hook: `Buildings.setPlumber(scale, keepClear)`, `Buildings.unclog(plot)`.
- `Staff.luau`: the team's staff (Helper, Lifeguard, Firefighter, Plumber; hired at the Lifeguard
  Tower, a cove shop): `Staff` remote (assign, any member), output from rates on a tick (D4: a member
  present and playing) at half the post's hand pay, 2x while any member works that area
  (`state.workArea`, set in `onAct`), Lifeguard walk bonus (`state.nearLifeguard`), Plumbers into
  `Buildings.setPlumber`.
- `Payroll.luau`: ticked pay (buildings and staff, `owe`) paid into the team's wallet in batches;
  `Run` calls `Payroll.payNow()` before a leave, at the run's end, on close and before a reset.

Client (`src/client/`, all started from `init.client.luau`):
- `Hud.luau`: fills `StarterGui.Hud` (wallet, waiting text, card, the top-right `Progress`
  panel: `Area` (map name), `AreaSub` ("AREAS 2/5 OPEN"), the pill `Bar` with `Fill`, `Label`
  (`shared/Format.fill`, two decimals below 10%) and `Litres` (Current / Target) inside it, `Goal`
  under it, `Time` (stopwatch), `BoostTag`), frees the cursor while
  a window is open. Exposes helpers `Hud.find` (asserting path lookup), `Hud.set` (write only on
  change), `Hud.short` (1.2K) and `Hud.money` (12,480; both `shared/Format`), the team's economy
  `Hud.wallet()`, `Hud.levels`, `Hud.items`, `Hud.buildings`, `Hud.teamSize()` and `Hud.price(cost)`
  (what a listed price costs the team; every price shown goes through it), `Hud.offer` (what
  TAB offers next: `Items.tabOffer`; `"useless"` for a level that changes nothing, `Ladder.helps`), `Hud.ocean`,
  `Hud.pulseFill(litres)` (the fill bar's pulse when poured water reaches the ocean) and
  `Hud.walletHold` (money still flying in as coins; the wallet shows Wallet minus it).
- `Action.luau`: scoop and pour input (aim at the water + hold E / LMB / RT / touch button), one
  full sweep or pour per action, the `ActHint` text. Viewmodel and Feel read `Action.current()`.
- `Feel.luau`: sounds and splashes for scoop and pour (own and other players'), from `Cues`;
  `Feel.splash` is shared with `Channels`.
- `Channels.luau`: poured water's trip to the ocean: open areas' `Channel.Water` textures trickle,
  each `LastPour` at an area's Pour sends a pooled `Vfx.ChannelWave` down its `Channel.Path`, which
  splashes at the ocean and pulses the fill bar (cove pours just pulse it); fades the seabed's
  `Ocean.PourDecal` as the ocean fills (`Cues.channel`, `shared/PourFlow`). Its `textures` / `scroll`
  also scroll the aqueducts (`Buildings`).
- `Payout.luau`: when your `Earned` goes up (your own income; teammates' and staff/building pay
  just raise the wallet), coins burst from the pour, land around you and fly into the
  wallet with rising ticks, plus a "+amount" pop (`Vfx.Coin`, `Vfx.MoneyPop`, `Cues.coins`).
- `Honeycomb.luau`: the upgrades honeycomb (`Hud.Honeycomb`, layout from `shared/Honeycomb`), a
  full-screen cover: opening blurs the world (`Lighting.HoneycombBlur`) and fades in `Backdrop`; the
  hotbar, wallet, run panel and guide strip hide. One hex per upgrade (copies of
  `Hud.Templates.Hex` in `Board.Canvas`, `Comb.SPACING` apart so a small even gap shows, the view
  fitted to the board with `Canvas.Zoom`, no pan). The main view: the tool hex at the centre (a
  click buys its next tool level) and a ring of six category hexes (Boosts, Gear, Vehicles,
  Buildings, Staff, Areas) with a red `Badge` count; a category view: its Back hex at the centre
  (click, Backspace, gamepad B: back to main, then close; the old `BackButton` is hidden) and its
  upgrades around it (`Comb.ringSlots`). Opens through `Window` (no frame pop); `CloseButton` and
  Roblox's menu (Esc) close it. The `Tooltip` card sits by the hovered hex, else the selected one
  (`HoneycombCard`). A mouse click on an affordable hex buys its next level (`Buy(id, bought)`; a
  gate: `Buy("gate:<areaId>", 0)`; clicks are ignored until the last buy has landed); a tap or
  gamepad A selects first, then buys; the D-pad / stick steps between hexes
  (`shared/Honeycomb.step`); a short hex shakes and pulses the card. A landing plays on the bought
  hex (water rises, pop, check, Level ticks up, then it wakes; `Cues.honeycomb`); only your own buy
  (your `LastBuy`) also gets `Purchase.landed`. Only attributes a hex reads refresh it (closed: the
  badges, a wallet change only when it crosses a badge's price, the fill only when it puts a gate
  on sale). `Honeycomb.show(id)` opens the view holding an id's hex and selects it (Goal);
  `Honeycomb.guideTarget(id)` is the next thing to tap for it (Guide: category hex, then the hex).
- `HoneycombHex.luau`: the honeycomb's hexes: copies of the template painted from one `PAINT`
  table per kind (upgrade blue, owned cyan, locked slate, category warm, Back red, empty dark: one
  colour with a subtle `Body.Shade` gradient (top 10% lighter), a lighter `Outline` rim; the
  template's `Glow` is hidden, no hex breathes; hover 105%, press 95%), each upgrade painted
  in its state (`Name` on top, art, `Level` "2/6" / "MAX", the next level's price at the bottom
  (`short` with a rising fill while short), "Owned" / "Open"; `BackArrow`, `AreaIcon`), dark empty
  hexes completing a category's rings (`Comb.emptySlots`),
  text at fixed `Theme.type` sizes (Name label, Level small, price label; TextScaled off) scaled
  only by the canvas `Zoom`, the landing (`celebrate`), enter / pop / wake
  scales. `HoneycombText.luau`: its words (names, effects, reasons, gate texts, staff posts).
  `HoneycombCard.luau`: the `Tooltip` card (words, placement, the staff `AssignButton`).
  `HoneycombData.luau`: the layout, upgrades by id and the team's state as `shared/Honeycomb` reads
  it (gates priced through `Areas.gateOffer`). `HoneycombButton.luau`: the `UpgradesButton` (right edge; squishes while Tab / gamepad Y /
  mouse / touch is held; Tab / Y toggle as they go down, the mouse / touch on release); its
  `Badge` shows while anything can be bought.
- `Stands.luau`: every stand's prompt texts ("Buy Backpack Tank (1,200)", the reason when a press
  buys nothing) and its price sign (copies of `Hud.Templates.StandSign`, from `Items.standOffer`
  and `shared/Format`, at the team's price); hides the Fire Station's `CallPrompt` until the team owns a vehicle.
- `Goal.luau`: the next-goal line `Hud.Progress.Goal` once the guide is gone (`shared/NextGoal`);
  a click or G opens the honeycomb on it or points the way (`Guide.pointTo` with the stand, gate
  or plot to outline, from ux/b1); `Stands.holder` is a stand's model.
- `Admin.luau`: the admin window (F2), only for user ids in `shared/Admins.luau`: buttons jump the
  ocean's fill (`Hud.Admin.Body.Fill0` / `Fill50` / `Fill95` / `Fill100`, `Admin` remote) and
  `Hud.Admin.Body.ResetRun` (pressed twice) starts the run over (`Admin "reset"`).
- `Purchase.luau`: the purchase moment's sounds and coins, `Purchase.landed` (from `Honeycomb`):
  a sting climbing per level of an upgrade, coins fly from the honeycomb's money into the hex, a chime
  and "NEW!" stamp (`Templates.BoughtStamp`) on a first; `Purchase.deny` shakes a button; new-tool
  swing-up sparkles and speed-upgrade whoosh/FOV kick when the honeycomb closes (`Cues.purchase`).
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
- `Hotbar.luau`: icon-only slots (no boxes, no glow; the ones not in hand sit at
  `Cues.hotbar.idleScale` on their `Press` UIScale with their `View` faded): the
  tool slot (1 / gamepad X / click to equip or unequip), one slot per owned
  hotbar gadget (`Hotbar.Gadgets.<itemId>`; 2 / 3 / 4, gamepad DPadRight) and the fill bar (springs
  with `Ease.pop`) for only what is in hand, its model at the left end: the tool's water, the Water
  Gun's water, the jetpack's fuel, the vehicle's tank (driving or by its hose); the Garden Hose
  shows `Hotbar.Status` text instead (clipped? flowing L/s). `Hotbar.Wave` (a cropped wavy water
  line with faded ends, sized in the place under every gadget slot) shortens to the owned slots.
- `Guide.luau`: the first-minute tutorial (new saves, until the first purchase): `Hud.Guide`
  objective at the top centre (theme `guide` yellow), a flat yellow lane from inside the player
  toward the step's place, `Cues.guide.belowCamera` studs under the camera whatever the ground does
  (up to ~40 studs, never within 8 of the goal: a clone of `Vfx.GuideLane`, a Part with Attachments
  `Start`/`End` and a textured Beam whose texture carries the rails and the sliding chevrons, cut
  cleanly at both ends; maths in `shared/GuideTrail`,
  numbers in `Cues.guide`) and a click hand (clone of `Hud.Templates.ClickHand`) tapping the button
  to press. `Guide.pointTo(position?, model?)` leads the lane anywhere once the tutorial isn't
  showing (nil hides it) and outlines `model` with a clone of `Vfx.GuideHighlight`.
- `Jetpack.luau`: with the Jetpack Tank out, holding jump asks the server to fly (`Gadget "fly"`).
- `Vehicles.luau`: drives your own vehicle while seated (sets its `Drive` / `Turn` constraints from
  the VehicleSeat's throttle and steer; bomber up/down on E/Q, R1/L1, touch), `driving` (seated in
  your own: CameraFeel goes third person, Viewmodel hides), `hoseReady` (on foot by
  your truck with water: Action sprays it) and `gauge` (Hotbar shows the tank); names the next vehicle
  in the Fire Station's `CallPrompt` while it shows (local `ActionText`, `Items.nextOwned`).
- `Mechanics.luau`: steam vent puffs and bursts (vent attributes), the golden spring's glow.
- `Milestones.luau`: every 5% (`Milestone` attribute, `shared/Milestones`): a 2 s camera swoop up
  and out over `Ocean.Basin` and back (Scriptable, restored exactly; skipped while driving or with
  the honeycomb open), `Music.duck` and a fanfare (the toast is the server's card); a sighting puts a
  copy of `ReplicatedStorage.Story.BaconHair` far out at sea for ~6 s (placeholder rise, sway, sink).
  Keeps `workspace.Map.Revive.M<n>` hidden (parts, decals, lights and emitters, their place looks
  remembered; stream-safe) until `Revived` names them; one revived live pops in with a sparkle.
  Numbers in `Cues.milestone`.
- `Buildings.luau`: the build picker (`Hud.BuildPicker`, options cloned from
  `Hud.Templates.BuildOption`) opened by a plot's prompt; scrolls flowing aqueducts' water.
- `Staff.luau`: staff bodies: from the ReplicatedStorage `Staff` attribute (the team's), clones of
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
  curve `firstPercent`, `growth` and per-area `stretches`, and `teamStep`, how much bigger a team's
  ocean is; `shared/Water`) and the upgrade tracks (`Config.tracks`: tool, pickup, hold,
  quick, walk, tip), each level with its price and the `area` that opens it; `Config.team.priceStep`
  (every price x (1 + step x (players - 1))); `Config.milestones` (20, one every 5%: a `boost` and
  one extra each, `revive` / `sighting` / `raindrops` / `cosmetic`; 100% is the `ending`). Balance
  changes go here; check them with `lune run tools/simulate [quiet] [team size]` (timeline) and
  `lune run tools/simulate targets` (the Phase 4 targets, also run by `tests/Simulator.spec`; the
  model is `tools/Simulator.luau`). Formulas and reasons: `C:\RobloxDev\library\balance\README.md`.
- `Ladder.luau`: `stats(config, levels)` (what the team's levels add up to, including `sweeps`),
  `openAreas(config, fill)` (areas open at a fill fraction), `offer(config, levels, trackId,
  openAreas)` (next level and `"buy"` / `"locked"` / `"max"`), `helps` (pickup only while the tool
  takes more than one sweep; the server refuses it otherwise), `baseSweeps`, `tripSeconds`.
- `Format.luau`: words and numbers the player reads, for the client and the server's cards:
  `short`, `money`, `litres`, `fill`, `percent`, `need`, `gateHint`, `standName`, `levelName`, and the stand
  texts `standAction` (prompt), `standCard` (why a press bought nothing), `standSign`; the price
  texts take an optional `priceOf` (the team's price, `Hud.price` / the server's `price`).
- `NextGoal.luau`: `pick(offers, gate, money, fill, formatters)`: the next-goal line's one thing
  (the dearest affordable buy, the gate on sale, the cheapest next buy, the next gate's fill).
- `Honeycomb.luau` (pure, tested): the upgrades honeycomb: flat-top hex maths (`toPixel`,
  `bounds` (with `SPACING`, the gap), `zoom`, `enterDelay`, `step` for gamepad moves), `ringSlots`
  (up to 18 cells around a centre, ring 1 then ring 2, mirror-symmetric, read top to bottom),
  `emptySlots` (the dark cells completing the rings reached),
  `layout(config)` (`tool`; the `ring` of categories; each category's upgrades, earlier areas
  first, in `ringSlots`: one hex per track, item, the backpacks, and per gate in Areas), `upgrades`,
  `ownedCount`, `link` (the level a hex sells), `state` / `states(layout, viewId, view)` (buy /
  short / max / locked, owned of total), `ownedShare`, `badges` (per view, `main` the tool, and the
  wallets that keep them), `find` (an id's view and upgrade), `pick` (the hex to select), `bought`
  (Buy's `bought`), `levelText`, `elsewhere` (bought at a stand or plot), the `LastBuy` attribute's
  `encodeBuy` / `decodeBuy`.
- `Boosts.luau`: milestone boosts (`Config.boosts`): `apply(config, stats, id)` (stats with the
  boost on; the server keeps bought stats separate); which milestone plays one is `Milestones`.
- `Milestones.luau` (pure, tested): the one milestone system (`Config.milestones`): `crossed(config,
  before, after)` (every one passed, in order), `reach` (adds the new ones to a run's reached list and
  returns them: once per run), `reachedBy` (an old save's, never granted), `reward`, `revived` (the
  `Revived` list), `raindrops` (what reached ones pay, minus an old save's skipped ones; the run
  re-pays on open, `Progress.payMilestones` keeps it once each), `card` (the team's toast), the
  `Milestone` attribute's `encode` / `decode`.
- `Cues.luau`: every feel number (sounds, volumes, pitches, splash sizes). Tune feel here.
- `Water.luau` (the fill curve: `fill`, `litresAt`; `pourAmount`, `scoopAmount`), `ToolView.luau`, `Session.luau`, `Ease.luau`, `CoinBurst.luau`,
  `Reveal.luau`, `Steps.luau`, `Gadgets.luau` (jetpack fuel), `AreaRules.luau` (vent timing, ice hits, deep pools, snow, rock tool,
  golden spring), `BodyPose.luau` (carry styles per tool, arm IK, walk/lean/look
  numbers for `Bodies`), `BuildingRules.luau` (building pay, output, clogs, the build check with an
  optional `priceOf`),
  `GuideTrail.luau` (the guide's lane: its stretch `lane`):
  maths, all Lune-tested (`Cues` too).
- `VehicleRules.luau` (pure, tested): `best` owned vehicle, `fill`, `spray`, `plausible` (could it
  have got there from its last fill), `skims` (bomber over a pool), `payArea` (refill bays pay the
  vehicle's own area). Numbers in `Config.vehicle`; `Water.share` splits a tank's value.
- `Zones.luau`, `ToolModels.luau`: touch the place (not pure, not tested). `Zones.channelPath` reads
  an area's `Channel.Path` (server/Map checks it, client/Channels follows it). `Zones.stand`,
  `Zones.shop` and `Zones.standPrompt` find stands for the server (`Map`) and the client (`Stands`).
- `PourFlow.luau` (pure, tested): the `LastPour` attribute's `encode` / `decode`, a wave's place
  `along` a channel path, the fill bar's `pulse` and the seabed marker's fade.
- `StaffRules.luau` (pure, tested): staff `targets` / `post` / `nextPost` (where each job may work),
  `rate`, `payPerLitre`, `bonus` (2x), `plumber`, `walkFactor`, the `Staff` attribute's
  `encode` / `decode`. Numbers in `Config.staff`.
- `StaffClips.luau` (pure data, tested): the staff's clips and gaits for the animation runtime, and
  `overlay` (the carry hold over the walk). `tests/StaffClips.spec` bakes and lints them on R15.

Vendored (`vendor/Animation` -> `ReplicatedStorage.Animation`): the owner's roblox-animation
runtime (pure core + `Roblox/` AnimPlayer etc.; `vendor/LICENSE`, `vendor/PROVENANCE.md`). Outside
`src`, so `selene src` doesn't lint it; don't edit it here, update it from the skill.

Common (`common/`, mapped to `ReplicatedStorage.Common` in both places):
- `RunSave.luau` (pure): a team's saved run (its `team`: `wallet`, track `levels`, `owned` items,
  `itemLevels`, staff `assign` (staff id -> area id); its `buildings` levels and `plots`; per player
  only `litres`; `milestones` reached (indices, nil in a save from before them: the server marks
  those below its fill without granting, and lists them in `milestonesSkipped`, never paid)), its key, the exact-team check (`sameTeam`), `blank` / `isBlank` (what erasing a run
  leaves), and `sanitize`, which turns a save from before the team economy (money, levels and items
  per player) into one team: money added up, the best levels, every item, the first member's posts;
  given gameplay's Config (`RunStore.load(key, Config)`) it also migrates a version 2 save's tool
  level by model (`V2_TOOL_MODELS`) and clamps every level and milestone to the Config.
- `Items.luau` (pure): things bought once at an area's stand (`Config.items`) and levelled in TAB,
  all the team's: `price(config, cost, teamSize)` / `priceScale` (every price for the save's team
  size), `canBuy`, `affords` (the one money check with the fractional-coin epsilon), `nextLevel`, the
  worn backpack and its `capacityBonus` (plus the Jetpack Tank's), `standPick` (an area's stand or
  a cove shop in `Config.stands`; never a building) and `standOffer` (what it shows: the pick, or
  the item and `"money"` / `"locked"`, or `"owned"`), `gadgetStat`,
  `slots` (hotbar gadgets), `reachable` (Cloud Catcher needs the Jetpack Tank), `teamOwned`,
  `buildingOffer` / `buildingStat` (the team's building levels), `tabOffer` (what TAB sells next:
  the one rule for server/Run's `onBuy`, `Hud.offer` and the honeycomb), `nextOwned` (the vehicle a Fire
  Station call brings next).
- `Areas.luau` (pure): open areas (`open`, `openIds`), `nextGate`, `gateOffer` (open / buy / fill
  / order: the one gate rule for server/Run's `openGate`, client/Gates' signs and the honeycomb),
  `gateId` / `fromGateId` (`"gate:<areaId>"`, the honeycomb's Buy id), `byId`.
- `RunStore.luau`: loads and saves runs (DataStore) and locks a run to one server (MemoryStore);
  `erase` (the lobby's New Game / Delete / profile reset) writes a blank save only while holding the lock.
- `Maps.luau` (pure): the maps, their difficulty numbers and what unlocks them.
- `Progress.luau` (pure) / `PlayerData.luau`: a player's Raindrops, saved-run keys and cleared maps
  (`forgetRun`: an erased run leaves the list and its ending's payment, its paid milestones stay;
  `reset`: an admin's profile reset;
  `payMilestones`: a run's milestone Raindrops, each milestone once per run, `paidMilestones`).
- `RunTicket.luau`: the lobby's ticket for a reserved server (`mapId`, run key, members).
- `SessionRules.luau` (pure): lobby pad rules (create, join, load only with the same team, and
  `newTeam` / `savedFor`: the save a new party would start over, one per map per team).
- `Places.luau`: the two place IDs. `Retry.luau`: retries DataStore, MemoryStore and Teleport
  calls, warning on every failure.

## Server ↔ client contract
The server publishes state as attributes; the client only reads them.
- `ReplicatedStorage` attributes: `Phase` (`loading`, `intro`, `playing`, `ending`, `done`),
  `MapId`, `MapName`, `Current`, `Target`, `Fill`, `Waiting`, `RunStartedAt` (server time) and
  `PlaySeconds` (time played on this save before this session), for the stopwatch, `Boost`
  (running boost id or `""`) and `BoostEndsAt` (server time), `Milestone` (`"<index>@<serverTime>"`,
  the last milestone granted, `shared/Milestones`) and `Revived` (`"1,2,5"`: the `Revive.M<n>`
  decorations the run's milestones brought back), `RocksBroken` (`"1,3"`), `Golden`
  (area id of the golden spring, 0 for none) and `GoldenEndsAt`, `LastPour`
  (`"<areaId>@<litres>@<serverTime>"`, set on every accepted `Act` pour; `shared/PourFlow`); vent parts carry `VentState`
  (`warn` / `burst`) and `VentAt`. `Sweeps` is published with the
  boost applied. `BuildingLevel_<id>` (the team's upgrades per building, nil until built); a placed
  building (`Plots.PlotN.Building`) carries `Clogged`; `Town.Aqueduct_<side>` carries `Flowing`.
  The team's economy (everything bought is the team's, owner 2026-11-10): `Wallet` (the team's
  coins), `TeamSize` (the save's members, fixed for the run), `PriceScale` (every listed price x
  this, rounded: `Items.price`), `Level_<trackId>` per upgrade track (`Level_tool`, `Level_walk`,
  ...), `Owned` (item ids, `"backpackTank,bigTank"`), `ItemLevel_<itemId>` per item, and `Staff`
  (server/Staff: `"helper:2@2,firefighter:1@0"`: id:hires@post, post 0 = nowhere).
- Player attributes: `Earned` (coins this player's own pours, hose and vehicle brought the team this
  session), `Carried`, `Capacity`, `WalkSpeed`, `ActSeconds`, `Sweeps`,
  `ToolName`, `ToolModel`, `ToolTier`, `Equipped`, `Hold`, `CoinBonus` (all from the team's levels),
  and `Backpack` (the worn pack's model or
  `""`); `Capacity` includes the pack and the Jetpack Tank; `Gadget` (the hotbar gadget out instead
  of the tool, an item id or `""`), `HoseArea` (area id the Garden Hose is clipped to, 0 for none),
  `Spraying`, `Flying` and `Fuel` (jetpack seconds left, only once owned), `IceHits` (hits on the
  current Glacier ice block); `ActKind` + `ActAt`
  (server time) when an action is accepted, and `Look` (pitch in whole degrees) for other clients.
  `LastBuy` (`"<id>@<bought>@<serverTime>"`, `shared/Honeycomb.encodeBuy`): set on the buyer only
  by every `Buy` the server credits (`bought`: the id's new count, as `Honeycomb.bought` reads it);
  client/Honeycomb plays its buy moment only for its own `LastBuy`.
  Vehicles (server/Vehicles): `Vehicle` (item id out or `""`), `Tank`, `TankMax` (whole litres),
  `Filling`, `VehicleSpraying`; the vehicle model carries `Owner` (UserId of who called it), `ItemId`, `Speed`, `Flies`.
- Remotes (`ReplicatedStorage.Remotes`, declared in `default.project.json`): `Buy` (id, bought: a
  track id, or an owned item's id to level it, or a built building's id to level it, for the team;
  `bought` is how many levels of it the client saw bought (-1 for an item not owned or a building
  not built): a lower count than the server's means a teammate bought that level first, and the
  buyer gets a card instead of the level after it; `"gate:<areaId>", 0` buys that gate through
  `openGate`, the gate prompt's own checks minus the reach),
  `Build` (plot number, building id; server checks plot empty, area open, the team's price, reach, rate),
  `Staff` (`"assign", itemId, areaId`: one of the team's staff's post, checked against
  `StaffRules.targets`; rate-limited),
  `Equip` (boolean for the tool, or an owned hotbar gadget's id), `Act` (`"scoop"` or `"pour"`, sent
  when an action starts; the server credits a scoop ActSeconds later and a pour at once; with the
  Water Gun out a pour reaches its range), `Gadget` (`"clip"`, `"spray", on`, `"fly", on`;
  rate-limited, water and fuel follow the server's clock), `Vehicle` (`"spray", on`: the truck's hose
  while on foot within reach of your own truck by the water; rate-limited), `Look` (camera pitch in degrees, range-checked and
  rate-limited), `Admin` (a fill fraction 0-1, or `"reset"`: the run starts over live for the same
  team and map, at most once per 10 s; the server checks `shared/Admins` and only acts
  while Phase is `playing`), `Card` (server to client).
- A new attribute: set it in `Run.luau`'s `publish` (a player's) or `publishTeam` (the team's). A new remote: add it to
  `default.project.json` AND to the `remote(...)` list in `Run.start`, validate its arguments, and
  tell the owner to restart `rojo serve` (a running Rojo does not reload the project file; the
  server errors "missing remote" until then).

## UI
- All UI is built in Studio under `StarterGui.Hud` (Wallet, Hotbar, Honeycomb, Card, Waiting,
  Progress, Admin, BuildPicker; `Templates.StandSign` is the stands' BillboardGui, `Templates.Hex`
  the honeycomb's piece: a transparent ImageButton hit area over `Glow` (1.25x, lowest; hidden by
  code), `Body`
  (+ UIGradient `Shade`), `Outline` (the rim), `Water.Fill`, `Name`, `View`, `Icon`, `Level`
  (above `PriceRow`), `Lock`, `Check`, `Badge.Count`, `BackArrow` and `AreaIcon` (hidden
  ImageLabels), `Select`, `Press`; `Bottom` is hidden and unused; `Templates.Bridge` is no longer used). `Hud.Honeycomb` is a full-screen
  cover (no window frame): `Backdrop`, `Board.Canvas`, `Title`, `BackButton` (hidden by code),
  `CloseButton`, `Wallet`, `Tooltip`; with `Lighting.HoneycombBlur` (a BlurEffect at Size 0).
  Code never builds new UI (it only clones hidden templates like `Hud.Templates`); it finds
  elements by name with `Hud.find` and fills them. Renaming or removing an
  element breaks the client with "Hud is missing ...". New UI elements are an Owner step.
- Look: style `clear-tide` (`C:\RobloxDev\library\ui\styles\clear-tide\style.md`). Colours,
  fonts, image ids, 9-slice settings, text stroke and motion come from the theme module
  `ReplicatedStorage.Kit.UI.Themes["clear-tide"]` (`C:\RobloxDev\shared\UI\Themes\clear-tide.luau`).
  Never hard-code a colour or image id in game code; read it from the theme, by its semantic key
  (`upgradeTop`, `owned`, `short`, `text`, `guide`, ...; the old key names are only aliases).
- The look: icon-led HUD with no boxes or panels behind HUD numbers (a big icon and a plain
  number), an icon-only hotbar, flat-coloured hexes with a subtle top-to-bottom gradient and a thin
  lighter rim (no glow, no hard outline), one colour per job, Montserrat (Bold names, ExtraBold numbers and
  titles; sizes from `Theme.type`), white text with a solid dark stroke (`textStroke`: thickness
  2, colour `shadow`). Tintable images are white; colour them with `ImageColor3` from the theme.
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
- Tab opens the honeycomb, so Roblox's player list is disabled in `Honeycomb.luau`.
- `Templates.Hex` has a child called `Name`: `hex.Name` is the property, so find it with
  `Hud.find(hex, "Name")`.
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
  Session, RunSave, Maps, Progress, SessionRules, Format, NextGoal, Honeycomb, Cues, Items) must stay
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
  (`RunSave.sameTeam`, checked in the lobby and again in the gameplay server). The lobby only ever
  erases a run (`RunStore.erase`: a blank save, written while it holds the run's lock, so never
  while a gameplay server has it open). One save per map per team: a New Game replaces it.
- For Roblox API facts, check the LihFolk vault:
  `C:\Users\lexru\.claude\plugins\cache\lihfolk\lihfolk\2.5.0\LihFolk Vault V2\` (search it by keyword).
- The owner's taste and numbers: `C:\RobloxDev\library` (rules in `LIBRARY-RULES.md`).
  Order of authority: this game's `CLAUDE.md` > the library > the LihFolk vault.

## Style
- Luau, tabs, existing naming (PascalCase modules, camelCase locals, UPPER_CASE constants).
- Short comments that say why, not what.
