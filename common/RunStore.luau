-- Team runs (server only). Saves live in a DataStore under RunSave.key and are written only by the
-- gameplay server, with UpdateAsync. A run is open in one server at a time: the server that plays it
-- holds a lock in the MemoryStore map RunLocks_v1 (90 s TTL) and calls lock again every
-- RENEW_SECONDS to renew it; a crashed server's lock simply expires. Every failure is retried, then
-- reported to the caller and the Output.
-- The lobby never saves a run; it only erases one (RunStore.erase), and only while it holds the lock.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")

local Retry = require(script.Parent.Retry)
local RunSave = require(script.Parent.RunSave)

local STORE_NAME = "TeamRuns_v1"
local LOCK_MAP = "RunLocks_v1"
local RELEASE_SECONDS = 1 -- unlock shortens the holder's lock to this instead of racing a remove

local RunStore = {}

RunStore.LOCK_SECONDS = 90
RunStore.RENEW_SECONDS = 30

local store: DataStore? = nil
local locks: MemoryStoreHashMap? = nil

local function getStore(): DataStore
	if not store then
		store = DataStoreService:GetDataStore(STORE_NAME)
	end
	return store :: DataStore
end

local function getLocks(): MemoryStoreHashMap
	if not locks then
		locks = MemoryStoreService:GetHashMap(LOCK_MAP)
	end
	return locks :: MemoryStoreHashMap
end

-- Returns the save, nil if there is none yet, or nil plus an error. A stored value that can't be
-- read as a save is an error, not "none": treating it as empty would let a fresh run overwrite it.
function RunStore.load(key: string): (RunSave.Save?, string?)
	local ok, result = Retry.run(`load run {key}`, function()
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getStore():GetAsync(key)
	end)
	if not ok then
		return nil, tostring(result)
	end
	if result == nil then
		return nil, nil
	end
	local save = RunSave.sanitize(result)
	if not save then
		return nil, `run {key} is stored but unreadable`
	end
	return save, nil
end

-- Writes the save unless the stored one is newer (a higher updatedAt), so a late write from an old
-- session can't roll the run back. The members are tagged on the key (privacy deletion requests).
-- Returns ok plus an error.
function RunStore.save(key: string, save: RunSave.Save): (boolean, string?)
	local storedAt: number? = nil
	local ok, result = Retry.run(`save run {key}`, function()
		storedAt = nil
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getStore():UpdateAsync(key, function(old)
			if type(old) == "table" and type(old.updatedAt) == "number" and old.updatedAt > save.updatedAt then
				storedAt = old.updatedAt
				return nil -- cancels the write
			end
			return save, save.members
		end)
	end)
	if not ok then
		return false, tostring(result)
	end
	if storedAt then
		return false, `run {key} is stored newer ({storedAt}) than this save ({save.updatedAt}); not written`
	end
	return true, nil
end

-- Takes or renews the lock for this server. Fails if another server holds it (the third result is
-- then true), or MemoryStore failed.
function RunStore.lock(key: string, serverId: string): (boolean, string?, boolean)
	local holder: string? = nil
	local ok, result = Retry.run(`lock run {key}`, function()
		holder = nil
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getLocks():UpdateAsync(key, function(current)
			if current ~= nil and current ~= serverId then
				holder = tostring(current)
				return nil -- cancels the write
			end
			return serverId
		end, RunStore.LOCK_SECONDS)
	end)
	if not ok then
		return false, tostring(result), false
	end
	if holder then
		return false, `run {key} is open in another server ({holder})`, true
	end
	return true, nil, false
end

-- Releases this server's lock (a lock another server holds is left alone). Returns ok plus an error.
function RunStore.unlock(key: string, serverId: string): (boolean, string?)
	local ok, result = Retry.run(`unlock run {key}`, function()
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getLocks():UpdateAsync(key, function(current)
			if current ~= serverId then
				return nil -- not ours (or already gone): leave it
			end
			return serverId
		end, RELEASE_SECONDS)
	end)
	return ok, if ok then nil else tostring(result)
end

-- Erases a run from the lobby (New Game, Delete, an admin's profile reset): a blank save of the same
-- map and team (RunSave.blank) replaces it. Only while this call holds the run's lock, so no gameplay
-- server has it open or opens it during the write; the blank's newer updatedAt also makes
-- RunStore.save refuse an older write. A run that isn't stored is left alone; one that can't be read
-- is not overwritten. Returns ok, an error, and whether it failed because a server has the run open.
function RunStore.erase(key: string): (boolean, string?, boolean)
	local probe = HttpService:GenerateGUID(false)
	local locked, lockErr, open = RunStore.lock(key, probe)
	if not locked then
		return false, lockErr, open
	end
	local unreadable = false
	local ok, result = Retry.run(`erase run {key}`, function()
		unreadable = false
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getStore():UpdateAsync(key, function(old)
			if old == nil then
				return nil -- nothing stored: nothing to erase
			end
			local save = RunSave.sanitize(old)
			if not save then
				unreadable = true
				return nil
			end
			local blank = RunSave.blank(save, os.time())
			return blank, blank.members
		end)
	end)
	local released, unlockErr = RunStore.unlock(key, probe)
	if not released then
		warn(`[RunStore] couldn't release the erase lock on {key}: {unlockErr}; it runs out in {RunStore.LOCK_SECONDS} s`)
	end
	if not ok then
		return false, tostring(result), false
	end
	if unreadable then
		return false, `run {key} is stored but unreadable; not erased`, false
	end
	return true, nil, false
end

return RunStore
