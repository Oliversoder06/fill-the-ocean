-- Every stand's prompt and price sign, for this player; the server sells and checks every buy
-- (server/Run onStand). The stands: each area's own (Zones.stand, the cove's first) and each cove
-- shop (Config.stands, Zones.shop). Each gets a copy of StarterGui.Hud.Templates.StandSign (a
-- BillboardGui with TextLabels Title and Line, built in Studio) over its prompt: the item a press
-- buys or saves up for and its price (teal when you can afford it), where a locked one opens, or
-- "Owned". The prompt names the stand and says what a press does (Items.standOffer, shared/Format).
-- The Fire Station's CallPrompt shows only once you own a vehicle. Stands not streamed in yet are
-- picked up when they arrive.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local Hud = require(script.Parent.Hud)

local REFRESH_SECONDS = 0.25

local player = Players.LocalPlayer
local colors = Theme.colors
local set = Hud.set

local Stands = {}

-- A stand: `key` ("area1", "ToolShack"), the area whose stand it is (the cove for a shop), the cove
-- shop it is (nil for an area's own stand) and its name.
export type Stand = { key: string, area: any, shop: string?, place: string }

local stands: { Stand } = {}
for _, area in Config.areas do
	table.insert(stands, { key = `area{area.id}`, area = area, place = Format.standName(Config, nil, area) })
end
for shop in Config.stands do
	local cove = Areas.byId(Config, 1)
	table.insert(stands, { key = shop, area = cove, shop = shop, place = Format.standName(Config, shop, cove) })
end
table.sort(stands, function(a, b)
	return a.key < b.key
end)

function Stands.list(): { Stand }
	return stands
end

function Stands.byKey(key: string): Stand?
	for _, stand in stands do
		if stand.key == key then
			return stand
		end
	end
	return nil
end

-- The stand's prompt, or nil while it isn't there (not streamed in, or not built in the place yet).
function Stands.prompt(stand: Stand): ProximityPrompt?
	local ocean = Hud.ocean()
	local holder = if stand.shop then Zones.shop(stand.shop) elseif ocean then Zones.stand(ocean, stand.area) else nil
	return holder and Zones.standPrompt(holder)
end

-- What the stand shows this player now (Items.standOffer, as the server picks it). `snap`: Hud.snapshot.
function Stands.offer(stand: Stand, snap: Hud.Snapshot, money: number)
	return Items.standOffer(Config, snap.items, stand.area.id, snap.openAreas, money, stand.shop)
end

-- Whether this player can get to the stand (Items.reachable: Cloud Catcher's needs the Jetpack Tank).
function Stands.reachable(stand: Stand, items: Items.State): boolean
	return Items.reachable(Config, items, { stand.area.id })[1] ~= nil
end

local LINE_COLORS = { buy = colors.speedTag, money = colors.buyCoral, locked = colors.drySand, owned = colors.foam }

function Stands.start()
	local gui = player:WaitForChild("PlayerGui")
	local template = Hud.find(gui:WaitForChild("Hud"), "Templates.StandSign")
	assert(template:IsA("BillboardGui"), "Hud.Templates.StandSign must be a BillboardGui")
	Hud.find(template, "Title")
	Hud.find(template, "Line")
	local signs: { [string]: BillboardGui } = {}
	local prompts: { [string]: ProximityPrompt } = {}
	local callPrompt: ProximityPrompt? = nil

	local nextAt = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextAt then
			return
		end
		nextAt = now + REFRESH_SECONDS
		local snap = Hud.snapshot()
		local money = player:GetAttribute("Money") or 0
		for _, stand in stands do
			local prompt = prompts[stand.key]
			if not (prompt and prompt:IsDescendantOf(workspace)) then
				prompt = Stands.prompt(stand)
				prompts[stand.key] = prompt :: any
			end
			local sign = signs[stand.key]
			if not sign then
				sign = template:Clone()
				sign.Name = `StandSign_{stand.key}`
				sign.ResetOnSpawn = false
				sign.Parent = gui
				signs[stand.key] = sign
			end
			local shown = if prompt and Stands.reachable(stand, snap.items) then prompt else nil
			local s = sign :: BillboardGui
			set(s, "Adornee", if shown then shown.Parent else nil)
			set(s, "Enabled", shown ~= nil)
			if shown then
				local item, status = Stands.offer(stand, snap, money)
				local area = item and Areas.byId(Config, item.area)
				local title, line = Format.standSign(item, status, area, stand.place)
				set(Hud.find(s, "Title"), "Text", title)
				set(Hud.find(s, "Line"), "Text", line)
				set(Hud.find(s, "Line"), "TextColor3", LINE_COLORS[status])
				set(shown, "ObjectText", stand.place)
				set(shown, "ActionText", Format.standAction(item, status, nil, area))
			end
		end
		-- Calling a vehicle out needs one to call.
		if not (callPrompt and callPrompt:IsDescendantOf(workspace)) then
			local station = Zones.shop("FireStation")
			local found = station and station:FindFirstChild("CallPrompt", true)
			callPrompt = if found and found:IsA("ProximityPrompt") then found else nil
		end
		if callPrompt then
			set(callPrompt, "Enabled", Items.furthest(Config, snap.items, "vehicle") ~= nil)
		end
	end)
end

return Stands
