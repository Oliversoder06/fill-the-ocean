# Fill the Ocean: game design and prototype scope

Date: 2026-11-04. Status: design settled for the prototype. Rewards' use and difficulties are parked.

## Intent

The evil sun has evaporated all the water on Earth. Up to 10 friends refill it, starting with a
spoon. The model is the "Needle in a Haystack" loop (about 40k CCU): collect, deposit, earn, upgrade,
until the goal is reached. The owner finds that game boring and believes it holds players because
upgrades make you go from feeling slow to feeling fast quickly. **Every purchase must make the
next trip noticeably quicker or bigger.** The upgrade ladder (spoon to the Moon) is the joke and the
hook.

## Goals, non-goals, anti-goals

- Goal: a fun, felt-in-the-hands slow-to-fast climb in one session-based co-op run.
- Goal (later, not prototype): day 1 / day 7 retention through difficulty unlocks and rewards.
- Non-goal now: saving, lobby, matchmaking, rewards spending, difficulties, cutscenes, polish.
- Anti-goal: **filling is never automatic.** Every tool, even a hose or fire truck, only collects
  or pours while the player holds the input. A Robux auto-fill may come later; not in the prototype.
- Anti-goal: dead time. No more than about 2.5 minutes between new tools, plus speed upgrades
  in between.

## The run (settled)

- Session-based. A group of 1-10 forms in the lobby and teleports together to a private gameplay
  server. **No joining mid-run.** Nothing carries over between runs except unlocked difficulties and
  the reward currency (both later).
- One run = pool (7 min) -> lake (13 min) -> ocean (25 min), about 45 min at Difficulty 1. A cutscene
  of the sun draining each body of water starts each stage (prototype: a text card).
- **Tools, speed upgrades and money carry over** between stages within a run. Each stage adds its
  own set of new tools. Each stage pays more per litre, so a player who fell behind buys the
  previous stage's remaining upgrades within seconds.
- Each stage's water is sized so a player starting it with the previous stage's best gear and
  climbing that stage's upgrades fills their share in the stage's target time.
- **Water scales with players:** target = X(stage) x player count. When a player leaves, the
  target rescales and the fill **percentage** stays the same, so the time left per player stays
  equal.
- Rewards are paid only at the end of the run. Leaving early forfeits them.

## Core action (settled)

- Trip: scoop at a water source -> carry -> pour into the basin. Scoop and pour are each **one hold
  prompt** that fills or empties the whole tool at once, with no meter climbing (owner, 2026-11-04). The
  hold starts at 0.5 s; Quick Hands upgrades shorten it to 0.2 s. The path is 80 studs. Owner accepted
  the shorter run this gives: trips 11 s down to 5.4 s, and a perfect solo player fills pool / lake /
  ocean in about 4:50 / 9:10 / 18:45 (about 33 min). The tables below still show the original 45 min
  targets the prices were built from.
- Upgrade types, each felt differently:
  1. **Tool size** (the joke ladder): visible tool, more litres per trip.
  2. **Move speed**: felt most in the hands.
  3. **Scoop and pour hold time**: big tools must not take forever; pour should look bigger with
     bigger tools (polish phase).
- Later (not prototype): closer or better sources unlocking mid-stage; late tools that change *how*
  you collect (drive the fire truck, a rain cloud follows you), still hold-to-act.

## Draft numbers (placeholders, tune in the prototype)

Built backwards: each upgrade gets a target time for a single player, price = income earned since
the previous purchase, X = litres one player pours in the stage. Model:
`C:\Users\lexru\AppData\Local\Temp\claude\2a7cc7c6701c7ee1\430103f8-e6c9-49b7-b847-54bb9ae8f024\scratchpad\model.py`
(scratch, not in the repo; the builder should move it into the repo if kept).

"Trip" is the full cycle time (walk there, scoop, walk back, pour). Speed upgrades are listed as
the trip time they bring; the builder splits them into move-speed and scoop/pour-speed upgrades
and picks distances so the trip times match.

**Pool**: 7 min, 10 coins per litre, X about 970 L per player. Starts: Spoon (1 L), trip 16 s.

| Time | Upgrade | Cost (coins) |
|---|---|---|
| 0:35 | Cup (4 L) | 20 (two whole spoon trips) |
| 1:30 | Trip 13 s | 138 |
| 2:00 | Jug (10 L) | 92 |
| 3:30 | Watering Can (25 L) | 692 |
| 4:10 | Trip 11 s | 769 |
| 5:00 | Bucket (60 L) | 1,136 |
| 6:00 | Trip 10 s | 3,273 |

**Lake**: 13 min, 50 coins per litre, X about 131,000 L per player.

| Time | Upgrade | Cost |
|---|---|---|
| 0:30 | Barrel (150 L) | 9,000 |
| 1:45 | Trip 9 s | 56,250 |
| 3:00 | Bathtub (350 L) | 62,500 |
| 5:30 | Hot Tub (800 L) | 291,667 |
| 6:45 | Trip 8 s | 333,333 |
| 8:00 | Kiddie Pool (1,800 L) | 375,000 |
| 10:30 | Fire Truck (4,000 L) | 1,687,500 |

