local StaffRules = require("../src/shared/StaffRules")
local Config = require("../src/shared/Config")
local Items = require("../../common/Items")

local tests = {}

local TOWER = "Stage_Ocean_LifeguardTower"

local function staff()
	local list = {}
	for _, item in Config.items do
		if item.kind == "staff" then
			list[item.id] = item
		end
	end
	return list
end

-- An item's stat at upgrade n (0 = just hired), as Items.stat reads it.
local function stat(item, n: number, name: string): number
	return Items.stat({ owned = { item.id }, itemLevels = { [item.id] = n } }, item, name)
end

-- 3f: Helper, Lifeguard, Firefighter, Plumber, one per area from Mountain Spring on, all at the tower.
function tests.four_staff_at_the_lifeguard_tower(t)
	local want = {
		helper = { "Helper", 2, "area" },
		lifeguard = { "Lifeguard", 3, "area" },
		firefighter = { "Firefighter", 4, "truck" },
		plumber = { "Plumber", 5, "plots" },
	}
	local count = 0
	for id, item in staff() do
		count += 1
		local w = want[id]
		t.expectEq(w ~= nil, true, `unexpected staff {id}`)
		t.expectEq(item.name, w[1])
		t.expectEq(item.area, w[2], `{id}'s area`)
		t.expectEq(item.job, w[3], `{id}'s job`)
		t.expectEq(item.model, w[1], `{id}'s model`)
		t.expectEq(item.stand, TOWER, `{id} is hired at the tower`)
	end
	t.expectEq(count, 4)
	t.expectEq(Config.stands[TOWER], "Lifeguard Tower", "the tower's name for the shop")
end

-- Up to three hires each (D3): the first is the buy, the 2nd and 3rd are TAB levels between speed
-- and carry levels. Every level costs more than the last and makes something better, nothing worse.
function tests.levels_add_up_to_three_hires(t)
	for id, item in staff() do
		t.expectEq(item.hires, 1, `{id}: the buy is the first hire`)
		local last, cost = item, 0
		for i, level in item.levels do
			t.expectEq(level.cost > cost, true, `{id} level {i} costs more`)
			local better = level.hires > last.hires
			t.expectEq(level.hires >= last.hires, true, `{id} level {i} keeps its hires`)
			for _, name in { "carry", "boost" } do
				if last[name] ~= nil then
					t.expectEq(level[name] >= last[name], true, `{id} level {i} keeps {name}`)
					better = better or level[name] > last[name]
				end
			end
			if last.tripSeconds ~= nil then
				t.expectEq(level.tripSeconds <= last.tripSeconds, true, `{id} level {i} keeps its pace`)
				better = better or level.tripSeconds < last.tripSeconds
			end
			t.expectEq(better, true, `{id} level {i} improves something`)
			last, cost = level, level.cost
		end
		t.expectEq(last.hires, 3, `{id}: three hires at most, all reachable`)
	end
end

-- The economy rule: each hire (the buy, the 2nd and the 3rd) pays itself back in 10-15 minutes at
-- half the hand rate of its own area. A Firefighter is sized for its area's vehicle (Snowcat Tanker).
function tests.each_hire_pays_back_in_10_to_15_minutes(t)
	local snowcat = Items.get(Config, "snowcatTanker")
	for id, item in staff() do
		if item.job == "plots" then
			continue -- the Plumber raises the team's buildings instead (Config comment)
		end
		local pay = StaffRules.payPerLitre(Config, Config.areas[item.area])
		local function rate(n: number): number
			local carry = if item.job == "area" then stat(item, n, "carry") else nil
			return StaffRules.rate(item.job, stat(item, n, "hires"), carry, stat(item, n, "tripSeconds"), snowcat.tank)
		end
		local seconds = item.price / (rate(0) * pay)
		t.expectEq(seconds >= 600 and seconds <= 900, true, `{id}'s first hire pays back in {seconds} s`)
		for n, level in item.levels do
			if level.hires > stat(item, n - 1, "hires") then
				local back = level.cost / ((rate(n) - rate(n - 1)) * pay)
				t.expectEq(back >= 600 and back <= 900, true, `{id}'s hire {level.hires} pays back in {back} s`)
			end
		end
	end
