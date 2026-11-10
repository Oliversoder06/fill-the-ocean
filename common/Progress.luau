--!strict
-- A player's saved progress: Raindrops, their saved-run keys (newest first), the maps they cleared,
-- the runs whose ending paid them (each pays once) and the milestones each run paid them for (by
-- index, each once). Pure: Lune-tested. PlayerData does the DataStore calls; this module only
-- decides the data.

export type Data = {
	raindrops: number,
	runs: { string },
	mapsCleared: { [string]: boolean },
	paidRuns: { [string]: boolean },
	paidMilestones: { [string]: { number } },
}

local Progress = {}

-- Owner decision D5: no expiry, at most this many saved runs per player; the oldest drops off.
Progress.MAX_RUNS = 10

function Progress.default(): Data
	return { raindrops = 0, runs = {}, mapsCleared = {}, paidRuns = {}, paidMilestones = {} }
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
		if type(raw.paidRuns) == "table" then
			for key, paid in raw.paidRuns do
				if type(key) == "string" and key ~= "" and paid == true then
					data.paidRuns[key] = true
				end
			end
		end
		if type(raw.paidMilestones) == "table" then
			for key, list in raw.paidMilestones do
				if type(key) ~= "string" or key == "" or type(list) ~= "table" then
					continue
				end
				local indices = {}
				for _, index in list do
					if type(index) == "number" and index % 1 == 0 and index >= 1 and not table.find(indices, index) then
						table.insert(indices, index)
					end
				end
				if #indices > 0 then
					data.paidMilestones[key] = indices
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

-- The run was erased (New Game, Delete): it leaves the list and its payment, so the fresh run on the
-- same key pays when it fills. Raindrops already paid and cleared maps stay. Returns a new table.
function Progress.forgetRun(raw: any, key: string): Data
	local data = Progress.removeRun(raw, key)
	data.paidRuns[key] = nil
	data.paidMilestones[key] = nil
	return data
end

-- Has the ending of run runKey already paid this player?
function Progress.isPaid(raw: any, runKey: string): boolean
	return Progress.sanitize(raw).paidRuns[runKey] == true
end

-- Run runKey filled mapId's ocean: add the Raindrops and mark the map cleared and the run paid. A run
-- that already paid this player pays nothing again, so an ending that runs twice can't pay twice.
-- Returns a new table.
function Progress.clearMap(raw: any, mapId: string, raindrops: number, runKey: string): Data
	local data = Progress.sanitize(raw)
	if not data.paidRuns[runKey] then
		data.raindrops += math.max(0, math.floor(raindrops))
		data.paidRuns[runKey] = true
	end
	data.mapsCleared[mapId] = true
	return data
end

-- Run runKey reached milestones worth `raindrops` (by index into gameplay's Config.milestones): add
-- those this run hasn't paid this player for yet and remember them, so a milestone granted again (a
-- run reloaded from an older save) can't pay twice. Returns a new table.
function Progress.payMilestones(raw: any, runKey: string, raindrops: { [number]: number }): Data
	local data = Progress.sanitize(raw)
	local paid = data.paidMilestones[runKey] or {}
	for index, amount in raindrops do
		if not table.find(paid, index) then
			data.raindrops += math.max(0, math.floor(amount))
			table.insert(paid, index)
		end
	end
	if #paid > 0 then
		data.paidMilestones[runKey] = paid
	end
	return data
end

return Progress
