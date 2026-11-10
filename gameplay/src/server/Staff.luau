-- Staff (3f, D3; Config.items kind "staff", shared/StaffRules): the team's Helper, Lifeguard,
-- Firefighter and Plumber (since 2026-11-10 everything bought is the team's), hired at the Lifeguard
-- Tower (a cove shop, server/Run onStand) and levelled in TAB, where the 2nd and 3rd hire are levels.
-- Assigned in TAB by any member: Staff("assign", itemId, areaId) sets where an owned one works
-- (StaffRules.targets: an area the team reaches, an owned truck's area for a Firefighter
-- (StaffRules.truck: never the flying bomber), the cove's plots for a Plumber), kept in the team's
-- `assign` (saved by server/Run). Unassigned, or no longer allowed, they work their default post
-- (StaffRules.post).
-- No bodies here (client/Staff draws them): every TICK while the run plays with a member present (D4),
-- the staff pour StaffRules.rate litres a second into the ocean (hooks.fill), paid into the team's
-- wallet in batches (server/Payroll) at half the hand pay of the area they work
-- (StaffRules.payPerLitre), and twice as fast while any member scooped or poured in that area within
-- Config.staff.workSeconds (state.workArea / state.workedAt, set by server/Run's onAct).
-- Lifeguards: players within Config.staff.lifeguardRadius of the Source or Pour a Lifeguard works
-- walk faster (state.nearLifeguard; server/Run applies it with the other walk factors).
-- Plumbers: the best assigned one sets server/Buildings.setPlumber for the team.
-- Published: ReplicatedStorage attribute Staff ("helper:2@2,firefighter:1@0", StaffRules.encode:
-- id:hires@post, post 0 = nowhere to work yet), read by client/Staff and client/Shop.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local StaffRules = require(ReplicatedStorage.Shared.StaffRules)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Buildings = require(script.Parent.Buildings)
local Payroll = require(script.Parent.Payroll)

local TICK = 1 -- seconds between output ticks
local NEAR_TICK = 0.5 -- seconds between checks of who stands near a Lifeguard
local MAX_STAFF_PER_SECOND = 5 -- Assign presses

export type Hooks = {
	states: { [Player]: any }, -- server/Run's player states (workArea, workedAt, nearLifeguard, rate limits)
	team: () -> any, -- the team's owned, itemLevels and assign (RunSave.Team)
	playing: () -> boolean,
	openIds: () -> { number }, -- the open area ids (Areas.openIds)
	rootOf: (Player) -> BasePart?,
	allow: (any, string, number) -> boolean, -- server/Run's per-player rate limit
	fill: (number) -> number, -- pours litres into the ocean; returns the litres it took
	walkChanged: (Player) -> (), -- re-apply a player's walk speed (state.nearLifeguard changed)
}

type Hire = { item: any, hires: number, post: number? }

local Staff = {}

local ocean: Model
local hooks: Hooks
local plumbing = { scale = 1, keepClear = false }

-- The team's staff: every owned staff item, how many are hired and where they work.
local function roster(): { Hire }
	local team = hooks.team()
	local reachable = Items.reachable(Config, team, hooks.openIds())
	local list = {}
	for _, item in Config.items do
		if item.kind == "staff" and Items.owned(team, item.id) then
			local post = StaffRules.post(Config, item, team.owned, reachable, team.assign[item.id])
			table.insert(list, { item = item, hires = Items.stat(team, item, "hires"), post = post })
		end
	end
	return list
end

local function publish(list: { Hire })
	local entries = {}
	for _, hire in list do
		table.insert(entries, { id = hire.item.id, hires = hire.hires, post = hire.post or 0 })
	end
	local text = StaffRules.encode(entries)
	if ReplicatedStorage:GetAttribute("Staff") ~= text then
		ReplicatedStorage:SetAttribute("Staff", text)
	end
end

-- Litres a second a hire makes (a Firefighter: a tank of the team's truck at its post).
local function rateOf(hire: Hire): number
	local team = hooks.team()
	local item = hire.item
	local truck = if item.job == "truck" then StaffRules.truck(Config, hire.post :: number, team.owned) else nil
	local tank = if truck then Items.stat(team, truck, "tank") else nil
	local carry = if item.job == "area" then Items.stat(team, item, "carry") else nil
	return StaffRules.rate(item.job, hire.hires, carry, Items.stat(team, item, "tripSeconds"), tank)
end

-- The work bonus at `post` now: the best of every present member's (StaffRules.bonus).
local function bonusAt(post: number, now: number): number
	local bonus = 1
	for _, state in hooks.states do
		bonus = math.max(bonus, StaffRules.bonus(Config, state.workArea, state.workedAt, post, now))
	end
	return bonus
end

local function setPlumbers(boosts: { number })
	local scale, keepClear = StaffRules.plumber(boosts)
	if scale ~= plumbing.scale or keepClear ~= plumbing.keepClear then
		plumbing.scale, plumbing.keepClear = scale, keepClear
		Buildings.setPlumber(scale, keepClear)
	end
end

-- One output tick of `dt` seconds: the team's staff pour and are owed their pay, while a member is
-- present (D4).
local function tick(dt: number)
	local list = roster()
	publish(list)
	if not hooks.playing() or next(hooks.states) == nil then
		return -- D4: nothing fills while the run isn't playing or nobody is here
	end
	local now = os.clock()
	local boosts = {}
	for _, hire in list do
		local post = hire.post
		if not post then
			continue
		elseif hire.item.job == "plots" then
			table.insert(boosts, Items.stat(hooks.team(), hire.item, "boost"))
			continue
		end
		local litres = rateOf(hire) * dt * bonusAt(post, now)
		local taken = if litres > 0 then hooks.fill(litres) else 0
		if taken > 0 then
			Payroll.owe(taken * StaffRules.payPerLitre(Config, Areas.byId(Config, post)))
		end
	end
	setPlumbers(boosts)
end

-- Who stands within reach of a Source or Pour a Lifeguard works (their walk speeds up).
local function checkLifeguards()
	local watched = {}
	for _, hire in if hooks.playing() then roster() else {} do
		if hire.item.id == "lifeguard" and hire.post then
			local area = Areas.byId(Config, hire.post)
			for _, part in { Zones.areaPart(ocean, area, "Source") or false, Zones.pourPart(ocean, area) or false } do
				if part then
					table.insert(watched, part.Position)
				end
			end
		end
	end
	for player, state in hooks.states do
		local root = hooks.rootOf(player)
		local near = false
		for _, at in watched do
			near = near or (root ~= nil and (root.Position - at).Magnitude <= Config.staff.lifeguardRadius)
		end
		if near ~= state.nearLifeguard then
			state.nearLifeguard = near
			hooks.walkChanged(player)
		end
	end
end

-- Staff("assign", itemId, areaId) from client/Shop's Assign button: one of the team's staff works
-- at `areaId` from now on, if its job may work there (StaffRules.targets). Any member may move them.
local function onStaff(player: Player, action: unknown, id: unknown, areaId: unknown)
	local state = hooks.states[player]
	if not state or not hooks.playing() or not hooks.allow(state, "staff", MAX_STAFF_PER_SECOND) then
		return
	end
	local team = hooks.team()
	local item = Items.get(Config, id)
	if action ~= "assign" or not item or item.kind ~= "staff" or not Items.owned(team, item.id) or type(areaId) ~= "number" then
		return
	end
	local reachable = Items.reachable(Config, team, hooks.openIds())
	if not table.find(StaffRules.targets(Config, item, team.owned, reachable), areaId) then
		return
	end
	team.assign[item.id] = areaId
	publish(roster())
end

function Staff.start(oceanModel: Model, runHooks: Hooks, staffRemote: RemoteEvent)
	ocean, hooks = oceanModel, runHooks
	staffRemote.OnServerEvent:Connect(onStaff)
	local sinceTick, sinceNear = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		sinceTick += dt
		sinceNear += dt
		if sinceTick >= TICK then
			tick(sinceTick)
			sinceTick = 0
		end
		if sinceNear >= NEAR_TICK then
			sinceNear = 0
			checkLifeguards()
		end
	end)
end

return Staff
