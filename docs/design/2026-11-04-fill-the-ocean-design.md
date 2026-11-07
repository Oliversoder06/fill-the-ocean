# Save the Ocean: game design

Working title (owner, 2026-11-05: "can be called like Save the Ocean or something"). Settled on
2026-11-05 after the owner's first full playtest; it replaces the earlier 35-minute run design
completely. The build plan is `docs/plans/2026-11-05-save-the-ocean.md`.

## Why this design
The first playtest (owner and a friend): "time flew by, but I would never come back… nothing
special." A short run that throws everything away at the end gives no reason to return. Players "like
to grind for something". The proven model is Chop a Forest (about 40k CCU): a lobby, a party, and a
saved run you jump back into. Owner's target: 200-500 CCU.

## The pitch
You own the ocean. A bacon-hair drinks all of it while you nap. You get it back: starting with a
spoon, you scoop and pour, earn money, and grow a whole operation (bigger tools, gadgets, buildings,
fire trucks, hired staff) until the ocean is full again. One ocean, one mission. It takes a long
time (target about 20 hours for a solo player on the first map), and your progress is saved, so you
play it in many sessions. You claim your world, like Chop a Forest.

## Story (owner, 2026-11-05)
- **Intro cutscene (the first time a save starts):** you sleep in a beach chair by your ocean. You
  wake and spot a bacon-hair, who starts drinking the water. You don't mind and fall back asleep.
  A loud burp wakes you: the ocean is gone and the bacon-hair rolls away, huge. You go "GRRRRR",
  and play starts.
- **Ending cutscene (at 100%):** you look satisfied: the ocean is back. You spot the same
  bacon-hair approaching. Right before he drinks, you smack him out of frame. End.
- There is no evil sun any more. The heat and drought look of an empty ocean stays (it was drunk
  dry, and the world looks parched until you fill it).

## Core loop
- Scoop at a water source, carry, and pour into the ocean (aim at the water and hold E / click /
  RT / the touch button; each sweep or pour plays out in full). Every litre poured earns money.
- Money buys upgrades that make each trip bigger and faster, then things that **fill the ocean for
  you**. **Filling may be automatic** (owner, 2026-11-05): the old rule "filling is never
  automatic" is dropped. Automation (staff, vehicles, machines) is the late-game payoff.
- Upgrade layers, from first to last:
  1. **Tools:** the joke ladder, spoon to cup to bucket to bathtub and onwards (giant tools later).
  2. **Personal boosts:** Pickup (fewer sweeps), Hold (keep scooping), Quick Scoop, Sneakers, Tip Jar.
  3. **Gadgets:** things you use yourself that change how you collect (for example a hose, a
     water gun, a jetpack tank).
  4. **Buildings:** placed structures that make water or shorten the trip (for example a pump, a
     pipeline, a water tower near the shore).
  5. **Vehicles:** fire truck and bigger, carrying huge loads.
  6. **Staff:** hired helpers who scoop and pour on their own.
- Fill milestones (every few percent) open new things, so there is always a next goal in sight.
  The exact milestone list is open (see Open).

## Purchases and where they are on the map (2026-11-06)
Claude drafted this list; the owner approved it as a first pass ("finish the game and then get a
feel of it"), so every item and number here is expected to change after playtests. Aim: something new
to buy roughly every 5 to 10 minutes. The arc runs hands, then gadgets, then a truck, then
buildings, then staff running it all: by hour 10 the player runs a waterworks instead of walking.

**Buying rule (owner, 2026-11-06):** each thing is bought once at its place on the map, then
levelled up in the TAB menu, which lists everything (a honeycomb upgrade board was considered and
dropped).

**Since 2026-11-07 this table covers the cove (Area 1) only:** items of areas 2 to 5 sell at their
area's stand (see Areas and the build plan's Phase 3 for the full item list).

**Layout (owner, 2026-11-06): a cove valley.** Planned on the map planner artifact
(https://claude.ai/artifact/3AsYZMQuYYVmJR6w1xpY2K, which holds every piece's purpose, needs and
position) and built in Studio from it. Rock cliffs on both sides (inner face about 150 studs from the
centre) end in headlands in the sea, so the map is narrow and full; hills close the back. Main
Street runs up the middle from a hard-sand truck beach to the Fire Station at the back. The shop
side (+X) holds the well plaza, Tool Shack, spawn and Backpack stand; the staff side (-X) holds the
Lifeguard Tower and a staff well. The plots line Main Street, with a raised aqueduct between the
street and each row of plots, down to the sea.

