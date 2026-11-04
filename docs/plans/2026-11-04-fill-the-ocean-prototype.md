# Fill the Ocean Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A playable graybox run in the gameplay place: pool, then lake, then ocean, with hold-to-scoop and hold-to-pour, the full upgrade ladder, water that scales with players, a live share board and a results screen.

**Architecture:** Pure logic (config, ladder, water, rewards) lives in `gameplay/src/shared` as dependency-free modules. They take their inputs as arguments and never `require` or touch `game`, so Lune can test them offline. One server module owns the run (state machine, per-player state, remotes) and replicates state through attributes. One client module draws a plain HUD and sends hold input. The graybox map is built by code only if `workspace.Stages` is missing, so a Studio-built map can replace it later.

**Tech Stack:** Luau, Rojo 7 (`gameplay/default.project.json`), selene, Lune 0.11.1 (tests only, installed with `cargo install lune --locked`).

**Spec:** `docs/design/2026-11-04-fill-the-ocean-design.md`

## Global Constraints

- Work only in `gameplay/`. Checks for every task that touches `src`: `selene src` is clean and `rojo build -o gameplay.rbxlx` succeeds (run inside `gameplay/`).
- Filling is never automatic: litres move only while the player holds the action input.
- Server-authoritative: the server owns money, carried litres, water and purchases. The client only sends "I am holding" / "I released" and "buy next".
- Money, tools and upgrades are per player. Everything carries over between stages. Nothing is saved.
- Water target = `waterPerPlayer(stage) x playerCount`. When the player count changes, the target rescales and the fill percentage stays the same.
- Money is paid per litre actually added. Overfill past the target pays nothing.
- No time limit and no way to lose. A stage ends only when its basin is full.
- Rewards: pot = 100 x players present at the end. 50 each to players who poured at least once in every stage. The other half is split by share. Not saved.
- Share = sum over stages of `weight(stage) x playerLitres(stage) / allLitres(stage)`, weights 7/45, 13/45, 25/45. `allLitres` includes players who left.
- No silent error swallowing. No new dependency besides Lune. Never wait more than 2 minutes on one check.
- Plain UI built in code (no UI style is set). No art, sound, VFX or cutscenes.

## Review Focus

1. **A player leaves mid-stage**: the target shrinks, the fill % holds, and the leaver's litres still count in that stage's share totals. When the last player leaves, nothing errors and the run just stops. Pinned in Task 3 (`rescale` test) and Task 6 (playtest step).
2. **Last pour overshoots**: a big tool pours more than is missing. Only the missing litres are added and paid, and the rest stays carried. Pinned in Task 3 (`pourAmount` test).
3. **Spamming remotes**: an exploiter fires `Buy` 100 times a second, or `SetAction("pour")` while far from the basin. One purchase per affordable item, and no litres move outside the zone. Pinned in Task 6 (rate limit and zone check).
4. **Buying past the end of a stage's list**: the next item of a later stage must not be buyable early, and the last item of the run returns nothing. Pinned in Task 2 (`nextItem` tests).
5. **The share board with someone who never poured**: a 0% player must not produce NaN or a divide-by-zero, and a stage with nobody pouring yet shows 0%. Pinned in Task 4 (`shares` tests).

---

## File Structure

```
gameplay/
  src/shared/Config.luau     -- all numbers: stages, items, distances, rates (data only)
  src/shared/Ladder.luau     -- which item is next, what a purchase changes
  src/shared/Water.luau      -- target, rescale, how much a scoop/pour moves
  src/shared/Rewards.luau    -- shares and the reward split
  src/server/init.server.luau -- requires and starts Map, then Run
  src/server/Map.luau        -- graybox stages if workspace.Stages is missing
  src/server/Run.luau        -- run state machine, players, remotes, attributes
  src/client/init.client.luau -- requires and starts Hud
  src/client/Hud.luau        -- input + plain HUD, share board, cards, results
  tests/run.luau             -- Lune runner: requires every *.spec.luau, prints pass/fail, exits 1 on failure
  tests/Config.spec.luau
  tests/Ladder.spec.luau
  tests/Water.spec.luau
  tests/Rewards.spec.luau
```

