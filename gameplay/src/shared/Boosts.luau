--!strict
-- Fill-milestone boosts (Config.boosts): which milestone a pour crossed, and what a boost does to a
-- player's stats. Pure: config is passed in.

local Boosts = {}

-- The last milestone index passed going from `before` to `after` (fill fractions), or nil.
function Boosts.crossed(milestones: { number }, before: number, after: number): number?
	local found = nil
	for i, m in milestones do
		if before < m and after >= m then
			found = i
		end
	end
	return found
end

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
