--!strict
-- All run numbers (draft, from docs/design/2026-11-04-fill-the-ocean-design.md). Data only:
-- no requires, so Lune tests and Roblox load it the same way.
-- Upgrades are free choice: six tracks, each bought level by level. A level can be bought once its
-- `area` is open, so each area opens a few more levels of every track.
-- Trip time = 2 * tripDistance / walkSpeed + sweeps * actSeconds + pourSeconds (walk there and back,
-- scoop sweeps, one quick pour). Each tool needs more sweeps (see Ladder.baseSweeps); each Pickup
-- level takes one off, but tools add sweeps faster than Pickup removes them.

export type Level = {
	cost: number,
	area: number, -- the area that opens it
	name: string?, -- tools only; other tracks show "<track name> <n>"
	model: string?, -- tools: the hero model shown in hand ("Cup" for Cup and Cup Lv2)
	capacity: number?, -- tool
	walkSpeed: number?, -- walk
	actSeconds: number?, -- quick: seconds per scoop sweep
	coinBonus: number?, -- tip: coins per litre multiplier
}

export type Area = {
	id: number,
	name: string,
	payMultiplier: number, -- a litre scooped here pays coinsPerLitre * this
	scoopFactor: number, -- scoop sweeps here take actSeconds * this
	gate: { fill: number, price: number }?, -- on sale once the ocean is `fill` full; nil = open from the start
	model: string?, -- its model in workspace.Areas (server/Map); nil = the cove, whose parts are the ocean's
	needs: string?, -- an item id: only players who own it reach this area (spawn, scoop, pour)
	-- its area mechanic (shared/AreaRules, server/Mechanics): "steam" vents knock you back and Heat
	-- Gloves speed up its pools; "ice": its Source gives ice blocks you chip; "cloud": its Source drifts
	mechanic: ("steam" | "ice" | "cloud")?,
	rockTool: string, -- the tool model whose first level breaks the rock in front of its deeper pool
}

export type Track = {
	id: string,
	name: string,
	panel: "tool" | "boosts", -- which shop panel shows it
	about: string, -- one line for the shop
	levels: { Level },
}

