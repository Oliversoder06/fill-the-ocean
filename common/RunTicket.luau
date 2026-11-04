-- Run tickets (server only). The lobby writes {difficulty, members} under the reserved server id it
-- generated, then teleports the party with that id. The gameplay server reads it with
-- game.PrivateServerId. Teleport data from clients is never trusted for this.
local MemoryStoreService = game:GetService("MemoryStoreService")
local Retry = require(script.Parent.Retry)

local MAP_NAME = "RunTickets_v1"
local TTL_SECONDS = 900

export type Ticket = { difficulty: number, members: { number } }

local RunTicket = {}

local map: MemoryStoreHashMap? = nil

local function getMap(): MemoryStoreHashMap
	if not map then
		map = MemoryStoreService:GetHashMap(MAP_NAME)
	end
	return map :: MemoryStoreHashMap
end

function RunTicket.write(serverId: string, ticket: Ticket): (boolean, string?)
	local ok, err = Retry.run(`write {serverId}`, function()
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		getMap():SetAsync(serverId, ticket, TTL_SECONDS)
	end)
	return ok, if ok then nil else tostring(err)
end

-- Returns the ticket, nil if none exists, or nil plus an error if MemoryStore failed.
function RunTicket.read(serverId: string): (Ticket?, string?)
	local ok, result = Retry.run(`read {serverId}`, function()
		-- lihfolk-ignore: datastore-no-pcall (runs inside Retry.run, which pcalls with backoff)
		return getMap():GetAsync(serverId)
	end)
	if not ok then
		return nil, tostring(result)
	end
	if type(result) ~= "table" or type(result.difficulty) ~= "number" or type(result.members) ~= "table" then
		return nil, nil
	end
	return result :: Ticket, nil
end

return RunTicket