Tests run with `lune run tests/run` from inside `gameplay/`. Specs require modules by relative path, for example `require("../src/shared/Ladder")`. Every shared module returns a table and requires nothing, so it runs the same in Lune and in Roblox. On the Roblox side, server and client require them through `ReplicatedStorage.Shared.<Name>`.

---

### Task 1: Test runner and Config

**Files:**
- Create: `gameplay/tests/run.luau`, `gameplay/tests/Config.spec.luau`, `gameplay/src/shared/Config.luau`
- Modify: `CLAUDE.md` (Checks section: add `lune run tests/run` for `gameplay/`)

**Interfaces:**
- Produces: `Config` table:
  - `Config.tripDistance: number = 40` (studs, source centre to basin pour edge, same in every stage)
  - `Config.start = { capacity = 1, walkSpeed = 16, actSeconds = 5.5 }`
  - `Config.stages: { Stage }` in run order, where `Stage = { name: string, minutes: number, coinsPerLitre: number, waterPerPlayer: number, items: { Item } }`
  - `Item = { name: string, kind: "tool" | "walk" | "hands", cost: number, capacity: number? , walkSpeed: number?, actSeconds: number? }`
  - `Config.stageWeights(): { number }` returns `minutes / total minutes` per stage
- Spec helper: each `*.spec.luau` returns `{ [testName]: () -> () }`. `run.luau` calls each one with `pcall`, prints `PASS name` or `FAIL name: err`, prints a total, and calls `process.exit(1)` if any failed. Errors are reported, never swallowed. Give it `expectEq(a, b)` and `expectNear(a, b, tol)` helpers that error with both values.

Item values, copied from the spec. Each "Trip" row is split into a `walk` item ("Sneakers N") and a `hands` item ("Quick Hands N"), each costing half the row, adjacent, walk first. Trip time = `2 x 40 / walkSpeed + 2 x actSeconds`.

| Stage | min | coins/L | waterPerPlayer | Items in order (name, cost, effect) |
|---|---|---|---|---|
| Pool | 7 | 10 | 972 | Cup 20 cap 4; Sneakers 1 69 ws 20; Quick Hands 1 69 act 4.5; Jug 92 cap 10; Watering Can 692 cap 25; Sneakers 2 385 ws 24; Quick Hands 2 384 act 3.85; Bucket 1136 cap 60; Sneakers 3 1637 ws 28; Quick Hands 3 1636 act 3.57 |
| Lake | 13 | 50 | 131305 | Barrel 9000 cap 150; Sneakers 4 28125 ws 32; Quick Hands 4 28125 act 3.25; Bathtub 62500 cap 350; Hot Tub 291667 cap 800; Sneakers 5 166667 ws 36; Quick Hands 5 166666 act 2.9; Kiddie Pool 375000 cap 1800; Fire Truck 1687500 cap 4000 |
| Ocean | 25 | 250 | 361183125 | Swimming Pool 5e6 cap 9000; Sneakers 6 9140625 ws 40; Quick Hands 6 9140625 act 2.75; Water Tower 22.5e6 cap 20000; Tanker Truck 100e6 cap 45000; Cargo Ship 225e6 cap 100000; Rain Cloud 500e6 cap 220000; Sneakers 7 275e6 ws 44; Quick Hands 7 275e6 act 2.6; Iceberg 589285714 cap 480000; Waterfall 2571428571 cap 1e6; Hurricane 5357142857 cap 2.2e6; Glacier 11785714286 cap 4.8e6; The Moon 25714285714 cap 10e6 |

