--!strict
-- The maps: their difficulty numbers and what unlocks them. Pure: Lune-tested.
-- waterMultiplier scales the ocean's target; rewardRaindrops are paid to each member on a clear.

export type Map = {
	id: string,
	name: string,
	waterMultiplier: number,
	rewardRaindrops: number,
	unlockedBy: string?, -- the map that must be cleared first; nil = always open
}

local Maps = {}

Maps.list = {
	{ id = "map1", name = "The Ocean", waterMultiplier = 1, rewardRaindrops = 100, unlockedBy = nil },
	{ id = "map2", name = "Map 2 (placeholder)", waterMultiplier = 1.6, rewardRaindrops = 200, unlockedBy = "map1" },
} :: { Map }

-- id may be anything (a ticket or attribute value); only a listed map's id returns a map.
function Maps.get(id: any): Map?
	for _, map in Maps.list do
		if map.id == id then
			return map
		end
	end
	return nil
end

-- mapsCleared is Progress's set of cleared map ids. An unknown map is never unlocked.
function Maps.unlocked(mapsCleared: { [string]: boolean }, id: string): boolean
	local map = Maps.get(id)
	if not map then
		return false
	end
	return map.unlockedBy == nil or mapsCleared[map.unlockedBy] == true
end

return Maps
