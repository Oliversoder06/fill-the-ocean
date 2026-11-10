--!strict
-- Milestones every 5% of the ocean (Config.milestones, D9): which ones a change of fill passed, what
-- each gives, the run's reached set (save.milestones: indices, in order, each once) and the
-- Milestone attribute. Decides when; shared/Boosts keeps what a boost does. Pure: config is passed in.

local Milestones = {}

-- Every milestone passed going from `before` to `after` (fill fractions), in order. Water going down
-- (an admin reset) passes none.
function Milestones.crossed(config, before: number, after: number): { number }
	local passed = {}
	for i, m in config.milestones do
		if before < m.fill and after >= m.fill then
			table.insert(passed, i)
		end
	end
	return passed
end

-- The milestones at or below `fill`: what a save from before milestones has reached (never granted).
function Milestones.reachedBy(config, fill: number): { number }
	return Milestones.crossed(config, -math.huge, fill)
end

-- Adds every milestone passed from `before` to `after` that `reached` doesn't hold yet to it (kept
-- in order) and returns those: each is granted once per run.
function Milestones.reach(config, reached: { number }, before: number, after: number): { number }
	local new = {}
	for _, i in Milestones.crossed(config, before, after) do
		if not table.find(reached, i) then
			table.insert(reached, i)
			table.insert(new, i)
		end
	end
	table.sort(reached)
	return new
end

-- The milestone at `index`. Errors on anything else.
function Milestones.reward(config, index: number)
	local m = config.milestones[index]
	assert(m, `unknown milestone {index}`)
	return m
end

-- The cove decorations (Revive.M<n>) the `reached` milestones brought back, in that order.
function Milestones.revived(config, reached: { number }): { number }
	local list = {}
	for _, i in reached do
		local n = Milestones.reward(config, i).revive
		if n then
			table.insert(list, n)
		end
	end
	return list
end

-- The Raindrops the `reached` milestones pay (index -> Raindrops), leaving out `skipped` (those an old
-- save was marked as having reached without granting them).
function Milestones.raindrops(config, reached: { number }, skipped: { number }): { [number]: number }
	local pay = {}
	for _, i in reached do
		local amount = Milestones.reward(config, i).raindrops
		if amount and not table.find(skipped, i) then
			pay[i] = amount
		end
	end
	return pay
end

-- The team's toast: "5% — The old rowboat floats again! 2X COINS for 30 s". Nil for the ending.
function Milestones.card(config, index: number): string?
	local m = Milestones.reward(config, index)
	if m.ending then
		return nil
	end
	local tag = nil
	for _, kind in config.boosts.kinds do
		if kind.id == m.boost then
			tag = kind.tag
		end
	end
	assert(tag, `milestone {index}: unknown boost {m.boost}`)
	local raindrops = if m.raindrops then `+{m.raindrops} Raindrops, ` else ""
	return `{math.round(m.fill * 100)}% — {m.text} {raindrops}{tag} for {config.boosts.seconds} s`
end

-- The ReplicatedStorage Milestone attribute: "<index>@<serverTime>".
function Milestones.encode(index: number, at: number): string
	return `{index}@{at}`
end

function Milestones.decode(text: any): (number?, number?)
	if type(text) ~= "string" then
		return nil, nil
	end
	local index, at = text:match("^(%d+)@(.+)$")
	local i, t = tonumber(index), tonumber(at)
	if not (i and t) then
		return nil, nil
	end
	return i, t
end

return Milestones