- [ ] **Step 1: Confirm Lune is installed.** Run: `lune --version`. Expected: `lune 0.11.1`. If missing: `cargo install lune --locked`.
- [ ] **Step 2: Write `tests/Config.spec.luau`** with these tests:
  - `stages_in_order`: names are `{"Pool","Lake","Ocean"}`.
  - `weights_sum_to_one`: `expectNear(sum(Config.stageWeights()), 1, 1e-9)`, and weight 1 is `7/45`.
  - `start_trip_is_16s`: `2*40/16 + 2*5.5 == 16`.
  - `trip_times_match_spec`: after applying every walk/hands item in order, the trip times after each pair are 13, 11, 10 (pool), 9, 8 (lake), 7.5, 7 (ocean), each within 0.05.
  - `tools_grow`: every tool's capacity is larger than the previous tool's, across all stages, ending at The Moon `10e6`.
  - `cup_costs_two_spoon_trips`: Pool item 1 is Cup with cost `20 == 2 * 1 * 10`.
- [ ] **Step 3: Run it.** `lune run tests/run`. Expected: FAIL, Config not found.
- [ ] **Step 4: Write `run.luau` and `Config.luau`** with the values above.
- [ ] **Step 5: Run it.** `lune run tests/run`. Expected: 6 PASS, exit 0. Then `selene src` (clean) and `rojo build -o gameplay.rbxlx` (succeeds).
- [ ] **Step 6: Update CLAUDE.md Checks** with the line: `- gameplay/: lune run tests/run passes.`
- [ ] **Step 7: Commit** (only if the owner has said to commit): `git add gameplay/tests gameplay/src/shared/Config.luau CLAUDE.md` then `git commit -m "feat(gameplay): config and Lune test runner"`.

### Task 2: Ladder

**Files:**
- Create: `gameplay/src/shared/Ladder.luau`, `gameplay/tests/Ladder.spec.luau`

**Interfaces:**
- Consumes: `Config` (passed in, not required).
- Produces:
  - `Ladder.nextItem(config, stageIndex: number, boughtInStage: number): Item?`: the item after `boughtInStage` in that stage's list, or `nil` when the stage list is used up. It never returns another stage's item.
  - `Ladder.apply(stats: Stats, item: Item): Stats`: returns a new table. `Stats = { capacity: number, walkSpeed: number, actSeconds: number }`.
  - `Ladder.tripSeconds(config, stats): number` = `2 * config.tripDistance / stats.walkSpeed + 2 * stats.actSeconds`.
  - `Ladder.missedFromEarlierStages(config, stageIndex, boughtPerStage: { number }): { {stage: number, item: Item} }`: items left unbought in earlier stages. Players who skipped them can still buy them first (catch-up), cheapest stage first.
- Buying order rule: the buy button offers earlier-stage leftovers first, then the current stage's next item.

- [ ] **Step 1: Write `tests/Ladder.spec.luau`:**
  - `first_pool_item_is_cup`: `nextItem(Config, 1, 0).name == "Cup"`.
  - `pool_list_ends`: `nextItem(Config, 1, #Config.stages[1].items) == nil`.
  - `no_peeking_into_lake`: the same call does not return "Barrel".
  - `last_item_of_run_is_moon_then_nil`: `nextItem(Config, 3, 13).name == "The Moon"` (14 ocean items) and `nextItem(Config, 3, 14) == nil`.
  - `apply_tool_sets_capacity`: `apply({capacity=1,walkSpeed=16,actSeconds=5.5}, Cup).capacity == 4` and the input table is unchanged.
  - `apply_walk_and_hands`: Sneakers 1 sets walkSpeed 20, Quick Hands 1 sets actSeconds 4.5, and other fields are kept.
  - `missed_items_listed`: with `boughtPerStage = {3, 0}` in stage 2, the result starts with Pool item 4 (Jug) and lists the 7 remaining pool items.
- [ ] **Step 2: Run** `lune run tests/run`. Expected: Ladder tests FAIL (module missing).
- [ ] **Step 3: Implement** `Ladder.luau` with the signatures above.
- [ ] **Step 4: Run** `lune run tests/run`. Expected: all PASS. `selene src` is clean.
- [ ] **Step 5: Commit** (if allowed): `feat(gameplay): upgrade ladder`.

