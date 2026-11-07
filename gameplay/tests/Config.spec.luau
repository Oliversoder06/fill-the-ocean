local Config = require("../src/shared/Config")

local tests = {}

function tests.six_tracks_in_shop_order(t)
	local ids = {}
	for _, track in Config.tracks do
		table.insert(ids, track.id)
	end
	t.expectEq(table.concat(ids, ","), "tool,pickup,hold,quick,walk,tip")
	t.expectEq(Config.track("walk").name, "Sneakers")
	t.expectEq(Config.track("nope"), nil)
end

-- Within a track the area never goes down, so each area opens the next levels of every track.
function tests.levels_open_in_order(t)
	local areas = #Config.ocean.standInOpens + 1
	for _, track in Config.tracks do
		t.expectEq(#track.levels > 0, true, `{track.id} has levels`)
		local lastArea = 1
		for i, level in track.levels do
			if type(level.area) ~= "number" or level.area < lastArea or level.area > areas then
				error(`{track.id} level {i} opens in area {level.area}`)
			end
			lastArea = level.area
		end
	end
end

function tests.every_level_costs_more_than_the_last(t)
	for _, track in Config.tracks do
		local lastCost = 0
		for i, level in track.levels do
			t.expectEq(type(level.cost), "number", `{track.id} {i} cost`)
			if level.cost <= lastCost then
				error(`{track.id} level {i} cost {level.cost} is not above {lastCost}`)
			end
			lastCost = level.cost
		end
	end
end

function tests.tools_grow_to_the_moon(t)
	local last = Config.start.capacity
	local levels = Config.track("tool").levels
	for _, level in levels do
		if level.capacity <= last then
			error(`{level.name} capacity {level.capacity} is not above {last}`)
		end
		last = level.capacity
	end
	t.expectEq(#levels, 19)
	t.expectEq(levels[#levels].name, "The Moon Lv4")
	t.expectEq(last, 10e6)
end

function tests.eight_hero_models(t)
	local seen, order = { [Config.start.toolModel] = true }, { Config.start.toolModel }
	for _, level in Config.track("tool").levels do
		t.expectEq(type(level.model), "string", `{level.name} model`)
		if not seen[level.model] then
			seen[level.model] = true
			table.insert(order, level.model)
		end
	end
	t.expectEq(table.concat(order, ","), "Spoon,Cup,Bucket,Bathtub,KiddiePool,SwimmingPool,CargoShip,TheMoon")
end

function tests.scoops_get_faster_to_02(t)
	local last = Config.start.actSeconds
	t.expectEq(last, 0.5)
	for _, level in Config.track("quick").levels do
		if level.actSeconds >= last then
			error(`quick {level.actSeconds} is not faster than {last}`)
		end
		last = level.actSeconds
	end
	t.expectEq(last, 0.2)
end

function tests.hold_is_one_purchase_in_the_first_area(t)
	local levels = Config.track("hold").levels
	t.expectEq(#levels, 1)
	t.expectEq(levels[1].area, 1)
end

function tests.pour_is_quick(t)
	t.expectEq(Config.pourSeconds <= 0.3, true, "pour plays fast")
end

return tests
