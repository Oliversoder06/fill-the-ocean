# Save the Ocean Build Plan

> **For agentic workers:** follow `AGENTS.md`. Do the tasks in order. Steps use checkbox (`- [ ]`)
> syntax. Run every command and compare it to its `Expected:` line. Phases 2 to 5 are outlines:
> before building one, write its step-by-step tasks into this file and get the owner's OK.

**Goal:** turn the current build (a 35-minute run through three bodies of water) into the design in
`docs/design/2026-11-04-fill-the-ocean-design.md`: one ocean per map, a long climb, runs saved
per team, story cutscenes, and progression outside the run.

**Owner approval (2026-11-05):** remove everything from the old run design that does not carry
over, including its code, Studio objects and tests. That approval covers deleting and rewriting the
tests listed in each task below. Any other test still follows the hard rule in `AGENTS.md`.

**Tech:** Luau, Rojo, selene, Lune 0.11.1, DataStore + MemoryStore (`common/`), Studio MCP for
Owner-step help.

## Global constraints
- Server-authoritative. Saves are written only by the gameplay server, with `UpdateAsync`.
- One save is loaded in at most one server at a time (a MemoryStore lock).
- Pure modules (no `require`, no `game`) stay Lune-tested in `gameplay/tests/`.
- Checks after every task, in each folder touched: `selene src` (0 errors, 0 warnings),
  `rojo build -o <folder>.rbxlx` succeeds, and in `gameplay/` `lune run tests/run` ends with
  `0 failed`. For `common/`: copy `gameplay/selene.toml` in, run `selene .`, remove it.
- The scoop and pour feel, coins, shop, HUD, sound, music, bodies and lighting must keep working
  after every task. Play test in Studio at the end of each task (the plan says which checks).

## Review focus
1. **A save can't be loaded by the wrong team, or into two servers.** `RunSave.sameTeam` and the
   lock are the gates, and both are tested or checked.
2. **No progress is lost:** autosave on a timer, on PlayerRemoving and on BindToClose; a failed
   load never overwrites a save.
3. **Nothing left behind:** no code, UI or doc still talks about the removed run design
   (search for `Stage`, `stage`, `Pool`, `Lake` after Phase 1).

---

## Phase 1: one saved ocean (conversion)

### Task 1: Config becomes one ocean with a fill curve
**Why:** the old stages set how much a litre pays (10, 50, 250) and which upgrade levels are on
sale. **Owner (2026-11-06): the pay never rises on its own;** higher pay comes from the water of a
harder area (Phase 2). **The fill curve (2026-11-07):** income grows exponentially, so if every
litre counted the same, the fill % would sit near 0 for most of the run and jump at the end. Each
percent therefore needs more litres than the one before (the beach slopes, so the ocean widens as
it rises), chosen so the fill % rises at a steady pace. Phase 4 tunes the numbers; this task only
changes the shape.

**Files:** `gameplay/src/shared/Config.luau`, `Ladder.luau`, `Water.luau`, `Boosts.luau`;
tests `Config.spec`, `Ladder.spec`, `Water.spec`, `Rewards.spec`, `Session.spec`; `tools/simulate.luau`.

**Interfaces:**
- `Config.ocean = { name = "The Ocean", coinsPerLitre = 10, firstPercent = <litres>, growth =
  <factor> }`: percent k needs `firstPercent × growth^(k-1)` litres per player, scaled by team size.
- `Water.fill(current, ocean, players): number` returns the fill fraction 0..1 (inverse of the
  curve, exact at whole percents, straight between them). `Water.litresAt(fraction, ocean, players)`
  is its inverse, used for the target and the admin fill jump.
- Every upgrade level's `stage` field is renamed `area` (same numbers: 1, 2, 3). Until Phase 2
  builds the gates, levels of area 2 and 3 open at stand-in fill points `Config.ocean.standInOpens
  = { 0.07, 0.22 }`; Phase 2 deletes that field.
