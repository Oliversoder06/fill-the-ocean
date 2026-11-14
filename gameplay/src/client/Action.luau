-- Scoop and pour. Stand by an open area's Source (the cove's is the well) to scoop, and by an open
-- area's Pour or anywhere next to where the water will be (shared/Zones.nearFlood) to pour, aim at
-- the water and press E, left mouse, RT, the touch button or (touch) tap anywhere on the world. A scoop is one sweep (the tool fills over
-- `Sweeps` of them); each press does one sweep, and holding keeps sweeping only once the player owns
-- the Hold upgrade. A pour is one quick tip that empties the tool. An action that has started always
-- plays to the end. The server re-checks and credits each action (server/Run onAct). Viewmodel and
-- Feel read the current action from here.
-- Hotbar gadgets use the same input: with the Water Gun out (instead of the tool) a pour reaches the
-- gun's range; with the Garden Hose out a press by a Tap clips it there, then holding the input aimed
-- at the water sprays (Gadget remote; the server pours while it sprays). The jetpack's hint shows here
-- too (client/Jetpack flies it).
-- Standing on foot by your own truck with water in it (client/Vehicles.hoseReady), by the ocean, the
-- same input sprays its hose instead (Vehicle remote; the server pours from the tank while it sprays),
-- unless the tool is out with water in it: then it pours the tool.
-- Area mechanics (shared/AreaRules): a deep pool behind a broken rock and, with the Cloud Net, the
-- drifting cloud from the net's range are scooped like a Source (Hud.scoopSpot); at the Glacier's
-- Source each sweep chips the ice block (IceHits); Heat Gloves shorten sweeps in hot pools.
-- The hint (Hud.ActHint) sits just under the crosshair: a keycap (Hud.paintKey; "TAP" on touch,
-- where a tap anywhere on the world presses too) and one short word, so it can't be missed.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AreaRules = require(ReplicatedStorage.Shared.AreaRules)
local Config = require(ReplicatedStorage.Shared.Config)
local Icons = require(ReplicatedStorage.Shared.Icons)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Items = require(ReplicatedStorage.Common.Items)
local Hud = require(script.Parent.Hud)
local Vehicles = require(script.Parent.Vehicles)

local AIM_DISTANCE = 80
local AIM_MARGIN = 6 -- studs around a Source/Pour (sideways and below) that still count as aiming at it
local AIM_DOWN = 0.2 -- from inside that box, how far down (look.Y) the camera must point
local PENDING_GRACE = 0.75 -- seconds after an action ends to wait for the server's credit
local ACTION_NAME = "FillAct"
local SPRAY_RESEND_SECONDS = 0.25 -- while the server's Spraying disagrees with the input, ask again this often
-- The touch button: Roblox's default is tiny and hugs Jump, so kids jump instead. It is this times
-- Jump's size, BUTTON_GAP pixels left of it and BUTTON_RISE of its size higher.
local BUTTON_SCALE = 1.15
local BUTTON_GAP = 14
local BUTTON_RISE = 0.35
local HINT_BELOW = 18 -- HUD pixels from the crosshair's middle down to the hint's top

export type Kind = "scoop" | "pour"
export type Current = { kind: Kind, id: number, started: number, duration: number, hit: Vector3 }

local player = Players.LocalPlayer
local Action = {}

local current: Current? = nil
local startedListeners: { (Current) -> () } = {}
local finishedListeners: { (Current) -> () } = {}

function Action.current(): Current?
	return current
end

function Action.onStarted(fn: (Current) -> ())
	table.insert(startedListeners, fn)
end

function Action.onFinished(fn: (Current) -> ())
	table.insert(finishedListeners, fn)
end

local function emit(listeners: { (Current) -> () }, action: Current)
	for _, fn in listeners do
		fn(action)
	end
end

-- The key the act input is on, for the hint's keycap (touch: a tap anywhere on the world, or the
-- big button).
local function keyName(): string?
	local input = Hud.input()
	if input == "touch" then
		return "TAP"
	elseif input == "gamepad" then
		return "RT"
	end
	return "E"
end

