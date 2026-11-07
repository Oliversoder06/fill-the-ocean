--!strict
-- A player's saved progress: Raindrops, their saved-run keys (newest first) and the maps they
-- cleared. Pure: Lune-tested. PlayerData does the DataStore calls; this module only decides the data.

export type Data = { raindrops: number, runs: { string }, mapsCleared: { [string]: boolean } }

local Progress = {}

-- Owner decision D5: no expiry, at most this many saved runs per player; the oldest drops off.
Progress.MAX_RUNS = 10

function Progress.default(): Data
	return { raindrops = 0, runs = {}, mapsCleared = {} }
end

-- Fills in missing or broken fields so old or partial saves still load. Unknown fields (such as
-- the old difficulty `unlocked`) are dropped.
function Progress.sanitize(raw: any): Data
	local data = Progress.default()
	if type(raw) == "table" then
		if type(raw.raindrops) == "number" and raw.raindrops >= 0 then
			data.raindrops = math.floor(raw.raindrops)
		end
		if type(raw.runs) == "table" then
			for _, key in raw.runs do
				if #data.runs >= Progress.MAX_RUNS then
					break
				end
				if type(key) == "string" and key ~= "" and not table.find(data.runs, key) then
					table.insert(data.runs, key)
				end
			end
		end
		if type(raw.mapsCleared) == "table" then
			for mapId, cleared in raw.mapsCleared do
				if type(mapId) == "string" and cleared == true then
					data.mapsCleared[mapId] = true
				end
			end
		end
	end
	return data
end

-- A run the player is in: its key goes first (moved there if already listed), and the oldest
-- drops off past MAX_RUNS. Returns a new table.
function Progress.addRun(raw: any, key: string): Data
	local data = Progress.removeRun(raw, key)
	table.insert(data.runs, 1, key)
	while #data.runs > Progress.MAX_RUNS do
		table.remove(data.runs)
	end
	return data
end

-- The player left that run ("Leave run" on the Saved Runs card). Returns a new table.
function Progress.removeRun(raw: any, key: string): Data
	local data = Progress.sanitize(raw)
	local at = table.find(data.runs, key)
	if at then
		table.remove(data.runs, at)
	end
	return data
end

-- The ocean of mapId was filled: add the Raindrops and mark the map cleared. Returns a new table.
function Progress.clearMap(raw: any, mapId: string, raindrops: number): Data
	local data = Progress.sanitize(raw)
	data.raindrops += math.max(0, math.floor(raindrops))
	data.mapsCleared[mapId] = true
	return data
end

return Progress
