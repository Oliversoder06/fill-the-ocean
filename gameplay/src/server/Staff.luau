-- Staff (3f, D3; Config.items kind "staff", shared/StaffRules): each player's own Helper, Lifeguard,
-- Firefighter and Plumber, hired at the Lifeguard Tower (a cove shop, server/Run onStand) and
-- levelled in TAB, where the 2nd and 3rd hire are levels. Assigned in TAB: Staff("assign", itemId,
-- areaId) sets where an owned one works (StaffRules.targets: an area the owner reaches, an owned
-- vehicle's area for a Firefighter, the cove's plots for a Plumber), kept per player in state.assign
-- (saved by server/Run). Unassigned, or no longer allowed, they work their default post
-- (StaffRules.post).
-- No bodies here (client/Staff draws them): every TICK while the run plays, each present player's
-- staff (D4: never an absent owner's) pour StaffRules.rate litres a second into the ocean
-- (hooks.fill), paid to their owner in batches (server/Payroll) at half the hand pay of the area they
-- work (StaffRules.payPerLitre), and twice as fast while the owner scooped or poured in that area
-- within Config.staff.workSeconds (state.workArea / state.workedAt, set by server/Run's onAct).
-- Lifeguards: players within Config.staff.lifeguardRadius of a Source a present player's Lifeguard
-- works walk faster (state.nearLifeguard; server/Run applies it with the other walk factors).
-- Plumbers: the best present, assigned one sets server/Buildings.setPlumber for the team.
-- Published: player attribute Staff ("helper:2@2,firefighter:1@0", StaffRules.encode: id:hires@post,
-- post 0 = nowhere to work yet), read by client/Staff and client/Shop.
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
	states: { [Player]: any }, -- server/Run's player states (owned, itemLevels, assign, workArea, workedAt, nearLifeguard)
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

-- A player's staff: every owned staff item, how many are hired and where they work.
local function roster(state): { Hire }
	local reachable = Items.reachable(Config, state, hooks.openIds())
	local list = {}
	for _, item in Config.items do
		if item.kind == "staff" and Items.owned(state, item.id) then
			local post = StaffRules.post(Config, item, state.owned, reachable, state.assign[item.id])
			table.insert(list, { item = item, hires = Items.stat(state, item, "hires"), post = post })
		end
	end
	return list
end

local function publish(player: Player, list: { Hire })
	local entries = {}
	for _, hire in list do
		table.insert(entries, { id = hire.item.id, hires = hire.hires, post = hire.post or 0 })
	end
	local text = StaffRules.encode(entries)
	if player:GetAttribute("Staff") ~= text then
		player:SetAttribute("Staff", text)
	end
end

-- Litres a second a hire makes (a Firefighter: a tank of the owner's vehicle of its post's area).
local function rateOf(state, hire: Hire): number
	local item = hire.item
	local tank = nil
	if item.job == "truck" then
		for _, vehicle in Config.items do
			if vehicle.kind == "vehicle" and vehicle.area == hire.post and Items.owned(state, vehicle.id) then
				tank = Items.stat(state, vehicle, "tank")
			end
		end
	end
	local carry = if item.job == "area" then Items.stat(state, item, "carry") else nil
	return StaffRules.rate(item.job, hire.hires, carry, Items.stat(state, item, "tripSeconds"), tank)
end

local function setPlumbers(boosts: { number })
	local scale, keepClear = StaffRules.plumber(boosts)
	if scale ~= plumbing.scale or keepClear ~= plumbing.keepClear then
		plumbing.scale, plumbing.keepClear = scale, keepClear
		Buildings.setPlumber(scale, keepClear)
	end
end

-- One output tick of `dt` seconds: every present player's staff pour and are owed their pay.
local function tick(dt: number)
	if not hooks.playing() then
		return -- D4: nothing fills while the run isn't playing
	end
	local now = os.clock()
	local boosts = {}
	for player, state in hooks.states do
		local list = roster(state)
		publish(player, list)
		for _, hire in list do
			local post = hire.post
			if not post then
				continue
			elseif hire.item.job == "plots" then
				table.insert(boosts, Items.stat(state, hire.item, "boost"))
				continue
			end
			local litres = rateOf(state, hire) * dt * StaffRules.bonus(Config, state.workArea, state.workedAt, post, now)
			local taken = if litres > 0 then hooks.fill(litres) else 0
			if taken > 0 then
				Payroll.owe(player, taken * StaffRules.payPerLitre(Config, Areas.byId(Config, post)))
			end
		end
	end
	setPlumbers(boosts)
end

-- Who stands within reach of a Source a present player's Lifeguard works (their walk speeds up).
local function checkLifeguards()
	local watched = {}
	for _, state in if hooks.playing() then hooks.states else {} do
		for _, hire in roster(state) do
			local source = if hire.item.id == "lifeguard" and hire.post then Zones.areaPart(ocean, Areas.byId(Config, hire.post), "Source") else nil
			if source then
				table.insert(watched, source.Position)
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

-- Staff("assign", itemId, areaId) from client/Shop's Assign button: an owned staff item works at
-- `areaId` from now on, if its job may work there (StaffRules.targets).
local function onStaff(player: Player, action: unknown, id: unknown, areaId: unknown)
	local state = hooks.states[player]
	if not state or not hooks.playing() or not hooks.allow(state, "staff", MAX_STAFF_PER_SECOND) then
		return
	end
	local item = Items.get(Config, id)
	if action ~= "assign" or not item or item.kind ~= "staff" or not Items.owned(state, item.id) or type(areaId) ~= "number" then
		return
	end
	local reachable = Items.reachable(Config, state, hooks.openIds())
	if not table.find(StaffRules.targets(Config, item, state.owned, reachable), areaId) then
		return
	end
	state.assign[item.id] = areaId
	publish(player, roster(state))
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
