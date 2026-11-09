--!strict
-- Vehicle maths (Config.items kind "vehicle", Config.vehicle; server/Vehicles). Pure: no requires, so
-- Lune tests and Roblox load it the same way.

local VehicleRules = {}

-- The tank after `dt` seconds filling at `rate` litres a second, never above `max`.
function VehicleRules.fill(tank: number, max: number, rate: number, dt: number): number
	return math.min(max, tank + rate * dt)
end

-- Litres sprayed in `dt` seconds at `rate` litres a second, never more than the tank holds.
function VehicleRules.spray(tank: number, rate: number, dt: number): number
	return math.min(tank, rate * dt)
end

-- Whether a vehicle could have covered `distance` studs in `seconds` at its top `speed` (with the
-- rules' tripSlack for lag and tripMargin for parking beside the hydrant or pool).
function VehicleRules.plausible(rules, distance: number, seconds: number, speed: number): boolean
	return distance <= speed * rules.tripSlack * seconds + rules.tripMargin
end

-- Whether a bomber `horizontal` studs from a Source's centre and `height` studs above it skims its pool.
function VehicleRules.skims(rules, horizontal: number, height: number): boolean
	return horizontal <= rules.skimRadius and math.abs(height) <= rules.skimHeight
end

-- Whether the bomber may skim area `areaId`'s Source: never the cove's well, which lies in the ocean.
function VehicleRules.skimmable(areaId: number): boolean
	return areaId ~= 1
end

-- Whether the bomber drops its load now: water in it, over the ocean, after a plausible trip, and not
-- skimming this tick (or it could fill and drop where a pool meets the ocean without a trip).
function VehicleRules.drops(tank: number, skimming: boolean, travelled: boolean, overWater: boolean): boolean
	return tank > 0 and not skimming and travelled and overWater
end

-- The area whose pay a hydrant's water carries. An area's Hydrant pays that area, never more than the
-- vehicle's own (a truck moved to a later area's hydrant earns no more). The cove's refill
-- bays (`hydrantArea` nil) pay the vehicle's own area: trucks can't drive behind the cliffs to the
-- areas, so bay water at cove pay would make every vehicle worth 1/5 to 1/625 of hand water.
function VehicleRules.payArea(vehicleArea: number, hydrantArea: number?): number
	return if hydrantArea then math.min(hydrantArea, vehicleArea) else vehicleArea
end

return VehicleRules