-- One upgrade of a bought item (TAB): its cost and the stats it gives from then on. An item's
-- first-buy stats sit on the item itself under the same names (common/Items.stat).
export type ItemLevel = {
	cost: number,
	capacity: number?, -- backpack, Jetpack Tank: litres it holds
	range: number?, -- Water Gun: studs it pours from; Cloud Net: studs it scoops the drifting cloud from
	rate: number?, -- Garden Hose: litres a second it pours; building: litres a second it makes
	reach: number?, -- Garden Hose: studs you may walk from its tap
	flightSeconds: number?, -- Jetpack Tank: seconds of thrust on a full tank
	hotFill: number?, -- Heat Gloves: sweeps in hot pools take 1 / this of the time
	hits: number?, -- Ice Pick: hits to chip one ice block loose
	tank: number?, -- vehicle: litres it holds
	speed: number?, -- vehicle: top speed, studs a second
	fillRate: number?, -- vehicle: litres a second at a hydrant (the bomber: skimming a pool)
	sprayRate: number?, -- truck: litres a second its hose sprays (the bomber drops its load at once)
	hires: number?, -- staff: how many work (D3: up to 3)
	carry: number?, -- Helper, Lifeguard: litres each brings a trip
	tripSeconds: number?, -- staff: seconds one loop takes (scoop, walk, pour, back; a Firefighter's truck loop)
	boost: number?, -- Plumber: the team's buildings' output scale (1.1 = +10 %)
}

-- A thing bought once at its area's stand (common/Items), then levelled in TAB.
export type Item = {
	id: string,
	name: string,
	kind: "backpack" | "gadget" | "vehicle" | "building" | "staff",
	area: number, -- sold at this area's stand once it is open
	stand: string?, -- sold at this cove shop instead (a key of Config.stands)
	price: number, -- the first buy, at the stand
	about: string, -- one line for the shop
	-- backpack: its Accessory in ReplicatedStorage.ToolModels.Backpacks; gadget: its Model in
	-- ReplicatedStorage.ToolModels.Gadgets (held in the hand while it is out); vehicle: its Model in
	-- ReplicatedStorage.Vehicles (server/Vehicles); building: its Model in ReplicatedStorage.Buildings
	-- (placed on a plot); staff: its rig in ReplicatedStorage.Staff (client/Staff walks a copy)
	model: string?,
	-- gadget: how it is used from its hotbar slot; nil = it works on its own once owned (no slot)
	use: ("pour" | "hose" | "fly")?,
	capacity: number?, -- the ItemLevel stats when bought (see ItemLevel)
	range: number?,
	rate: number?,
	reach: number?,
	flightSeconds: number?,
	hotFill: number?,
	hits: number?,
	riseSpeed: number?, -- Jetpack Tank: studs a second it climbs (every level)
	rechargeSeconds: number?, -- Jetpack Tank: seconds on the ground from empty to full (every level)
	tank: number?,
	speed: number?,
	fillRate: number?,
	sprayRate: number?,
	flies: boolean?, -- vehicle: the Water Bomber flies, skims pools and drops its load on the ocean
	-- staff: where it works (shared/StaffRules.targets): "area" an open area's loop, "truck" an owned
	-- vehicle's loop at that vehicle's area, "plots" the team's buildings
	job: ("area" | "truck" | "plots")?,
	hires: number?,
	carry: number?,
	tripSeconds: number?,
	boost: number?,
	levels: { ItemLevel }, -- upgrades in order, after the first buy
}

local function tool(name: string, model: string, cost: number, capacity: number, area: number): Level
	return { name = name, model = model, cost = cost, capacity = capacity, area = area }
end

local Config = {}

Config.tripDistance = 80 -- studs, source centre to basin pour edge
Config.pourSeconds = 0.25 -- a pour is instant; this is only how long the tip plays
-- Everything bought is the team's, from one wallet; every price is x (1 + priceStep x (players - 1))
-- for the save's team (common/Items.price): a duo pays 1.25x, a quad 1.75x. Teams also get a bigger
-- ocean (Config.ocean.teamStep). Hands scale with the team but staff and buildings don't, so both
-- steps sit well under 1; tools/simulate picked the pair that lands 2 and 4 players within a few
-- percent of solo (0.3 / 0.25: x1.00 and x1.03).
Config.team = { priceStep = 0.25 }
Config.start = { capacity = 1, walkSpeed = 16, actSeconds = 0.5, toolName = "Spoon", toolModel = "Spoon" }
-- Sweeps to fill a tool: 1 for the Spoon, then one more every `toolsPerSweep` tool levels, at most `maxSweeps`.
-- Tools add sweeps faster than Pickup takes them off, so big tools never fill in one sweep and
-- Quick Scoop keeps mattering. Every 3 levels (24 tool levels) so the big tools still feel big.
Config.sweeps = { toolsPerSweep = 3, maxSweeps = 8 }

-- Boosts: each fill milestone (Config.milestones below) starts one for everyone for `seconds`. All
-- are bonuses, never penalties.
Config.boosts = {
	seconds = 30,
	kinds = {
		{ id = "coins", tag = "2X COINS", coins = 2 },
		{ id = "gusher", tag = "GUSHER", oneSweep = true },
		{ id = "tailwind", tag = "TAILWIND", walk = 1.5 },
	},
}

-- A milestone (shared/Milestones). Each but the ending starts a `boost` (a Config.boosts kind, for
-- everyone) and gives one extra: `revive` (the cove decoration workspace.Map.Revive.M<n> comes back
-- to life), `sighting` (the bacon-hair shows on the horizon), `raindrops` (onto every member's
-- profile) or `cosmetic` (an id kept for the season pass; nothing uses it yet). `text`: the toast.
export type Milestone = {
	fill: number,
	boost: string?,
	text: string?,
	revive: number?,
	sighting: boolean?,
	raindrops: number?,
	cosmetic: string?,
	ending: boolean?,
}

-- Milestones every 5% (D9): server/Run grants each once per run (save.milestones). The plan: the
-- boosts cycle 2X COINS, GUSHER, TAILWIND so neighbours never repeat; every 25% band runs revive,
-- Raindrops, revive, cosmetic, sighting, so the cove comes back to life about every 10%, a small
-- Raindrops payday sits between (5 rising to 25 by the final push, 75 a run), and every quarter ends
-- on the bacon-hair out on the horizon. 100% is the ending (its cutscene and the map's Raindrops).
Config.milestones = {
	{ fill = 0.05, boost = "coins", revive = 1, text = "The old rowboat floats again!" },
	{ fill = 0.1, boost = "gusher", raindrops = 5, text = "The first rain clouds roll in!" },
	{ fill = 0.15, boost = "tailwind", revive = 2, text = "The beach flags flutter again!" },
	{ fill = 0.2, boost = "coins", cosmetic = "seafoamSplash", text = "Seafoam splashes unlocked (coming soon)!" },
	{ fill = 0.25, boost = "gusher", sighting = true, text = "Is that... the bacon-hair? He's watching!" },
	{ fill = 0.3, boost = "tailwind", revive = 3, text = "The palm trees perk up!" },
	{ fill = 0.35, boost = "coins", raindrops = 10, text = "A warm summer shower!" },
	{ fill = 0.4, boost = "gusher", revive = 4, text = "The crabs are back on the rocks!" },
	{ fill = 0.45, boost = "tailwind", cosmetic = "pearlTrail", text = "Pearl trail unlocked (coming soon)!" },
	{ fill = 0.5, boost = "coins", sighting = true, text = "Halfway! The bacon-hair burps on the horizon..." },
	{ fill = 0.55, boost = "gusher", revive = 5, text = "The gulls are back on the pier!" },
	{ fill = 0.6, boost = "tailwind", raindrops = 15, text = "Rain on the horizon!" },
	{ fill = 0.65, boost = "coins", revive = 6, text = "The lighthouse shines again!" },
	{ fill = 0.7, boost = "gusher", cosmetic = "captainTitle", text = "Captain title unlocked (coming soon)!" },
	{ fill = 0.75, boost = "tailwind", sighting = true, text = "The bacon-hair is back... and he looks thirsty." },
	{ fill = 0.8, boost = "coins", revive = 7, text = "The pier lanterns glow again!" },
	{ fill = 0.85, boost = "gusher", raindrops = 20, text = "A downpour of Raindrops!" },
	{ fill = 0.9, boost = "tailwind", revive = 8, text = "The dolphins are jumping again!" },
	{ fill = 0.95, boost = "coins", raindrops = 25, text = "The final push! It's pouring!" },
	{ fill = 1, ending = true },
} :: { Milestone }

-- The one ocean. Pay is flat (it never rises on its own; harder areas pay more).
-- Fill curve (shared/Water): percent 1 needs firstPercent litres and each next percent `growth`
-- times the last, inside a stretch its own growth (C:\RobloxDev\library\balance\README.md, Economy).
-- Tuned with tools/simulate so every percent takes about 12 minutes (20 hours solo): the litres
-- grow as fast as the team's income does in that stretch. The stretches end at the gates because
-- each area's tools, staff and buildings grow income at their own pace: the cove fast from a spoon,
-- Mountain Spring fastest (its staff and pumps take over from the hands), Hot Springs and the
-- Glacier slower, Cloud Catcher's huge tools the slowest. teamStep: a team of n fills an ocean
-- 1 + 0.3 (n - 1) times as big (see Config.team).
Config.ocean = {
	name = "The Ocean",
	coinsPerLitre = 10,
	firstPercent = 4000,
	growth = 1.118, -- Cloud Catcher (percents 77-100)
	stretches = {
		{ to = 14, growth = 1.168 }, -- Cove Well
		{ to = 32, growth = 1.259 }, -- Mountain Spring
		{ to = 55, growth = 1.188 }, -- Hot Springs
		{ to = 76, growth = 1.107 }, -- Glacier
	},
	teamStep = 0.3,
}

-- The areas, in the order their gates open (common/Areas). Each pays 5x the last. Gate fills split
-- the 20 hours into areas of 3.3 to 4.9 hours; a gate costs about half of what one percent pays
-- just before it, so it opens soon after its fill (you wait for the water, not the coins).
Config.areas = {
	{ id = 1, name = "Cove Well", payMultiplier = 1, scoopFactor = 1, rockTool = "Bucket" },
	{ id = 2, name = "Mountain Spring", payMultiplier = 5, scoopFactor = 1.5, gate = { fill = 0.15, price = 93000 }, model = "MountainSpring", rockTool = "KiddiePool" },
	{ id = 3, name = "Hot Springs", payMultiplier = 25, scoopFactor = 2, gate = { fill = 0.33, price = 28e6 }, model = "HotSprings", mechanic = "steam", rockTool = "SwimmingPool" },
	{ id = 4, name = "Glacier", payMultiplier = 125, scoopFactor = 2.5, gate = { fill = 0.56, price = 7.9e9 }, model = "Glacier", mechanic = "ice", rockTool = "CargoShip" },
	-- Up in the clouds: only players with a Jetpack Tank get there.
	{ id = 5, name = "Cloud Catcher", payMultiplier = 625, scoopFactor = 3, gate = { fill = 0.77, price = 410e9 }, model = "CloudCatcher", needs = "jetpackTank", mechanic = "cloud", rockTool = "TheMoon" },
} :: { Area }

-- Area mechanics (shared/AreaRules, server/Mechanics).
-- Steam (Hot Springs): each vent puffs `warnSeconds` before it bursts, every `period` seconds
-- (vents staggered); a burst pushes a player within `radius` studs away at `push` and up at `lift`
-- studs a second for `pushSeconds`. Heat Gloves stop the push, and their hotFill (1.25 / 1.4 / 1.6,
-- Config.items) divides the sweep time in hot pools: 25 / 40 / 60 % faster.
Config.steam = { period = 6, warnSeconds = 1, radius = 6, push = 60, lift = 35, pushSeconds = 0.25 }
-- Ice (Glacier): every sweep at the Source is a hit; the `hits`-th frees a block worth `blockSweeps`
-- normal sweeps of litres (carried like water, melted when poured). Bare hands (6 hits for 4 sweeps)
-- are slower than scooping water; the Ice Pick's 4 / 3 / 2 hits make ice break even, then pay up to
-- twice the sweeps. Snow terrain under the feet slows walking to `walkFactor`.
Config.ice = { hits = 6, blockSweeps = 4 }
Config.snow = { walkFactor = 0.8 }
-- Cloud (Cloud Catcher): the Source drifts between its CloudPath points, `legSeconds` per leg. The
-- Cloud Net scoops it from the net's range instead of Zones.REACH.
Config.cloud = { legSeconds = 25 }
-- A deeper pool in every area behind a rock that the area's tool (its `rockTool`, the plan's tool per
-- area) breaks (AreaRules.rockTool):
-- a sweep there brings `sweepScale` sweeps of litres. Broken rocks stay broken for the team (save).
Config.deepPool = { sweepScale = 1.5 }
-- Golden spring: every minSeconds-maxSeconds of play one open area's Source pays `pay` times for
-- `seconds`.
Config.golden = { minSeconds = 480, maxSeconds = 720, seconds = 120, pay = 3 }

-- Shop order. Prices (tools/simulate, Phase 4): the opening buys (Cup to Bucket, the first Quick
-- Scoop and Sneakers, Hold) cost a few minutes so the first comes in under a minute; after that
-- every level costs about the coins one percent of the ocean pays where it is meant to be bought
-- (tools 0.6 of a percent, boosts about one: a tool doubles the hands, a boost adds a little), so
-- something new comes every 5-10 minutes. Every area opens a few levels of every track; the joke
-- levels between hero models (Bucket Lv3, Bathtub Lv3, ...) keep a bigger tool coming every hour.
Config.tracks = {
	{
		id = "tool",
		name = "Tool",
		panel = "tool",
		about = "A bigger tool carries more water every trip.",
		levels = {
			tool("Cup", "Cup", 20, 4, 1),
			tool("Cup Lv2", "Cup", 92, 10, 1),
			tool("Bucket", "Bucket", 692, 25, 1),
			tool("Bucket Lv2", "Bucket", 46000, 45, 1),
			tool("Bucket Lv3", "Bucket", 180000, 80, 1),
			tool("Bathtub", "Bathtub", 1.3e6, 145, 2),
			tool("Bathtub Lv2", "Bathtub", 3.4e6, 260, 2),
			tool("Bathtub Lv3", "Bathtub", 6.5e6, 470, 2),
			tool("Kiddie Pool", "KiddiePool", 11e6, 850, 2),
			tool("Kiddie Pool Lv2", "KiddiePool", 31e6, 1500, 2),
			tool("Kiddie Pool Lv3", "KiddiePool", 280e6, 2700, 3),
			tool("Swimming Pool", "SwimmingPool", 710e6, 5000, 3),
			tool("Swimming Pool Lv2", "SwimmingPool", 1.4e9, 9000, 3),
			tool("Swimming Pool Lv3", "SwimmingPool", 3e9, 16000, 3),
			tool("Swimming Pool Lv4", "SwimmingPool", 7.1e9, 29000, 3),
			tool("Cargo Ship", "CargoShip", 56e9, 52000, 4),
			tool("Cargo Ship Lv2", "CargoShip", 84e9, 94000, 4),
			tool("Cargo Ship Lv3", "CargoShip", 130e9, 170000, 4),
			tool("Cargo Ship Lv4", "CargoShip", 180e9, 300000, 4),
			tool("Cargo Ship Lv5", "CargoShip", 320e9, 550000, 4),
			tool("The Moon", "TheMoon", 2.4e12, 1.2e6, 5),
			tool("The Moon Lv2", "TheMoon", 4.4e12, 2.4e6, 5),
			tool("The Moon Lv3", "TheMoon", 13e12, 5e6, 5),
			tool("The Moon Lv4", "TheMoon", 24e12, 10e6, 5),
		},
	},
	{
		id = "pickup",
		name = "Bigger Scoops",
		panel = "tool",
		about = "Each scoop picks up more, so your tool fills in fewer sweeps.",
		levels = {
			{ cost = 192, area = 1 },
			{ cost = 3.2e6, area = 2 },
			{ cost = 33e6, area = 2 },
			{ cost = 2e9, area = 3 },
		},
	},
	{
		id = "hold",
		name = "Hold to Scoop",
		panel = "tool",
		about = "Hold the button to keep scooping until your tool is full.",
		levels = { { cost = 40, area = 1 } },
	},
	{
		id = "quick",
		name = "Quick Scoop",
		panel = "boosts",
		about = "Every scoop sweep is quicker.",
		levels = {
			{ cost = 35, area = 1, actSeconds = 0.45 },
			{ cost = 250, area = 1, actSeconds = 0.42 },
			{ cost = 130000, area = 1, actSeconds = 0.38 },
			{ cost = 2.3e6, area = 2, actSeconds = 0.35 },
			{ cost = 28e6, area = 2, actSeconds = 0.32 },
			{ cost = 640e6, area = 3, actSeconds = 0.29 },
			{ cost = 5.5e9, area = 3, actSeconds = 0.27 },
			{ cost = 100e9, area = 4, actSeconds = 0.25 },
			{ cost = 320e9, area = 4, actSeconds = 0.23 },
			{ cost = 9.2e12, area = 5, actSeconds = 0.2 },
		},
	},
	{
		id = "walk",
		name = "Sneakers",
		panel = "boosts",
		about = "Walk faster between the water and the ocean.",
		levels = {
			{ cost = 69, area = 1, walkSpeed = 20 },
			{ cost = 400, area = 1, walkSpeed = 21.5 },
			{ cost = 130000, area = 1, walkSpeed = 23 },
			{ cost = 2.5e6, area = 2, walkSpeed = 24.5 },
			{ cost = 28e6, area = 2, walkSpeed = 26 },
			{ cost = 640e6, area = 3, walkSpeed = 27.5 },
			{ cost = 5.5e9, area = 3, walkSpeed = 29 },
			{ cost = 100e9, area = 4, walkSpeed = 30 },
			{ cost = 330e9, area = 4, walkSpeed = 31 },
			{ cost = 9.5e12, area = 5, walkSpeed = 32 },
		},
	},
	{
		id = "tip",
		name = "Tip Jar",
		panel = "boosts",
		about = "Earn more coins for every litre you pour.",
		levels = {
			{ cost = 65000, area = 1, coinBonus = 1.05 },
			{ cost = 230000, area = 1, coinBonus = 1.1 },
			{ cost = 2.6e6, area = 2, coinBonus = 1.15 },
			{ cost = 23e6, area = 2, coinBonus = 1.2 },
			{ cost = 560e6, area = 3, coinBonus = 1.25 },
			{ cost = 5e9, area = 3, coinBonus = 1.3 },
			{ cost = 100e9, area = 4, coinBonus = 1.35 },
			{ cost = 320e9, area = 4, coinBonus = 1.4 },
			{ cost = 9.5e12, area = 5, coinBonus = 1.5 },
		},
	},
} :: { Track }

local function backpack(id: string, name: string, model: string, area: number, price: number, capacity: number, levels: { ItemLevel }): Item
	return {
		id = id,
		name = name,
		kind = "backpack",
		area = area,
		price = price,
		about = "Carries water on your back: scooping fills it once your tool is full.",
		model = model,
		capacity = capacity,
		levels = levels,
	}
end

-- Backpacks: extra litres on top of the tool, filled at the tool's pace (same litres per sweep,
-- more sweeps), so a pack saves walking, not scooping. Each one is worn instead of the last and is
-- bigger than a fully levelled earlier one. Each sizes to its area's tools: bought it holds about
-- one trip of the area's first tool, fully levelled about its last (the cove's starts small, 30 L,
-- so the cove's ladder doesn't outgrow the later areas'). Five levels each, every level about 20 %
-- more, priced like the tracks (tools/simulate): a small buy every so often between the tools.
local backpacks = {
	backpack("backpackTank", "Backpack Tank", "BackpackTank", 1, 40000, 30, {
		{ cost = 81000, capacity = 40 },
		{ cost = 120000, capacity = 52 },
		{ cost = 210000, capacity = 69 },
		{ cost = 290000, capacity = 91 },
		{ cost = 350000, capacity = 120 },
	}),
	backpack("bigTank", "Big Tank", "BigTank", 2, 1.6e6, 300, {
		{ cost = 3.2e6, capacity = 360 },
		{ cost = 7.1e6, capacity = 420 },
		{ cost = 13e6, capacity = 500 },
		{ cost = 30e6, capacity = 590 },
		{ cost = 56e6, capacity = 700 },
	}),
	backpack("twinTanks", "Twin Tanks", "TwinTanks", 3, 270e6, 8000, {
		{ cost = 840e6, capacity = 9400 },
		{ cost = 1.6e9, capacity = 11000 },
		{ cost = 3.1e9, capacity = 13000 },
		{ cost = 6.3e9, capacity = 15000 },
		{ cost = 14e9, capacity = 18000 },
	}),
	backpack("insulatedTank", "Insulated Tank", "InsulatedTank", 4, 82e9, 80000, {
		{ cost = 140e9, capacity = 96000 },
		{ cost = 190e9, capacity = 120000 },
		{ cost = 280e9, capacity = 140000 },
		{ cost = 370e9, capacity = 170000 },
		{ cost = 540e9, capacity = 200000 },
	}),
	backpack("cloudBag", "Cloud Bag", "CloudBag", 5, 3.4e12, 800000, {
		{ cost = 5.6e12, capacity = 960000 },
		{ cost = 8.7e12, capacity = 1.2e6 },
		{ cost = 16e12, capacity = 1.4e6 },
		{ cost = 28e12, capacity = 1.7e6 },
		{ cost = 41e12, capacity = 2e6 },
	}),
}
-- Gadgets: one mechanic each, bought once and levelled in TAB. Water Gun, Garden Hose and Jetpack Tank
-- are used from the hotbar; Heat Gloves, Ice Pick and Cloud Net act on the area mechanics on their own
-- once owned (shared/AreaRules: steam, ice, clouds). Prices are their area's like the backpacks
-- (tools/simulate); the Jetpack Tank opens Cloud Catcher, so it costs well under that gate (410B).
--   Water Gun (1, cove Tool Shack): pours from 30 up to 50 studs instead of Zones.REACH (12).
--   Garden Hose (2): clipped to a Tap, pours 10 up to 40 L/s at the tap's area pay while you stay
--     within 20 to 30 studs of it: about the hands' rate when bought, a break from walking.
--   Jetpack Tank (4): 3 up to 8 s of thrust, refills on the ground; holds 50K up to 120K L on top
--     of the backpack (next to a 52K L Cargo Ship).
local gadgets = {
	{
		id = "waterGun",
		name = "Water Gun",
		kind = "gadget",
		area = 1,
		stand = "ToolShack",
		price = 38000,
		about = "Pour your water from far away: no need to walk to the shore.",
		model = "WaterGun",
		use = "pour",
		range = 30,
		levels = {
			{ cost = 65000, range = 33 },
			{ cost = 83000, range = 37 },
			{ cost = 140000, range = 41 },
			{ cost = 240000, range = 45 },
			{ cost = 270000, range = 50 },
		},
	},
	{
		id = "gardenHose",
		name = "Garden Hose",
		kind = "gadget",
		area = 2,
		price = 1.2e6,
		about = "Clip it to a tap by a pour spot and pour non-stop while you stay close.",
		model = "GardenHose",
		use = "hose",
		rate = 10,
		reach = 20,
		levels = {
			{ cost = 2.7e6, rate = 13, reach = 22 },
			{ cost = 6.5e6, rate = 17, reach = 24 },
			{ cost = 11e6, rate = 23, reach = 26 },
			{ cost = 23e6, rate = 30, reach = 28 },
			{ cost = 53e6, rate = 40, reach = 30 },
		},
	},
	{
		id = "heatGloves",
		name = "Heat Gloves",
		kind = "gadget",
		area = 3,
		price = 440e6,
		about = "Steam can't knock you back, and hot pools fill faster.",
		model = "HeatGloves",
		hotFill = 1.25,
		levels = { { cost = 1.8e9, hotFill = 1.4 }, { cost = 8e9, hotFill = 1.6 } },
	},
	{
		id = "icePick",
		name = "Ice Pick",
		kind = "gadget",
		area = 4,
		price = 93e9,
		about = "Chip ice blocks loose in fewer hits.",
		model = "IcePick",
		hits = 4,
		levels = { { cost = 170e9, hits = 3 }, { cost = 430e9, hits = 2 } },
	},
	{
		id = "jetpackTank",
		name = "Jetpack Tank",
		kind = "gadget",
		area = 4,
		price = 65e9,
		about = "Hold jump to fly up to Cloud Catcher. Its tank holds water too.",
		model = "JetpackTank",
		use = "fly",
		flightSeconds = 3,
		capacity = 50000,
		riseSpeed = 30,
		rechargeSeconds = 4,
		levels = {
			{ cost = 110e9, flightSeconds = 3.7, capacity = 60000 },
			{ cost = 150e9, flightSeconds = 4.4, capacity = 71000 },
			{ cost = 200e9, flightSeconds = 5.4, capacity = 85000 },
			{ cost = 300e9, flightSeconds = 6.6, capacity = 100000 },
			{ cost = 480e9, flightSeconds = 8, capacity = 120000 },
		},
	},
	{
		id = "cloudNet",
		name = "Cloud Net",
		kind = "gadget",
		area = 5,
		price = 2.7e12,
		about = "Catch a drifting cloud from a distance.",
		model = "CloudNet",
		range = 20,
		levels = {
			{ cost = 4.5e12, range = 24 },
			{ cost = 7.4e12, range = 28 },
			{ cost = 13e12, range = 33 },
			{ cost = 23e12, range = 38 },
			{ cost = 35e12, range = 45 },
		},
	},
} :: { Item }
local function vehicle(id: string, name: string, model: string, area: number, price: number, about: string, stats, levels: { ItemLevel }): Item
	return {
		id = id,
		name = name,
		kind = "vehicle",
		area = area,
		stand = "FireStation",
		price = price,
		about = about,
		model = model,
		tank = stats.tank,
		speed = stats.speed,
		fillRate = stats.fillRate,
		sprayRate = stats.sprayRate,
		flies = stats.flies,
		levels = levels,
	}
