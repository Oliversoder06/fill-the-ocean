--!strict
-- Saved player progress and how a finished run changes it. Pure: Lune-tested.
-- PlayerData does the DataStore calls; this module only decides the numbers.

export type Data = { raindrops: number, unlocked: number, runs: number }

local Progress = {}

function Progress.default(): Data
	return { raindrops = 0, unlocked = 1, runs = 0 }
end

-- Fills in missing or broken fields so old or partial saves still load.
function Progress.sanitize(raw: any): Data
	local data = Progress.default()
	if type(raw) == "table" then
		if type(raw.raindrops) == "number" and raw.raindrops >= 0 then
			data.raindrops = math.floor(raw.raindrops)
		end
		if type(raw.unlocked) == "number" then
			data.unlocked = math.max(1, math.floor(raw.unlocked))
		end
		if type(raw.runs) == "number" and raw.runs >= 0 then
			data.runs = math.floor(raw.runs)
		end
	end
	return data
end

-- A finished run: add the Raindrops, count the run, and unlock the next difficulty if the player
-- beat their highest one. Returns a new table.
function Progress.applyRun(raw: any, raindrops: number, difficulty: number, maxDifficulty: number): Data
	local data = Progress.sanitize(raw)
	data.raindrops += math.max(0, math.floor(raindrops))
	data.runs += 1
	if difficulty >= data.unlocked then
		data.unlocked = math.min(maxDifficulty, difficulty + 1)
	end
	return data
end

return Progress
