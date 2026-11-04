-- Saved player progress (server only). Written once per finished run with an atomic UpdateAsync,
-- read by the lobby. No session lock: nothing holds the data between calls, and nothing ever saves
-- after a failed load. Every failure is retried, then reported to the caller and the Output.
local DataStoreService = game:GetService("DataStoreService")

local Difficulty = require(script.Parent.Difficulty)
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

-- Adds a finished run. Returns the new progress, or nil and an error.
function PlayerData.addRun(userId: number, raindrops: number, difficulty: number): (Progress.Data?, string?)
	local saved: Progress.Data? = nil
	local ok, result = Retry.run(`save run {userId}`, function()
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getStore():UpdateAsync(key(userId), function(old)
			saved = Progress.applyRun(old, raindrops, difficulty, Difficulty.MAX)
			return saved
		end)
	end)
	if not ok then
		return nil, tostring(result)
	end
	return saved, nil
end

return PlayerData