end

-- Vehicles (server/Vehicles): bought at the Fire Station once their area is open, called out there,
-- filled at a hydrant in about 25 s (tank / fillRate), driven to the beach and sprayed into the ocean
-- by hand, so their water pays the full rate. A trip (the fill, the drive both ways, 20-30 s of
-- spraying) earns about the hands' rate of the area's tools when bought, and you scoop by hand while
-- it fills, so a vehicle is a side-step from walking that the next tools overtake. Five levels
-- raise all four stats about 25 % each and keep the fill near 25 s; each vehicle holds more than a
-- maxed earlier one and its water pays its own area (refill bays, VehicleRules.payArea), so the next
-- vehicle is the upgrade. Prices are their area's (tools/simulate).
--   Fire Truck (2) 2,000-6,500 L, Tanker (3) 25,000-90,000 L, Snowcat Tanker (4) 250,000-900,000 L,
--   Water Bomber (5) 2.5M-9M L: it skims a pool instead of a hydrant and drops the whole tank at
--   once, a shorter trip, so it sprays nothing
local vehicles = {
	vehicle("fireTruck", "Fire Truck", "FireTruck", 2, 1.5e6, "Fill it at a hydrant, drive to the beach and spray the ocean from its hose.", { tank = 2000, speed = 40, fillRate = 70, sprayRate = 100 }, {
		{ cost = 3.2e6, tank = 2500, speed = 42, fillRate = 94, sprayRate = 130 },
		{ cost = 8.6e6, tank = 3200, speed = 44, fillRate = 130, sprayRate = 160 },
		{ cost = 13e6, tank = 4100, speed = 47, fillRate = 170, sprayRate = 200 },
		{ cost = 29e6, tank = 5100, speed = 49, fillRate = 220, sprayRate = 260 },
		{ cost = 60e6, tank = 6500, speed = 52, fillRate = 300, sprayRate = 330 },
	}),
	vehicle("tanker", "Tanker", "Tanker", 3, 270e6, "A huge tank on wheels: fill it at a hydrant and spray the ocean.", { tank = 25000, speed = 36, fillRate = 850, sprayRate = 1300 }, {
		{ cost = 840e6, tank = 32000, speed = 38, fillRate = 1200, sprayRate = 1600 },
		{ cost = 1.7e9, tank = 42000, speed = 40, fillRate = 1600, sprayRate = 2100 },
		{ cost = 3e9, tank = 54000, speed = 43, fillRate = 2200, sprayRate = 2700 },
		{ cost = 6.8e9, tank = 70000, speed = 45, fillRate = 2900, sprayRate = 3500 },
		{ cost = 15e9, tank = 90000, speed = 48, fillRate = 4000, sprayRate = 4500 },
	}),
	vehicle("snowcatTanker", "Snowcat Tanker", "SnowcatTanker", 4, 85e9, "A tracked tanker that carries a glacier's worth of water.", { tank = 250000, speed = 32, fillRate = 8500, sprayRate = 13000 }, {
		{ cost = 130e9, tank = 320000, speed = 34, fillRate = 12000, sprayRate = 16000 },
		{ cost = 200e9, tank = 420000, speed = 36, fillRate = 16000, sprayRate = 21000 },
		{ cost = 240e9, tank = 540000, speed = 39, fillRate = 22000, sprayRate = 27000 },
		{ cost = 400e9, tank = 700000, speed = 41, fillRate = 29000, sprayRate = 35000 },
		{ cost = 710e9, tank = 900000, speed = 44, fillRate = 40000, sprayRate = 45000 },
	}),
	vehicle("waterBomber", "Water Bomber", "WaterBomber", 5, 3.3e12, "Fly low over a pool to fill up, then drop it all on the ocean.", { tank = 2.5e6, speed = 60, fillRate = 100000, flies = true }, {
		{ cost = 5.6e12, tank = 3.2e6, speed = 64, fillRate = 140000 },
		{ cost = 8.9e12, tank = 4.2e6, speed = 67, fillRate = 180000 },
		{ cost = 16e12, tank = 5.4e6, speed = 71, fillRate = 250000 },
		{ cost = 27e12, tank = 7e6, speed = 76, fillRate = 330000 },
		{ cost = 42e12, tank = 9e6, speed = 80, fillRate = 450000 },
	}),
}

