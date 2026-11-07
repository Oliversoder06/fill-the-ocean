--!strict
-- Who may play in this gameplay server. Pure: Lune-tested; Run passes in the facts and
-- getMap (common/Maps.get, which returns nil for an unknown map id).
--   test   Studio play test: anyone, map from the StudioMap attribute (default map1).
--   party  a reserved server the lobby made: only the ticket's members, ticket's map.
--   closed anything else (a public or VIP server, a reserved server without a ticket or with a
--          ticket for an unknown map): nobody plays here; everyone is sent to the lobby. Covers
--          joining a friend into the gameplay place and any direct link to it.

export type Input = {
	isStudio: boolean,
	privateServerId: string,
	privateServerOwnerId: number,
	ticket: { mapId: any, members: { any } }?,
	studioMap: any?,
}

export type State = {
	mode: "test" | "party" | "closed",
	mapId: string,
	members: { [number]: boolean },
	expected: number,
}

local DEFAULT_MAP = "map1"

local Session = {}

function Session.decide(input: Input, getMap: (any) -> any?): State
	if input.isStudio then
		local mapId = if getMap(input.studioMap) then input.studioMap else DEFAULT_MAP
		return { mode = "test", mapId = mapId, members = {}, expected = 0 }
	end
	local reserved = input.privateServerId ~= "" and input.privateServerOwnerId == 0
	local ticket = input.ticket
	-- an unknown map can't be played, and falling back to another would load the wrong save
	if not reserved or not ticket or not getMap(ticket.mapId) then
		return { mode = "closed", mapId = DEFAULT_MAP, members = {}, expected = 0 }
	end
	local members, expected = {}, 0
	for _, userId in ticket.members do
		if type(userId) == "number" and not members[userId] then
			members[userId] = true
			expected += 1
		end
	end
	return { mode = "party", mapId = ticket.mapId, members = members, expected = expected }
end

function Session.admits(state: State, userId: number): boolean
	if state.mode == "test" then
		return true
	end
	return state.mode == "party" and state.members[userId] == true
end

return Session
