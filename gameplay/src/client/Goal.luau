-- The next-goal line under the fill bar (StarterGui.Hud.Progress.Goal, a TextButton built in Studio):
-- once the first-minute guide (client/Guide, Hud.Guide) is gone, the one most useful thing to do
-- next (shared/NextGoal), from what is on sale in TAB, at the stands (client/Stands) and on the
-- plots, and the next gate. Clicking it or pressing G opens the honeycomb on that upgrade, or points the
-- way to its stand, gate or plot with the guide's ground chevrons (Guide.pointTo).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local NextGoal = require(ReplicatedStorage.Shared.NextGoal)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Guide = require(script.Parent.Guide)
local Honeycomb = require(script.Parent.Honeycomb)
local Hud = require(script.Parent.Hud)
local Stands = require(script.Parent.Stands)

local REFRESH_SECONDS = 0.25
local FORMAT = { money = Format.money, fill = Format.fill, percent = Format.percent }

local player = Players.LocalPlayer
local set = Hud.set

local Goal = {}

-- The first plot without a building (workspace.Map.Plots.PlotN.Base), or nil.
local function emptyPlot(): Instance?
	local scenery = workspace:FindFirstChild("Map")
	local plots = scenery and scenery:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if not plot:FindFirstChild("Building") and plot:FindFirstChild("Base") then
			return plot:FindFirstChild("Base")
		end
	end
	return nil
end

-- Everything on sale now, as NextGoal offers. Targets are keys: "tab:<id>", "stand:<key>", "plots".
-- Only stands that are in the place and the player can reach, and builds while a plot is free.
local function offers(money: number): { NextGoal.Offer }
	local list = {}
	local levels = Hud.levels(0) :: { [string]: number }
	local snap = Hud.snapshot()
	local plotFree = emptyPlot() ~= nil
	for _, track in Config.tracks do
		local level, status, affordable = Hud.offer(levels, track.id, money, snap)
		if status == "buy" then
			local name = Format.levelName(track, levels[track.id] + 1, level)
			table.insert(list, { name = name, cost = Hud.price(level.cost), place = "in UPGRADES", affordable = affordable, target = `tab:{track.id}` })
		end
	end
	for _, item in Config.items do
		local level, status, affordable = Hud.offer(levels, item.id, money, snap)
		if status == "buy" then
			local bought = if item.kind == "building" then snap.buildings[item.id] else snap.items.itemLevels[item.id]
			table.insert(list, { name = `{item.name} Lv {bought + 2}`, cost = Hud.price(level.cost), place = "in UPGRADES", affordable = affordable, target = `tab:{item.id}` })
		elseif status == "unbuilt" and plotFree then
			local price = Hud.price(item.price)
			table.insert(list, { verb = "Build", name = item.name, cost = price, place = "on a town plot", affordable = Items.affords(money, price), target = "plots" })
		end
	end
	for _, stand in Stands.list() do
		if Stands.reachable(stand, snap.items) and Stands.prompt(stand) then
			local item, status = Stands.offer(stand, snap, money)
			if status == "buy" or status == "money" then
				table.insert(list, { name = item.name, cost = Hud.price(item.price), place = `at the {stand.place}`, affordable = status == "buy", target = `stand:{stand.key}` })
			end
		end
	end
	return list
end

-- The next closed gate, as NextGoal reads it.
local function nextGate(money: number, fill: number): NextGoal.Gate?
	local id, onSale = Areas.nextGate(Config, Hud.gatesOpen(), fill)
	local area = id and Areas.byId(Config, id)
	if not area then
		return nil
	end
	local price = Hud.price(area.gate.price)
	return { name = area.name, fill = area.gate.fill, price = price, onSale = onSale, affordable = Items.affords(money, price), target = `gate:{area.id}` }
end

-- Where a world target is, or nil while it isn't streamed in.
local function spotOf(target: string): Vector3?
	local kind, key = target:match("^(%a+):?(.*)$")
	local spot: Instance? = nil
	if kind == "stand" then
		local stand = Stands.byKey(key)
		local prompt = stand and Stands.prompt(stand)
		spot = prompt and prompt.Parent
	elseif kind == "gate" then
		local ocean = Hud.ocean()
		local area = Areas.byId(Config, tonumber(key))
		local model = ocean and area and Zones.areaModel(ocean, area)
		local gate = model and model:FindFirstChild("Gate")
		spot = gate and gate:FindFirstChild("Prompt")
	elseif kind == "plots" then
		spot = emptyPlot()
	end
	if spot and spot:IsA("BasePart") then
		return spot.Position
	elseif spot and spot:IsA("Attachment") then
		return spot.WorldPosition
	elseif spot and spot:IsA("PVInstance") then
		return spot:GetPivot().Position
	end
	return nil
end

function Goal.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local line = Hud.find(gui, "Progress.Goal") :: TextButton
	local guide = Hud.find(gui, "Guide")
	local target: any = nil
	local pointed: string? = nil -- the world target the chevrons show

	local function go()
		if type(target) ~= "string" or not line.Visible then
			return
		end
		local id = target:match("^tab:(.+)$")
		if id then
			Honeycomb.show(id)
			return
		end
		local at = spotOf(target)
		if at then
			pointed = target
			Guide.pointTo(at)
		end
	end
	line.Activated:Connect(go)
	ContextActionService:BindAction("NextGoal", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			go()
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.G)

	local nextAt = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextAt then
			return
		end
		nextAt = now + REFRESH_SECONDS
		local show = ReplicatedStorage:GetAttribute("Phase") == "playing" and not guide.Visible
		set(line, "Visible", show)
		if not show then
			return
		end
		local money = Hud.wallet()
		local raw = ReplicatedStorage:GetAttribute("Fill")
		local fill = if type(raw) == "number" then raw else 0
		local text
		text, target = NextGoal.pick(offers(money), nextGate(money, fill), money, fill, FORMAT)
		set(line, "Text", text)
		if pointed and pointed ~= target then -- a new goal: the old way off the ground
			pointed = nil
			Guide.pointTo(nil)
		end
	end)
end

return Goal