local function building(id: string, name: string, model: string, area: number, price: number, rate: number, about: string, levels: { ItemLevel }): Item
	return { id = id, name = name, kind = "building", area = area, price = price, about = about, model = model, rate = rate, levels = levels }
end

-- Buildings: the team's (D2), built on the cove's plots (server/Buildings) once their area is open,
-- levelled in TAB (a level counts on every plot with that building). Each makes `rate` litres a
-- second at half the hand pay of the best open area (Config.buildings.payShare), split between the
-- team. They are where idle play comes from: by the middle of the ocean the team's buildings and
-- staff make about four times what the hands do, so a player who stops working keeps about 40 % of
-- the active income (tools/simulate: idle / active 0.42 at 50 %). Each building is sized to the
-- hands of its area: every level adds, on each plot with it, about a quarter of the hands' litres at
-- Mountain Spring, 2.4x at Hot Springs (where automation takes over) and about 1.2x at the Glacier
-- and Cloud Catcher, so the eight levels keep automation growing with the tools. Prices are about
-- half what one percent of the ocean pays where each is meant to be bought (tools/simulate).
local buildings = {
	building("pump", "Pump", "Pump", 2, 95000, 6.3, "Pumps water up from the ground into the aqueduct, on its own.", {
		{ cost = 1.1e6, rate = 19 },
		{ cost = 2.8e6, rate = 38 },
		{ cost = 3e6, rate = 59 },
		{ cost = 5.3e6, rate = 92 },
		{ cost = 9.6e6, rate = 130 },
		{ cost = 10e6, rate = 180 },
		{ cost = 26e6, rate = 250 },
		{ cost = 29e6, rate = 350 },
	}),
	building("waterTower", "Water Tower", "WaterTower", 3, 56e6, 740, "Stores spring water and lets it down the aqueduct, on its own.", {
		{ cost = 280e6, rate = 3200 },
		{ cost = 590e6, rate = 6700 },
		{ cost = 710e6, rate = 13000 },
		{ cost = 1.1e9, rate = 19000 },
		{ cost = 1.9e9, rate = 29000 },
		{ cost = 2.5e9, rate = 43000 },
		{ cost = 5e9, rate = 58000 },
		{ cost = 7.9e9, rate = 83000 },
	}),
	building("pipeline", "Pipeline", "Pipeline", 4, 34e9, 90000, "Pipes meltwater from the Glacier into the aqueduct.", {
		{ cost = 47e9, rate = 100000 },
		{ cost = 73e9, rate = 115000 },
		{ cost = 80e9, rate = 135000 },
		{ cost = 110e9, rate = 165000 },
		{ cost = 150e9, rate = 210000 },
		{ cost = 170e9, rate = 280000 },
		{ cost = 240e9, rate = 390000 },
		{ cost = 410e9, rate = 550000 },
	}),
	building("rainMachine", "Rain Machine", "RainMachine", 5, 1.1e12, 600000, "Makes it rain into the aqueduct.", {
		{ cost = 2.6e12, rate = 820000 },
		{ cost = 3.3e12, rate = 1.1e6 },
		{ cost = 3.7e12, rate = 1.5e6 },
		{ cost = 5.7e12, rate = 2.1e6 },
		{ cost = 11e12, rate = 2.8e6 },
		{ cost = 12e12, rate = 3.8e6 },
		{ cost = 15e12, rate = 5.2e6 },
		{ cost = 22e12, rate = 7.2e6 },
	}),
} :: { Item }