local function jumpName(): string?
	local input = Hud.input()
	if input == "touch" then
		return nil
	elseif input == "gamepad" then
		return "A"
	end
	return "Space"
end

function Action.start()
	local actRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Act") :: RemoteEvent
	local gadgetRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gadget") :: RemoteEvent
	local vehicleRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Vehicle") :: RemoteEvent
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local hint = Hud.find(gui, "ActHint") :: GuiObject
	local hintText = Hud.find(hint, "Text") :: TextLabel
	local hintKey = Hud.find(hint, "Key") :: GuiObject
	local hintKeyText = Hud.find(hintKey, "Text") :: TextLabel
	Hud.paintKey(hintKey)
	local crosshair = Hud.find(player.PlayerGui:WaitForChild("Cursor"), "Cursor") :: GuiObject
	local honeycomb = Hud.find(gui, "Honeycomb")

	local seeParams = RaycastParams.new()
	seeParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Expiry times of actions sent but not yet credited, so a chain of sweeps stops at full
	-- without waiting for the server's Carried to catch up.
	local pendingScoops: { number } = {}
	local pendingPours: { number } = {}
	local lastCarried = player:GetAttribute("Carried") or 0
	player:GetAttributeChangedSignal("Carried"):Connect(function()
		local carried = player:GetAttribute("Carried") or 0
		if carried > lastCarried + 1e-9 then
			table.remove(pendingScoops, 1)
		elseif carried < lastCarried - 1e-9 then
			table.remove(pendingPours, 1)
		end
		lastCarried = carried
	end)

	local held = false
	-- A press not yet used. A press during an action waits for it to end, so quick double clicks
	-- each give a sweep; anywhere else it is dropped at the end of the frame.
	local tapped = false
	ContextActionService:BindAction(ACTION_NAME, function(_, state)
		if state == Enum.UserInputState.Begin then
			held, tapped = true, true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			held = false
		end
		return Enum.ContextActionResult.Pass
	end, true, Enum.KeyCode.E, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	-- A key released while the window is unfocused never sends End.
	UserInputService.WindowFocusReleased:Connect(function()
		held = false
	end)
	-- On touch a tap anywhere on the world is a press too (the button still works): the act happens
	-- only if the look is on the water, like any press. Taps on UI (joystick, jump, hotbar, windows)
	-- and camera drags never fire this.
	UserInputService.TouchTapInWorld:Connect(function(_, processedByUI)
		if not processedByUI then
			tapped = true
		end
	end)

	-- Where the aim enters `part` (a Source, DeepPool, cloud or Pour) grown by AIM_MARGIN sideways and
	-- below, or nil when it misses. Box maths, not a raycast: the visible water spills past the zone
	-- part and sits at its bottom, and a raycast never hits a part the camera is already inside.
	local function aimAt(part: BasePart, origin: Vector3, look: Vector3): Vector3?
		local cf = part.CFrame
		local half = part.Size / 2
		local low = Vector3.new(-half.X - AIM_MARGIN, -half.Y - AIM_MARGIN, -half.Z - AIM_MARGIN)
		local high = Vector3.new(half.X + AIM_MARGIN, half.Y, half.Z + AIM_MARGIN)
		local from = cf:PointToObjectSpace(origin)
		local dir = cf:VectorToObjectSpace(look)
		local enter, leave = 0, 1
		for _, axis in { "X", "Y", "Z" } do
			local p, d = (from :: any)[axis], (dir :: any)[axis]
			local lo, hi = (low :: any)[axis], (high :: any)[axis]
			if math.abs(d) < 1e-9 then
				if p < lo or p > hi then
					return nil
				end
			else
				local t1, t2 = (lo - p) / d, (hi - p) / d
				if t1 > t2 then
					t1, t2 = t2, t1
				end
				enter, leave = math.max(enter, t1), math.min(leave, t2)
				if enter > leave then
					return nil
				end
			end
		end
		-- From inside the box only a look down at the water counts, not the sky.
		if enter == 0 and look.Unit.Y > -AIM_DOWN then
			return nil
		end
		return origin + look * enter
	end

	-- A zone's water: the middle of its bottom face (the visible water sits there).
	local function waterOf(part: BasePart): Vector3
		return (part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0)).Position
	end

	-- The action this spot offers, the visible point aimed at (nil = not aimed at its water) and,
	-- for a scoop, the area scooped. Scooping is at an open area's Source; pouring at an open area's
	-- Pour, or anywhere next to where the water will be, aimed at a spot it will cover. `reach`: studs
	-- a pour reaches (Hud.REACH by default); `pourOnly`: no scooping (a gadget in hand). The last
	-- result says whether the scoop is at a deep pool.
	local function target(ocean: Model, root: BasePart, character: Model, camera: Camera, reach: number?, pourOnly: boolean): (Kind?, Vector3?, any, boolean)
		local origin, look = camera.CFrame.Position, camera.CFrame.LookVector * AIM_DISTANCE
		local area, source, deep = nil, nil, false
		if not pourOnly then
			area, source, deep = Hud.scoopSpot(ocean, root.Position)
		end
		-- Splash where the eye lands (the source's water or the basin), not on the invisible zone parts.
		-- Their lookups are nil-safe: a part not streamed in yet is simply not ignored.
		local ignore: { Instance } = { character, camera }
		for _, part in { source or ocean:FindFirstChild("Source"), ocean:FindFirstChild("PourPoint") } do
			if part then
				table.insert(ignore, part)
			end
		end
		seeParams.FilterDescendantsInstances = ignore
		-- Close enough is enough everywhere (owner, 2026-11-11): a look that misses the water still acts,
		-- splashing at the zone's water (its bottom).
		if source then
			local aim = aimAt(source, origin, look)
			if not aim then
				return "scoop", waterOf(source), area, deep
			end
			local seen = workspace:Raycast(origin, look, seeParams)
			return "scoop", if seen then seen.Position else aim, area, deep
		end
		local _, pour = Hud.openSpot(ocean, "Pour", root.Position, reach)
		if pour then
			return "pour", aimAt(pour, origin, look) or waterOf(pour), nil, false -- the splash plays on the channel inlet
		end
		if not Hud.nearPour(ocean, root.Position, reach) then
			return nil, nil, nil, false
		end
		local seen = workspace:Raycast(origin, look, seeParams)
		if seen and Zones.willFlood(ocean, seen.Position) then
			return "pour", seen.Position, nil, false
		end
		-- Close enough is enough: no need to look down at the seabed (owner, 2026-11-11).
		return "pour", Hud.floodPoint(ocean, root.Position, reach, look), nil, false
	end

	local function canStart(kind: Kind): boolean
		local carried = player:GetAttribute("Carried") or 0
		local capacity = player:GetAttribute("Capacity") or 0
		if kind == "scoop" then
			local per = capacity / math.max(1, player:GetAttribute("Sweeps") or 1)
			return carried + #pendingScoops * per < capacity * (1 - 1e-6)
		end
		return carried > 0 and #pendingPours == 0
	end

	local nextId = 0
	-- `area`: the area scooped (AreaRules.scoopSeconds paces the sweep, as the server does).
	local function begin(kind: Kind, hit: Vector3, now: number, area)
		nextId += 1
		local hotFill = Items.gadgetStat(Config, Hud.items(), "heatGloves", "hotFill")
		local duration = if kind == "pour"
			then Config.pourSeconds
			else AreaRules.scoopSeconds(player:GetAttribute("ActSeconds") or Config.start.actSeconds, area, hotFill)
		local action: Current = { kind = kind, id = nextId, started = now, duration = duration, hit = hit }
		current = action
		table.insert(if kind == "scoop" then pendingScoops else pendingPours, now + duration + PENDING_GRACE)
		actRemote:FireServer(kind)
		emit(startedListeners, action)
	end

	-- `ice`: the scoop chips an ice block (the Glacier's Source). Returns the hint's word and its key.
	local function hintFor(kind: Kind?, aimed: boolean, ice: boolean): (string?, string?)
		if not kind or current then
			return nil, nil
		end
		local carried = player:GetAttribute("Carried") or 0
		local capacity = player:GetAttribute("Capacity") or 0
		if kind == "scoop" and carried >= capacity * (1 - 1e-6) then
			return "Full! Go pour", nil
		elseif kind == "pour" and carried <= 0 then
			return "Empty! Go scoop", nil
		elseif not aimed then
			return "Aim at the water", nil
		end
		if ice then
			local needed = AreaRules.iceHits(Config, Items.gadgetStat(Config, Hud.items(), "icePick", "hits"))
			return `Chip the ice {player:GetAttribute("IceHits") or 0}/{needed}`, keyName()
		end
		if kind == "scoop" then
			return if player:GetAttribute("Hold") then "Hold to scoop" else "Scoop", keyName()
		end
		return "Pour", keyName()
	end

	-- The Garden Hose: a press by a Tap clips it there; once clipped it sprays while the input is held
	-- aimed at the water. Returns the hint, the touch button's title and the hint's key.
	-- A hose's spraying is compared with the server's (`attribute`) and resent while they differ: a
	-- toggle the server's rate limit drops must not leave it stuck on or off.
	local function sprayToggle(remote: RemoteEvent, attribute: string): (boolean) -> ()
		local sentAt = -math.huge
		return function(on: boolean)
			local now = os.clock()
			if on ~= (player:GetAttribute(attribute) == true) and now - sentAt >= SPRAY_RESEND_SECONDS then
				sentAt = now
				remote:FireServer("spray", on)
			end
		end
	end
	local setSpray = sprayToggle(gadgetRemote, "Spraying")
	local setTruckSpray = sprayToggle(vehicleRemote, "VehicleSpraying")
	local function hoseStep(ocean: Model, root: BasePart, character: Model, camera: Camera): (string, string?, string?)
		if (player:GetAttribute("HoseArea") or 0) == 0 then
			if not Hud.openSpot(ocean, "Tap", root.Position) then
				return "Find a tap by a pour spot", nil, nil
			end
			if tapped then
				gadgetRemote:FireServer("clip")
			end
			return "Clip the hose", "Clip", keyName()
		end
		local reach = Items.gadgetStat(Config, Hud.items(), "gardenHose", "reach")
		local _, hit = target(ocean, root, character, camera, reach, true)
		local want = held and hit ~= nil
		setSpray(want)
		if not hit then
			return "Aim at the water", "Spray", nil
		end
		if want then
			return "Spraying!", "Spray", nil
		end
		return "Spray", "Spray", keyName()
	end

	-- The truck's hose (the caller checked Vehicles.hoseReady): sprays from the tank while the input is
	-- held aimed at the water.
	local function truckStep(ocean: Model, root: BasePart, character: Model, camera: Camera): (string, string?, string?)
		local _, hit = target(ocean, root, character, camera, nil, true)
		local want = held and hit ~= nil
		setTruckSpray(want)
		if not hit then
			return "Aim at the water", "Spray", nil
		end
		if want then
			return "Spraying!", "Spray", nil
		end
		return "Spray from the truck", "Spray", keyName()
	end

	local shownTitle: string? = nil
	local shownIcon: string? = nil
	-- The touch button, fetched off the frame loop: GetButton waits until Roblox has made it (it may
	-- never, e.g. before the touch controls exist), and a wait there would stall every act on touch.
	local actButton: GuiObject? = nil
	local buttonAskedAt = -math.huge
	local function fetchButton(now: number)
		if (actButton and actButton.Parent) or not UserInputService.TouchEnabled or now - buttonAskedAt < 1 then
			return
		end
		buttonAskedAt = math.huge -- one ask at a time
		task.spawn(function()
			actButton = ContextActionService:GetButton(ACTION_NAME)
			buttonAskedAt = os.clock()
		end)
	end
	-- The touch button: big, left of Jump, showing the thing in hand (shared/Icons).
	local function fitButton(button: GuiObject, gadget: any)
		local touchGui = player.PlayerGui:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
		local frame = button.Parent
		if jump and jump:IsA("GuiObject") and frame and frame:IsA("GuiObject") then
			local size = math.floor(jump.AbsoluteSize.X * BUTTON_SCALE)
			local at = jump.AbsolutePosition - frame.AbsolutePosition - Vector2.new(size + BUTTON_GAP, size * BUTTON_RISE)
			Hud.set(button, "Size", UDim2.fromOffset(size, size))
			Hud.set(button, "Position", UDim2.fromOffset(math.round(at.X), math.round(at.Y)))
		end
		local item = if type(gadget) == "string" and gadget ~= "" then Items.get(Config, gadget) else nil
		local model = if item then item.model else player:GetAttribute("ToolModel")
		local icon = if type(model) == "string" then Icons.of(model) else nil
		if icon and icon ~= shownIcon then
			shownIcon = icon
			ContextActionService:SetImage(ACTION_NAME, icon)
		end
	end
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local finished = current
		if finished and now >= finished.started + finished.duration then
			current = nil
			emit(finishedListeners, finished)
		end
		while pendingScoops[1] and pendingScoops[1] < now do
			table.remove(pendingScoops, 1)
		end
		while pendingPours[1] and pendingPours[1] < now do
			table.remove(pendingPours, 1)
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local camera = workspace.CurrentCamera
		local ocean = Hud.ocean()
		local windowOpen = honeycomb.Visible
		local gadget = player:GetAttribute("Gadget")
		local gun = gadget == "waterGun"
		local ready = ReplicatedStorage:GetAttribute("Phase") == "playing"
			and not Hud.cutscene
			and ocean
			and character
			and root
			and root:IsA("BasePart")
			and humanoid
			and humanoid.Health > 0
			and camera
			and not windowOpen
		local kind, hit, area, deep = nil, nil, nil, false
		local text, title, key = nil, nil, nil
		local toolFull = player:GetAttribute("Equipped") ~= false and (player:GetAttribute("Carried") or 0) > 0
		if ready and gadget == "gardenHose" then
			setTruckSpray(false)
			text, title, key = hoseStep(ocean, root, character, camera)
		elseif ready and not toolFull and Vehicles.hoseReady(root.Position) and Hud.nearPour(ocean, root.Position) then
			setSpray(false)
			text, title, key = truckStep(ocean, root, character, camera)
		else
			setSpray(false)
			setTruckSpray(false)
			if ready and (player:GetAttribute("Equipped") ~= false or gun) then
				local reach = if gun then Items.gadgetStat(Config, Hud.items(), "waterGun", "range") else nil
				kind, hit, area, deep = target(ocean, root, character, camera, reach, gun)
				title = if kind == "scoop" then "Scoop" elseif kind then "Pour" else nil
			end
			local ice = kind == "scoop" and not deep and area.mechanic == "ice"
			text, key = hintFor(kind, hit ~= nil, ice)
			if ready and gadget == "jetpackTank" then
				if (player:GetAttribute("Fuel") or 0) > 0 then
					text, key = "Fly", jumpName()
				else
					text, key = "Out of fuel: land to refill", nil
				end
			end
		end

		Hud.set(hint, "Visible", text ~= nil)
		if text then
			Hud.set(hintText, "Text", text)
			Hud.set(hintKey, "Visible", key ~= nil)
			if key then
				Hud.set(hintKeyText, "Text", key)
			end
			-- Just under the crosshair (its own ScreenGui; AbsolutePosition is shared screen space).
			local middle = (crosshair.AbsolutePosition + crosshair.AbsoluteSize / 2 - gui.AbsolutePosition) / Hud.uiScale()
			Hud.set(hint, "Position", UDim2.fromOffset(math.round(middle.X), math.round(middle.Y + HINT_BELOW)))
		end
		fetchButton(now)
		local button = actButton
		if button and button.Parent then
			Hud.set(button, "Visible", title ~= nil)
			if title then
				fitButton(button, gadget)
			end
		end
		if title and title ~= shownTitle then
			shownTitle = title
			ContextActionService:SetTitle(ACTION_NAME, title)
		end


		-- Without Hold, only a fresh press starts a sweep; holding the button does nothing more.
		local repeatHeld = held and player:GetAttribute("Hold") == true
		if not current and (repeatHeld or tapped) and kind and hit and canStart(kind) then
			begin(kind, hit, now, area)
			tapped = false
		elseif not current then
			tapped = false
		end
	end)
end

return Action
