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
}

export type Track = {
	id: string,
	name: string,
	panel: "tool" | "boosts", -- which shop panel shows it
	about: string, -- one line for the shop
	levels: { Level },
}

-- One upgrade of a bought item (TAB): its cost and the stat it gives from then on.
export type ItemLevel = {
	cost: number,
	capacity: number?, -- backpack: litres it holds
}

-- A thing bought once at its area's stand (common/Items), then levelled in TAB.
export type Item = {
	id: string,
	name: string,
	kind: "backpack" | "gadget" | "vehicle" | "building" | "staff",
	area: number, -- sold at this area's stand once it is open
	price: number, -- the first buy, at the stand
	about: string, -- one line for the shop
	model: string?, -- backpack: its Accessory in ReplicatedStorage.ToolModels.Backpacks
	capacity: number?, -- backpack: litres it holds when bought
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
	{ id = 1, name = "Cove Well", payMultiplier = 1, scoopFactor = 1 },
	{ id = 2, name = "Mountain Spring", payMultiplier = 5, scoopFactor = 1.5, gate = { fill = 0.07, price = 16000 }, model = "MountainSpring" },
	{ id = 3, name = "Hot Springs", payMultiplier = 25, scoopFactor = 2, gate = { fill = 0.22, price = 88000 }, model = "HotSprings" },
	{ id = 4, name = "Glacier", payMultiplier = 125, scoopFactor = 2.5, gate = { fill = 0.45, price = 1.6e6 }, model = "Glacier" },
	{ id = 5, name = "Cloud Catcher", payMultiplier = 625, scoopFactor = 3, gate = { fill = 0.7, price = 120e6 }, model = "CloudCatcher" },
} :: { Area }

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
local gadgets = {} -- 3b: Water Gun, Garden Hose, Heat Gloves, Ice Pick, Jetpack Tank, Cloud Net
local vehicles = {} -- 3d: Fire Truck, Tanker, Snowcat Tanker, Water Bomber
local buildings = {} -- 3e: Pump, Water Tower, Pipeline, Rain Machine (the team's, save.buildings)
local staff = {} -- 3f: Helper, Lifeguard, Firefighter, Plumber

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