- `Config.stages`, `Config.stageWeights` and the `Stage` type are deleted. Payout is
  `litres × coinsPerLitre × coinBonus`.
- `Ladder.offer(config, levels, trackId, openAreas)` takes the number of open areas where it took a
  stage; nothing else changes.
- Fill-milestone boosts (`Config.boosts`) keep working on the one ocean: milestones are fractions
  of the whole ocean and each plays once per save (Task 2's `Save` gets `boostsPlayed: { string }`).

- [ ] Delete the stage tests (`Config.stages_in_order`, `Config.weights_sum_to_one`, and every test
  that reads `Config.stages`), `Rewards.spec.luau` and `Rewards.luau` (the share split is removed),
  and replace them with:
  - `Water.fill_is_exact_at_whole_percents`
  - `Water.fill_and_litresAt_round_trip`
  - `Water.fill_scales_with_players`
  - `Config.levels_open_in_order` (within a track, `area` never goes down)
  - `Ladder.level_waits_for_its_area`
- [ ] Run `lune run tests/run`. Expected: the new tests FAIL (functions missing).
- [ ] Implement it. Update `tools/simulate.luau` to fill one ocean (flat pay, buy each level when
  affordable and open) and print the time at every 10%. Pick `growth` so each 10% takes between half
  and twice the average.
- [ ] Run the checks. Expected: tests end `0 failed`; `lune run tools/simulate` prints one `FULL`
  line. The total time is not a target yet (pay is flat until areas exist, so the tier 2 and 3
  prices feel slow; Phase 4 tunes them).

### Task 2: Run saves (pure)
**Files:** create `common/RunSave.luau` and `gameplay/tests/RunSave.spec.luau`, and add the spec
to `tests/run.luau`.

**Interfaces:**
- `export type PlayerState = { money: number, levels: { [string]: number }, litres: number }`
- `export type Save = { version: 1, mapId: string, members: { number }, current: number,
  players: { [string]: PlayerState }, playSeconds: number, introSeen: boolean,
  boostsPlayed: { string }, finished: boolean, updatedAt: number }` (`players` is keyed by the
  user id as a string, because DataStores need string keys).
- `RunSave.new(mapId, members)` returns a fresh save with the members sorted and deduplicated.
- `RunSave.key(mapId, members)` returns `"<mapId>_<sorted ids joined by _>"`. The same team on the
  same map always gets the same key.
- `RunSave.sameTeam(save, userIds)` is true only for the exact same set: no one missing, no one extra.
- `RunSave.sanitize(raw)` returns a Save or nil. It fixes types, clamps negatives to 0, and drops
  unknown fields.

- [ ] Write the tests first:
  - `key_is_order_independent`
  - `same_team_needs_exactly_the_members` (a missing member, an extra member and a duplicate all fail)
  - `sanitize_repairs_bad_fields`
  - `sanitize_rejects_non_tables`
  - `new_save_starts_empty`
- [ ] Expected: `FAIL RunSave.spec (load)`. Implement it, then run the checks. Expected: `0 failed`.

### Task 3: Run storage, locks and the player's run list
**Files:** create `common/RunStore.luau` (not pure, not tested). Edit `common/Progress.luau` and
`common/PlayerData.luau`, and the `Progress` tests in `gameplay/tests/Difficulty.spec.luau`.

**Interfaces:**
- `RunStore.load(key)` returns the Save, nil (no save yet), or nil plus an error.
  `RunStore.save(key, save)` writes with `UpdateAsync`, refuses to write a save that is older than
  the stored one (`updatedAt`), and returns ok plus an error.
- `RunStore.lock(key, serverId)` and `RunStore.unlock(key, serverId)` use a MemoryStore map
  `RunLocks_v1` with a 90-second TTL, renewed every 30 s by the holder. `lock` fails if another
  server holds the key.
- Progress becomes `{ raindrops, runs: { string } (save keys, newest first, at most 10),
  mapsCleared: { [string]: boolean } }`. The difficulty `unlocked` field is removed.
  `Progress.addRun(raw, key)` puts the key first. `Progress.clearMap(raw, mapId, raindrops)`.
- Delete `common/Difficulty.luau`, its tests and every use of it (the map replaces it, Task 4).

- [ ] Move the Progress tests out of `gameplay/tests/Difficulty.spec.luau` into a new
  `gameplay/tests/Progress.spec.luau` (add it to `SPECS` in `tests/run.luau`), rewritten for the new
  shape: old saves with `unlocked` still sanitize, and the field is dropped. Delete
  `Difficulty.spec.luau` and remove `"Difficulty"` from `SPECS`. Expected: the new tests fail
  first, then pass.
- [ ] Checks.

### Task 4: Maps
**Files:** create `common/Maps.luau` (pure) and its spec. Edit `common/RunTicket.luau` and
`gameplay/src/shared/Session.luau` with its spec.

**Interfaces:**
- `Maps.list = { { id = "map1", name = "The Ocean", waterMultiplier = 1, rewardRaindrops = 100,
  unlockedBy = nil }, { id = "map2", name = "Map 2 (placeholder)", waterMultiplier = 1.6,
  rewardRaindrops = 200, unlockedBy = "map1" } }`
- `Maps.get(id)` returns the map or nil. `Maps.unlocked(mapsCleared, id)` returns a boolean.
- The ticket becomes `{ mapId: string, key: string, members: { number } }`.
- `Session.decide` reads `mapId` where it read `difficulty`. In Studio the map comes from the
  workspace attribute `StudioMap` (default `"map1"`).

- [ ] Tests first:
  - `map1_is_always_unlocked`
  - `map2_needs_map1_cleared`
  - `unknown_map_is_nil`
  - the Session tests, rewritten for `mapId`
- [ ] Checks.

### Task 5: The gameplay run loads, plays and saves one ocean
**Files:** `gameplay/src/server/Run.luau`, `Map.luau`, `init.server.luau`;
`gameplay/src/shared/Zones.luau`; `gameplay/default.project.json` (remove the `Card` remote if
unused, see below).

**Behaviour:**
- Phases: `loading`, then `intro` (only when `introSeen` is false; Phase 2 fills it in, until then
  it is skipped), then `playing`, then `ending` (the ocean reached 100%), then `done`.
- On start: read the ticket, take the lock (or send everyone to the lobby with "This run is
  already open"), then load the save or create one with `RunSave.new`. Apply each member's money and
  levels and the shared `current` water.
- The target is `Water.litresAt(1, ocean, teamSize)` × the map's `waterMultiplier`. The fill
  fraction is `Water.fill` (Task 1's curve), not current / target.
- Pours pay `litres × coinsPerLitre × coinBonus`. Open areas come from the stand-in fill points
  until Phase 2.
- Autosave every 60 s, on each PlayerRemoving, and on `game:BindToClose` (wait for it, at most 25 s).
- At 100%: phase `ending`, save `finished = true`, and for each member call `Progress.clearMap`
  (Raindrops from the map) and `Progress.addRun`. Then teleport back to the lobby.
- Delete from Run: stages and `startStage`, cards between stages, shares, reward split and
  results, `RETURN_SECONDS` results timing, `onAdmin` stage jumps (replaced by an admin fill jump:
  `Admin` remote with a number 0-1, admins only).
- Map contract: one model `workspace.Ocean` holding `Spawn`, `Source`, `PourPoint`, `Basin` and
  `Water` (same rules as today). `Map.ensure()` checks it. `Zones` works on that one model.
- Published attributes: drop `Stage`, `Share`, `ReturnAt` and `Difficulty`; add `MapId` and
  `MapName`. Keep `Fill`, `Current`, `Target`, `RunStartedAt`, and replace `RunEndedAt` with
  `PlaySeconds` (total time played on this save, for the stopwatch).

- [ ] **Owner step (Studio, the agent can do it through the Studio connection if asked):**
  1. Move `workspace.Stages.Ocean` to `workspace.Ocean`.
  2. Delete `workspace.Stages`, `workspace.Scenery.Pool` and `workspace.Scenery.Lake`, and the
     backups in `ServerStorage` (`ReplacedScenery`, `OceanBackup`, `HudBackup_BeforeRestyle`).
  3. Remove the pool and lake models from `ServerStorage.StageModels` (keep the ocean ones and
     the sources).
  4. Save the place.
- [ ] Implement it. Checks.
- [ ] Studio play test (StudioMap `map1`): play starts at the ocean; scoop and pour pay; stop and
  play again and the money, levels and water come back (Studio needs API access turned on for
  DataStores); `StudioFill` (admin) to 100% shows the ending phase and clears the map.

### Task 6: Client cleanup for one ocean
**Files:** `gameplay/src/client/Hud.luau`, `Music.luau`, `Ambience.luau`, `Admin.luau`,
`Mood.luau`, `Action.luau`, `Feel.luau`, `Payout.luau`, `Shop.luau`; `shared/Cues.luau` and its spec.

**Behaviour:**
- `Hud.currentStage` becomes `Hud.ocean()` (returns `workspace.Ocean`).
- The progress panel shows the map name; the `STAGE 1/3` tag is deleted. The stopwatch shows
  `PlaySeconds` plus the time since joining.
- Music: one ocean track and the calm track. The final-push rule becomes the last 5% of the map.
  `Cues.musicTrack(phase, fill)`.
- Ambience: one bed (the ocean) plus the heat layer. `Cues.ambience.beds` becomes `Cues.ambience.bed`.
- Admin: buttons jump the fill (0%, 50%, 95%, 100%) instead of stages.
- Mood: remove the angry-sun billboard (`MoodSun`, `Vfx.SkySun`) and show the real sun disc again.
- Shop: a locked level's tile says "Opens at N% full" (its stand-in fill point) instead of a stage
  name; Phase 2 changes it to the area's name.
- Rewrite the stage-based `Cues` tests (`each_stage_plays_its_own_track`,
  `every_stage_has_an_ambience_bed`, `every_music_track_is_named`) for one ocean. Delete
  `waiting_and_results_are_calm` if results no longer exist.
- [ ] **Owner step (Studio):**
  1. Delete `StarterGui.Hud.Progress.StageTag`, `Hud.Results` and its `RowTemplate`, the shop's
     `Sun` decoration (and its `Reveal` entry), `ReplicatedStorage.Vfx.SkySun`, and
     `Audio.MusicPool`, `MusicLake`, `AmbPool` and `AmbLake`.
  2. Rename `Audio.MusicOcean` to `Audio.MusicMap1`.
  3. Rebuild the Admin window's buttons as `Fill0`, `Fill50`, `Fill95`, `Fill100`.
  4. Save the place.
- [ ] Implement it. Checks. Play test: HUD, music, ambience, shop and admin all work, and the
  console shows no "Hud is missing" errors.

### Task 7: Lobby: Create Party and Saved Runs
**Files:** `lobby/src/server/Queue.luau`, `Profiles.luau`; `lobby/src/client/Session.luau`;
`common/SessionRules.luau` and its spec; `lobby/default.project.json`.

**Behaviour (modelled on the owner's Chop a Forest reference):**
- A pad offers two things:
  - **Create Party:** pick a map (unlocked maps only, the others shown locked with "Clear
    <map> first"), party size 1-10, and friends-only. The run starts when the pad is full or the
    host presses Start, as today.
  - **Saved Runs:** the host's runs (from Progress `runs`). Each card shows the map, the members'
    names, the fill % and the last played time, plus a **Load** button. Load is only enabled when
    exactly that team is on the pad (`RunSave.sameTeam`); otherwise the card says who is missing
    or who has to step off.
- The server re-checks everything on launch: the save exists, it isn't locked, it isn't finished,
  and it's the same team. Then it writes the ticket (`mapId`, `key`, `members`) and teleports.
- `SessionRules.validate` takes `mapId` instead of `difficulty`, and gets
  `SessionRules.loadError(saveMembers, padMembers)` returning `"missing"`, `"extra"` or nil.
- Delete the lobby's difficulty selector and the "Difficulty N unlocked" toast.
- [ ] **Owner step (Studio, lobby place):** build the Create Party window (map card with a
  left/right pager, party size −/+, friends-only toggle, Back, Create) and the Saved Runs panel (a
  card template with map, members, fill bar, last played and Load) in the sunbaked-sea style, under
  `StarterGui.LobbyHud`. The agent then wires them by name. Restart `rojo serve` for any new remote.
- [ ] Tests first for `loadError` and the new `validate`. Checks in `lobby/` and `common/`.
- [ ] Two-account test (Studio "2 players" or the published game):
  1. Create a party, play, and leave.
  2. Load the run with the same two players: it works.
  3. Try to load it with one of them: Load is blocked and says who is missing.

### Task 8: Remove leftovers
- [ ] Search `gameplay/`, `lobby/`, `common/` and `docs/` for `Stage`, `stage`, `Pool`, `Lake`,
  `Difficulty`, `difficulty`, `Share` and `Reward`. Every hit is either removed or is an unrelated
  use (the Kiddie Pool and Swimming Pool tools, `Cues.purchase`), and the unrelated ones are listed
  in the task report.
- [ ] Delete `art/models/stages/Stage_Pool_*` and `Stage_Lake_*`, their textures and their
  `art/manifest.json` entries.
- [ ] Update `CLAUDE.md` and `AGENTS.md` (code map, contract, Studio objects) to the new code.
- [ ] Checks in all three folders.

---

## Order and playtest points
The phases run in order. Art (Phase 6) runs alongside from Phase 2 on: every new thing first ships
with a placeholder model under its final name, so code never waits for art.

| After | What can be playtested |
|---|---|
| Phase 1 | A saved run: play, leave, load again with the same team. |
| Phase 2 | The whole area flow: gates, channels, pads, Area 2 fully built, areas 3 to 5 as blockouts. |
| Phase 3 | Everything buyable and working with placeholder models: the first test of every system. |
| Phase 4 | The tuned 20-hour climb with a goal every few minutes. This is the playtest that matters. |
| Phases 5 to 8 | The finished game: real art, story, account level and season pass, launch checks. |

## Owner decisions
Each one has the default Claude builds with unless the owner changes it before the phase that
needs it.

| # | Question | Needed by | Default |
|---|---|---|---|
| D1 | One player buys a gate: does it open for the whole team? | Phase 2 | Yes. |
| D2 | Are buildings the team's or one player's? | Phase 3 | The team's: anyone buys or levels one, its pay is split evenly (6 plots cannot hold 10 players' own buildings). |
| D3 | Are staff the team's or one player's? | Phase 3 | One player's: up to 3 each, their pay goes to the owner. |
| D4 | Does anything fill while nobody plays? | Phase 3 | No. |
| D5 | Save expiry, save count, leaving a team's save | Phase 1 Task 3 | No expiry; 10 runs per player, oldest drops off; a "Leave run" button on the Saved Runs card. |
| D6 | Five areas with these themes? | Phase 2 | Cove Well, Mountain Spring, Hot Springs, Glacier, Cloud Catcher. |
| D7 | Where are the shops? | Phase 2 | One stand per area for its new things; the cove shops stay; TAB levels everything. |
| D8 | What is sold for Robux? | Phase 8 | Nothing before the first public playtest. |
| D9 | The milestone list (one every 5%) | Phase 4 | Claude drafts it in Phase 4; playtests change it. |

---

## Phase 2: areas (outline)
Design: "Areas" in `docs/design/2026-11-04-fill-the-ocean-design.md`; the look and flow are drafted
in the Cove Areas Plan artifact (https://claude.ai/artifact/VaM2mqL6gYWKwHrpAEpWXs). Built as a
vertical slice: Area 2 finished, areas 3 to 5 as blockouts with working gates.
- **Planner first:** add the areas, gates, channels, stands, pads and hydrants to the map planner
  artifact; the owner arranges them; build from its `layouts/main`.
- **Config:** `Config.areas` (id, name, pay multiplier, scoop time factor, gate fill point, gate
  price). Draft gate points 7 / 22 / 45 / 70%. `Config.ocean.standInOpens` is deleted.
- **Pure modules, tests first:** `Areas.luau` (which areas are open, which area a part belongs to,
  the next gate); `Water.mix` (a tool holds litres and their total value, so water scooped in two
  areas pays each area's rate).
- **Map contract:** `workspace.Areas.<Name>` holds `Source` (one or more parts), `Pour` (the
  channel inlet), `Gate` (`Blocker`, `Boards`, `Sign` with its labels, `Prompt`), `Stand`, `Pad`,
  `Hydrant` and `Spawn`. Area 1 is the cove (`workspace.Ocean` keeps its parts). `Map.ensure`
  checks every area.
- **Server:**
  - A gate's sign says "Fill the ocean to N%" until its fill point, then shows the price. Buying
    it (a ProximityPrompt, checked by the server) opens it for the team (D1) and saves it in
    `gatesOpen`; the boards burst, the blocker goes, and everyone gets a toast.
  - Pouring into an open area's `Pour` counts as pouring into the ocean (`Zones` learns the spots).
  - Pads move you between open areas; you spawn at your furthest open area.
  - Shop levels of a closed area say "Opens with <Area>".
- **Client:** channel flow VFX after a pour (the water visibly runs down to the ocean), the gate
  states, the area toast, and ambience and music that follow the area you stand in.
- **Performance:** StreamingEnabled, each area a streamed model; check fps and memory with Studio
  device emulation and one real phone.
- **Owner step (Studio):** Area 2's terrain and props. Claude can build the blockouts of areas 3
  to 5 through the Studio connection.
- **Done when:** from a fresh save, with the admin fill and money jumps: buy gate 2, scoop spring
  water, pour it in its channel and get its pay, use the pads, rejoin and spawn in Area 2.

## Phase 3: everything you can buy (outline)
The buying rule: each thing is bought once at its place on the map, then levelled in TAB, which
lists everything.
- **Ownership:** `Config.items` (id, kind, area, place, price, levels). The save keeps `owned` and
  `levels` per player, and team buildings in a team section (D2). TAB is rebuilt with tabs Tools,
  Gear, Vehicles, Buildings and Staff; things you don't own say where to buy them ("Buy at the
  Mountain Spring stand").
- **Tools (all 8 models exist):** the current ladder split by area: Spoon, Cup, Bucket (1);
  Bathtub, Kiddie Pool (2); Swimming Pool (3); Cargo Ship (4); The Moon (5). Phase 4 may add joke
  tools where the ladder has gaps.
- **Backpacks (5):** Backpack Tank, Big Tank, Twin Tanks, Insulated Tank, Cloud Bag. Once the tool
  is full, scooping fills the pack; one pour empties both. Worn on the back. Levels: size.
- **Gadgets (6), on the hotbar, one mechanic each:**
  - Water Gun (area 1): pour from up to 30 studs away.
  - Garden Hose (2): clip it to a tap and pour non-stop without carrying while you stay within
    reach. A tap sits by every pour spot.
  - Heat Gloves (3): steam no longer knocks you back, and hot pools fill faster.
  - Ice Pick (4): fewer hits per ice block.
  - Jetpack Tank (4): short flights, needed to reach Area 5; it also holds water.
  - Cloud Net (5): catch a drifting cloud from a distance.
  - Levels: range, rate, reach or capacity, whichever fits the gadget.
- **Area mechanics:** shallow spring pools (2, more sweeps per fill); steam vents on a telegraphed
  timer (3); ice blocks you chip, carry and melt at the pour, with snow that slows walking (4);
  drifting clouds that move the source (5). Every area also has a deeper pool behind a breakable
  rock (needs that area's tool) and a golden spring that appears now and then for 2 minutes at
  3× pay.
- **Vehicles (4):** Fire Truck (2), Tanker (3), Snowcat Tanker (4), Water Bomber (5).
  - Called at the Fire Station or an area garage; one per player out at a time; passes through
    players (collision group).
  - WASD driving (VehicleSeat), plus touch and gamepad controls.
  - Fill at any hydrant (about 30 s; leave it filling and scoop by hand meanwhile), drive, take the
    hose off its side (a tethered tool, about 20 studs) and spray anywhere along the waterline.
  - The Water Bomber flies, fills by skimming an area's lake, and drops its load on the ocean.
  - Levels: tank, speed, fill rate, spray rate.
  - The driver gets network ownership of the vehicle; the server checks every fill and spray
    (rate and distance), so a hacked client cannot fake water.
- **Buildings (4), on the 6 cove plots (D2):** Pump, Water Tower, Pipeline, Rain Machine. Each
  makes litres every second at half pay, carried to the sea by the aqueducts. Every few minutes
  one clogs and makes half until someone taps it (or a Plumber fixes it). Levels: output.
- **Staff (4):** Helper (2), Lifeguard (3), Firefighter (4), Plumber (5). Hired at the Lifeguard
  Tower and assigned to an open area, a truck or the plots.
  - Helper: scoops and pours on a loop.
  - Lifeguard: scoops faster, and players near them walk 10% faster.
  - Firefighter: drives a truck loop on their own.
  - Plumber: keeps buildings unclogged and raises their output.
  - Staff work twice as fast while their owner works in the same area (active play pays about
    twice idle).
  - Levels: speed, carry, and a second and third hire (D3).
  - Tech: the server computes their output from rates (no physics); their bodies are client-side
    visuals walking the loop, so 30 staff cost the server nothing.
  - Animations (R15, made with the roblox-animation skill): idle, walk empty, walk carrying, scoop,
    pour, cheer, plus one each: wave (Helper), whistle (Lifeguard), hose spray (Firefighter), wrench
    (Plumber).
- **Remotes:** every buy, level, gate, gadget and vehicle remote is checked by the server and rate
  limited (secure-remotes review).
- **Done when:** with admin money every item can be bought, levelled, used and saved, with
  placeholder models, and a 2-player test shows team buildings and personal staff working.

## Phase 4: the 20-hour climb (outline)
- **Simulator:** `tools/simulate` plays the whole map (hands, areas, gadgets, vehicles, buildings,
  staff) as an active player and as an idle one, and prints a timeline of every purchase and gate.
- **Targets:** solo about 20 hours (±2); something new to buy every 5 to 10 minutes; each area 2.5
  to 5 hours; active play about twice idle; 2 and 4 players within 10% of solo; a steady fill
  (1% ≈ 12 minutes).
- **Milestones every 5% (D9):** each gives a 30 s boost (2× coins, Gusher, Tailwind), a cove
  decoration that comes back to life, a sighting of the bacon-hair, Raindrops, or a cosmetic. The
  camera swoops over the ocean for 2 seconds.
- **Next chip:** the HUD always shows the closest goal ("Heat Gloves Lv3: 82%").
- **Views:** every area's pour spot looks out over the ocean.
- **First 10 minutes:** an arrow to the well, the first pour within 30 s, the first buy within 60 s,
  the TAB hint, and the first gate sign in view (lihfolk-tutorial).
- **Done when:** the simulator meets every target and a 2-hour owner playtest from a new save feels
  right.

## Phase 5: story cutscenes (outline)
- Intro (once per new save, when `introSeen` is false; anyone can skip, which skips for all) and
  ending (at 100%), as written in the design.
- **Owner steps:** a beach chair and sleeping pose for the player, a bacon-hair rig with
  drink / burp / roll-away / smacked animations, camera shot markers
  (`workspace.Ocean.Cutscenes.Intro.Shot1..n`, `Ending.Shot1..n`), and the burp, gulp, "GRRRRR" and
  smack sounds.
- **Code:** `client/Cutscene.luau` plays shots from the markers and the animations, letterbox bars
  and subtitles. The server phases `intro` and `ending` wait for it (with a time cap).

## Phase 6: art and audio (runs alongside Phases 2 to 5)
Pipeline: Blender scripts in `art/source` (like `build_map_kit.py` and `build_buildings.py`)
export GLB files to `art/models`, listed in `art/manifest.json`. The owner imports them into Studio
under the contract names, replacing the placeholders.

| Group | Pieces | Already made |
|---|---|---|
| Areas | Spring (pines, boulders, waterfall, stone pools); Hot Springs (terraces, vents, mineral crust); Glacier (ice walls, ski lift, ice blocks); Cloud Catcher (cloud islands) | none |
| Area kit | gate (rock arch, boards, sign) ×4; channel ×4 (stream, gutter, meltwater slide, waterfall); stand ×4; hydrant; pad; garage | Hydrant, TunnelCliff |
| Cove | garden tap, aqueducts, Backpack stand, refill bays | placeholders |
| Tools | 8 | all 8 |
| Backpacks | 5 | none |
| Gadgets | 6 | none |
| Vehicles | Fire Truck, Tanker, Snowcat Tanker, Water Bomber | Fire Truck |
| Buildings | Pump, Water Tower, Pipeline, Rain Machine | Pump, Water Tower |
| Staff | 4 outfits, their props (whistle, wrench, hose) and the Phase 3 animations | none |
| Story | bacon-hair rig, beach chair pose | none |
| VFX | gate burst, channel flow, steam vent and its warning, ice chip, cloud wring, truck spray, milestone burst | scoop and pour splashes |
| Audio | ambience and music per area, steam hiss, ice chip, engine and horn, staff blips, gate burst | cove ambience and music |
| UI (sunbaked-sea) | TAB for every item kind, gate sign, Next chip, area toast, touch buttons for vehicles and gadgets | HUD, shop |

## Phase 7: account level and season pass (outline)
As in the design: XP from pouring and milestones, the level curve (100 × level^1.5), 50 pass tiers
× 750 XP, calendar seasons, the free track first, a level display over heads and in the lobby, and a
pass window. **Owner first:** the perk list with caps and the season-1 reward list.

## Phase 8: launch readiness (outline)
- Phone, tablet and gamepad controls for every action (vehicles, gadgets, TAB, pads).
- Performance on a low-end phone: fps, memory, part count, streaming, staff visuals (measured,
  with the performance-audit skill).
- Security review of every remote; data safety review (save lock, autosave, a failed load never
  overwrites, save size).
- Analytics funnel: first pour, first buy, gate 2, session length, day-1 return.
- Robux items (D8), then the monetization compliance check.
- Two or three private playtests with kids, with fixes between them.
- Store page: icon, thumbnails, a trailer (roblox-cinematics skill).

## Phase 9: map 2 (outline)
A new map built in its own place or area, unlocked by clearing map 1 (`Maps.unlocked`), harder
through `waterMultiplier`, its own fill curve and its own areas. **Owner first:** the theme and
layout.