**Ocean**: 25 min, 250 coins per litre, X about 361,000,000 L per player.

| Time | Upgrade | Cost |
|---|---|---|
| 0:40 | Swimming Pool (9,000 L) | 5.0M |
| 1:45 | Trip 7.5 s | 18.3M |
| 3:00 | Water Tower (20,000 L) | 22.5M |
| 5:30 | Tanker Truck (45,000 L) | 100M |
| 8:00 | Cargo Ship (100,000 L) | 225M |
| 10:30 | Rain Cloud (220,000 L) | 500M |
| 11:45 | Trip 7 s | 550M |
| 13:00 | Iceberg (480,000 L) | 589M |
| 15:30 | Waterfall (1,000,000 L) | 2.57B |
| 18:00 | Hurricane (2,200,000 L) | 5.36B |
| 20:30 | Glacier (4,800,000 L) | 11.8B |
| 23:00 | The Moon (10,000,000 L) | 25.7B |

Tool names are placeholders; spoon -> cup -> bucket -> ... -> absurd is the owner's.

## Contribution and rewards (settled; rewards not saved in the prototype)

- Pot = 100 per player in the group. Half split evenly (50 each), half split by share of water
  poured.
- To get the guaranteed 50, a player must pour at least once per stage (Claude's default; owner
  did not object).
- Shown live: each player's share as a percentage on a small side board. At the end: a ranked
  results screen with each player's share and reward.
- **Claude's call: how "share" is measured.** Litres grow about 1000x per stage, so raw litres would
  make the ocean count for everything. Share = each player's percentage of each stage's water,
  averaged over the three stages weighted by stage length (7 / 13 / 25).

## End of run (settled; prototype gets a text version)

1. Final push: last 5% of the ocean, faster music, glowing meter, the sun gets desperate.
2. "FINAL DROP!" callout naming whoever pours the last drop.
3. About 3 s of pure win: "FULL!", splash.
4. Comedy cutscene: the sun turns, makes the ugliest face, a POV from space shows the blue Earth,
   the sun fires and Earth explodes like a cartoon, a tiny spoon flies past the camera.
5. Reward screen over the debris (podium by share, reward split).
6. Back to lobby: "Difficulty 2 unlocked: the sun is angrier."

Pool and lake end with a short splash plus "FULL!" and then the sun's cutscene to the next stage.

## Prototype scope (what to build now)

Phase order (owner's): design -> plain prototype -> look and feel. This is the prototype.

- **Gameplay place only** (`gameplay/`, place 96136704873524). Press Play and the run starts in
  the pool. No lobby, no teleport, no saving.
- Plain parts. Three basins (pool, lake, ocean), each with a water source. The water surface rises
  with the fill percentage.
- Full tool ladder and speed upgrades from the tables above, bought in order through a plain buy UI.
- Hold-to-scoop and hold-to-pour. Money is paid per litre actually added (overfill past the target
  pays nothing; Claude's call).
- Water target scales with player count; a leaving player rescales it and keeps the percentage.
- Stage transitions: text card ("The sun drains the lake!"), move players to the next basin.
- Live share board, ranked results text screen at the end with the computed rewards (not saved).
- Server-authoritative: the server owns money, water and purchases, and checks that a scoop or
  pour happens at the right spot, with the player's real capacity and timing.

Out of the prototype: cutscenes, final-push effects, "FINAL DROP!" callout, the Earth explosion,
art, sound, VFX, closer sources, Robux, saving, lobby, difficulties, reward spending.

## Constraints

- Follow `CLAUDE.md` at the game root (two Rojo projects, checks per folder). Rojo owns code only.
  The map lives only in the Studio place and must be saved and published there.
- `CLAUDE.md` says formulas come from `C:\RobloxDev\shared\Lib`, but Lib is empty and these numbers
  are a hand-tuned table, not a formula. For the prototype the table lives in
  `gameplay/src/shared` as data. Moving any formula into Lib is a later library step.
- Roblox facts come from LihFolk.

## Claude's calls (owner to check)

- Money, tools and upgrades are per player, not shared by the team.
- One ordered buy list per stage in table order, unlocked when the stage starts. Each "trip" row
  becomes move-speed and scoop/pour-speed items in that slot.
- A stage ends only when the basin is full: no timer and no way to lose.
- Rewards use the players still there at the end (leavers forfeit). A stage share is a player's
  litres divided by all litres poured in that stage, leavers' litres included.
- Cup costs 20 so the first buy lands after two whole spoon trips (about 0:32). The model counts
  part-trips, so other buys will drift a little too; that is prototype tuning.

## Left to the builder

- Map layout, basin sizes and distances (to hit the trip times), how the water rises visually.
- Splitting "trip" upgrades into move speed vs scoop/pour speed.
- How the run starts in Studio play tests (for example, a short countdown after the first player
  spawns), and module and remote structure.
- Buy UI layout (plain; no UI style is set yet).
