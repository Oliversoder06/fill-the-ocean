local Session = require("../src/shared/Session")
local Maps = require("../../common/Maps")

local tests = {}

local TICKET = { mapId = "map2", key = "map2_11_22", members = { 11, 22 } }

function tests.studio_is_test_mode(t)
	local s = Session.decide({ isStudio = true, privateServerId = "", privateServerOwnerId = 0, ticket = nil }, Maps.get)
	t.expectEq(s.mode, "test")
	t.expectEq(Session.admits(s, 999), true, "anyone may test in Studio")
end

function tests.public_live_server_is_closed(t)
	-- someone reached the gameplay place without the lobby (direct join, join-a-friend, old link)
	local s = Session.decide({ isStudio = false, privateServerId = "", privateServerOwnerId = 0, ticket = nil }, Maps.get)
	t.expectEq(s.mode, "closed")
	t.expectEq(Session.admits(s, 11), false)
end

function tests.vip_private_server_is_closed(t)
	local s = Session.decide({ isStudio = false, privateServerId = "abc", privateServerOwnerId = 55, ticket = TICKET }, Maps.get)
	t.expectEq(s.mode, "closed")
end

function tests.reserved_without_ticket_is_closed(t)
	local s = Session.decide({ isStudio = false, privateServerId = "abc", privateServerOwnerId = 0, ticket = nil }, Maps.get)
	t.expectEq(s.mode, "closed")
	t.expectEq(Session.admits(s, 11), false)
end

function tests.reserved_with_ticket_admits_only_the_party(t)
	local s = Session.decide({ isStudio = false, privateServerId = "abc", privateServerOwnerId = 0, ticket = TICKET }, Maps.get)
	t.expectEq(s.mode, "party")
	t.expectEq(s.mapId, "map2")
	t.expectEq(s.expected, 2)
	t.expectEq(Session.admits(s, 11), true)
	t.expectEq(Session.admits(s, 22), true)
	t.expectEq(Session.admits(s, 33), false, "a friend who follows in is sent to the lobby")
end

function tests.ticket_with_unknown_map_is_closed(t)
	-- a ticket for a map this server doesn't know can't be played, and must not fall back to another map
	local ticket = { mapId = "map9", key = "map9_1", members = { 1 } }
	local s = Session.decide({ isStudio = false, privateServerId = "abc", privateServerOwnerId = 0, ticket = ticket }, Maps.get)
	t.expectEq(s.mode, "closed")
	t.expectEq(Session.admits(s, 1), false)
end

function tests.studio_map_from_attribute(t)
	local s = Session.decide({ isStudio = true, privateServerId = "", privateServerOwnerId = 0, ticket = nil, studioMap = "map2" }, Maps.get)
	t.expectEq(s.mapId, "map2")
end

function tests.studio_map_defaults_to_map1(t)
	local unset = Session.decide({ isStudio = true, privateServerId = "", privateServerOwnerId = 0, ticket = nil }, Maps.get)
	t.expectEq(unset.mapId, "map1", "no StudioMap attribute")
	local unknown = Session.decide({ isStudio = true, privateServerId = "", privateServerOwnerId = 0, ticket = nil, studioMap = "map9" }, Maps.get)
	t.expectEq(unknown.mapId, "map1", "an unknown StudioMap")
end

return tests
