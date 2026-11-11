-- The hotbar (StarterGui.Hud.Hotbar, built in Studio): icon-only slots, no boxes. The tool's slot:
-- press 1, gamepad X or click it to put the tool away or take it out (the server decides).
-- Gadget slots (Hotbar.Gadgets.<itemId>, one per hotbar gadget in Config.items, built like Slot):
-- shown once owned; press 2, 3, 4 (in config order), gamepad DPadRight (next one) or click a slot to
-- take that gadget out instead of the tool, again to put it away. The server decides (Equip remote).
-- The thing in hand shows at full size; the rest sit smaller and fainter (Cues.hotbar).
-- The fill bar above the slots shows only what the thing in hand uses, its model at the left end:
-- the tool's "carried / capacity" litres, the Water Gun's water, the Jetpack Tank's fuel, or, while
-- the player drives their vehicle or stands by its hose (client/Vehicles.gauge), its tank. The Garden
-- Hose has no bar: Hotbar.Status says whether it is clipped and how fast it flows. Nothing in hand:
-- neither shows.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Kit.UI.Themes["clear-tide"])
local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Items = require(ReplicatedStorage.Common.Items)
local Ease = require(ReplicatedStorage.Shared.Ease)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local Hud = require(script.Parent.Hud)
local Vehicles = require(script.Parent.Vehicles)

local player = Players.LocalPlayer
local colors, motion = Theme.colors, Theme.motion
local set = Hud.set

