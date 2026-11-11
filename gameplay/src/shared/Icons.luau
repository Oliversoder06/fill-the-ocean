-- The UI's image for each model (art/ui/icons, outlined renders of the 3D models), by model name:
-- hero tools (Config tool levels' `model`) and items (Config.items `model`). Pure: Lune tests check
-- every model has one.
local Icons = {}

local BY_MODEL: { [string]: string } = {
	-- tools
	Spoon = "rbxassetid://113705942012262",
	Cup = "rbxassetid://88477649194161",
	Bucket = "rbxassetid://139821896772476",
	Bathtub = "rbxassetid://86332048173274",
	KiddiePool = "rbxassetid://123331381336465",
	SwimmingPool = "rbxassetid://97290646513396",
	CargoShip = "rbxassetid://83025477571351",
	TheMoon = "rbxassetid://80713594906764",
	-- gadgets
	WaterGun = "rbxassetid://95669699916461",
	GardenHose = "rbxassetid://123718762752183",
	HeatGloves = "rbxassetid://113001293774751",
	IcePick = "rbxassetid://89999696053971",
	JetpackTank = "rbxassetid://82153205429776",
	CloudNet = "rbxassetid://138615669320635",
	-- backpacks
	BackpackTank = "rbxassetid://121199264981060",
	BigTank = "rbxassetid://134899345217928",
	TwinTanks = "rbxassetid://97963649725891",
	InsulatedTank = "rbxassetid://76590156880096",
	CloudBag = "rbxassetid://121125008907394",
	-- vehicles
	FireTruck = "rbxassetid://81635704201202",
	Tanker = "rbxassetid://100045071296503",
	SnowcatTanker = "rbxassetid://78152527409764",
	WaterBomber = "rbxassetid://89565995434019",
	-- buildings
	Pump = "rbxassetid://124585719198198",
	WaterTower = "rbxassetid://89448471465685",
	Pipeline = "rbxassetid://78158688828173",
	RainMachine = "rbxassetid://83455482510696",
	-- staff
	Helper = "rbxassetid://95484367395382",
	Lifeguard = "rbxassetid://72166720126701",
	Firefighter = "rbxassetid://126691122796962",
	Plumber = "rbxassetid://109748541464809",
}

-- A model's image, nil if it has none yet.
function Icons.of(model: string): string?
	return BY_MODEL[model]
end

return Icons
