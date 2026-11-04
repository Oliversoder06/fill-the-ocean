--!strict
-- Who may play in this gameplay server. Pure: Lune-tested; Run passes in the facts and clamp.
--   test   Studio play test: anyone, difficulty from the StudioDifficulty attribute.
--   party  a reserved server the lobby made: only the ticket's members, ticket's difficulty.
--   closed anything else (a public or VIP server, a reserved server without a ticket): nobody
--          plays here; everyone is sent to the lobby. Covers joining a friend into the
--          gameplay place and any direct link to it.

export type Input = {
	isStudio: boolean,
	privateServerId: string,
	privateServerOwnerId: number,
	ticket: { difficulty: any, members: { any } }?,
	studioDifficulty: any?,
}

export type State = {
	mode: "test" | "party" | "closed",
	difficulty: number,
	members: { [number]: boolean },
	expected: number,
}

local Session = {}

function Session.decide(input: Input, clamp: (any) -> number): State
	if input.isStudio then
		return { mode = "test", difficulty = clamp(input.studioDifficulty), members = {}, expected = 0 }
	end
	local reserved = input.privateServerId ~= "" and input.privateServerOwnerId == 0
	local ticket = input.ticket
	if not reserved or not ticket then
		return { mode = "closed", difficulty = 1, members = {}, expected = 0 }
	end
	local members, expected = {}, 0
	for _, userId in ticket.members do
		if type(userId) == "number" and not members[userId] then
			members[userId] = true
			expected += 1
		end
	end
	return { mode = "party", difficulty = clamp(ticket.difficulty), members = members, expected = expected }
end

function Session.admits(state: State, userId: number): boolean
	if state.mode == "test" then
		return true
	end
	return state.mode == "party" and state.members[userId] == true
end

return Session