-- Buildings (server/Buildings): a building litre pays `payShare` of the hand pay of the best open
-- area. Every minSeconds-maxSeconds of play a building clogs and makes `factor` of its rate until
-- someone holds its Unclog prompt.
Config.buildings = { payShare = 0.5, clog = { minSeconds = 240, maxSeconds = 420, factor = 0.5 } }

local function hire(id: string, name: string, area: number, job: "area" | "truck" | "plots", price: number, about: string, stats, levels: { ItemLevel }): Item
	return {
		id = id,
		name = name,
		kind = "staff",
		area = area,
		stand = "Stage_Ocean_LifeguardTower",
		price = price,
		about = about,
		model = name,
		job = job,
		hires = 1,
		carry = stats.carry,
		tripSeconds = stats.tripSeconds,
		boost = stats.boost,
		levels = levels,
	}
end

-- Staff (D3, server/Staff, shared/StaffRules): the team's, hired at the Lifeguard Tower once their
-- area is open and assigned in TAB. The buy is the first hire; TAB levels add a 2nd and a 3rd hire
-- with a speed level (shorter trip) and a carry level between them. Their output follows from the
-- stats (hires x carry / tripSeconds litres a second, no physics), paid at half the hand pay of the
-- area they work (Config.staff.payShare), twice as fast while a member works there. Every level pays
-- itself back in about 12.5 minutes at its own area (750 s; the rule StaffRules.spec checks), so the
-- price follows from the rate. Each first hire is sized to the hands of its area when it opens
-- (tools/simulate): a Helper about a sixth of the hands' litres, a Lifeguard about twice, a
-- Firefighter's crew about the same as the team's Snowcat run by hand. Their litres never grow with
-- the area they work, so a Helper moved to a later area earns that area's pay on a trickle of water.
--   Helper (2): 100 L every 15 s; Lifeguard (3): 8,300 L every 10 s, and players near the water it
--   watches walk 10 % faster; Firefighter (4): a tank of the team's vehicle every 28 s (the crew fills,
--   drives and sprays in turns); Plumber (5): no water of its own: the team's buildings never clog
--   and make +10 % / 15 % / 20 %
local staff = {
	hire("helper", "Helper", 2, "area", 130000, "Scoops and pours for you in the area you pick, on their own.", { carry = 100, tripSeconds = 15 }, {
		{ cost = 31000, hires = 1, carry = 100, tripSeconds = 12 },
		{ cost = 160000, hires = 2, carry = 100, tripSeconds = 12 },
		{ cost = 190000, hires = 2, carry = 160, tripSeconds = 12 },
		{ cost = 250000, hires = 3, carry = 160, tripSeconds = 12 },
		{ cost = 330000, hires = 3, carry = 160, tripSeconds = 8.3 },
	}),
	hire("lifeguard", "Lifeguard", 3, "area", 78e6, "Scoops faster than a Helper, and everyone near the water they watch walks 10% faster.", { carry = 8300, tripSeconds = 10 }, {
		{ cost = 20e6, hires = 1, carry = 8300, tripSeconds = 8 },
		{ cost = 97e6, hires = 2, carry = 8300, tripSeconds = 8 },
		{ cost = 110e6, hires = 2, carry = 13000, tripSeconds = 8 },
		{ cost = 150e6, hires = 3, carry = 13000, tripSeconds = 8 },
		{ cost = 210e6, hires = 3, carry = 13000, tripSeconds = 5.5 },
	}),
	hire("firefighter", "Firefighter", 4, "truck", 4.2e9, "Runs your vehicle's loop on their own, tank after tank into the ocean.", { tripSeconds = 28 }, {
		{ cost = 1.1e9, hires = 1, tripSeconds = 22 },
		{ cost = 5.3e9, hires = 2, tripSeconds = 22 },
		{ cost = 6.1e9, hires = 2, tripSeconds = 14 },
		{ cost = 8.4e9, hires = 3, tripSeconds = 14 },
		{ cost = 12e9, hires = 3, tripSeconds = 9.6 },
	}),
	hire("plumber", "Plumber", 5, "plots", 4.7e12, "Keeps the team's buildings from clogging and makes them pour 10% more.", { boost = 1.1 }, {
		{ cost = 12e12, hires = 2, boost = 1.15 },
		{ cost = 35e12, hires = 3, boost = 1.2 },
	}),
} :: { Item }

