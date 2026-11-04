local Config = require("../src/shared/Config")

local tests = {}

function tests.stages_in_order(t)
	t.expectEq(#Config.stages, 3, "stage count")
	t.expectEq(Config.stages[1].name, "Pool")
	t.expectEq(Config.stages[2].name, "Lake")
	t.expectEq(Config.stages[3].name, "Ocean")
end

function tests.weights_sum_to_one(t)
	local weights = Config.stageWeights()
	local sum = 0
	for _, w in weights do
		sum += w
	end
	t.expectNear(sum, 1, 1e-9, "sum")
	t.expectNear(weights[1], 7 / 45, 1e-12, "pool weight")
end

function tests.start_trip_is_11s(t)
	local s = Config.start
	t.expectNear(2 * Config.tripDistance / s.walkSpeed + 2 * s.actSeconds, 11, 1e-9, "start trip")
end

function tests.trip_times_match_spec(t)
	-- 0.5 s holds (owner, 2026-11-04): trips are shorter than the original 16..7 s plan
	local expected = { 8.9, 7.61, 7.1, 6.4, 5.74, 5.56, 5.4 }
	local walk, act = Config.start.walkSpeed, Config.start.actSeconds
	local found = {}
	for _, stage in Config.stages do
		for _, item in stage.items do
			if item.kind == "walk" then
				walk = item.walkSpeed
			elseif item.kind == "hands" then
				act = item.actSeconds
				table.insert(found, 2 * Config.tripDistance / walk + 2 * act)
			end
		end
	end
	t.expectEq(#found, #expected, "speed pairs")
	for i, trip in expected do
		t.expectNear(found[i], trip, 0.05, `trip {i}`)
	end
end

function tests.tools_grow(t)
	local last = Config.start.capacity
	local lastName
	for _, stage in Config.stages do
		for _, item in stage.items do
			if item.kind == "tool" then
				if item.capacity <= last then
					error(`{item.name} capacity {item.capacity} is not above {last}`)
				end
				last = item.capacity
				lastName = item.name
			end
		end
	end
	t.expectEq(lastName, "The Moon Lv4")
	t.expectEq(last, 10e6)
end

function tests.hold_starts_at_half_second_and_ends_at_02(t)
	t.expectEq(Config.start.actSeconds, 0.5)
	local last = Config.start.actSeconds
	for _, stage in Config.stages do
		for _, item in stage.items do
			if item.kind == "hands" then
				if item.actSeconds >= last then
					error(`{item.name} hold {item.actSeconds} is not shorter than {last}`)
				end
				last = item.actSeconds
			end
		end
	end
	t.expectEq(last, 0.2)
end

function tests.eight_hero_models(t)
	local seen, order = {}, { Config.start.toolModel }
	seen[Config.start.toolModel] = true
	for _, stage in Config.stages do
		for _, item in stage.items do
			if item.kind == "tool" then
				t.expectEq(type(item.model), "string", `{item.name} model`)
				if not seen[item.model] then
					seen[item.model] = true
					table.insert(order, item.model)
				end
			end
		end
	end
	t.expectEq(table.concat(order, ","), "Spoon,Cup,Bucket,Bathtub,KiddiePool,SwimmingPool,CargoShip,TheMoon")
end

function tests.cup_costs_two_spoon_trips(t)
	local cup = Config.stages[1].items[1]
	t.expectEq(cup.name, "Cup")
	t.expectEq(cup.cost, 2 * Config.start.capacity * Config.stages[1].coinsPerLitre)
end

return tests
