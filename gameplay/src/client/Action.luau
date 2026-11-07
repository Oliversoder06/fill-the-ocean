-- Scoop and pour. Stand by the well (the ocean's Source) or anywhere next to where the water will
-- be (shared/Zones.nearFlood), aim at the
-- water and press E, left mouse, RT or the touch button. A scoop is one sweep (the tool fills over
-- `Sweeps` of them); each press does one sweep, and holding keeps sweeping only once the player owns
-- the Hold upgrade. A pour is one quick tip that empties the tool. An action that has started always
-- plays to the end. The server re-checks and credits each action (server/Run onAct). Viewmodel and
-- Feel read the current action from here.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Hud = require(script.Parent.Hud)

local REACH = Hud.REACH
local AIM_DISTANCE = 80
local PENDING_GRACE = 0.75 -- seconds after an action ends to wait for the server's credit
local ACTION_NAME = "FillAct"

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

local function keyName(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "the button"
	elseif last.Name:sub(1, 7) == "Gamepad" then
		return "RT"
	end
	return "E"
end

function Action.start()
	local actRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Act") :: RemoteEvent
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("Hud")
	local hint = Hud.find(gui, "ActHint")
	local shop = Hud.find(gui, "Shop")

	local aimParams = RaycastParams.new()
	aimParams.FilterType = Enum.RaycastFilterType.Include
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

	-- The action this spot offers, whether the aim is on its water, and the visible point aimed at.
	-- Pouring works anywhere next to where the water will be, aimed at a spot it will cover.
	local function target(ocean: Model, root: BasePart, character: Model, camera: Camera): (Kind?, Vector3?)
		local source = Zones.part(ocean, "Source")
		local pourPoint = Zones.part(ocean, "PourPoint")
		local origin, look = camera.CFrame.Position, camera.CFrame.LookVector * AIM_DISTANCE
		-- Splash where the eye lands (the well's water or the basin), not on the invisible zone part.
		seeParams.FilterDescendantsInstances = { character, camera, source, pourPoint }
		if (root.Position - source.Position).Magnitude <= REACH then
			aimParams.FilterDescendantsInstances = { source }
			local aim = workspace:Raycast(origin, look, aimParams)
			if not aim then
				return "scoop", nil
			end
			local seen = workspace:Raycast(origin, look, seeParams)
			return "scoop", if seen then seen.Position else aim.Position
		end
		if not Hud.nearPour(ocean, root.Position) then
			return nil, nil
		end
		local seen = workspace:Raycast(origin, look, seeParams)
		return "pour", if seen and Zones.willFlood(ocean, seen.Position) then seen.Position else nil
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
	local function begin(kind: Kind, hit: Vector3, now: number)
		nextId += 1
		local duration = if kind == "pour" then Config.pourSeconds else player:GetAttribute("ActSeconds") or Config.start.actSeconds
		local action: Current = { kind = kind, id = nextId, started = now, duration = duration, hit = hit }
		current = action
		table.insert(if kind == "scoop" then pendingScoops else pendingPours, now + duration + PENDING_GRACE)
		actRemote:FireServer(kind)
		emit(startedListeners, action)
	end

	local function hintText(kind: Kind?, aimed: boolean, ocean: Model?): string?
		if not kind or current then
			return nil
		end
		local carried = player:GetAttribute("Carried") or 0
		local capacity = player:GetAttribute("Capacity") or 0
		if kind == "scoop" and carried >= capacity * (1 - 1e-6) then
			return `Full! Pour it into the {if ocean then ocean.Name:lower() else "water"}`
		elseif kind == "pour" and carried <= 0 then
			return "Empty! Scoop more at the well"
		elseif not aimed then
			return "Aim at the water"
		end
		local verb = if kind == "scoop" and player:GetAttribute("Hold") then "Hold" else "Press"
		return `{verb} {keyName()} to {kind}`
	end

	local shownKind: Kind? = nil
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
		local windowOpen = shop.Visible
		local kind, hit = nil, nil
		if
			ReplicatedStorage:GetAttribute("Phase") == "playing"
			and player:GetAttribute("Equipped") ~= false
			and ocean
			and character
			and root
			and root:IsA("BasePart")
			and humanoid
			and humanoid.Health > 0
			and camera
			and not windowOpen
		then
			kind, hit = target(ocean, root, character, camera)
		end

		local text = hintText(kind, hit ~= nil, ocean)
		Hud.set(hint, "Visible", text ~= nil)
		if text then
			Hud.set(hint, "Text", text)
		end
		local button = ContextActionService:GetButton(ACTION_NAME)
		if button then
			Hud.set(button, "Visible", kind ~= nil)
		end
		if kind and kind ~= shownKind then
			shownKind = kind
			ContextActionService:SetTitle(ACTION_NAME, if kind == "scoop" then "Scoop" else "Pour")
		end

		-- Without Hold, only a fresh press starts a sweep; holding the button does nothing more.
		local repeatHeld = held and player:GetAttribute("Hold") == true
		if not current and (repeatHeld or tapped) and kind and hit and canStart(kind) then
			begin(kind, hit, now)
			tapped = false
		elseif not current then
			tapped = false
		end
	end)
end

return Action
