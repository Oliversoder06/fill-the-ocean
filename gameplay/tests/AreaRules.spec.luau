local AreaRules = require("../src/shared/AreaRules")
local Config = require("../src/shared/Config")

local tests = {}

local function areaWith(mechanic: string)
	for _, area in Config.areas do
		if area.mechanic == mechanic then
			return area
		end
	end
	error(`no area with mechanic {mechanic}`)
end

-- Hot Springs has the steam, Glacier the ice, Cloud Catcher the drifting cloud.
function tests.areas_have_their_mechanic(t)
	t.expectEq(areaWith("steam").id, 3)
	t.expectEq(areaWith("ice").id, 4)
	t.expectEq(areaWith("cloud").id, 5)
end

-- A vent warns `warnSeconds` before each burst and bursts every `period`, from its offset.
function tests.vent_warns_then_bursts(t)
	local steam = { period = 6, warnSeconds = 1 }
	local warned, burst = AreaRules.ventEvents(4.9, 5.1, 0, steam)
	t.expectEq(warned, true, "warn at 5")
	t.expectEq(burst, false)
	warned, burst = AreaRules.ventEvents(5.9, 6.0, 0, steam)
	t.expectEq(warned, false)
	t.expectEq(burst, true, "burst at 6 (end of the step counts)")
	warned, burst = AreaRules.ventEvents(6.0, 6.5, 0, steam)
	t.expectEq(warned or burst, false, "nothing right after a burst")
	warned, burst = AreaRules.ventEvents(13.5, 14.5, 2, steam)
	t.expectEq(burst, true, "offset 2 bursts at 14")
	t.expectEq(warned, false, "its warn was at 13")
	warned, burst = AreaRules.ventEvents(0, 30, 0, steam)
	t.expectEq(warned and burst, true, "a long step catches both")
end

function tests.vents_are_staggered(t)
	t.expectEq(AreaRules.ventOffset(1, 4, 6), 0)
	t.expectNear(AreaRules.ventOffset(3, 4, 6), 3, 1e-9)
end

-- A burst knocks back within the radius, never with Heat Gloves.
function tests.steam_knocks_back_without_gloves(t)
	local steam = { radius = 6 }
	t.expectEq(AreaRules.knocked(5.9, steam, false), true)
	t.expectEq(AreaRules.knocked(6.1, steam, false), false, "out of range")
	t.expectEq(AreaRules.knocked(1, steam, true), false, "gloves")
end

-- Heat Gloves make hot pools fill faster (hotFill times); elsewhere, and without them, nothing changes.
function tests.gloves_speed_up_hot_pools(t)
	local hot, cove = areaWith("steam"), Config.areas[1]
	t.expectNear(AreaRules.scoopSeconds(0.5, hot, nil), 0.5 * hot.scoopFactor, 1e-9)
	t.expectNear(AreaRules.scoopSeconds(0.5, hot, 2), 0.5 * hot.scoopFactor / 2, 1e-9)
	t.expectNear(AreaRules.scoopSeconds(0.5, cove, 2), 0.5, 1e-9, "gloves only work in hot pools")
end

-- Without an Ice Pick a block takes Config.ice.hits; the pick takes fewer.
function tests.ice_pick_lowers_hits(t)
	t.expectEq(AreaRules.iceHits(Config, nil), Config.ice.hits)
	for _, item in Config.items do
		if item.id == "icePick" then
			t.expectEq(item.hits < Config.ice.hits, true, "the pick's first level beats bare hands")
			t.expectEq(AreaRules.iceHits(Config, item.hits), item.hits)
		end
	end
end

