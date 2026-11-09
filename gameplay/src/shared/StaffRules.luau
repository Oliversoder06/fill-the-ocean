--!strict
-- Staff maths (Config.items kind "staff", Config.staff; server/Staff, client/Staff, client/Shop):
-- where each job may work, its output, pay, the work bonus and the Staff attribute. Pure: config is
-- passed in, so Lune tests and Roblox load it the same way.

export type Entry = { id: string, hires: number, post: number } -- post 0: nowhere to work yet

local StaffRules = {}

-- The area ids staff `item` may work at: a Helper or Lifeguard ("area") any area the owner reaches
-- (`reachable`: Items.reachable), a Firefighter ("truck") the area of each owned vehicle (that
-- vehicle's loop; `owned`: the owner's item ids), a Plumber ("plots") the cove, where the plots are.
function StaffRules.targets(config, item, owned: { string }, reachable: { number }): { number }
	if item.job == "area" then
		return table.clone(reachable)
	elseif item.job == "plots" then
		return { 1 }
	end
	local areas = {}
	for _, other in config.items do
		if other.kind == "vehicle" and table.find(owned, other.id) and not table.find(areas, other.area) then
			table.insert(areas, other.area)
		end
	end
	table.sort(areas)
	return areas
end

-- Where `item` works: the `assigned` post while it is still allowed, else its default (a carrier's
-- own area, else the furthest it may; a Firefighter's best vehicle; the plots). Nil: nowhere yet.
function StaffRules.post(config, item, owned: { string }, reachable: { number }, assigned: number?): number?
	local targets = StaffRules.targets(config, item, owned, reachable)
	if assigned and table.find(targets, assigned) then
		return assigned
	elseif item.job == "area" and table.find(targets, item.area) then
		return item.area
	end
	return targets[#targets]
end

-- The post after `current` in `targets` (the TAB Assign button), wrapping round; nil when none.
function StaffRules.nextPost(targets: { number }, current: number?): number?
	local i = if current then table.find(targets, current) else nil
	return targets[if i then i % #targets + 1 else 1]
end

-- Litres a second from `hires` working one `job`: carriers bring `carry` litres a trip, a
-- Firefighter its truck's `tank` (nil: no truck); a Plumber pours nothing.
function StaffRules.rate(job: string, hires: number, carry: number?, tripSeconds: number?, tank: number?): number
	if job == "area" then
		return hires * (carry :: number) / (tripSeconds :: number)
	elseif job == "truck" and tank then
		return hires * tank / (tripSeconds :: number)
	end
	return 0
end

-- Coins a staff litre pays its owner: payShare (half) of `area`'s hand pay.
function StaffRules.payPerLitre(config, area): number
	return config.ocean.coinsPerLitre * area.payMultiplier * config.staff.payShare
end

-- The output multiplier at `now` for staff at `post` whose owner last scooped or poured in area
-- `workArea` at `workedAt` (same clock): workBonus while that was this area within workSeconds.
function StaffRules.bonus(config, workArea: number, workedAt: number, post: number, now: number): number
	return if workArea == post and now - workedAt <= config.staff.workSeconds then config.staff.workBonus else 1
end

-- The team's buildings with the present, assigned Plumbers' `boosts`: the best one's scale, and
-- whether they are kept clear (any Plumber). server/Buildings.setPlumber takes both.
function StaffRules.plumber(boosts: { number }): (number, boolean)
	local scale = 1
	for _, boost in boosts do
		scale = math.max(scale, boost)
	end
	return scale, #boosts > 0
end

-- Walking speed factor near a Lifeguard's Source (`near`) or not.
function StaffRules.walkFactor(config, near: boolean): number
	return if near then config.staff.lifeguardWalk else 1
end

-- The player attribute Staff: "helper:2@2,firefighter:1@0" (id:hires@post), in the entries' order.
function StaffRules.encode(entries: { Entry }): string
	local parts = {}
	for _, e in entries do
		table.insert(parts, `{e.id}:{e.hires}@{e.post}`)
	end
	return table.concat(parts, ",")
end

-- The entries of a Staff attribute value (anything else, or broken entries, give none).
function StaffRules.decode(text: any): { Entry }
	local entries = {}
	if type(text) ~= "string" then
		return entries
	end
	for part in text:gmatch("[^,]+") do
		local id, hires, post = part:match("^([%w_]+):(%d+)@(%d+)$")
		if id then
			table.insert(entries, { id = id, hires = tonumber(hires) :: number, post = tonumber(post) :: number })
		end
	end
	return entries
end

return StaffRules