end

function tests.rate_by_job(t)
	t.expectNear(StaffRules.rate("area", 2, 30, 12, nil), 5, 1e-9, "hires x carry / trip")
	t.expectNear(StaffRules.rate("truck", 3, nil, 300, 2000), 20, 1e-9, "hires x tank / trip")
	t.expectEq(StaffRules.rate("truck", 1, nil, 300, nil), 0, "no truck, no loop")
	t.expectEq(StaffRules.rate("plots", 3, nil, nil, nil), 0, "the Plumber pours nothing")
end

-- Automated water pays half the hand rate of the area it lands from.
function tests.pay_is_half_the_assigned_area(t)
	t.expectEq(Config.staff.payShare, 0.5)
	t.expectEq(StaffRules.payPerLitre(Config, Config.areas[1]), 5)
	t.expectEq(StaffRules.payPerLitre(Config, Config.areas[3]), 125)
end

-- Staff work twice as fast while their owner scooped or poured in the same area in the last 10 s.
function tests.owner_working_beside_doubles(t)
	t.expectEq(Config.staff.workBonus, 2)
	t.expectEq(StaffRules.bonus(Config, 2, 100, 2, 105), 2)
	t.expectEq(StaffRules.bonus(Config, 2, 100, 2, 100 + Config.staff.workSeconds), 2, "the window's edge counts")
	t.expectEq(StaffRules.bonus(Config, 2, 100, 2, 111), 1, "too long ago")
	t.expectEq(StaffRules.bonus(Config, 3, 100, 2, 101), 1, "another area")
	t.expectEq(StaffRules.bonus(Config, 0, -math.huge, 2, 0), 1, "never worked")
end

