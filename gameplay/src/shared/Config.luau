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
Config.start = { capacity = 1, walkSpeed = 16, actSeconds = 0.5, toolName = "Spoon", toolModel = "Spoon" }
-- Sweeps to fill a tool: 1 for the Spoon, then one more every `toolsPerSweep` tool levels, at most `maxSweeps`.
-- Tools add sweeps faster than Pickup takes them off, so big tools never fill in one sweep and
-- Quick Scoop keeps mattering.
Config.sweeps = { toolsPerSweep = 2, maxSweeps = 8 }

-- Fill milestones (fractions of the whole ocean): crossing one starts a boost for everyone for
-- `seconds`. Each plays once per save. All are bonuses, never penalties.
Config.boosts = {
	seconds = 30,
	milestones = { 0.25, 0.5, 0.75 },
	kinds = {
		{ id = "coins", tag = "2X COINS", card = "The sun dozed off! Double coins!", coins = 2 },
		{ id = "gusher", tag = "GUSHER", card = "The well is gushing! Fill up in one sweep!", oneSweep = true },
		{ id = "tailwind", tag = "TAILWIND", card = "A cool breeze! Run faster!", walk = 1.5 },
	},
}

-- The one ocean. Pay is flat (it never rises on its own; harder areas pay more from Phase 2).
-- Fill curve (Water.fill): percent k needs firstPercent * growth^(k-1) litres per player, so the
-- fill rises at a steady pace while income grows. Phase 4 tunes the numbers (tools/simulate).
Config.ocean = {
	name = "The Ocean",
	coinsPerLitre = 10,
	firstPercent = 250,
	growth = 1.05,
}

