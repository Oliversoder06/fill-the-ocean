local Config = require("../src/shared/Config")
local Boosts = require("../src/shared/Boosts")
local Milestones = require("../src/shared/Milestones")

local tests = {}

local EXTRAS = { "revive", "sighting", "raindrops", "cosmetic" }

local function extraOf(m): string?
	local found = nil
	for _, extra in EXTRAS do
		if m[extra] ~= nil then
			assert(found == nil, `milestone at {m.fill} has two extras ({found}, {extra})`)
			found = extra
		end
	end
	return found
end

-- Three made-up milestones, so the rules don't depend on the tuned list.
local small = {
	boosts = Config.boosts,
	milestones = {
		{ fill = 0.25, boost = "coins", revive = 2, text = "A" },
		{ fill = 0.5, boost = "gusher", raindrops = 5, text = "B" },
		{ fill = 0.75, boost = "tailwind", revive = 1, text = "C" },
		{ fill = 1, ending = true },
	},
}

function tests.one_milestone_every_five_percent(t)
	t.expectEq(#Config.milestones, 20)
	for i, m in Config.milestones do
		t.expectNear(m.fill, i * 0.05, 1e-9, `milestone {i}`)
	end
	local last = Config.milestones[20]
	t.expectEq(last.ending, true, "100% is the ending")
	t.expectEq(last.boost, nil, "the ending starts no boost")
	t.expectEq(extraOf(last), nil, "the ending's reward is the map's own")
end

function tests.each_milestone_has_a_boost_and_one_extra(t)
	for i = 1, 19 do
		local m = Config.milestones[i]
		t.expectEq(Boosts.kind(Config, m.boost) ~= nil, true, `milestone {i} boost {m.boost}`)
		t.expectEq(type(m.text), "string", `milestone {i} text`)
		t.expectEq(extraOf(m) ~= nil, true, `milestone {i} has an extra`)
		t.expectEq(m.ending, nil, `milestone {i} is not the ending`)
	end
end

function tests.neighbours_always_feel_different(t)
	for i = 2, 19 do
		local a, b = Config.milestones[i - 1], Config.milestones[i]
		t.expectEq(a.boost ~= b.boost, true, `milestones {i - 1} and {i} share a boost`)
		t.expectEq(extraOf(a) ~= extraOf(b), true, `milestones {i - 1} and {i} share an extra`)
	end
end

function tests.the_bacon_hair_shows_every_quarter(t)
	local fills = {}
	for _, m in Config.milestones do
		if m.sighting then
			table.insert(fills, math.round(m.fill * 100))
		end
	end
	t.expectEq(table.concat(fills, ","), "25,50,75")
end

function tests.revives_are_numbered_once_each(t)
	local seen = {}
	local n = 0
	for _, m in Config.milestones do
		if m.revive then
			n += 1
			t.expectEq(seen[m.revive], nil, `M{m.revive} revived twice`)
			seen[m.revive] = true
		end
	end
	for i = 1, n do
		t.expectEq(seen[i], true, `revives are numbered 1..{n} (M{i} missing)`)
	end
end

function tests.raindrops_are_small_whole_amounts(t)
	for i, m in Config.milestones do
		if m.raindrops then
			t.expectEq(m.raindrops % 1, 0, `milestone {i}`)
			t.expectEq(m.raindrops >= 5 and m.raindrops <= 25, true, `milestone {i}: {m.raindrops}`)
		end
	end
end

function tests.crossed_lists_every_milestone_passed(t)
	local function crossed(before, after)
		return table.concat(Milestones.crossed(small, before, after), ",")
	end
	t.expectEq(crossed(0, 0.2), "", "below the first")
	t.expectEq(crossed(0.2, 0.25), "1", "landing exactly on it counts")
	t.expectEq(crossed(0.25, 0.3), "", "already past")
	t.expectEq(crossed(0.4, 0.6), "2")
	t.expectEq(crossed(0.1, 0.8), "1,2,3", "one big jump: every one, in order")
	t.expectEq(crossed(0.9, 1), "4", "the ending")
	t.expectEq(crossed(0.8, 0.1), "", "water going down crosses nothing")
	t.expectEq(crossed(0.5, 0.5), "", "no change")
end

function tests.reach_grants_each_milestone_once(t)
	local reached = {}
	t.expectEq(table.concat(Milestones.reach(small, reached, 0.2, 0.6), ","), "1,2")
	t.expectEq(table.concat(reached, ","), "1,2", "remembered")
	t.expectEq(table.concat(Milestones.reach(small, reached, 0.2, 0.6), ","), "", "never twice")
	t.expectEq(table.concat(Milestones.reach(small, reached, 0, 0.8), ","), "3", "only the new one")
	t.expectEq(table.concat(reached, ","), "1,2,3")
	local loaded = { 3 }
	t.expectEq(table.concat(Milestones.reach(small, loaded, 0, 0.8), ","), "1,2")
	t.expectEq(table.concat(loaded, ","), "1,2,3", "kept in order")
end

function tests.an_old_save_reached_everything_below_its_fill(t)
	t.expectEq(table.concat(Milestones.reachedBy(small, 0), ","), "")
	t.expectEq(table.concat(Milestones.reachedBy(small, 0.6), ","), "1,2")
	t.expectEq(table.concat(Milestones.reachedBy(small, 0.75), ","), "1,2,3")
	t.expectEq(#Milestones.reachedBy(Config, 1), 20)
end

function tests.reward_is_the_milestone(t)
	t.expectEq(Milestones.reward(small, 2).raindrops, 5)
	t.expectEq(Milestones.reward(Config, 20).ending, true)
	for _, bad in { 0, 5, 1.5, -1 } do
		t.expectEq(pcall(Milestones.reward, small, bad), false, `index {bad}`)
	end
end

function tests.revived_lists_the_decorations_back(t)
	t.expectEq(table.concat(Milestones.revived(small, {}), ","), "")
	t.expectEq(table.concat(Milestones.revived(small, { 1, 2, 3 }), ","), "2,1", "in the order reached")
	t.expectEq(table.concat(Milestones.revived(small, { 2 }), ","), "", "no revive there")
end

-- The Raindrops reached milestones pay (index -> Raindrops), never those an old save skipped.
function tests.raindrops_of_the_reached_milestones(t)
	local function list(map: { [number]: number }): string
		local parts = {}
		for index, amount in map do
			table.insert(parts, `{index}={amount}`)
		end
		table.sort(parts)
		return table.concat(parts, ",")
	end
	t.expectEq(list(Milestones.raindrops(small, {}, {})), "")
	t.expectEq(list(Milestones.raindrops(small, { 1, 2, 3, 4 }, {})), "2=5")
	t.expectEq(list(Milestones.raindrops(small, { 1, 2, 3 }, { 2 })), "", "skipped: never paid")
	t.expectEq(list(Milestones.raindrops(Config, { 1, 2, 7, 19 }, { 7 })), "19=25,2=5")
end

function tests.card_says_what_happened(t)
	t.expectEq(Milestones.card(small, 1), `25% — A 2X COINS for {Config.boosts.seconds} s`)
	t.expectEq(Milestones.card(small, 2), `50% — B +5 Raindrops, GUSHER for {Config.boosts.seconds} s`)
	t.expectEq(Milestones.card(small, 4), nil, "the ending has its own card")
	t.expectEq(string.sub(Milestones.card(Config, 1) :: string, 1, 3), "5% ")
end

function tests.the_milestone_attribute_round_trips(t)
	local text = Milestones.encode(7, 1234.5)
	local index, at = Milestones.decode(text)
	t.expectEq(index, 7)
	t.expectEq(at, 1234.5)
	for _, bad in { "", "x@1", "7", "7@", 7, nil } do
		local i, a = Milestones.decode(bad)
		t.expectEq(i, nil, `index from {tostring(bad)}`)
		t.expectEq(a, nil, `time from {tostring(bad)}`)
	end
end

return tests