-- Where each job may work: Helpers and Lifeguards any area the owner reaches, a Firefighter the
-- area of an owned vehicle (that vehicle's truck loop), a Plumber the cove's plots.
function tests.targets_by_job(t)
	local list = staff()
	t.expectEq(table.concat(StaffRules.targets(Config, list.helper, {}, { 1, 2, 3 }), ","), "1,2,3")
	t.expectEq(#StaffRules.targets(Config, list.firefighter, { "helper" }, { 1, 2, 3, 4 }), 0, "no vehicle")
	local owned = { "tanker", "waterGun", "fireTruck" }
	t.expectEq(table.concat(StaffRules.targets(Config, list.firefighter, owned, { 1 }), ","), "2,3", "owned vehicles' areas, in order")
	t.expectEq(table.concat(StaffRules.targets(Config, list.plumber, {}, { 1, 2 }), ","), "1")
	t.expectEq(#StaffRules.targets(Config, list.firefighter, { "waterBomber" }, { 1 }), 0, "the bomber flies: no truck loop")
	t.expectEq(StaffRules.post(Config, list.firefighter, { "fireTruck", "waterBomber" }, { 1 }, nil), 2, "the best truck, not the bomber")
	t.expectEq(StaffRules.post(Config, list.firefighter, { "fireTruck", "waterBomber" }, { 1 }, 5), 2, "never posted to the bomber")
end

-- The vehicle a Firefighter drives at an area: that area's truck (never the flying bomber), only an
-- owned one when the owned ids are given.
function tests.truck_by_area(t)
	t.expectEq(StaffRules.truck(Config, 2), Items.get(Config, "fireTruck"))
	t.expectEq(StaffRules.truck(Config, 4), Items.get(Config, "snowcatTanker"))
	t.expectEq(StaffRules.truck(Config, 5), nil, "the Water Bomber flies")
	t.expectEq(StaffRules.truck(Config, 1), nil, "no vehicle at the cove")
	t.expectEq(StaffRules.truck(Config, 3, { "fireTruck" }), nil, "the Tanker isn't owned")
	t.expectEq(StaffRules.truck(Config, 3, { "tanker" }), Items.get(Config, "tanker"))
end

-- A saved post that is still allowed stays; otherwise the default: a carrier's own area, a
-- Firefighter's best vehicle, the plots. Nil when the job has nowhere to work.
function tests.post_keeps_a_valid_assignment(t)
	local list = staff()
	t.expectEq(StaffRules.post(Config, list.helper, {}, { 1, 2, 3 }, 3), 3)
	t.expectEq(StaffRules.post(Config, list.helper, {}, { 1, 2, 3 }, nil), 2, "its own area")
	t.expectEq(StaffRules.post(Config, list.helper, {}, { 1, 2, 3 }, 5), 2, "a post it can't reach falls back")
	t.expectEq(StaffRules.post(Config, list.lifeguard, {}, { 1, 2 }, nil), 2, "own area closed: the furthest reached")
	t.expectEq(StaffRules.post(Config, list.firefighter, {}, { 1, 2, 3, 4 }, 4), nil, "no truck to run")
	t.expectEq(StaffRules.post(Config, list.firefighter, { "fireTruck", "tanker" }, { 1 }, nil), 3, "the best vehicle")
	t.expectEq(StaffRules.post(Config, list.firefighter, { "fireTruck", "tanker" }, { 1 }, 2), 2)
	t.expectEq(StaffRules.post(Config, list.plumber, {}, { 1 }, nil), 1)
end

-- The Assign button cycles the allowed posts, wrapping round.
function tests.next_post_cycles(t)
	t.expectEq(StaffRules.nextPost({ 1, 2, 3 }, 1), 2)
	t.expectEq(StaffRules.nextPost({ 1, 2, 3 }, 3), 1)
	t.expectEq(StaffRules.nextPost({ 1, 2, 3 }, nil), 1, "unassigned starts at the first")
	t.expectEq(StaffRules.nextPost({ 2, 4 }, 3), 2, "an unlisted post starts over")
	t.expectEq(StaffRules.nextPost({}, 1), nil)
end

-- The Plumber: the best present one sets the team's buildings' scale; any keeps them clear.
function tests.plumber_scale(t)
	local scale, keepClear = StaffRules.plumber({})
	t.expectEq(scale, 1)
	t.expectEq(keepClear, false)
	scale, keepClear = StaffRules.plumber({ 1.1, 1.2, 1.15 })
	t.expectEq(scale, 1.2)
	t.expectEq(keepClear, true)
	t.expectEq(Items.get(Config, "plumber").boost, 1.1, "+10 % output")
end

function tests.lifeguard_speeds_up_walking_nearby(t)
	t.expectEq(Config.staff.lifeguardRadius, 25)
	t.expectNear(StaffRules.walkFactor(Config, true), 1.1, 1e-9)
	t.expectEq(StaffRules.walkFactor(Config, false), 1)
end

-- The Staff attribute: "helper:2@2,lifeguard:1@3" (id:hires@post, post 0 = nowhere to work).
function tests.attribute_round_trip(t)
	local text = StaffRules.encode({ { id = "helper", hires = 2, post = 2 }, { id = "firefighter", hires = 1, post = 0 } })
	t.expectEq(text, "helper:2@2,firefighter:1@0")
	local back = StaffRules.decode(text)
	t.expectEq(#back, 2)
	t.expectEq(back[1].id, "helper")
	t.expectEq(back[1].hires, 2)
	t.expectEq(back[1].post, 2)
	t.expectEq(back[2].post, 0)
	t.expectEq(#StaffRules.decode(""), 0)
	t.expectEq(#StaffRules.decode(nil), 0, "not published yet")
	t.expectEq(#StaffRules.decode("helper:x@2,:1@1,lifeguard:1@3"), 1, "broken entries are skipped")
end

-- Stands still never sell buildings, and staff are hired only at the tower.
function tests.tower_hires_staff(t)
	local state = { owned = {}, itemLevels = {} }
	t.expectEq(Items.standPick(Config, state, 1, 1, 1e12, TOWER), nil, "no staff before Mountain Spring")
	t.expectEq(Items.standPick(Config, state, 1, 5, 1e12, TOWER), Items.get(Config, "helper"), "the cheapest first")
	for area = 1, 5 do
		local pick = Items.standPick(Config, state, area, 5, 1e12)
		t.expectEq(pick == nil or pick.kind ~= "staff", true, `area {area}'s stand hires no staff`)
	end
end

return tests
