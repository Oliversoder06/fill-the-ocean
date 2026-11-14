local Report = require("../tools/AnalyticsReport")

local tests = {}

local HOUR = 3600
local NOW = 100 * 24 * HOUR

local function session(at: number, seconds: number, extra: { [string]: any }?)
	local s = { format = 1, at = at, seconds = seconds, build = 8, place = "Run", new = false, trail = {}, counts = {}, errors = {}, warnings = {} }
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

-- A new player who leaves the lobby after 40 s.
local function bouncer(at: number)
	return { userId = 1, sessions = { session(at, 40, { place = "Lobby", new = true, onboarding = 2, leave = { doing = "Roaming", stage = "Lobby" } }) } }
end

-- A new player: 30 s in the lobby, teleported, 570 s in a run; back 30 hours later.
local function stayer(at: number)
	return {
		userId = 2,
		sessions = {
			session(at, 30, { place = "Lobby", new = true, onboarding = 3, left = "teleport" }),
			session(at + 40, 570, {
				onboarding = 10,
				device = "Touch",
				fps = 33,
				leave = { doing = "Carrying", stage = "Guide:3" },
				trail = {
					{ t = 5, k = "step", s = "Honeycomb_v1:Opened" },
					{ t = 6, k = "step", s = "Honeycomb_v1:Viewed" },
					{ t = 30, k = "event", s = "TripEnd", v = 12, f = { Outcome = "Poured", Area = "Area1", Stage = "Guide:4" } },
					{ t = 99, k = "event", s = "TripEnd", v = 3, f = { Outcome = "Quit", Area = "Area1", Stage = "F0" } },
					{ t = 120, k = "event", s = "GateOpened", v = 300, f = { Area = "Area2", TeamSize = "1" } },
				},
				errors = { { text = "boom", n = 2 } },
			}),
			session(at + 30 * HOUR, 200),
		},
	}
end

function tests.first_visit_chains_teleports(t)
	local visits = Report.firstVisits({ stayer(1000) })
	t.expectEq(#visits, 1)
	t.expectEq(visits[1].seconds, 600, "lobby and run in one first visit")
	t.expectEq(visits[1].onboarding, 10, "the furthest step of the visit")
	t.expectEq(visits[1].leave.doing, "Carrying", "how the visit ended: its last session")
end

function tests.gone_within_60_and_180(t)
	local s = Report.summary({ bouncer(1000), stayer(1000) }, NOW)
	t.expectEq(s.newPlayers, 2)
	t.expectNear(s.gone60, 0.5, 1e-9)
	t.expectNear(s.gone180, 0.5, 1e-9)
end

function tests.d1_counts_only_passed_windows(t)
	local late = bouncer(NOW - 10 * HOUR) -- their day 1 hasn't come yet
	late.userId = 3
	local s = Report.summary({ stayer(1000), late }, NOW)
	t.expectEq(s.d1.eligible, 1)
	t.expectEq(s.d1.returned, 1)
	t.expectEq(s.d7.eligible, 1)
	t.expectEq(s.d7.returned, 0)
end

function tests.onboarding_reach(t)
	local s = Report.summary({ bouncer(1000), stayer(1000) }, NOW)
	t.expectEq(s.onboarding[1], 2)
	t.expectEq(s.onboarding[2], 2)
	t.expectEq(s.onboarding[3], 1)
	t.expectEq(s.onboarding[10], 1)
end

function tests.trail_counts(t)
	local s = Report.summary({ stayer(1000) }, NOW)
	t.expectEq(s.trips.Poured, 1)
	t.expectEq(s.trips.Quit, 1)
	t.expectEq(s.honeycomb.Opened, 1)
	t.expectEq(s.honeycomb.Viewed, 1)
	t.expectEq(s.honeycomb.Bought or 0, 0)
	t.expectEq(s.pace.Area2[1], 300)
	t.expectEq(s.devices.Touch, 1)
	t.expectEq(s.fps["25-40"], 1)
	t.expectEq(s.ended["Carrying @ Guide:3"], 1, "the run session that ended the first visit")
end

function tests.errors_by_players(t)
	local other = stayer(5000)
	other.userId = 9
	local s = Report.summary({ stayer(1000), other }, NOW)
	t.expectEq(s.errors.boom, 2, "players who met it, not times")
end

function tests.build_filter(t)
	local old = stayer(1000)
	for _, s in old.sessions do
		s.build = 7
	end
	local s = Report.summary({ old, bouncer(1000) }, NOW, 8)
	t.expectEq(s.newPlayers, 1, "only build 8's first visits")
	t.expectEq(Report.summary({ old, bouncer(1000) }, NOW, 7).newPlayers, 1)
end

function tests.format_and_story_print(t)
	local text = Report.format(Report.summary({ bouncer(1000), stayer(1000) }, NOW))
	t.expectEq(text:find("gone within 60 s", 1, true) ~= nil, true)
	t.expectEq(text:find("FirstUpgrade", 1, true) ~= nil, true, "onboarding steps by name")
	local story = Report.story(stayer(1000))
	t.expectEq(story:find("TripEnd", 1, true) ~= nil, true)
	t.expectEq(story:find("Honeycomb_v1:Opened", 1, true) ~= nil, true)
end

return tests
