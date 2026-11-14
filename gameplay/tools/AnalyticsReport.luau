-- The analytics report over session records (common/AnalyticsRecord), for `lune run tools/analytics`
-- (which pulls the records through Open Cloud). Pure: plain tables in, numbers and text out, so it is
-- spec'd against synthetic players (tests/AnalyticsReport.spec). What it answers, in the order of the
-- playbook in docs/analytics.md: how long first visits last and how many are gone within 60 s / 180 s
-- (what Roblox ranks on), day-1 and day-7 return, how far new players get through onboarding, where
-- and doing what first visits end, devices and frame rates, trips, the honeycomb funnel, the real
-- pace of gates and milestones, and errors by how many players met them.
local Analytics = require("../../common/Analytics")

local Report = {}

local DAY = 24 * 3600
local CHAIN_GAP = 120 -- seconds: a session starting this soon after the last one ended is the same visit (a teleport)

export type Player = { userId: number, sessions: { any } }
export type Visit = { userId: number, at: number, seconds: number, onboarding: number, leave: any, sessions: { any } }

local function sorted(sessions: { any }): { any }
	local list = table.clone(sessions)
	table.sort(list, function(a, b)
		return a.at < b.at
	end)
	return list
end

local function inBuild(sessions: { any }, build: number?): { any }
	if not build then
		return sorted(sessions)
	end
	local list = {}
	for _, s in sessions do
		if s.build == build then
			table.insert(list, s)
		end
	end
	return sorted(list)
end

-- Each new player's first visit: their first-ever session and the sessions chained to it by
-- teleports (lobby -> run -> lobby), with its length, furthest onboarding step and how it ended.
function Report.firstVisits(players: { Player }, build: number?): { Visit }
	local visits = {}
	for _, player in players do
		local sessions = inBuild(player.sessions, build)
		local first = nil
		for i, s in sessions do
			if s.new then
				first = i
				break
			end
		end
		if not first then
			continue
		end
		local chain = { sessions[first] }
		local last = sessions[first]
		for i = first + 1, #sessions do
			local s = sessions[i]
			if s.at > last.at + last.seconds + CHAIN_GAP then
				break
			end
			table.insert(chain, s)
			last = s
		end
		local seconds, onboarding = 0, 0
		for _, s in chain do
			seconds += s.seconds or 0
			onboarding = math.max(onboarding, s.onboarding or 0)
		end
		table.insert(visits, { userId = player.userId, at = chain[1].at, seconds = seconds, onboarding = onboarding, leave = last.leave, sessions = chain })
	end
	return visits
end