local QUICK = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FILL_POP = TweenInfo.new(Ease.POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FILL_POP_SCALE = 1.08 -- the bar swells a little each time water lands (shows even at 100%)
local IDLE = Cues.hotbar
local IDLE_TWEEN = TweenInfo.new(IDLE.seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GADGET_KEYS = { Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

local Hotbar = {}

-- `press`: the slot's one UIScale, carrying both its rest size and hover / press.
type Held = { press: UIScale, view: ViewportFrame, held: boolean? }

local function restScale(entry: Held): number
	return if entry.held then 1 else IDLE.idleScale
end

-- A slot in hand grows to full size and opacity; one put away settles smaller and fainter.
local function hold(entry: Held, held: boolean)
	if entry.held == held then
		return
	end
	entry.held = held
	TweenService:Create(entry.press, IDLE_TWEEN, { Scale = restScale(entry) }):Play()
	TweenService:Create(entry.view, IDLE_TWEEN, { ImageTransparency = if held then 0 else IDLE.idleTransparency }):Play()
end

-- Litres for the fill label: whole numbers when whole (sweeps can leave thirds), 1.2K above 1000.
local function litres(n: number): string
	if n >= 1000 then
		return Hud.short(n)
	end
	local rounded = math.floor(n * 10 + 0.5) / 10
	return if rounded % 1 == 0 then tostring(math.floor(rounded)) else string.format("%.1f", rounded)
end

function Hotbar.start()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local equipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Equip") :: RemoteEvent
	local bar = Hud.find(gui, "Hotbar")
	local honeycomb = Hud.find(gui, "Honeycomb") -- its full-screen cover hides the bar
	local fillBar = Hud.find(bar, "FillBar")
	local fill = Hud.find(fillBar, "Fill")
	local fillLabel = Hud.find(fillBar, "Label")
	local fillPop = Hud.find(fillBar, "Pop")
	local fillTool = Hud.find(fillBar, "Tool") -- the model of what the bar measures, at its left end
	local status = Hud.find(bar, "Status") -- the Garden Hose's line instead of the bar
	local slot = Hud.find(bar, "Slot")
	local view = Hud.find(slot, "View")
	local press = Hud.find(slot, "Press")
	local toolHeld: Held = { press = press, view = view }
	fill.BackgroundColor3 = colors.owned
	fillBar.BackgroundColor3 = colors.shadow
	-- Hotbar gadgets (a `use`), in config order: each one's slot and key.
	local gadgets = {}
	for _, item in Config.items do
		if item.kind == "gadget" and item.use then
			local gadgetSlot = Hud.find(bar, `Gadgets.{item.id}`)
			table.insert(gadgets, {
				item = item,
				slot = gadgetSlot,
				view = Hud.find(gadgetSlot, "View"),
				press = Hud.find(gadgetSlot, "Press"),
				shown = false,
			})
		end
	end
	assert(#gadgets <= #GADGET_KEYS, "Hotbar: more hotbar gadgets than keys")

	local function bump(entry: Held)
		entry.press.Scale = restScale(entry) * motion.pressScale
		TweenService:Create(entry.press, POP, { Scale = restScale(entry) }):Play()
	end
	-- The tool: out (also from a gadget) or away.
	local function toggle()
		equipRemote:FireServer(player:GetAttribute("Equipped") == false)
		bump(toolHeld)
	end
	-- A gadget: out instead of the tool, or away when it already is. Only owned ones have a slot.
	local function pick(entry)
		if not Items.owned(Hud.items(), entry.item.id) then
			return
		end
		equipRemote:FireServer(if player:GetAttribute("Gadget") == entry.item.id then false else entry.item.id)
		bump(entry)
	end
	-- Gamepad: the next owned gadget after the one out (the tool after the last).
	local function cycle()
		local owned = Items.slots(Config, Hud.items())
		local out = player:GetAttribute("Gadget")
		local at = 0
		for i, item in owned do
			if item.id == out then
				at = i
			end
		end
		local nextItem = owned[at + 1]
		equipRemote:FireServer(if nextItem then nextItem.id else true)
	end

	ContextActionService:BindAction("ToggleEquip", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.One, Enum.KeyCode.ButtonX)
	slot.Activated:Connect(toggle)
	local keys = {}
	for i, entry in gadgets do
		keys[GADGET_KEYS[i]] = entry
		entry.slot.Activated:Connect(function()
			pick(entry)
		end)
	end
	ContextActionService:BindAction("PickGadget", function(_, inputState, input)
		if inputState == Enum.UserInputState.Begin then
			if input.KeyCode == Enum.KeyCode.DPadRight then
				cycle()
			elseif keys[input.KeyCode] then
				pick(keys[input.KeyCode])
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.DPadRight, table.unpack(GADGET_KEYS, 1, #gadgets))
	slot.MouseEnter:Connect(function()
		TweenService:Create(press, QUICK, { Scale = restScale(toolHeld) * motion.hoverScale }):Play()
	end)
	slot.MouseLeave:Connect(function()
		TweenService:Create(press, QUICK, { Scale = restScale(toolHeld) }):Play()
	end)

	-- The template for the bar's icon: the vehicle's, a gadget's or the tool's; nil until replicated.
	local function iconOf(kind: string, gadget: Config.Item?, toolModel: string): Model?
		if kind == "tank" then
			local id = player:GetAttribute("Vehicle")
			local item = if type(id) == "string" then Items.get(Config, id) else nil
			return if item then ToolModels.itemModel(item) :: Model? else nil
		end
		return if gadget then ToolModels.find(gadget.model, "Gadgets") else ToolModels.find(toolModel)
	end

	local shownModel: string? = nil
	local shownIcon: Model? = nil
	local shownKind: string? = nil
	-- The bar springs to each new fill (Ease.pop) instead of jumping.
	local shown, from, to, changedAt = 0, 0, 0, -math.huge
	RunService.RenderStepped:Connect(function()
		local modelName = player:GetAttribute("ToolModel")
		set(bar, "Visible", type(modelName) == "string" and not honeycomb.Visible)
		if type(modelName) ~= "string" then
			return
		end
		if modelName ~= shownModel then
			local template = ToolModels.find(modelName)
			if template then -- nil until replicated; try again next frame
				ToolModels.showIn(view, template)
				shownModel = modelName
			end
		end

		local equipped = player:GetAttribute("Equipped") ~= false
		local out = player:GetAttribute("Gadget")
		local itemState = Hud.items()
		for _, entry in gadgets do
			local id = entry.item.id
			set(entry.slot, "Visible", Items.owned(itemState, id))
			hold(entry, out == id)
			if not entry.shown and entry.slot.Visible then
				local template = ToolModels.find(entry.item.model, "Gadgets")
				if template then -- nil until replicated; try again next frame
					ToolModels.showIn(entry.view, template)
					entry.shown = true
				end
			end
		end

		-- What the bar measures: the vehicle's tank, else the gadget out, else the tool while it is out.
		local gadget = if type(out) == "string" and out ~= "" then Items.get(Config, out) else nil
		hold(toolHeld, equipped and not gadget)
		local tank, tankMax = Vehicles.gauge()
		local kind = if tank then "tank" elseif gadget then gadget.id elseif equipped then "tool" else nil
		local hose = kind == "gardenHose"
		set(fillBar, "Visible", kind ~= nil and not hose)
		set(status, "Visible", hose)
		if hose then
			local rate = Items.gadgetStat(Config, itemState, "gardenHose", "rate") or 0
			set(status, "Text", if (player:GetAttribute("HoseArea") or 0) == 0 then "Clip to a tap" elseif player:GetAttribute("Spraying") == true then `Flowing {litres(rate)} L/s` else "Clipped to the tap")
		end
		if not fillBar.Visible then
			shownKind = nil
			return
		end
		local icon = iconOf(kind :: string, gadget, modelName)
		if icon and icon ~= shownIcon then
			ToolModels.showIn(fillTool, icon)
			shownIcon = icon
		elseif not icon and kind ~= shownKind and shownIcon then -- not the last thing's icon while this one's replicates
			fillTool:ClearAllChildren()
			shownIcon = nil
		end
		local jetpack = kind == "jetpackTank"
		local carried = player:GetAttribute("Carried") or 0
		local capacity = player:GetAttribute("Capacity") or 0
		if tank then
			carried, capacity = tank, tankMax :: number
		elseif jetpack then
			carried = player:GetAttribute("Fuel") or 0
			capacity = Items.gadgetStat(Config, itemState, "jetpackTank", "flightSeconds") or 0
		end
		local ratio = if capacity > 0 then math.clamp(carried / capacity, 0, 1) else 0
		local now = os.clock()
		if kind ~= shownKind then -- something else in hand: its bar starts where it stands
			shownKind = kind
			shown, from, to, changedAt = ratio, ratio, ratio, -math.huge
		elseif ratio ~= to then
			if ratio > to and not jetpack and not tank then -- refuelling and hydrants rise every tick: no swell
				fillPop.Scale = FILL_POP_SCALE
				TweenService:Create(fillPop, FILL_POP, { Scale = 1 }):Play()
			end
			from, to, changedAt = shown, ratio, now
		end
		shown = math.clamp(Ease.pop(from, to, now - changedAt), 0, 1)
		set(fill, "Size", UDim2.fromScale(shown, 1))
		set(fill, "Visible", shown > 0)
		set(fillLabel, "Text", if tank then `Tank {litres(carried)} / {litres(capacity)}` elseif jetpack then `Fuel {string.format("%.1f", carried)}s` elseif kind == "waterGun" then `Gun water {litres(carried)} / {litres(capacity)}` else `{litres(carried)} / {litres(capacity)}`)
	end)
end

return Hotbar
