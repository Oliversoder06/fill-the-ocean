-- Reads the session records (common/AnalyticsRecord, DataStore AnalyticsSessions_v1) through Open
-- Cloud and prints the report (tools/AnalyticsReport). Run from gameplay/, a day after every release:
--   lune run tools/analytics                  every player's records
--   lune run tools/analytics --build 412      only sessions on that PlaceVersion
--   lune run tools/analytics player 12345     one player's whole story
--   lune run tools/analytics errors           server errors and warnings per place and build
--   add --studio to read the Studio test store, --limit N to read at most N players
-- Needs ROBLOX_API_KEY_DATASTORE: an Open Cloud key with DataStore list and read on this experience.
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Places = require("../../common/Places")
local Report = require("./AnalyticsReport")

local STORE = "AnalyticsSessions_v1"
local PACE = 0.25 -- seconds between reads (Open Cloud rate limits)

local args = process.args
local function flag(name: string): string?
	local at = table.find(args, name)
	return if at then args[at + 1] else nil
end

local key = process.env.ROBLOX_API_KEY_DATASTORE
if not key or key == "" then
	error("set ROBLOX_API_KEY_DATASTORE (an Open Cloud API key with DataStore list and read on this experience)", 0)
end
local store = if table.find(args, "--studio") then `{STORE}_Studio` else STORE
local build = tonumber(flag("--build"))
local limit = tonumber(flag("--limit")) or math.huge

local function get(url: string): any
	local response = net.request({ url = url, method = "GET", headers = { ["x-api-key"] = key :: string } })
	if not response.ok then
		error(`GET {url} failed: {response.statusCode} {response.body}`, 0)
	end
	return serde.decode("json", response.body)
end

local universe = get(`https://apis.roblox.com/universes/v1/places/{Places.GAMEPLAY}/universe`).universeId
assert(type(universe) == "number", "couldn't read the experience's universe id")
local base = `https://apis.roblox.com/datastores/v1/universes/{universe}/standard-datastores/datastore`

-- Every key in the store starting with `prefix`.
local function keys(prefix: string): { string }
	local list, cursor = {}, nil
	repeat
		local url = `{base}/entries?datastoreName={net.urlEncode(store)}&prefix={net.urlEncode(prefix)}&limit=100`
		if cursor then
			url ..= `&cursor={net.urlEncode(cursor)}`
		end
		local page = get(url)
		for _, entry in page.keys or {} do
			table.insert(list, entry.key)
		end
		cursor = if page.nextPageCursor and page.nextPageCursor ~= "" then page.nextPageCursor else nil
		task.wait(PACE)
	until not cursor or #list >= limit
	return list
end

local function entry(name: string): any
	task.wait(PACE)
	return get(`{base}/entries/entry?datastoreName={net.urlEncode(store)}&entryKey={net.urlEncode(name)}`)
end

local function player(userId: number): Report.Player
	local record = entry(`u_{userId}`)
	return { userId = userId, sessions = if type(record) == "table" then record.sessions or {} else {} }
end

if args[1] == "player" then
	local userId = tonumber(args[2])
	assert(userId, "usage: lune run tools/analytics player <userId>")
	print(Report.story(player(userId)))
	return
end

if args[1] == "errors" then
	for _, name in keys("errors_") do
		print(`== {name}`)
		local counts = entry(name)
		local lines = {}
		for text, n in counts do
			table.insert(lines, { text = text, n = n })
		end
		table.sort(lines, function(a, b)
			return a.n > b.n
		end)
		for _, line in lines do
			print(`  {line.n}  {line.text}`)
		end
	end
	return
end

local players = {}
for _, name in keys("u_") do
	if #players >= limit then
		break
	end
	local userId = tonumber(name:match("^u_(%d+)$"))
	if userId then
		table.insert(players, player(userId))
	end
end
print(`{store}{if build then `, build {build}` else ""}`)
print(Report.format(Report.summary(players, os.time(), build)))