local function median(list: { number }): number?
	if #list == 0 then
		return nil
	end
	local copy = table.clone(list)
	table.sort(copy)
	local mid = (#copy + 1) / 2
	return (copy[math.floor(mid)] + copy[math.ceil(mid)]) / 2
end

local function bump(map: { [string]: number }, key: string?)
	if key then
		map[key] = (map[key] or 0) + 1
	end
end

-- Returned between `from` and `to` seconds after their first session, for players whose window has
-- passed by `now` (a window still open would count them as gone).
local function retention(players: { Player }, visits: { Visit }, now: number, from: number, to: number)
	local byId = {}
	for _, player in players do
		byId[player.userId] = player
	end
	local eligible, returned = 0, 0
	for _, visit in visits do
		if now < visit.at + to then
			continue
		end
		eligible += 1
		for _, s in byId[visit.userId].sessions do
			if s.at >= visit.at + from and s.at < visit.at + to then
				returned += 1
				break
			end
		end
	end
	return { eligible = eligible, returned = returned }
end

-- Everything the report prints, as numbers. `build`: only sessions of that PlaceVersion.
function Report.summary(players: { Player }, now: number, build: number?)
	local visits = Report.firstVisits(players, build)
	local gone60, gone180, lengths = 0, 0, {}
	local onboarding: { [number]: number } = {}
	local ended: { [string]: number } = {}
	for _, visit in visits do
		table.insert(lengths, visit.seconds)
		if visit.seconds < 60 then
			gone60 += 1
		end
		if visit.seconds < 180 then
			gone180 += 1
		end
		local furthest = 0
		for _, player in players do
			if player.userId == visit.userId then
				for _, s in player.sessions do
					furthest = math.max(furthest, s.onboarding or 0)
				end
			end
		end
		for step = 1, furthest do
			onboarding[step] = (onboarding[step] or 0) + 1
		end
		local leave = visit.leave
		bump(ended, if leave then `{leave.doing} @ {leave.stage}` else "unknown")
	end

	local devices, fps, trips, honeycomb = {}, {}, {}, {}
	local pace: { [string]: { number } } = {}
	local errorPlayers: { [string]: { [number]: boolean } } = {}
	local sessions = 0
	for _, player in players do
		for _, s in inBuild(player.sessions, build) do
			sessions += 1
			bump(devices, s.device)
			if type(s.fps) == "number" then
				bump(fps, Analytics.bucket(Analytics.BANDS.fps, s.fps))
			end
			for _, kind in { "errors", "warnings" } do
				for _, row in s[kind] or {} do
					local key = if kind == "warnings" then `(warn) {row.text}` else row.text
					errorPlayers[key] = errorPlayers[key] or {}
					errorPlayers[key][player.userId] = true
				end
			end
			for _, entry in s.trail or {} do
				local f = entry.f or {}
				if entry.k == "event" and entry.s == "TripEnd" then
					bump(trips, f.Outcome)
				elseif entry.k == "event" and (entry.s == "GateOpened" or entry.s == "Milestone") then
					local key = f.Area or f.Milestone
					if key then
						pace[key] = pace[key] or {}
						table.insert(pace[key], entry.v)
					end
				elseif entry.k == "step" and type(entry.s) == "string" then
					local step = entry.s:match("^Honeycomb_v1:(%w+)$")
					bump(honeycomb, step)
				end
			end
		end
	end
	local errors = {}
	for text, who in errorPlayers do
		local n = 0
		for _ in who do
			n += 1
		end
		errors[text] = n
	end

	local n = #visits
	return {
		players = #players,
		sessions = sessions,
		newPlayers = n,
		firstMedian = median(lengths),
		gone60 = if n > 0 then gone60 / n else 0,
		gone180 = if n > 0 then gone180 / n else 0,
		d1 = retention(players, visits, now, DAY, 2 * DAY),
		d7 = retention(players, visits, now, 7 * DAY, 8 * DAY),
		onboarding = onboarding,
		ended = ended,
		devices = devices,
		fps = fps,
		trips = trips,
		honeycomb = honeycomb,
		pace = pace,
		errors = errors,
	}
end

local function percent(part: number, whole: number): string
	return if whole > 0 then `{math.round(part / whole * 100)}%` else "-"
end

-- A count map as lines, largest first.
local function ranked(map: { [string]: number }, total: number?): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return if map[a] == map[b] then a < b else map[a] > map[b]
	end)
	local lines = {}
	for _, key in keys do
		table.insert(lines, `  {map[key]}{if total then ` ({percent(map[key], total)})` else ""}  {key}`)
	end
	return lines
end