### Task 3: Water

**Files:**
- Create: `gameplay/src/shared/Water.luau`, `gameplay/tests/Water.spec.luau`

**Interfaces:**
- Produces:
  - `Water.target(waterPerPlayer: number, players: number, scale: number): number` = `waterPerPlayer * math.max(players, 1) * scale`.
  - `Water.rescale(current: number, oldTarget: number, newTarget: number): number`: new current with the same fraction, `current / oldTarget * newTarget`.
  - `Water.scoopAmount(carried: number, capacity: number, actSeconds: number, dt: number): number`: litres added to carried this tick, `min(capacity - carried, capacity / actSeconds * dt)`, never below 0.
  - `Water.pourAmount(carried: number, capacity: number, actSeconds: number, dt: number, current: number, target: number): number`: litres moved this tick, `min(carried, capacity / actSeconds * dt, target - current)`, never below 0.

- [ ] **Step 1: Write `tests/Water.spec.luau`:**
  - `target_scales_with_players`: `target(972, 2, 1) == 1944` and `target(972, 0, 1) == 972`.
  - `rescale_keeps_percent`: `rescale(400, 1000, 500) == 200`.
  - `rescale_up_keeps_percent`: `rescale(300, 1000, 2000) == 600` (a player joining in a Studio test).
  - `full_scoop_takes_act_seconds`: sum `scoopAmount` over 5.5 s in 0.1 s ticks with capacity 1 and act 5.5 gives `1` (within 1e-6), and never exceeds capacity.
  - `pour_stops_at_target`: `pourAmount(60, 60, 3.6, 10, 990, 1000) == 10` (overshoot case: only 10 L move, 50 L stay carried).
  - `pour_needs_carried`: `pourAmount(0, 60, 3.6, 0.1, 0, 1000) == 0`.
- [ ] **Step 2: Run** `lune run tests/run`. Expected: Water tests FAIL.
- [ ] **Step 3: Implement** `Water.luau`.
- [ ] **Step 4: Run** `lune run tests/run`. Expected: all PASS. `selene src` is clean.
- [ ] **Step 5: Commit** (if allowed): `feat(gameplay): water target, rescale, scoop and pour amounts`.

### Task 4: Rewards

**Files:**
- Create: `gameplay/src/shared/Rewards.luau`, `gameplay/tests/Rewards.spec.luau`

**Interfaces:**
- Produces:
  - `Rewards.shares(weights: { number }, playerLitres: { [stage]: number }, allLitres: { [stage]: number }): number`: the weighted sum from Global Constraints. A stage with `allLitres == 0` contributes 0.
  - `Rewards.split(players: { { id: any, share: number, pouredEveryStage: boolean } }): { [id]: number }`: pot = `100 * #players`. Eligible players get `50`. Every player gets `round(50 * #players * share)`. Integers, using `math.floor(x + 0.5)`.

- [ ] **Step 1: Write `tests/Rewards.spec.luau`:**
  - `even_group_gets_100_each`: 4 players with share 0.25 each, all eligible, each gets 100.
  - `spec_example`: shares 0.40, 0.25, 0.25, 0.05 (one leaver held the rest) gives 130, 100, 100, 60.
  - `ineligible_gets_only_share`: a 0.10 share who missed a stage, in a group of 2, gets `10`.
  - `zero_share_no_nan`: share 0 and allLitres 0 in a stage gives 0, not NaN (`x == x`).
  - `weights_applied`: a player with all the pool and none of the rest gets `7/45`.
- [ ] **Step 2: Run** `lune run tests/run`. Expected: Rewards tests FAIL.
- [ ] **Step 3: Implement** `Rewards.luau`.
- [ ] **Step 4: Run** `lune run tests/run`. Expected: all PASS. `selene src` is clean.
- [ ] **Step 5: Commit** (if allowed): `feat(gameplay): contribution share and reward split`.

### Task 5: Graybox map

