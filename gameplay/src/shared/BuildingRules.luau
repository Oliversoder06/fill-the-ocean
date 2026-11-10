--!strict
-- Building maths (Config.items kind "building", server/Buildings): pay, output, clogs and the build
-- check. Pure: config is passed in, so Lune tests and Roblox load it the same way.

local MONEY_EPSILON = 1e-6 -- pours add fractional coins; 49999.9999999 must still build a 50,000-coin Pump

local BuildingRules = {}

-- Coins a building litre pays: payShare (half) of the hand pay of the best open area. A building's
-- water comes from no area, so it pays at the team's best (`openIds`: the open area ids).
function BuildingRules.payPerLitre(config, openIds: { number }): number
	local best = 0
	for _, area in config.areas do
		if table.find(openIds, area.id) and area.payMultiplier > best then
			best = area.payMultiplier
		end
	end
	return config.ocean.coinsPerLitre * best * config.buildings.payShare
end

-- Litres a building with `rate` L/s makes in `dt` seconds: a clogged one makes clog.factor of it.
-- `scale` multiplies it (3f's Plumber; 1 without).
function BuildingRules.litres(config, rate: number, dt: number, clogged: boolean, scale: number): number
	return rate * dt * scale * (if clogged then config.buildings.clog.factor else 1)
end

-- Seconds of play until a building clogs, from `r` in [0, 1).
function BuildingRules.clogDelay(config, r: number): number
	local clog = config.buildings.clog
	return clog.minSeconds + r * (clog.maxSeconds - clog.minSeconds)
end

-- Whether `money` covers `price` (a build or a TAB level of a building), for buildable. Server code
-- uses common/Items.affords, the same check: pure modules can't require each other.
function BuildingRules.affords(money: number, price: number): boolean
	return money + MONEY_EPSILON >= price
end

-- Whether building `item` can be built now with `openAreas` areas open (Ladder.openAreas) and
-- `money`, plot aside. `priceOf` turns a listed price into the team's (common/Items.price).
-- The reason when not: "locked" (its area is closed) or "money".
function BuildingRules.buildable(item, openAreas: number, money: number, priceOf: (number) -> number): (boolean, string?)
	if item.area > openAreas then
		return false, "locked"
	elseif not BuildingRules.affords(money, priceOf(item.price)) then
		return false, "money"
	end
	return true, nil
end

-- Whether `item` may be built on plot `index` (1..plotCount; a remote value) now, with `plots` the
-- save's plots (plot number as a string -> building id), `openAreas` areas open (Ladder.openAreas)
-- and `money` (`priceOf` as buildable). The reason when not: "plot" (no such plot), "taken",
-- "unknown" (not a building), or buildable's "locked" / "money".
function BuildingRules.canBuild(plots: { [string]: string }, plotCount: number, index: any, item, openAreas: number, money: number, priceOf: (number) -> number): (boolean, string?)
	if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > plotCount then
		return false, "plot"
	elseif plots[tostring(index)] ~= nil then
		return false, "taken"
	elseif not item or item.kind ~= "building" then
		return false, "unknown"
	end
	return BuildingRules.buildable(item, openAreas, money, priceOf)
end

-- The aqueduct a plot's water runs down (Town.Aqueduct_<side>): the shop side is +X.
function BuildingRules.side(x: number): string
	return if x > 0 then "ShopSide" else "StaffSide"
end

return BuildingRules
