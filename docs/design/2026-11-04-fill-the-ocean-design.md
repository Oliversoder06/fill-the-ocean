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

- Trip: scoop at a water source -> carry -> pour into the basin. **Changed by the owner on
  2026-11-05:** no prompts. Aim at the well and hold E / left mouse / RT / the touch button: each
  scoop is one full sweep (ActSeconds) and adds capacity / sweeps; each new tool adds one sweep to
  fill it, and each Quick Hands upgrade brings it back to one sweep and makes sweeps faster. Pour is
  one full tip that empties the tool. An action that starts always plays to the end; letting go
  only stops the next one. (Before: one hold prompt filled or emptied the whole tool, owner
  2026-11-04.) The hold starts at 0.5 s; Quick Hands upgrades shorten it to 0.2 s. The path is 80
  studs. A perfect solo player now fills pool / lake / ocean in about 5:01 / 9:39 / 20:31 (about
  35 min; it was 33 min before sweeps). The tables below still show the original 45 min targets
  the prices were built from.
- **Changed by the owner on 2026-11-05: free-choice upgrades.** Players pick what to buy instead
  of one forced list. Each scoop sweep is one press; holding only repeats sweeps once the player
  owns Hold. Pouring is always instant (a 0.25 s tip that empties the tool). Six tracks, each
  bought level by level (Config.tracks); a level can be bought once its stage has started, so each
  stage opens a few more levels of every track (Claude's call, keeps the pacing):
  1. **Tool** (the joke ladder, in order): more litres per trip. A tool needs 1 sweep for the Spoon,
     then one more every 2 tool levels, at most 8. **Changed on 2026-11-05** (was every 4, at most
     5): with 4 Pickup levels a maxed Pickup filled every tool in one sweep and made Quick Scoop
     useless. Now tools add sweeps faster than Pickup takes them off; stage-end gear takes 2 / 3 / 4
     sweeps (pool / lake / ocean).
  2. **Pickup**: each level takes one sweep off (never below 1); 4 levels.
  3. **Hold**: one-time buy (40); hold the button to keep sweeping until full.
  4. **Quick Scoop**: faster sweeps, 0.5 s down to 0.2 s; 7 levels.
  5. **Sneakers**: walk speed; 7 levels.
  6. **Tip Jar**: +5 / 10 / 15 / 20 % coins per litre; 4 levels.
  Prices: tools and Sneakers keep the ordered list's prices; each old Quick Hands price is split
  between Quick Scoop and Pickup. A perfect solo player who buys the cheapest affordable upgrade
  fills pool / lake / ocean in about 6:07 / 11:11 / 20:15 (37:35, `lune run tools/simulate`;
  boosts not counted).
- **Fill-milestone boosts (2026-11-05)**, against the trips feeling the same: at 25 / 50 / 75 %
  fill everyone gets a 30 s bonus, each kind once per stage in a shuffled order: double coins,
  a gushing well (fill in one sweep) or a tailwind (x1.5 walk speed). Bonuses only, never penalties.
  Announced with the stage card text; the run panel's stage tag counts it down (Config.boosts,
  shared/Boosts).
- Before 2026-11-05 the upgrade types were Tool size, Move speed and Quick Hands (back to one sweep
  and faster), bought in one fixed order.
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
- (Replaced 2026-11-05 by free-choice tracks, see Core action.) One ordered buy list per stage in
  table order, unlocked when the stage starts.
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

## Full game build (2026-11-04, owner decisions)

- **Ladder:** 8 hero tools with levels between them: Spoon, Cup, Cup Lv2, Bucket, Bucket Lv2,
  Bucket Lv3, Bathtub, Bathtub Lv2, Kiddie Pool, Kiddie Pool Lv2, Swimming Pool Lv1-3,
  Cargo Ship Lv1-3, The Moon Lv1-4. Capacities, prices and pacing are unchanged from the tables
  above; only names and models changed. Levels reuse their hero model, a little bigger on screen.
- **Rewards:** Raindrops are saved (DataStore) and shown in the lobby; nothing to spend them on yet.
- **Difficulty:** 5 levels. Each needs +40% water and pays +50% Raindrops. Beating your highest
  unlocks the next.