-- At the Glacier's Source every sweep is a hit; only the last hit frees a block worth blockSweeps
-- sweeps. Other areas and deep pools scoop normally; a deep pool gives deepPool.sweepScale.
function tests.sweeps_chip_ice_and_deep_pools_give_more(t)
	local ice, cove = areaWith("ice"), Config.areas[1]
	local hits, scale = AreaRules.sweep(Config, ice, false, 0, 3)
	t.expectEq(hits, 1)
	t.expectEq(scale, 0, "a hit alone carries nothing")
	hits, scale = AreaRules.sweep(Config, ice, false, 2, 3)
	t.expectEq(hits, 0, "the block came loose: start a new one")
	t.expectEq(scale, Config.ice.blockSweeps)
	hits, scale = AreaRules.sweep(Config, ice, false, 0, nil)
	t.expectEq(hits, 1, "no pick: Config.ice.hits needed")
	hits, scale = AreaRules.sweep(Config, cove, false, 2, nil)
	t.expectEq(hits, 0, "scooping anywhere else drops the half-chipped block")
	t.expectEq(scale, 1)
	hits, scale = AreaRules.sweep(Config, cove, true, 0, nil)
	t.expectEq(scale, Config.deepPool.sweepScale)
	t.expectEq(Config.deepPool.sweepScale, 1.5)
	hits, scale = AreaRules.sweep(Config, ice, true, 2, nil)
	t.expectEq(hits, 0, "the Glacier's deep pool is water, not ice: the block is dropped")
	t.expectEq(scale, Config.deepPool.sweepScale)
end

function tests.snow_slows_walking(t)
	t.expectNear(AreaRules.walkSpeed(Config, 20, true), 16, 1e-9)
	t.expectEq(AreaRules.walkSpeed(Config, 20, false), 20)
end

-- The rock needs the area's tool (Config.areas rockTool): the first level of that tool model.
function tests.rock_needs_the_areas_top_tool(t)
	local track = Config.track("tool")
	assert(track, "tool track")
	local index, level = AreaRules.rockTool(Config, 1)
	t.expectEq(level.model, "Bucket")
	t.expectEq(track.levels[index - 1].model ~= "Bucket", true, "the first Bucket level")
	t.expectEq(AreaRules.canBreak(Config, { tool = index - 1 }, 1), false)
	t.expectEq(AreaRules.canBreak(Config, { tool = index }, 1), true)
	t.expectEq(AreaRules.canBreak(Config, {}, 1), false, "the Spoon breaks nothing")
	for areaId, model in { "Bucket", "KiddiePool", "SwimmingPool", "CargoShip", "TheMoon" } do
		local i, level = AreaRules.rockTool(Config, areaId)
		t.expectEq(level.model, model, `area {areaId}'s rock tool`)
		t.expectEq(track.levels[i], level)
		t.expectEq(track.levels[i - 1].model ~= model, true, `area {areaId}: the first {model} level`)
	end
end

function tests.golden_waits_between_min_and_max(t)
	local g = Config.golden
	t.expectEq(g.minSeconds, 480)
	t.expectEq(g.maxSeconds, 720)
	t.expectEq(g.seconds, 120)
	t.expectEq(AreaRules.goldenDelay(Config, 0), 480)
	t.expectNear(AreaRules.goldenDelay(Config, 0.5), 600, 1e-9)
	t.expectEq(AreaRules.goldenDelay(Config, 0.999999) <= 720, true)
end

function tests.golden_picks_an_open_area(t)
	t.expectEq(AreaRules.goldenPick({ 1 }, 0.7), 1)
	t.expectEq(AreaRules.goldenPick({ 1, 2, 3 }, 0), 1)
	t.expectEq(AreaRules.goldenPick({ 1, 2, 3 }, 0.5), 2)
	t.expectEq(AreaRules.goldenPick({ 1, 2, 3 }, 0.999999), 3)
end

-- The golden Source pays Config.golden.pay times; its deep pool and other areas don't.
function tests.golden_source_pays_more(t)
	t.expectEq(Config.golden.pay, 3)
	t.expectEq(AreaRules.payScale(Config, 2, false, 2), 3)
	t.expectEq(AreaRules.payScale(Config, 2, true, 2), 1, "the deep pool isn't the spring")
	t.expectEq(AreaRules.payScale(Config, 1, false, 2), 1)
	t.expectEq(AreaRules.payScale(Config, 1, false, nil), 1)
end

return tests
