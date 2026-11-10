--!strict
-- Milestone boosts (Config.boosts): what a boost does to a player's stats. Which milestones a fill
-- change passes is shared/Milestones. Pure: config is passed in.

local Boosts = {}

function Boosts.kind(config, id: string)
	for _, kind in config.boosts.kinds do
		if kind.id == id then
			return kind
		end
	end
	return nil
end

-- A copy of `stats` with the boost applied (nil = no boost). Errors on an unknown boost id.
function Boosts.apply(config, stats, id: string?)
	local s = table.clone(stats)
	if id == nil then
		return s
	end
	local kind = Boosts.kind(config, id)
	assert(kind, `unknown boost {id}`)
	s.coinBonus *= kind.coins or 1
	s.walkSpeed *= kind.walk or 1
	if kind.oneSweep then
		s.sweeps = 1
	end
	return s
end

return Boosts
