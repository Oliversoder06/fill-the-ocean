--!strict
-- The session record: the second analytics sink, the raw rows Roblox never gives you (docs/analytics.md).
-- Each player's last MAX_SESSIONS place visits, kept in their own DataStore key (TelemetryCore), one
-- write per visit as they leave. A session holds when, how long, the build (PlaceVersion: the only way
-- to say whether a release helped), whether it was their first, what they were doing as they left,
-- counts, their client's errors and warnings, and a trail: every funnel step, event and money move
-- in order. Pure: no requires, so Lune tests it.

local Record = {}

Record.FORMAT = 1 -- bump whenever a field changes meaning, so readers can tell old sessions from new
Record.MAX_SESSIONS = 25
Record.TRAIL_MAX = 400 -- rows per session; past it the first TRAIL_FIRST and every milestone stay
Record.TRAIL_FIRST = 40
Record.TEXTS_MAX = 5 -- distinct errors and warnings per session, each

-- t: seconds into the session; k: "step", "event", "money", "flag"; s: what (funnel:step, event name,
-- money reason); v: its value; f: its fields; m: a milestone, never dropped while filler is left.
export type Entry = { t: number, k: string, s: string?, v: number?, f: { [string]: string }?, m: boolean? }
export type Text = { text: string, n: number }
export type Session = {
	format: number,
	at: number, -- os.time() it started
	build: number,
	place: string, -- "Lobby" / "Run"
	new: boolean, -- their first session ever
	seconds: number,
	trail: { Entry },
	dropped: number, -- trail rows cut past TRAIL_MAX
	counts: { [string]: number },
	errors: { Text },
	warnings: { Text },
	[string]: any, -- the place's facts (device, fps, load, leave, onboarding, progress...)
}
export type Record = { format: number, sessions: { Session } }

export type SessionFacts = { at: number, build: number, place: string, new: boolean }

function Record.newSession(facts: SessionFacts): Session
	return {
		format = Record.FORMAT,
		at = facts.at,
		build = facts.build,
		place = facts.place,
		new = facts.new,
		seconds = 0,
		trail = {},
		dropped = 0,
		counts = {},
		errors = {},
		warnings = {},
	}
end

-- Adds 1 (or `by`) to a count.
function Record.count(session: Session, name: string, by: number?)
	session.counts[name] = (session.counts[name] or 0) + (by or 1)
end

-- Appends a trail row. Past TRAIL_MAX the oldest filler after the first TRAIL_FIRST rows goes; only
-- when none is left does the oldest milestone after them go.
function Record.add(session: Session, entry: Entry)
	local trail = session.trail
	table.insert(trail, entry)
	if #trail <= Record.TRAIL_MAX then
		return
	end
	local cut = Record.TRAIL_FIRST + 1
	for i = Record.TRAIL_FIRST + 1, #trail do
		if not trail[i].m then
			cut = i
			break
		end
	end
	table.remove(trail, cut)
	session.dropped += 1
end

-- Keeps `text` in `list` (errors or warnings): each distinct text once with how often it came, at
-- most TEXTS_MAX of them.
function Record.text(list: { Text }, text: string)
	for _, row in list do
		if row.text == text then
			row.n += 1
			return
		end
	end
	if #list < Record.TEXTS_MAX then
		table.insert(list, { text = text, n = 1 })
	end
end

-- A stored record, repaired: sessions that aren't tables with a trail are dropped.
function Record.sanitize(raw: any): Record
	local record: Record = { format = Record.FORMAT, sessions = {} }
	if type(raw) == "table" and type(raw.sessions) == "table" then
		for _, session in raw.sessions do
			if type(session) == "table" and type(session.trail) == "table" and type(session.at) == "number" then
				table.insert(record.sessions, session)
			end
		end
	end
	return record
end

-- Adds a finished session; the oldest go past MAX_SESSIONS. Returns a new record.
function Record.push(raw: any, session: Session): Record
	local record = Record.sanitize(raw)
	table.insert(record.sessions, session)
	while #record.sessions > Record.MAX_SESSIONS do
		table.remove(record.sessions, 1)
	end
	return record
end

-- Makes a record smaller (too big for its DataStore key): cuts half the trail of the oldest session
-- that still has one, from its end. False when no trail is left to cut.
function Record.shrink(record: Record): boolean
	for _, session in record.sessions do
		local trail = session.trail
		if #trail > 0 then
			local cut = math.ceil(#trail / 2)
			for _ = 1, cut do
				table.remove(trail)
			end
			session.dropped = (session.dropped or 0) + cut
			return true
		end
	end
	return false
end

return Record
