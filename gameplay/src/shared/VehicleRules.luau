--!strict
-- Vehicle maths (Config.items kind "vehicle", Config.vehicle; server/Vehicles). Pure: no requires, so
-- Lune tests and Roblox load it the same way.

local VehicleRules = {}

-- The vehicle a call at the Fire Station brings out: the owned one of the furthest area, or nil.
function VehicleRules.best(config, owned: { string })
	local best = nil
	for _, item in config.items do
		if item.kind == "vehicle" and table.find(owned, item.id) and (not best or item.area > best.area) then
			best = item
		end
	end
	return best
end

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

-- The area whose pay a hydrant's water carries. An area's Hydrant pays that area. The cove's refill
-- bays (`hydrantArea` nil) pay the vehicle's own area: trucks can't drive behind the cliffs to the
-- areas, so bay water at cove pay would make every vehicle worth 1/5 to 1/625 of hand water.
function VehicleRules.payArea(vehicleArea: number, hydrantArea: number?): number
	return hydrantArea or vehicleArea
end

return VehicleRules