-- Staff (server/Staff): a staff litre pays `payShare` of its area's hand pay; staff work `workBonus`
-- times as fast while their owner scooped or poured in the same area within `workSeconds`. Players
-- within `lifeguardRadius` studs of a Source a Lifeguard works walk `lifeguardWalk` times as fast.
Config.staff = { payShare = 0.5, workBonus = 2, workSeconds = 10, lifeguardRadius = 25, lifeguardWalk = 1.1 }

-- Cove shops that sell items instead of the cove's stand (Item.stand), whatever the items' area: the
-- shop's model in workspace.Map.Town or workspace.Map.Beach (holding a ProximityPrompt "Prompt",
-- server/Map.shopPrompt) and its name in the shop.
Config.stands = { ToolShack = "Tool Shack", FireStation = "Fire Station", Stage_Ocean_LifeguardTower = "Lifeguard Tower" }

-- Driving and filling (server/Vehicles, client/Vehicles, shared/VehicleRules), in studs and seconds.
-- hydrantReach: a truck parked (slower than parkedSpeed) this close to a hydrant fills; hoseReach: its
-- owner sprays from this close to it; skimRadius / skimHeight: the bomber fills this close to a
-- Source; accel: studs a second gained per second; turnSpeed: radians a second; climbSpeed: the
-- bomber's up and down; tripSlack / tripMargin: the server's allowance on how fast a vehicle got from
-- its last fill to where it sprays or drops (VehicleRules.plausible).
Config.vehicle = {
	hydrantReach = 25,
	parkedSpeed = 3,
	hoseReach = 20,
	skimRadius = 40,
	skimHeight = 20,
	accel = 30,
	turnSpeed = 1.6,
	climbSpeed = 25,
	tripSlack = 1.5,
	tripMargin = 30,
}

-- Everything bought once at a stand beyond the tool ladder, by kind (common/Items).
Config.items = {} :: { Item }
for _, list in { backpacks, gadgets, vehicles, buildings, staff } do
	table.move(list, 1, #list, #Config.items + 1, Config.items)
end

function Config.track(id: string): Track?
	for _, track in Config.tracks do
		if track.id == id then
			return track
		end
	end
	return nil
end

return Config
