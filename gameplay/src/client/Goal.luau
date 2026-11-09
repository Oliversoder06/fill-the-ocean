-- The next-goal line under the fill bar (StarterGui.Hud.Progress.Goal, a TextButton built in Studio):
-- once the first-minute guide (client/Guide, Hud.Guide) is gone, the one most useful thing to do
-- next (shared/NextGoal), from what is on sale in TAB, at the stands (client/Stands) and on the
-- plots, and the next gate. Clicking it or pressing G opens the shop on that upgrade, or points the
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
local Hud = require(script.Parent.Hud)
local Shop = require(script.Parent.Shop)
local Stands = require(script.Parent.Stands)

local REFRESH_SECONDS = 0.25
local FORMAT = { money = Format.money, fill = Format.fill, percent = Format.percent }

local player = Players.LocalPlayer
local set = Hud.set

local Goal = {}

-- Everything on sale now, as NextGoal offers. Targets are keys: "tab:<id>", "stand:<key>", "plots".
local function offers(money: number): { NextGoal.Offer }
	local list = {}
	local levels = Hud.levels(0) :: { [string]: number }
	local items = Hud.items()
	local buildings = Hud.buildings()
	for _, track in Config.tracks do
		local level, status, affordable = Hud.offer(levels, track.id, money)
		if status == "buy" then
			local name = Shop.levelName(track, levels[track.id] + 1, level)
			table.insert(list, { name = name, cost = level.cost, place = "in UPGRADES", affordable = affordable, target = `tab:{track.id}` })
		end
	end
	for _, item in Config.items do
		local level, status, affordable = Hud.offer(levels, item.id, money)
		if status == "buy" then
			local bought = if item.kind == "building" then buildings[item.id] else items.itemLevels[item.id]
			table.insert(list, { name = `{item.name} Lv {bought + 2}`, cost = level.cost, place = "in UPGRADES", affordable = affordable, target = `tab:{item.id}` })
		elseif status == "unbuilt" then
			table.insert(list, { verb = "Build", name = item.name, cost = item.price, place = "on a town plot", affordable = Items.affords(money, item.price), target = "plots" })
		end
	end
	for _, stand in Stands.list() do
		local item, status = Stands.offer(stand, items, money)
		if status == "buy" or status == "money" then
			table.insert(list, { name = item.name, cost = item.price, place = `at the {stand.place}`, affordable = status == "buy", target = `stand:{stand.key}` })
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
	return { name = area.name, fill = area.gate.fill, price = area.gate.price, onSale = onSale, affordable = Items.affords(money, area.gate.price), target = `gate:{area.id}` }
end

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

-- TODO(ux/b1): ux/b1 adds Guide.pointTo (ground chevrons to a spot, nil clears them); until it is
-- merged a world goal's click only warns once.
local warned = false
local function pointTo(position: Vector3?)
	local show = (Guide :: any).pointTo
	if show then
		show(position)
	elseif not warned then
		warned = true
		warn("[Goal] Guide.pointTo is missing (ux/b1 adds it): no chevrons to the goal")
	end
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
			Shop.show(id)
			return
		end
		local at = spotOf(target)
		if at then
			pointed = target
			pointTo(at)
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
		local money = player:GetAttribute("Money") or 0
		local raw = ReplicatedStorage:GetAttribute("Fill")
		local fill = if type(raw) == "number" then raw else 0
		local text
		text, target = NextGoal.pick(offers(money), nextGate(money, fill), money, fill, FORMAT)
		set(line, "Text", text)
		if pointed and pointed ~= target then -- a new goal: the old way off the ground
			pointed = nil
			pointTo(nil)
		end
	end)
end

return Goal
