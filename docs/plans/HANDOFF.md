# Handoff: how to continue building Fill the Ocean

Read this first in every new session. Then read CLAUDE.md, AGENTS.md and
`docs/plans/2026-11-05-save-the-ocean.md` (the build plan; its "Phase N tasks" sections are the to-do list).

## Where things are (2026-11-09)
- `main` has everything: Phase 1 (saved runs), Phase 2 (areas) and Phase 3 (3a-3f: items, gadgets,
  area mechanics, vehicles, buildings, staff).
  The owner's checkout `C:/RobloxDev/games/fill the ocean` is on `main`; Rojo serves it to Studio
  (gameplay port 34675, lobby 34674), so whatever is on `main` runs in Studio.
- Phase 3 is done, and a UX round after it (ux/b1-b4, 2026-11-09): hotbar info per held item,
  tutorial at the top with ground chevrons and a click hand, third-person driving, lobby Create Party +
  Saved Runs side by side (New Game replaces the team's save), admin Reset run / Reset my profile,
  pads removed (owner: no teleporting at all), pour basins + channel waves to the ocean, prices and
  real reasons at every stand, a Next goal line (G), clearer shop. **Next: Phase 4** (write its
  step-by-step tasks into the plan first), then 5-9.
- Team economy + honeycomb (2026-11-10): one team wallet, everything bought is the team's, prices x
  (1 + 0.6 per extra player), save version 2 (old saves migrate); the TAB shop is now the honeycomb
  (`client/Honeycomb*.luau`, pure `shared/Honeycomb.luau`, layout in the library's `shop.md`).
- Restarting `rojo serve` drops Studio's Rojo connection; only the owner can click Connect again.
- Phase 2 leftovers (do with 3b or later): per-area ambience/music, guide hint toward the next gate, a
  gate-burst VFX.
- Owner decisions D1-D9 in the plan: use the defaults, never change one.

## Owner's preferences (follow them)
- Use as FEW tokens as possible: few agents, short prompts, no big workflows (the Workflow tool may
  be off). The owner hit the 5-hour limit twice.
- Don't ask the owner to place things or make design choices; decide yourself ("you know better").
- Work in batches. After each batch: merge, play test, report briefly, then ask whether to continue.
- Don't push to GitHub unless asked. Committing and fast-forwarding `main` is fine.
- Plain, short reports.

## How to build one batch (the process that worked)
1. **Worker (one Agent, general-purpose, run in background).** It makes its own worktree:
   `git -C "C:/RobloxDev/games/fill the ocean" worktree add "C:/RobloxDev/games/fto-<id>" -b phaseN/<id> main`.
   The worktree MUST be at `C:/RobloxDev/games/fto-<id>` (that depth makes the Rojo path
   `../../../shared` resolve to `C:/RobloxDev/shared`). Never edit or switch the main checkout.
   Prompt contents: what to read (CLAUDE.md, AGENTS.md, the plan's batch section), the exact job, the
   files it owns, rules (tests first for pure logic, never weaken tests, no swallowed errors, surgical, no
   duplication, server-authoritative, no Roblox Studio tools: list Studio needs under "studioSteps"
   with exact paths), the checks, commit message ending
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, "return briefly".
2. **Reviewer (one fresh Agent, review only).** Give it the brief, the worktree, `git diff main...<branch>`,
   what to look hard at (exploits, saves, races, no duplication), the checks; return pass/fail +
   defects as file:line, problem, fix. One fix round: SendMessage the defects back to the worker.
3. **Studio steps (one Agent, the ONLY one allowed to use Roblox Studio MCP tools)**, run in parallel
   with the review. Rules to give it: edit mode, never edit scripts, never delete (move to
   `ServerStorage.PhaseNRemoved`), never publish, owner's CLAUDE.md camera rule, max 2 min per check,
   sunbaked-sea style (sunny orange #FFB23F, navy #1B2A3A, cream #FFF1C9, shallow water #3FA9E0,
   teal #2FC7B0), clone existing UI pieces, verify every path with execute_luau.
4. **Merge:** in the main checkout `git merge --ff-only phaseN/<id>` (only after the Studio pieces the code
   asserts exist, or the HUD breaks).
5. **Lead play test (you, directly with Studio MCP, no agent):** see below. Fix small things yourself.
6. Report to the owner and remind them to save the place in Studio (File > Save to Roblox).

## Checks (each with `timeout 110`; never wait more than 2 minutes on one)
- gameplay/: `selene src`, `rojo build -o gameplay.rbxlx` (delete output), `lune run tests/run` ("0 failed").
- gameplay/: syntax check (selene and Lune miss Luau's "ambiguous syntax" errors, which stop a script
  from compiling): `& "$env:USERPROFILE\.vscode\extensions\johnnymorganz.luau-lsp-1.70.1-win32-x64\bin\server.exe" analyze --platform=standard src 2>&1 | Select-String "SyntaxError|Ambiguous"` prints nothing.
- lobby/: `selene src`, `rojo build -o lobby.rbxlx`.
- common/: copy `gameplay/selene.toml` in, `selene .`, delete the copy.

## Play testing in Studio (lead)
- `list_roblox_studios` (ids change when Studio reopens), `start_stop_play`, `execute_luau` on
  Server/Client, `user_keyboard_input`, `user_mouse_input`, `screen_capture` (no camera positions, or
  unlock the camera after with the CLAUDE.md fix), `get_console_output` for errors.
- Test helpers (workspace attributes, Studio only): `StudioMoney` (coins to everyone), `StudioFill`
  (fraction 0-1). Admin remote: `ReplicatedStorage.Remotes.Admin:FireServer(0.5)` jumps the fill.
- Aiming: the camera ignores PivotTo in first person. To face something, place the character so the
  camera's current LookVector points at it: `pos = target - flat(LookVector) * 8`.
- Proximity prompts only show when the part is in front of the camera (same trick), then hold E.
- Scoop: stand ~9 studs from a Source facing it, hold E 1.5 s. Pour: the empty ocean needs aiming at
  the seabed (stand at e.g. (60,3,-52) facing -Z or lower).
- Studio play writes to the real DataStores (owner's profile has test data; a finished Studio save
  is replaced by a fresh one automatically).
- Watch the console: ignore the known lines (asset 203785492, Atmos plugin); anything else is a bug.

## Scoring (1-10 per line; the lower of yours and a fresh judge's counts if a judge is used)
- Logic: saves can't be loaded by the wrong team or two servers; autosave on timer/leave/close;
  nothing exploitable from the client.
- Feel: scoop, pour, coins, shop, sound, music, lighting work as before.
- Map: matches the planner; nothing floating, no gaps or empty areas.
- UX: a new player knows what to do within 60 s; works at phone size; sunbaked-sea style.
- Code: surgical, no swallowed errors, no duplication, tests never weakened.
8 = all checks pass and no defect a player would notice. Last scores (Phase 1): Logic 8, Feel 8,
Map 8, UX 7.5, Code 8.

## Batch status (update this table when a batch is merged)
| Batch | Status | Needs first |
|---|---|---|
| 3a Items core + backpacks | done (`40a8030`) | |
| 3b Gadgets | done (`308199d`) | 3a |
| 3c Area mechanics | done (`b7d481f`) | 3b (gloves, pick, net take effect here) |
| 3d Vehicles | done (`8c6274d`) | 3a |
| 3e Buildings | done (`fd27274`) | 3a |
| 3f Staff | done (`7260af9` + lead fixes) | 3d and 3e (Firefighter drives a truck, Plumber fixes buildings) |
If the owner asks for a batch whose "needs first" isn't done, say so and do the missing one first.

## When the owner says "do 3X now"
1. Read this file, then the plan's "Phase 3 tasks" and the batch brief below.
2. Run the batch process above: worker → reviewer (+ one fix round) and the Studio agent in parallel
   → merge → your play test of the brief's "Play test" line → fix small things yourself → checks.
3. Mark the batch done in the status table with its commit, add any new debt below, commit this file.
4. Report briefly (what works, what was tested, scores if you scored, what the owner must save).
The economy rule for every batch: prices and stats fit the tool ladder of the item's area (look at
`Config.tracks` costs for that area and the backpack table in Config); write the reasoning in a comment.
Automated water (buildings, staff) pays HALF the hand rate per litre. Phase 4 retunes everything.

## Batch briefs

### 3b Gadgets
One per area, `Config.items` kind "gadget", sold at their area's stand, levelled in TAB (Gear tab
exists), equipped from the hotbar (new slots next to the tool):
- Water Gun (1): pour from up to 30 studs (levels: range 30/40/55).
- Garden Hose (2): clip to a tap next to each pour spot; while within the hose length you pour
  continuously without carrying (levels: length, litres/s). Server checks distance every tick.
- Heat Gloves (3), Ice Pick (4), Cloud Net (5): stats only now (no effect until 3c).
- Jetpack Tank (4): short flights (press Space in air; levels: fuel seconds), and it adds capacity
  like a small backpack. Cloud Catcher's gate can stay walkable; the jetpack is the fast way up.
Studio: placeholder models `ReplicatedStorage.ToolModels.Gadgets.<Name>`, gear tiles for the 6 items
(clone the existing gear tiles), a `Tap` part next to every area's Pour and next to Ocean.PourPoint,
hotbar slots if the hotbar needs Studio pieces.
Play test: buy Water Gun, pour from 25 studs; buy Garden Hose in Mountain Spring, clip to the tap,
water flows and pays; jetpack flight works and saves.

### 3c Area mechanics
- Steam vents in Hot Springs: 4-6 vent parts, a 1 s warning puff then a burst every ~6 s; a burst
  knocks back a player within 6 studs (server-driven timing, client VFX). Heat Gloves stop knockback
  and make hot pools fill 25/40/60 % faster.
- Ice in Glacier: the Source becomes ice blocks: hit a block N times (Ice Pick lowers N), carry it
  (counts as litres), it melts into litres when poured. Snow slows walking 20 % on snow terrain.
- Clouds in Cloud Catcher: the Source moves slowly between 3-4 points (tween); Cloud Net lets you
  scoop it from 15/25/35 studs.
- A deeper pool per area behind a breakable rock (needs that area's top tool to break; 1.5× litres per
  sweep there).
- Golden spring: every 8-12 minutes one open area's Source glows gold for 2 minutes at 3× pay; a toast
  tells everyone.
Studio: vent parts + steam emitters, ice-block Source setup, cloud waypoints, rocks + deeper pools,
golden VFX in `ReplicatedStorage.Vfx`.
Play test: steam knocks back without gloves, not with; chipping ice works; the cloud moves and the net
reaches it; break a rock; force a golden spring (add a Studio-only `StudioGolden` attribute) and see 3×.

### 3d Vehicles
Fire Truck (2), Tanker (3), Snowcat Tanker (4), Water Bomber (5); kind "vehicle", bought at the Fire
Station (`workspace.Map.Town.FireStation`), one out per player, despawn on leave.
- Called with a prompt at the Fire Station; spawns in front of it. VehicleSeat, W/S throttle, A/D
  steer; collision group so it passes through players; network owner = driver.
- Fill at any hydrant (`Map.Roads.TruckRefillBay1/2` and one per area): about 30 s; you may leave and
  scoop by hand meanwhile. Tank litres valued at the hydrant's area pay (Water.mix).
- Spray: take the hose off the side (a tethered tool, ~20 studs from the truck), aim at the
  waterline, hold to pour; server checks distance, rate and that the truck has water.
- Water Bomber: flies (simple up/down + steer), fills by skimming an area's pool, drops on the ocean.
- Levels: tank size, speed, fill rate, spray rate.
Studio: vehicle models in `ReplicatedStorage.Vehicles.<Name>` (the Fire Truck model exists in the map
kit; make the others as placeholders), hydrants per area, a call prompt at the Fire Station, Vehicles
tab tiles in the shop (replace "Coming soon" for that tab).
Play test: buy the Fire Truck, call it, drive down Main Street, fill at a bay, spray the ocean, fill %
rises and coins pay; leave and rejoin keeps ownership.

### 3e Buildings
Pump, Water Tower, Pipeline, Rain Machine on `workspace.Map.Plots.Plot1..6`; kind "building",
TEAM-owned (D2): anyone buys or levels one, its pay is split evenly between the team.
- Buy: a prompt on an empty plot opens a picker of the buildings on sale (one building per plot;
  the same building may be built on several plots). Save: the team `buildings` table (exists).
- Output: litres per second at HALF the hand pay of the best open area, carried down the aqueducts
  (`Town.Aqueduct_ShopSide/_StaffSide` water flows when any plot on that side is producing).
- Clog: every 4-7 minutes a building clogs and makes half until someone holds E on it.
- Levels: output.
Studio: building models in `ReplicatedStorage.Buildings.<Name>` (Pump and WaterTower exist in the
map kit), plot prompts, Buildings tab tiles in the shop, aqueduct water parts.
Play test: build a Pump, fill rises on its own and coins arrive split between 2 players (Studio
"2 players" test), a clog halves output and holding E clears it; rejoin keeps the building.

### 3f Staff
Helper (2), Lifeguard (3), Firefighter (4), Plumber (5); kind "staff", PERSONAL (D3), up to 3 hires
each; hired at the Lifeguard Tower (`Map.Beach.Stage_Ocean_LifeguardTower`), assigned in TAB.
- Helper: scoops and pours in an assigned open area. Lifeguard: scoops faster; players near them walk
  10 % faster. Firefighter: runs a truck loop on their own (needs 3d). Plumber: keeps buildings
  unclogged and +10 % output (needs 3e).
- Output is computed on the server from rates (no physics); pays the owner HALF the hand rate.
  Staff work 2× while their owner works in the same area.
- Bodies are client-side NPC visuals walking the loop (no server characters): R15 rigs with outfits,
  animations made with the roblox-animation skill: idle, walk empty, walk carrying, scoop, pour,
  cheer, plus one each: wave, whistle, hose spray, wrench.
- Levels: speed, carry, 2nd and 3rd hire.
Studio: NPC rigs in `ReplicatedStorage.Staff.<Name>`, the hire prompt at the tower, Staff tab tiles,
the animations uploaded and their ids in a module.
Play test: hire a Helper, assign Mountain Spring, its body walks the loop and coins arrive; the 2×
bonus when you work beside it; rejoin keeps the hire and assignment.

## Known debt
Stages.blend still has pool/lake scenes; client WaitForChild calls without timeouts; three map
textures owned by user 62763090 not the group; a spoon + backpack needs ~50 scoops to fill
(Phase 4 tuning); the simulator doesn't model backpacks; per-area music missing; item tiles show
the "unknown" icon until icons are drawn. 3c: no ice/steam/golden sounds, no ice-chip VFX, carried ice
looks like water; rocks of areas 4-5 use the ladder's Cargo Ship/The Moon, whose levels still sit in
area 3 (Phase 4); the golden timer counts server time; Cloud Net not play tested (needs 3e9 coins);
Run.luau is ~1400 lines. 3d: the truck hose is proximity-based (within hoseReach of your truck), not a
tethered tool you take off it; tank water isn't saved; no vehicle sounds/VFX; trucks can't reach the
area hydrants (only the cove bays); bomber and Tanker/Snowcat not play tested. 3e: aqueducts have no
water texture; `Run.publish` writes unused `ItemLevel_<id>` for buildings; the money epsilon still
lives in Items, Hud and BuildingRules; 2-player pay split not play tested. 3f: bodies walk straight
lines (can clip through props); clips linted on the stand-in R15 only; Firefighter/Plumber bodies and
30-body perf not play tested; the Staff tiles clip "Lifeguard Tower" to "Lifeguard"; the vendored
animation runtime's LICENSE needs the owner's written OK for use in this game. UX round: the lobby
screen, New Game, Delete and profile reset are not play tested (lobby Rojo needed a reconnect); the
place has no water texture, so channel/aqueduct trickles don't scroll; the tutorial doesn't replay
after an admin reset; the Water Gun sits low-right in first person; the simulator fills the ocean in
16 minutes (Phase 4). Honeycomb: two-player buying and the coin flight on a buy are not play tested;
hex names/badge counts were fixed after the last play test without a visual re-check; no open-lock
image (open gates reuse the lock tinted blue); boost hexes have no icons; prices shown at phones'
smallest scale are about 8 px; `Ladder.offer` repeats `Items.tabOffer`'s track rule; publish only
after every old server is shut down (an old server would drop the team section of a v2 save).