Key fact: the seabed is flat at y -28 and under water at every fill; the waterline only moves about
55 studs up the beach slope. So the truck's trip is on land: refill at the back, drive down, spray.

| Place (gameplay `workspace.Map`) | Where (X, Z) | Sells / does | Items (draft) |
|---|---|---|---|
| `Town.Source_Well` (+ `Ocean.Source`) | (60, 30), in a cobble plaza | Hand-scoop water; 83 studs to the water | |
| `Town.GardenTap` (placeholder) | (44, 20) | Where the Garden Hose hooks on | |
| `Town.ToolShack` | (108, 50), faces the sea | Tools, boosts and gadgets | The tool ladder (Spoon to The Moon); Pickup, Hold, Quick Scoop, Sneakers, Tip Jar; **Water Gun**, **Garden Hose**, **Jetpack Tank** |
| `Beach.BackpackStand` (placeholder) | (84, -42), at the water | Backpack Tank | **Backpack Tank** |
| Spawn (`Ocean.Spawn`, chair and umbrella) | (112, -26), faces the sea | Intro and ending cutscenes; open sand in front | |
| `Town.FireStation` + `Roads.TruckRefillBay1/2` | (0, 228); bays at (±26, 197) | Vehicles. Refill at the bays, drive Main Street (about 260 studs), spray from the truck beach | **Fire Truck** (full WASD; the hose comes off its side and works like a tethered tool), **Tanker**, **Water Bomber** |
| `Beach.Stage_Ocean_LifeguardTower` + `Beach.StaffSign` | (-85, -42) | Staff | **Helper**, **Lifeguard**, **Firefighter**, **Plumber** |
| `Town.StaffWell` | (-60, 30) | Where staff scoop (Claude's idea, not decided) | |
| `Map.Plots.Plot1..6` | x ±62, z 92 / 136 / 180 | Buildings that fill for you | **Pump**, **Water Tower**, **Pipeline**, **Rain Machine** |
| `Town.Aqueduct_ShopSide` / `_StaffSide` (placeholder) | x ±36, z 190 to -58, raised 10 studs | Carries the plots' water to the sea | |

- The truck should pass through players (no collision) so it never shoves anyone; truck speed of
  40 studs/s is an assumption.
- Removed from the map: the Gadget Store (merged into the Tool Shack), the reservoir, river and Dam,
  the cross fences, the old hydrants and the boardwalk outside the shop side. They are kept in
  `ServerStorage.RemovedFromMap_2026_11_06`; backups: `Map_Backup_BeforeCompact_2026_11_06`,
  `Map_Backup_BeforeCove_2026_11_06` (with `Ocean`) and the `Terrain_Backup_*` regions.
- Automated water (buildings, staff) pays **half** the hand rate per litre (Claude's suggestion,
  owner asked for "earns money but doesn't break the game"); tuned in `tools/simulate`.
- The snack hut, boardwalk, palms, loungers, and the old mountains, road and tunnels (now behind
  the cliffs) stay as decoration.
- Costs, rates, capacities and the order of unlocks are left to Phase 3 tuning (`tools/simulate`
  toward about 20 hours solo).

## Areas (2026-11-07, draft)
The owner asked for areas like Chop a Forest's: finish one, open the next, where things are tougher
and worth more, with upgrades at every price range. Drafted on the Cove Areas Plan artifact
(https://claude.ai/artifact/VaM2mqL6gYWKwHrpAEpWXs); open choices are D1 to D9 in the build plan.
- **The ocean stays the one place you fill; areas are where the water comes from.** Five on map 1:
  Cove Well (the cove), Mountain Spring, Hot Springs, Glacier and Cloud Catcher, behind the cove's
  cliffs. A harder area's water takes longer to collect (shallow pools, steam, ice blocks,
  drifting clouds) and pays more per litre. The pay never rises on its own (owner, 2026-11-06).
- **Every area has its own pour spot** (a channel that runs down to the ocean) next to its source,
  so the hand loop stays short everywhere. Vehicles carry too much for a channel: they fill at a
  hydrant and drive the long way to the beach. Staff work an area while you are elsewhere.
- **Gates:** a gate shows its fill point from the start, goes on sale when the ocean reaches it,
  and opens when bought (about what a player holds by then).
- **Each area adds the next price range** of tools, backpacks, boosts, gadgets, vehicles, buildings
  and staff, bought once at the area's stand and levelled in TAB.
- **Pace (from the hour-6 walkthrough, 2026-11-07):** each percent of the ocean needs more litres
  than the last so the fill rises steadily (about 1% per 12 minutes); a small milestone every 5%;
  a "Next" goal on the HUD; 2 to 3 sources and a golden spring per area; active play pays about
  twice idle; you spawn at your furthest area.

## Saved runs, parties and the lobby (owner, 2026-11-05)
- Players load into the **lobby**. On a pad they **Create Party** (pick the map and the party
  size) or **load a saved run**.
- **A save belongs to its exact team.** A saved run can only be loaded when exactly the players
  who made it are on the pad together: no one missing, no one extra. A solo run belongs to that one
  player.
- Runs save automatically while playing (on a timer, when someone leaves, and when the server
  closes). Nothing is lost by leaving.
- Each player has their own money and upgrades inside the team's run; the ocean's water is shared.
  How team purchases (buildings, staff) work is open.
- The water needed scales with team size, so a run takes about as long at any party size.
- Reference: the owner's screenshot of Chop a Forest's lobby (Create Party with a map carousel,
  difficulty and party size; Saved Runs with a Load button).

## Maps and difficulty (owner, 2026-11-05)
- Each map has its own fixed difficulty. **Map 1** is the first ocean. Finishing map 1 (the ending
  cutscene) unlocks **map 2**: a new map, harder (more water, higher prices, better rewards). More
  maps can follow.
- This replaces the old "Difficulty 1-5 on the same map" selector.

## Progression outside a run: account level and season pass
**One XP, two tracks.** Playing earns XP (for water poured and for milestones reached). The same XP
fills both tracks.

| | Account level (permanent) | Season pass (seasonal) |
|---|---|---|
| Resets | Never. Shown above your head and in the lobby. | Pass tiers reset each season; claimed rewards are kept forever. |
| Gives | **Power, capped and spaced out:** small permanent perks (for example +1% coins, +1% walk, each capped) and starting gear (a better first tool in new runs at milestone levels). | **Fresh stuff:** cosmetics (tool skins, splash colours, trails, titles) and Raindrops. |
| Curve | Each level needs more XP than the last (owner). Draft: XP to the next level = 100 × level^1.5. | Flat XP per tier. Draft: 50 tiers × 750 XP. |
| Premium | n/a | Free track now; a premium (Robux) track later on the same tiers. |

- **Why split:** claimed rewards are kept, so power on a seasonal pass would stack every season.
  Power stays on the permanent level (capped); seasons only add cosmetics and Raindrops.
- **Seasons:** 3 months, aligned to the calendar: Jan 1, Apr 1, Jul 1, Oct 1.
- **Raindrops:** the soft currency for cosmetics. Earned from the pass and from finishing a map.
- **Open:** the perk list, caps and starting-gear levels; the season-1 rewards; the XP amounts
  (tune by playtest). The XP curve goes to `C:\RobloxDev\library\balance` once approved.

## What carries over from the current build
The scoop and pour feel (sweeps, splashes, viewmodel, bodies), coins and payout, the shop and the
purchase moment, the HUD (wallet, hotbar, fill bar, progress panel, Upgrades button, cursor),
footsteps, ambience and music, the dry-to-alive world (scorched light and dead grass that turn lush
as you fill), the ocean map and its props, the lobby pads and party flow, and saving player data.

## Removed (owner, 2026-11-05)
The pool and lake, multiple stages per run, stage cards, the 35-minute run timer target, the
end-of-run reward pot split by share, the difficulty 1-5 selector, the angry sun (the sky
billboard and the shop decoration), and the "filling is never automatic" rule.

## Constraints
- Server-authoritative: the server owns money, water, purchases and saves. Clients only send
  requests and show state.
- Nothing is generated at runtime: maps, UI and models are built in Studio and checked by code.
- One save is only ever loaded into one server at a time.

## Open (owner to decide later)
1. Goals along the way: the milestone list across the 20 hours (owner: "figure that out later").
2. Team purchases: does a building or a hired staff member belong to the team or to one player?
3. Does automation keep filling while nobody is online (offline progress)?
4. Do saved runs expire if nobody plays them (Chop a Forest deletes after 7 days)?
5. How many saved runs a player may have, and how a team member can leave a save for good.
6. Loot ("get loot in places"), events and enemies: skipped for now (owner).
