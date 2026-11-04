--!strict
-- All run numbers (draft, from docs/design/2026-11-04-fill-the-ocean-design.md). Data only:
-- no requires, so Lune tests and Roblox load it the same way.
-- Trip time = 2 * tripDistance / walkSpeed + 2 * actSeconds (walk there and back, scoop, pour).
-- actSeconds is the hold time of the scoop and pour prompts; each fills or empties the whole tool.

export type ItemKind = "tool" | "walk" | "hands"

export type Item = {
	name: string,
	kind: ItemKind,
	cost: number,
	capacity: number?,
	model: string?, -- tools: the hero model shown in hand ("Cup" for Cup and Cup Lv2)
	walkSpeed: number?,
	actSeconds: number?,
}

export type Stage = {
	name: string,
	minutes: number,
	coinsPerLitre: number,
	waterPerPlayer: number,
	items: { Item },
}

local function tool(name: string, model: string, cost: number, capacity: number): Item
	return { name = name, kind = "tool", model = model, cost = cost, capacity = capacity }
end

local function walk(name: string, cost: number, walkSpeed: number): Item
	return { name = name, kind = "walk", cost = cost, walkSpeed = walkSpeed }
end

local function hands(name: string, cost: number, actSeconds: number): Item
	return { name = name, kind = "hands", cost = cost, actSeconds = actSeconds }
end

local Config = {}

Config.tripDistance = 80 -- studs, source centre to basin pour edge, same in every stage
Config.start = { capacity = 1, walkSpeed = 16, actSeconds = 0.5, toolName = "Spoon", toolModel = "Spoon" }

Config.stages = {
	{
		name = "Pool",
		minutes = 7,
		coinsPerLitre = 10,
		waterPerPlayer = 972,
		items = {
			tool("Cup", "Cup", 20, 4),
			walk("Sneakers 1", 69, 20),
			hands("Quick Hands 1", 69, 0.45),
			tool("Cup Lv2", "Cup", 92, 10),
			tool("Bucket", "Bucket", 692, 25),
			walk("Sneakers 2", 385, 23.5),
			hands("Quick Hands 2", 384, 0.4),
			tool("Bucket Lv2", "Bucket", 1136, 60),
			walk("Sneakers 3", 1637, 25),
			hands("Quick Hands 3", 1636, 0.35),
		},
	},
	{
		name = "Lake",
		minutes = 13,
		coinsPerLitre = 50,
		waterPerPlayer = 131305,
		items = {
			tool("Bucket Lv3", "Bucket", 9000, 150),
			walk("Sneakers 4", 28125, 27.6),
			hands("Quick Hands 4", 28125, 0.3),
			tool("Bathtub", "Bathtub", 62500, 350),
			tool("Bathtub Lv2", "Bathtub", 291667, 800),
			walk("Sneakers 5", 166667, 30.8),
			hands("Quick Hands 5", 166666, 0.27),
			tool("Kiddie Pool", "KiddiePool", 375000, 1800),
			tool("Kiddie Pool Lv2", "KiddiePool", 1687500, 4000),
		},
	},
	{
		name = "Ocean",
		minutes = 25,
		coinsPerLitre = 250,
		waterPerPlayer = 361183125,
		items = {
			tool("Swimming Pool", "SwimmingPool", 5e6, 9000),
			walk("Sneakers 6", 9140625, 31.4),
			hands("Quick Hands 6", 9140625, 0.23),
			tool("Swimming Pool Lv2", "SwimmingPool", 22.5e6, 20000),
			tool("Swimming Pool Lv3", "SwimmingPool", 100e6, 45000),
			tool("Cargo Ship", "CargoShip", 225e6, 100000),
			tool("Cargo Ship Lv2", "CargoShip", 500e6, 220000),
			walk("Sneakers 7", 275e6, 32),
			hands("Quick Hands 7", 275e6, 0.2),
			tool("Cargo Ship Lv3", "CargoShip", 589285714, 480000),
			tool("The Moon", "TheMoon", 2571428571, 1e6),
			tool("The Moon Lv2", "TheMoon", 5357142857, 2.2e6),
			tool("The Moon Lv3", "TheMoon", 11785714286, 4.8e6),
			tool("The Moon Lv4", "TheMoon", 25714285714, 10e6),
		},
	},
} :: { Stage }

-- Share of the run each stage counts for: its minutes over the run's minutes.
function Config.stageWeights(): { number }
	local total = 0
	for _, stage in Config.stages do
		total += stage.minutes
	end
	local weights = {}
	for i, stage in Config.stages do
		weights[i] = stage.minutes / total
	end
	return weights
end

return Config
