local Record = require("../../common/AnalyticsRecord")

local tests = {}

local function session()
	return Record.newSession({ at = 1000, build = 42, place = "Run", new = true })
end

function tests.session_row_shape(t)
	local s = session()
	t.expectEq(s.format, Record.FORMAT, "format stamped")
	t.expectEq(s.at, 1000)
	t.expectEq(s.build, 42)
	t.expectEq(s.place, "Run")
	t.expectEq(s.new, true)
	t.expectEq(#s.trail, 0)
	t.expectEq(next(s.counts), nil)
	Record.count(s, "pours")
	Record.count(s, "pours", 2)
	t.expectEq(s.counts.pours, 3)
end

function tests.trail_keeps_milestones_past_the_cap(t)
	local s = session()
	Record.add(s, { t = 0, k = "step", s = "Onboarding:Joined", m = true })
	for i = 1, Record.TRAIL_MAX + 200 do
		Record.add(s, { t = i, k = "money", s = "Pour", v = 10 })
		if i == 300 then
			Record.add(s, { t = i, k = "event", s = "GateOpened", m = true })
		end
	end
	t.expectEq(#s.trail, Record.TRAIL_MAX, "capped")
	t.expectEq(s.trail[1].s, "Onboarding:Joined", "the first rows stay")
	local gate = false
	for _, entry in s.trail do
		gate = gate or entry.s == "GateOpened"
	end
	t.expectEq(gate, true, "a milestone row is never dropped")
	t.expectEq(s.trail[#s.trail].t, Record.TRAIL_MAX + 200, "the newest filler stays; the oldest went")
	t.expectEq(s.dropped, 202, "how many rows went is kept") -- 602 added, 400 kept
end

function tests.trail_drops_milestones_only_when_nothing_else_is_left(t)
	local s = session()
	for i = 1, Record.TRAIL_MAX + 10 do
		Record.add(s, { t = i, k = "step", m = true })
	end
	t.expectEq(#s.trail, Record.TRAIL_MAX)
	t.expectEq(s.trail[1].t, 1, "the first rows stay")
	t.expectEq(s.trail[#s.trail].t, Record.TRAIL_MAX + 10)
end

function tests.texts_kept_distinct_and_few(t)
	local s = session()
	for i = 1, 10 do
		Record.text(s.errors, `boom {i % 7}`)
		Record.text(s.errors, `boom {i % 7}`)
	end
	t.expectEq(#s.errors, Record.TEXTS_MAX)
	t.expectEq(s.errors[1].n, 4, "a repeat counts on its row") -- boom 1 at i = 1 and 8, twice each
end

function tests.record_keeps_last_25(t)
	local record = Record.sanitize(nil)
	t.expectEq(record.format, Record.FORMAT)
	for i = 1, Record.MAX_SESSIONS + 5 do
		local s = session()
		s.at = i
		record = Record.push(record, s)
	end
	t.expectEq(#record.sessions, Record.MAX_SESSIONS)
	t.expectEq(record.sessions[1].at, 6, "the oldest went")
	t.expectEq(record.sessions[#record.sessions].at, Record.MAX_SESSIONS + 5)
end

function tests.sanitize_drops_broken_sessions(t)
	local record = Record.sanitize({ format = 1, sessions = { { at = 5, trail = {} }, "x", { trail = 3 } } })
	t.expectEq(#record.sessions, 1)
	t.expectEq(Record.sanitize("nope").format, Record.FORMAT)
end

function tests.shrink_cuts_the_oldest_trail_first(t)
	local record = Record.sanitize(nil)
	for i = 1, 3 do
		local s = session()
		for j = 1, 100 do
			Record.add(s, { t = j, k = "money" })
		end
		s.at = i
		record = Record.push(record, s)
	end
	t.expectEq(Record.shrink(record), true)
	t.expectEq(#record.sessions[1].trail, 50, "half the oldest session's trail")
	t.expectEq(#record.sessions[3].trail, 100)
	for _ = 1, 40 do
		Record.shrink(record)
	end
	t.expectEq(Record.shrink(record), false, "nothing left to cut")
end

return tests