function Report.format(s): string
	local out = {}
	local function add(line: string)
		table.insert(out, line)
	end
	local n = s.newPlayers
	add(`{s.players} players, {s.sessions} sessions, {n} first visits`)
	add("")
	add("== First visits (what Roblox ranks on)")
	add(`  median length: {if s.firstMedian then `{math.round(s.firstMedian)} s` else "-"}`)
	add(`  gone within 60 s: {percent(s.gone60 * n, n)}   gone within 180 s: {percent(s.gone180 * n, n)}`)
	add(`  day-1 return: {s.d1.returned}/{s.d1.eligible} ({percent(s.d1.returned, s.d1.eligible)})   day-7 return: {s.d7.returned}/{s.d7.eligible} ({percent(s.d7.returned, s.d7.eligible)})`)
	add("")
	add("== Onboarding reach (new players)")
	for i, name in Analytics.ONBOARDING do
		local reached = s.onboarding[i] or 0
		add(`  {i}. {name}: {reached} ({percent(reached, n)})`)
	end
	add("")
	add("== Where first visits ended (doing @ stage)")
	for _, line in ranked(s.ended, n) do
		add(line)
	end
	add("")
	add("== Devices (sessions)")
	for _, line in ranked(s.devices) do
		add(line)
	end
	add("== Frame rate bands (sessions)")
	for _, line in ranked(s.fps) do
		add(line)
	end
	add("")
	add("== Trips (TripEnd by outcome)")
	for _, line in ranked(s.trips) do
		add(line)
	end
	add("== Honeycomb (Opened -> Viewed -> Bought)")
	add(`  {s.honeycomb.Opened or 0} -> {s.honeycomb.Viewed or 0} -> {s.honeycomb.Bought or 0}`)
	add("")
	add("== Pace (median minutes of the run's play; compare lune run tools/simulate)")
	local keys = {}
	for key in s.pace do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		local na, nb = tonumber(a:match("%d+")) or 0, tonumber(b:match("%d+")) or 0
		return if a:sub(1, 1) == b:sub(1, 1) then na < nb else a < b
	end)
	for _, key in keys do
		add(`  {key}: {math.round(median(s.pace[key]) :: number)} min ({#s.pace[key]} runs)`)
	end
	add("")
	add("== Errors and warnings (players who met them)")
	for _, line in ranked(s.errors) do
		add(line)
	end
	return table.concat(out, "\n")
end

-- A unix time as "YYYY-MM-DD hh:mm" (UTC).
local function date(at: number): string
	local days = math.floor(at / DAY)
	local rest = at - days * DAY
	-- days since 1970-01-01 to a civil date (Howard Hinnant's algorithm)
	local z = days + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	local y = yoe + era * 400 + (if m <= 2 then 1 else 0)
	return string.format("%04d-%02d-%02d %02d:%02d", y, m, d, math.floor(rest / 3600), math.floor(rest % 3600 / 60))
end

local function clock(t: number): string
	return string.format("%3d:%02d", math.floor(t / 60), math.floor(t % 60))
end

-- One player's whole story, session by session, minute by minute.
function Report.story(player: Player): string
	local out = { `Player {player.userId}` }
	for _, s in sorted(player.sessions) do
		local leave = s.leave or {}
		table.insert(out, "")
		table.insert(out, `# {date(s.at)} UTC  {s.place}  build {s.build}  {math.round(s.seconds or 0)} s{if s.new then "  FIRST" else ""}  left: {s.left or "?"} ({leave.doing or "?"} @ {leave.stage or "?"})`)
		local facts = {}
		for _, key in { "device", "fps", "load", "onboarding" } do
			if s[key] ~= nil then
				table.insert(facts, `{key}={s[key]}`)
			end
		end
		if #facts > 0 then
			table.insert(out, `  {table.concat(facts, "  ")}`)
		end
		for _, entry in s.trail or {} do
			local fields = {}
			for key, value in entry.f or {} do
				table.insert(fields, `{key}={value}`)
			end
			table.sort(fields)
			local value = if entry.v ~= nil then ` {math.round(entry.v * 100) / 100}` else ""
			table.insert(out, `  {clock(entry.t or 0)}  {entry.k} {entry.s or ""}{value} {table.concat(fields, " ")}`)
		end
		if (s.dropped or 0) > 0 then
			table.insert(out, `  ({s.dropped} filler rows dropped)`)
		end
		for _, kind in { "errors", "warnings" } do
			for _, row in s[kind] or {} do
				table.insert(out, `  {kind}: {row.text} (x{row.n})`)
			end
		end
	end
	return table.concat(out, "\n")
end

return Report