**Files:**
- Create: `gameplay/src/server/Map.luau`
- Modify: `gameplay/src/server/init.server.luau`

**Interfaces:**
- Produces: `Map.ensure(config): Folder` returns `workspace.Stages`. It builds it only if missing. Contract the rest of the code relies on, one Model per stage named after `config.stages[i].name`:
  - `Spawn` (Part, anchored, CanCollide false, transparent): where players are moved at stage start.
  - `Source` (Part, anchored, blue, 8x1x8): standing within 8 studs of its centre (XZ) counts as "at the source".
  - `Basin` (Part, anchored, the floor of the hole) and `Water` (Part, anchored, CanCollide false, blue, transparency 0.3). The water's height goes from 0 to `depth` with the fill fraction. Store the depth as an attribute `Depth` on Water.
  - `PourZone` (Part, anchored, CanCollide false, transparent): a 6-stud ring around the basin. Standing inside its bounds counts as "at the basin".
- Sizes (graybox): pool basin 30x30, depth 8; lake 90x90, depth 14; ocean 220x220, depth 24. Stages 600 studs apart on X. Source centre exactly `config.tripDistance` (40) studs from the nearest PourZone edge, on a flat path. A baseplate under each stage.

- [ ] **Step 1: Implement `Map.ensure`** and call it from `init.server.luau`.
- [ ] **Step 2: Check** `selene src` is clean and `rojo build -o gameplay.rbxlx` succeeds.
- [ ] **Step 3: Verify in Studio.** Open place 112769061602413, run `rojo serve` in `gameplay/`, and connect on port 34873. Start a play test through the Studio connection (`start_stop_play`). Use `execute_luau` to assert that `workspace.Stages` has Pool, Lake and Ocean, each with Spawn, Source, Basin, Water and PourZone. Check that the distance from Source to the PourZone edge is 40 ± 1. Stop the play test.
- [ ] **Step 4: Commit** (if allowed): `feat(gameplay): graybox stages`.

### Task 6: Run server

**Files:**
- Create: `gameplay/src/server/Run.luau`
- Modify: `gameplay/src/server/init.server.luau` (start Run after Map)

**Interfaces:**
- Consumes: `Config`, `Ladder`, `Water`, `Rewards` from `ReplicatedStorage.Shared`, and `Map.ensure`.
- Produces (the client contract):
  - Remotes in `ReplicatedStorage.Remotes` (created by Run): `SetAction: RemoteEvent` (client -> server, arg `"scoop" | "pour" | nil`), `Buy: RemoteEvent` (no args), `Card: RemoteEvent` (server -> client, arg `text: string`, `seconds: number`), `Results: RemoteEvent` (server -> client, arg `{ { name: string, share: number, reward: number } }`, sorted by share, highest first).
  - Player attributes: `Money`, `Carried`, `Capacity`, `WalkSpeed`, `ActSeconds`, `Share` (0-1, live), `NextItemName` (string or ""), `NextItemCost` (number or -1).
  - `ReplicatedStorage` attributes: `Stage` (1-3, 0 before start, 4 after end), `Fill` (0-1), `Current`, `Target`, `Phase` (`"waiting" | "card" | "playing" | "results"`).
- Behaviour:
  - Run starts 5 s after the first player spawns. The scale is `workspace:GetAttribute("WaterScale") or 1`, read at run start. This is for fast play tests only.
  - Each stage: `Phase="card"`. Fire `Card("The sun drained the <name>!", 3)`, move everyone to Spawn, then `Phase="playing"`. When `Current >= Target`: fire `Card("FULL!", 3)` and go to the next stage. After the ocean: compute rewards, fire `Results`, and set `Phase="results"`.
  - Heartbeat: for each player holding an action, scoop if at the source or pour if at the basin (zones from Task 5). Use the `Water` functions. A pour adds money as `litres * coinsPerLitre` and adds litres to that player's stage total and to the stage's all-player total. `Character.Humanoid.WalkSpeed = WalkSpeed`.
  - `SetAction`: accept only `"scoop"`, `"pour"` or `nil`, and ignore everything else. `Buy`: at most 5 per second per player, extra calls dropped. Buys `missedFromEarlierStages` first, then `nextItem`, only when `Money >= cost`.
  - Player count changes (PlayerAdded during a run, PlayerRemoving): recompute Target with `Water.target` and set Current with `Water.rescale`. Then check for completion right away.
  - Live `Share` uses `Rewards.shares` over the stages played so far.