-- The areas, in the order their gates open (common/Areas). Pay ratios match the old stage pay
-- (10/50/250) so the upgrade prices still fit. Gate prices are the money tools/simulate holds when
-- the ocean reaches the gate's fill, rounded down to 2 significant figures.
Config.areas = {
	{ id = 1, name = "Cove Well", payMultiplier = 1, scoopFactor = 1, rockTool = "Bucket" },
	{ id = 2, name = "Mountain Spring", payMultiplier = 5, scoopFactor = 1.5, gate = { fill = 0.07, price = 16000 }, model = "MountainSpring", rockTool = "KiddiePool" },
	{ id = 3, name = "Hot Springs", payMultiplier = 25, scoopFactor = 2, gate = { fill = 0.22, price = 88000 }, model = "HotSprings", mechanic = "steam", rockTool = "SwimmingPool" },
	{ id = 4, name = "Glacier", payMultiplier = 125, scoopFactor = 2.5, gate = { fill = 0.45, price = 1.6e6 }, model = "Glacier", mechanic = "ice", rockTool = "CargoShip" },
	-- Up in the clouds: only players with a Jetpack Tank get there.
	{ id = 5, name = "Cloud Catcher", payMultiplier = 625, scoopFactor = 3, gate = { fill = 0.7, price = 120e6 }, model = "CloudCatcher", needs = "jetpackTank", mechanic = "cloud", rockTool = "TheMoon" },
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

-- Shop order. Prices: tools and Sneakers keep the ordered list's prices; each old Quick Hands price
-- is split between Quick Scoop and Pickup.
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
			tool("Bucket Lv2", "Bucket", 1136, 60, 1),
			tool("Bucket Lv3", "Bucket", 9000, 150, 2),
			tool("Bathtub", "Bathtub", 62500, 350, 2),
			tool("Bathtub Lv2", "Bathtub", 291667, 800, 2),
			tool("Kiddie Pool", "KiddiePool", 375000, 1800, 2),
			tool("Kiddie Pool Lv2", "KiddiePool", 1687500, 4000, 2),
			tool("Swimming Pool", "SwimmingPool", 5e6, 9000, 3),
			tool("Swimming Pool Lv2", "SwimmingPool", 22.5e6, 20000, 3),
			tool("Swimming Pool Lv3", "SwimmingPool", 100e6, 45000, 3),
			tool("Cargo Ship", "CargoShip", 225e6, 100000, 3),
			tool("Cargo Ship Lv2", "CargoShip", 500e6, 220000, 3),
			tool("Cargo Ship Lv3", "CargoShip", 589285714, 480000, 3),
			tool("The Moon", "TheMoon", 2571428571, 1e6, 3),
			tool("The Moon Lv2", "TheMoon", 5357142857, 2.2e6, 3),
			tool("The Moon Lv3", "TheMoon", 11785714286, 4.8e6, 3),
			tool("The Moon Lv4", "TheMoon", 25714285714, 10e6, 3),
		},
	},
	{
		id = "pickup",
		name = "Pickup",
		panel = "tool",
		about = "Each scoop picks up more, so your tool fills in fewer sweeps.",
		levels = {
			{ cost = 192, area = 1 },
			{ cost = 14062, area = 2 },
			{ cost = 83333, area = 2 },
			{ cost = 4570312, area = 3 },
		},
	},
	{
		id = "hold",
		name = "Hold",
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
			{ cost = 192, area = 1, actSeconds = 0.4 },
			{ cost = 818, area = 1, actSeconds = 0.35 },
			{ cost = 14062, area = 2, actSeconds = 0.3 },
			{ cost = 83333, area = 2, actSeconds = 0.27 },
			{ cost = 4570312, area = 3, actSeconds = 0.23 },
			{ cost = 137.5e6, area = 3, actSeconds = 0.2 },
		},
	},
	{
		id = "walk",
		name = "Sneakers",
		panel = "boosts",
		about = "Walk faster between the water and the basin.",
		levels = {
			{ cost = 69, area = 1, walkSpeed = 20 },
			{ cost = 385, area = 1, walkSpeed = 23.5 },
			{ cost = 1637, area = 1, walkSpeed = 25 },
			{ cost = 28125, area = 2, walkSpeed = 27.6 },
			{ cost = 166667, area = 2, walkSpeed = 30.8 },
			{ cost = 9140625, area = 3, walkSpeed = 31.4 },
			{ cost = 275e6, area = 3, walkSpeed = 32 },
		},
	},
	{
		id = "tip",
		name = "Tip Jar",
		panel = "boosts",
		about = "Earn more coins for every litre you pour.",
		levels = {
			{ cost = 300, area = 1, coinBonus = 1.05 },
			{ cost = 30000, area = 2, coinBonus = 1.1 },
			{ cost = 200000, area = 2, coinBonus = 1.15 },
			{ cost = 100e6, area = 3, coinBonus = 1.2 },
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
-- bigger than a fully levelled earlier one. Each sizes to its area's matching tool: bought it holds
-- about one trip's worth of that tool and fully levelled about two (50 L to 120 L next to a 60 L
-- Bucket Lv2), and it costs about what that tool costs, so it competes with the next tool level:
--   1 Backpack Tank: Bucket Lv2 (60 L, 1,136): 50 / 80 / 120 L
--   2 Big Tank: Bathtub (350 L, 62,500): 300 / 500 / 700 L
--   3 Twin Tanks: Swimming Pool (9,000 L, 5M): 8,000 / 12,000 / 18,000 L
--   4 Insulated Tank: Cargo Ship (100,000 L, 225M): 80,000 / 130,000 / 200,000 L
--   5 Cloud Bag: The Moon (1M L, 2.57B): 800,000 / 1.3M / 2M L
-- Phase 4 retunes them with the ladder (tools/simulate).
local backpacks = {
	backpack("backpackTank", "Backpack Tank", "BackpackTank", 1, 1200, 50, {
		{ cost = 2500, capacity = 80 },
		{ cost = 5000, capacity = 120 },
	}),
	backpack("bigTank", "Big Tank", "BigTank", 2, 60000, 300, {
		{ cost = 150000, capacity = 500 },
		{ cost = 400000, capacity = 700 },
	}),
	backpack("twinTanks", "Twin Tanks", "TwinTanks", 3, 5e6, 8000, {
		{ cost = 12e6, capacity = 12000 },
		{ cost = 40e6, capacity = 18000 },
	}),
	backpack("insulatedTank", "Insulated Tank", "InsulatedTank", 4, 200e6, 80000, {
		{ cost = 450e6, capacity = 130000 },
		{ cost = 1e9, capacity = 200000 },
	}),
	backpack("cloudBag", "Cloud Bag", "CloudBag", 5, 2.5e9, 800000, {
		{ cost = 5e9, capacity = 1.3e6 },
		{ cost = 12e9, capacity = 2e6 },
	}),
}
-- Gadgets: one mechanic each, bought once and levelled in TAB. Water Gun, Garden Hose and Jetpack Tank
-- are used from the hotbar; Heat Gloves, Ice Pick and Cloud Net act on the area mechanics on their own
-- once owned (shared/AreaRules: steam, ice, clouds). Prices sit in their area's band
-- like the backpacks (tools/simulate retunes them in Phase 4); the Jetpack Tank opens Cloud Catcher,
-- so it costs well under that gate (120M).
--   Water Gun (1, cove Tool Shack): pours from 30 / 40 / 50 studs instead of Zones.REACH (12).
--   Garden Hose (2): clipped to a Tap, pours 10 / 20 / 40 L/s at the tap's area pay while you stay
--     within 20 / 25 / 30 studs of it (hand rate there: a 150 L Bucket Lv3 every ~20 s, ~7.5 L/s).
--   Jetpack Tank (4): 3 / 5 / 8 s of thrust, refills on the ground; holds 50K / 80K / 120K L on top
--     of the backpack (next to a 100K L Cargo Ship).
local gadgets = {
	{
		id = "waterGun",
		name = "Water Gun",
		kind = "gadget",
		area = 1,
		stand = "ToolShack",
		price = 2500,
		about = "Pour your water from far away: no need to walk to the shore.",
		model = "WaterGun",
		use = "pour",
		range = 30,
		levels = { { cost = 6000, range = 40 }, { cost = 12000, range = 50 } },
	},
	{
		id = "gardenHose",
		name = "Garden Hose",
		kind = "gadget",
		area = 2,
		price = 40000,
		about = "Clip it to a tap by a pour spot and pour non-stop while you stay close.",
		model = "GardenHose",
		use = "hose",
		rate = 10,
		reach = 20,
		levels = { { cost = 120000, rate = 20, reach = 25 }, { cost = 400000, rate = 40, reach = 30 } },
	},
	{
		id = "heatGloves",
		name = "Heat Gloves",
		kind = "gadget",
		area = 3,
		price = 2e6,
		about = "Steam can't knock you back, and hot pools fill faster.",
		model = "HeatGloves",
		hotFill = 1.25,
		levels = { { cost = 6e6, hotFill = 1.4 }, { cost = 20e6, hotFill = 1.6 } },
	},
	{
		id = "icePick",
		name = "Ice Pick",
		kind = "gadget",
		area = 4,
		price = 20e6,
		about = "Chip ice blocks loose in fewer hits.",
		model = "IcePick",
		hits = 4,
		levels = { { cost = 60e6, hits = 3 }, { cost = 150e6, hits = 2 } },
	},
	{
		id = "jetpackTank",
		name = "Jetpack Tank",
		kind = "gadget",
		area = 4,
		price = 40e6,
		about = "Hold jump to fly up to Cloud Catcher. Its tank holds water too.",
		model = "JetpackTank",
		use = "fly",
		flightSeconds = 3,
		capacity = 50000,
		riseSpeed = 30,
		rechargeSeconds = 4,
		levels = {
			{ cost = 90e6, flightSeconds = 5, capacity = 80000 },
			{ cost = 200e6, flightSeconds = 8, capacity = 120000 },
		},
	},
	{
		id = "cloudNet",
		name = "Cloud Net",
		kind = "gadget",
		area = 5,
		price = 3e9,
		about = "Catch a drifting cloud from a distance.",
		model = "CloudNet",
		range = 20,
		levels = { { cost = 7e9, range = 30 }, { cost = 15e9, range = 45 } },
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
-- filled at a hydrant in about 30 s (tank / fillRate), driven to the beach and sprayed into the ocean
-- by hand, so their water pays the full rate. A trip (30 s filling, the drive both ways, 20-30 s of
-- spraying) takes about 2.5 hand trips, so each tank holds about 2.5x its area's matching tool and
-- earns about that tool's hand rate; since you scoop by hand while it fills, it roughly doubles
-- income, so it costs about the next tool level. Levels raise all four stats and keep the fill near
-- 30 s; each vehicle holds more than a maxed earlier one and its water pays its own area (refill bays,
-- VehicleRules.payArea), so the next vehicle is the upgrade. Phase 4 retunes them (tools/simulate).
--   Fire Truck (2): Bathtub Lv2 (800 L, 291K) / Kiddie Pool (1,800 L, 375K): 2,000 L for 300K
--   Tanker (3): Swimming Pool (9,000 L, 5M) / Lv2 (20,000 L, 22.5M): 25,000 L for 20M
--   Snowcat Tanker (4): Cargo Ship (100,000 L, 225M), Insulated Tank 200M: 250,000 L for 400M
--   Water Bomber (5): The Moon (1M L, 2.57B): 2.5M L for 6B; it skims a pool instead of a hydrant
--     and drops the whole tank at once, a shorter trip, so it sprays nothing
local vehicles = {
	vehicle("fireTruck", "Fire Truck", "FireTruck", 2, 300000, "Fill it at a hydrant, drive to the beach and spray the ocean from its hose.", { tank = 2000, speed = 40, fillRate = 70, sprayRate = 100 }, {
		{ cost = 600000, tank = 3000, speed = 44, fillRate = 110, sprayRate = 150 },
		{ cost = 1.1e6, tank = 4500, speed = 48, fillRate = 180, sprayRate = 230 },
		{ cost = 1.8e6, tank = 6500, speed = 52, fillRate = 300, sprayRate = 330 },
	}),
	vehicle("tanker", "Tanker", "Tanker", 3, 20e6, "A huge tank on wheels: fill it at a hydrant and spray the ocean.", { tank = 25000, speed = 36, fillRate = 850, sprayRate = 1250 }, {
		{ cost = 45e6, tank = 40000, speed = 40, fillRate = 1500, sprayRate = 2000 },
		{ cost = 90e6, tank = 60000, speed = 44, fillRate = 2400, sprayRate = 3000 },
		{ cost = 160e6, tank = 90000, speed = 48, fillRate = 4000, sprayRate = 4500 },
	}),
	vehicle("snowcatTanker", "Snowcat Tanker", "SnowcatTanker", 4, 400e6, "A tracked tanker that carries a glacier's worth of water.", { tank = 250000, speed = 32, fillRate = 8500, sprayRate = 12500 }, {
		{ cost = 900e6, tank = 400000, speed = 36, fillRate = 15000, sprayRate = 20000 },
		{ cost = 1.8e9, tank = 600000, speed = 40, fillRate = 24000, sprayRate = 30000 },
		{ cost = 3.5e9, tank = 900000, speed = 44, fillRate = 40000, sprayRate = 45000 },
	}),
	vehicle("waterBomber", "Water Bomber", "WaterBomber", 5, 6e9, "Fly low over a pool to fill up, then drop it all on the ocean.", { tank = 2.5e6, speed = 60, fillRate = 100000, flies = true }, {
		{ cost = 12e9, tank = 4e6, speed = 66, fillRate = 170000 },
		{ cost = 25e9, tank = 6e6, speed = 72, fillRate = 270000 },
		{ cost = 50e9, tank = 9e6, speed = 80, fillRate = 450000 },
	}),
}

local function building(id: string, name: string, model: string, area: number, price: number, rate: number, about: string, levels: { ItemLevel }): Item
	return { id = id, name = name, kind = "building", area = area, price = price, about = about, model = model, rate = rate, levels = levels }
end

-- Buildings: the team's (D2), built on the cove's plots (server/Buildings) once their area is open,
-- levelled in TAB (a level counts on every plot with that building). Each makes `rate` litres a
-- second at half the hand pay of the best open area (Config.buildings.payShare), split between the
-- team. Each is sized to its area's tool like the backpacks: it costs about that tool and makes a
-- share of that tool's hand rate, so it pays itself back in about 10 minutes when bought, and six
-- of them make about what one player makes by hand (active play pays about twice idle). A level
-- doubles the rate for three times the price.
--   Pump (2): Bathtub (350 L, 62,500), hand ~10 L/s: 3 L/s at 50K = 75 coins/s, 11 min
--   Water Tower (3): Swimming Pool (9,000 L, 5M), hand ~200 L/s: 60 L/s at 4M = 7,500 coins/s, 9 min
--   Pipeline (4): Cargo Ship (100,000 L, 225M), hand ~2,000 L/s: 400 L/s at 150M = 250K coins/s, 10 min
--   Rain Machine (5): The Moon (1M L, 2.57B), hand ~15,000 L/s: 2,000 L/s at 4B = 6.25M coins/s, 11 min
local buildings = {
	building("pump", "Pump", "Pump", 2, 50000, 3, "Pumps water up from the ground into the aqueduct, on its own.", {
		{ cost = 150000, rate = 6 },
		{ cost = 450000, rate = 12 },
	}),
	building("waterTower", "Water Tower", "WaterTower", 3, 4e6, 60, "Stores spring water and lets it down the aqueduct, on its own.", {
		{ cost = 12e6, rate = 120 },
		{ cost = 36e6, rate = 240 },
	}),
	building("pipeline", "Pipeline", "Pipeline", 4, 150e6, 400, "Pipes meltwater from the Glacier into the aqueduct.", {
		{ cost = 450e6, rate = 800 },
		{ cost = 1.35e9, rate = 1600 },
	}),
	building("rainMachine", "Rain Machine", "RainMachine", 5, 4e9, 2000, "Makes it rain into the aqueduct.", {
		{ cost = 12e9, rate = 4000 },
		{ cost = 36e9, rate = 8000 },
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

-- Staff (D3, server/Staff, shared/StaffRules): each player's own, hired at the Lifeguard Tower once
-- their area is open and assigned in TAB. The buy is the first hire; TAB levels add a 2nd and a 3rd
-- hire with a speed level (shorter trip) and a carry level between them. Their output follows from
-- the stats (hires x carry / tripSeconds litres a second, no physics), paid to the owner at half the
-- hand pay of the area they work (Config.staff.payShare), twice as fast while the owner works there.
-- Each is sized to its area's band like the buildings: it costs about that area's Pump-like price
-- and each hire (the buy, the 2nd, the 3rd) pays itself back in about 13 minutes at its own area;
-- the speed and carry levels between them pay back a little slower. Its litres never grow with the
-- area it works, so a Helper moved to a later area earns that area's pay on a trickle of water.
--   Helper (2): 30 L every 15 s = 2 L/s next to a ~10 L/s hand rate, 50 coins/s for 40K: 13 min
--   Lifeguard (3): scoops faster (10 s trips), 400 L = 40 L/s next to ~200 L/s by hand, 5,000
--     coins/s for 4M: 13 min; players near the water it watches walk 10 % faster
--   Firefighter (4): one tank of the owner's vehicle every 300 s (a solo fill, drive and spray at
--     a staff pace); sized for its area's Snowcat Tanker (250,000 L = 833 L/s, 520K coins/s for 400M:
--     13 min); an earlier truck makes its own small share
--   Plumber (5): no water of its own: the team's buildings never clog and make +10 % / 15 % / 20 %.
--     A team at Cloud Catcher with two or three Rain Machines makes 12-19M coins/s; a clog halves
--     one for a few minutes now and then, so keeping them clear plus 10 % is worth ~2.5M coins/s to
--     the team (the hirer's share less): 1.5B pays back in about 10 minutes for the team
local staff = {
	hire("helper", "Helper", 2, "area", 40000, "Scoops and pours for you in the area you pick, on their own.", { carry = 30, tripSeconds = 15 }, {
		{ cost = 10000, hires = 1, carry = 30, tripSeconds = 12 },
		{ cost = 50000, hires = 2, carry = 30, tripSeconds = 12 },
		{ cost = 60000, hires = 2, carry = 45, tripSeconds = 12 },
		{ cost = 80000, hires = 3, carry = 45, tripSeconds = 12 },
		{ cost = 120000, hires = 3, carry = 45, tripSeconds = 9 },
	}),
	hire("lifeguard", "Lifeguard", 3, "area", 4e6, "Scoops faster than a Helper, and everyone near the water they watch walks 10% faster.", { carry = 400, tripSeconds = 10 }, {
		{ cost = 1e6, hires = 1, carry = 400, tripSeconds = 8 },
		{ cost = 5e6, hires = 2, carry = 400, tripSeconds = 8 },
		{ cost = 6e6, hires = 2, carry = 600, tripSeconds = 8 },
		{ cost = 8e6, hires = 3, carry = 600, tripSeconds = 8 },
		{ cost = 12e6, hires = 3, carry = 600, tripSeconds = 6 },
	}),
	hire("firefighter", "Firefighter", 4, "truck", 400e6, "Runs your vehicle's loop on their own: a full tank into the ocean every few minutes.", { tripSeconds = 300 }, {
		{ cost = 100e6, hires = 1, tripSeconds = 240 },
		{ cost = 500e6, hires = 2, tripSeconds = 240 },
		{ cost = 600e6, hires = 2, tripSeconds = 180 },
		{ cost = 700e6, hires = 3, tripSeconds = 180 },
		{ cost = 1.2e9, hires = 3, tripSeconds = 150 },
	}),
	hire("plumber", "Plumber", 5, "plots", 1.5e9, "Keeps the team's buildings from clogging and makes them pour 10% more.", { boost = 1.1 }, {
		{ cost = 3e9, hires = 2, boost = 1.15 },
		{ cost = 6e9, hires = 3, boost = 1.2 },
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
