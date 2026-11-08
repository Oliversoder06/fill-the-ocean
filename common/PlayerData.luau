-- Saved player progress (server only): Raindrops, saved-run keys and cleared maps (Progress).
-- Every write is one atomic UpdateAsync. No session lock: nothing holds the data between calls,
-- and nothing ever saves after a failed load. Every failure is retried, then reported to the caller
-- and the Output.
local DataStoreService = game:GetService("DataStoreService")

local Progress = require(script.Parent.Progress)
local Retry = require(script.Parent.Retry)

local STORE_NAME = "PlayerProgress_v1"

local PlayerData = {}

local store: DataStore? = nil

local function getStore(): DataStore
	if not store then
		store = DataStoreService:GetDataStore(STORE_NAME)
	end
	return store :: DataStore
end

local function key(userId: number): string
	return `u_{userId}`
end

-- Runs fn with retries and backoff; returns ok and the result or the last error.
-- Returns the player's progress, or nil and an error if the DataStore can't be reached.
function PlayerData.load(userId: number): (Progress.Data?, string?)
	local ok, result = Retry.run(`load {userId}`, function()
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getStore():GetAsync(key(userId))
	end)
	if not ok then
		return nil, tostring(result)
	end
	return Progress.sanitize(result), nil
end

-- Applies one Progress change to the stored progress. Returns the new progress, or nil and an error.
local function update(userId: number, label: string, change: (any) -> Progress.Data): (Progress.Data?, string?)
	local saved: Progress.Data? = nil
	local ok, result = Retry.run(`{label} {userId}`, function()
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getStore():UpdateAsync(key(userId), function(old)
			saved = change(old)
			return saved
		end)
	end)
	if not ok then
		return nil, tostring(result)
	end
	return saved, nil
end

-- Puts a run's key first in the player's saved runs (Progress.addRun).
function PlayerData.addRun(userId: number, runKey: string): (Progress.Data?, string?)
	return update(userId, "add run", function(old)
		return Progress.addRun(old, runKey)
	end)
end

-- Takes a run off the player's saved runs ("Leave run"). The team's save itself is untouched.
function PlayerData.removeRun(userId: number, runKey: string): (Progress.Data?, string?)
	return update(userId, "remove run", function(old)
		return Progress.removeRun(old, runKey)
	end)
end

-- The player's team filled mapId's ocean in run runKey: pays the Raindrops (once per run) and marks
-- the map cleared.
function PlayerData.clearMap(userId: number, mapId: string, raindrops: number, runKey: string): (Progress.Data?, string?)
	return update(userId, "clear map", function(old)
		return Progress.clearMap(old, mapId, raindrops, runKey)
	end)
end

return PlayerData