- [ ] **Step 1: Implement `Run.luau`** to the contract above.
- [ ] **Step 2: Check** `selene src` is clean, `rojo build` succeeds, and `lune run tests/run` still passes.
- [ ] **Step 3: Play test with 1 player through the Studio connection.** Set `workspace:SetAttribute("WaterScale", 0.02)` before play. Drive the run with `execute_luau` on the server: fire the action handlers directly or move the character into zones. Assert:
  - Stage goes 1 to 2 to 3 to 4.
  - Money increases only while pouring at the basin.
  - Nothing happens when pouring at the source.
  - Ten `Buy` calls in one frame buy at most one item when you can afford only one.
  - `Results` fires with one entry whose reward is 100 if the player poured in every stage.
  Read the console output for errors. There should be none.
- [ ] **Step 4: Leaver check (Review Focus 1).** Run a 2-player local server test from Studio (Test > Clients and Servers, 2 players) or simulate on the server. Remove one player mid-stage and assert that `Fill` is unchanged within 0.001, `Target` halved, and the stage's all-player litres total is unchanged. Remove the last player and check that the console has no errors.
- [ ] **Step 5: Commit** (if allowed): `feat(gameplay): run server`.

### Task 7: Client HUD and input

**Files:**
- Create: `gameplay/src/client/Hud.luau`
- Modify: `gameplay/src/client/init.client.luau` (start Hud)

**Interfaces:**
- Consumes: the remotes and attributes from Task 6.
- Produces: one ScreenGui built in code:
  - Top centre: stage name and fill bar (`Fill`, shown as `Current / Target L` with short numbers like 1.2M or 25.7B).
  - Bottom left: `Money`, `Carried / Capacity L`.
  - Bottom right: one buy button labelled `NextItemName - NextItemCost`, greyed out when unaffordable, and a big hold button "HOLD" for mobile.
  - Right side: share board with every player's name and `Share` as a %, sorted.
  - Centre: card text for `seconds`, and the results list at the end.
- Input: hold `E`, left mouse, or the HOLD button. While held, send `SetAction("scoop")` when inside the source radius and `SetAction("pour")` when inside the PourZone, as checked on the client for the label only. The server re-checks. Send `SetAction(nil)` on release or when leaving the zone. Send only on change, never every frame.

- [ ] **Step 1: Implement `Hud.luau`.**
- [ ] **Step 2: Check** `selene src` is clean and `rojo build` succeeds.
- [ ] **Step 3: Play test** with `WaterScale` 0.02. Hold at the source and check that Carried rises to Capacity and stops. Hold at the basin and check that Fill and Money rise. Buy the Cup and check that Capacity shows 4. Take a `screen_capture` of the HUD mid-pool and at the results screen. Check the console for errors.
- [ ] **Step 4: Commit** (if allowed): `feat(gameplay): plain HUD and hold input`.

### Task 8: Full-run timing check

**Files:**
- Modify: `gameplay/src/shared/Config.luau` only if the owner approves new numbers.

- [ ] **Step 1: Play the pool at `WaterScale` 1 solo** and note when Cup, Jug, Watering Can and Bucket are bought, and when the pool fills. Target: about 0:35, 2:00, 3:30, 5:00 and 7:00. If the play test can't be watched live, drive it with a server-side script that holds the action and buys immediately (a "perfect player"). Stop at 2 minutes of wall time per check, and use `WaterScale` to scale the time.
- [ ] **Step 2: Report** the measured vs target times to the owner. Do not retune numbers without their yes.