- **Lobby:** a plaza with 5 queue pads. Standing on an unlocked pad starts a 15 s countdown; up to
  10 players teleport together into a fresh reserved gameplay server. The lobby writes a run
  ticket (difficulty + members) to MemoryStore under the reserved server id; the gameplay server
  reads it, lets only those members in, and waits up to 20 s for the party.
- **End of run:** rewards saved, results shown for 15 s, then everyone returns to the lobby.
- **Maps:** Pool = a walled backyard with a sunken tiled pool. Lake = a natural terrain lake with a
  sandy shore in a pine valley (camp, pump, dock, cabin, tents). Ocean = a natural bay in a palm
  beach cove (boardwalk, pier, huts, lifeguard tower). Water is a flat surface rising inside each
  basin. All maps are enclosed (cliffs/walls plus invisible walls).
- **No runtime generation:** stages, tool templates, sounds, effects, HUDs and lighting are baked
  into the places; code only checks they exist and fails with a clear message if not.

## Lobby sessions (2026-11-05, owner decisions)
Replaces "one pad per difficulty". Any pad hosts a session: the first player to step on gets the
setup window (sunbaked-sea style, one column) and picks max players (1-10), a difficulty they have
unlocked, and friends-only (friends of the host). Others join by stepping on; anyone may join a
difficulty the host unlocked. The run starts when the session is full or the host presses Start.
If the host steps off or leaves, the earliest remaining member hosts. Rules: `common/SessionRules`.

## Progression: account level and season pass (2026-11-05, owner decisions)
**Why.** Owner's first full playtest (2 players, about 40 min): "time flew by, but I would never come
back… nothing special." Players "like to grind for something". The run itself stays chill and
satisfying (the owner rejected "the sun fights back"). What was missing is a reason to play beyond
one run: nothing earned in a run mattered afterwards.

**One XP, two tracks.** Every run earns XP. The same XP fills both tracks.

| | Account level (permanent) | Season pass (seasonal) |
|---|---|---|
| Resets | Never. Shown above your head and in the lobby. | Pass tiers reset each season; claimed rewards are kept forever. |
| Gives | **Power, capped and spaced out:** small permanent perks (for example +1% coins, +1% walk, each with a cap) and starting gear (begin runs with a better tool at milestone levels). | **Fresh stuff:** cosmetics (tool skins, splash colours, trails, titles) and Raindrops. |
| Curve | Each level needs more XP than the last (owner). Draft: XP to the next level = 100 × level^1.5. | Flat XP per tier. Draft: 50 tiers × 750 XP. |
| Premium | n/a | Free track now; a premium (Robux) track later on the same tiers. |

- **Why split.** Claimed rewards are kept, so power on a seasonal pass would stack every season
  and the runs would get trivially short, killing the slow-to-fast climb. Power stays on the
  permanent level (capped); seasons only add cosmetics and Raindrops.
- **Seasons:** 3 months, aligned to the calendar: Jan 1, Apr 1, Jul 1, Oct 1.
- **Draft pace (tune after testing):** a run at Difficulty 1 gives about 1,500 XP. A new player
  gains about 4 levels in their first run, about 1 level per 2 runs around level 10, and slower
  after that. Level table: 1→2 needs 100, 5→6 needs 1,118, 10→11 needs 3,162, 20→21 needs 8,944.
  Season: about 2 tiers per run, so about 25 runs to finish (2 runs a week over a season).
- **XP sources (draft):** XP for your share of each stage's water (by share, like rewards, so the
  ocean doesn't dwarf the pool), a bonus for each stage completed and for finishing the run, ×
  the difficulty multiplier.
- **In run:** a small level bar near the wallet fills as you pour. Level up: a sting, sparkles and
  a "LEVEL 12!" stamp, plus "next unlock" text. Pass tiers tick up the same way.
- **Open:** the exact perk list, caps and starting-gear levels; the season-1 reward list; where
  the pass window lives (lobby, gameplay or both); XP per run after a real playtest. The XP curve
  goes to `C:\RobloxDev\library\balance` once the owner approves the numbers.
