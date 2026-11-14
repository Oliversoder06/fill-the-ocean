local Maps = require("../../common/Maps")

local tests = {}

function tests.map1_is_always_unlocked(t)
	t.expectEq(Maps.unlocked({}, "map1"), true, "a new player")
	t.expectEq(Maps.unlocked({ map2 = true }, "map1"), true)
end

function tests.map2_needs_map1_cleared(t)
	t.expectEq(Maps.unlocked({}, "map2"), false, "nothing cleared")
	t.expectEq(Maps.unlocked({ map2 = true }, "map2"), false, "clearing map2 itself doesn't count")
	t.expectEq(Maps.unlocked({ map1 = true }, "map2"), true)
end

function tests.coming_soon_maps_are_never_playable(t)
	t.expectEq(Maps.get("map2").comingSoon, true)
	t.expectEq(Maps.playable({}, "map1"), true, "a new player")
	t.expectEq(Maps.playable({}, "map2"), false, "locked and coming soon")
	t.expectEq(Maps.playable({ map1 = true }, "map2"), false, "unlocked, but coming soon")
	t.expectEq(Maps.playable({ map1 = true }, "map9"), false, "an unknown map")
end

function tests.unknown_map_is_nil(t)
	t.expectEq(Maps.get("map1").id, "map1")
	t.expectEq(Maps.get("map2").unlockedBy, "map1")
	t.expectEq(Maps.get("map9"), nil)
	t.expectEq(Maps.get(nil), nil)
	t.expectEq(Maps.get(1), nil)
	t.expectEq(Maps.unlocked({ map1 = true }, "map9"), false, "an unknown map is never unlocked")
end

function tests.unlockers_are_real_maps(t)
	for _, map in Maps.list do
		if map.unlockedBy ~= nil then
			t.expectEq(Maps.get(map.unlockedBy) ~= nil, true, `{map.id} is unlocked by a map that exists`)
		end
	end
end

return tests
