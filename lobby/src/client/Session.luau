-- Session pad UI: the setup window (StarterGui.LobbyHud.SessionSetup) for the host, and the bar
-- (LobbyHud.HostBar) that shows the open session and the host's Start button. Built in Studio in
-- the sunbaked-sea style; colours come from the theme. The server decides everything; this only
-- shows SessionState and sends SessionAction("open" | "cancel" | "start").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SessionRules = require(ReplicatedStorage.Common.SessionRules)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])

local player = Players.LocalPlayer
local Session = {}

local C = Theme.colors
local POP = TweenInfo.new(Theme.motion.openSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHUT = TweenInfo.new(Theme.motion.closeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local NUDGE = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function find(root: Instance, path: string): any
	local node = root
	for name in path:gmatch("[^%.]+") do
		-- lihfolk-ignore: findfirstchild-chain (asserted on the next line)
		local child = node:FindFirstChild(name)
		assert(child, `LobbyHud is missing {root.Name}.{path} (built in Studio)`)
		node = child
	end
	return node
end

-- Hover grows, press shrinks (style motion), using each button's "Press" UIScale.
local function juice(button: GuiButton)
	local scale = button:FindFirstChild("Press") :: UIScale?
	if not scale then
		return
	end
	local function to(value: number)
		TweenService:Create(scale, NUDGE, { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		to(Theme.motion.hoverScale)
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		to(Theme.motion.pressScale)
	end)
	button.MouseButton1Up:Connect(function()
		to(Theme.motion.hoverScale)
	end)
end

local function show(frame: GuiObject, visible: boolean)
	-- lihfolk-ignore: findfirstchild-chain (nil-checked below before use)
	local scale = frame:FindFirstChild("Scale") :: UIScale?
	if visible == frame.Visible then
		return
	end
	if not scale then
		frame.Visible = visible
		return
	end
	if visible then
		scale.Scale = 0.6
		frame.Visible = true
		TweenService:Create(scale, POP, { Scale = 1 }):Play()
	else
		local tween = TweenService:Create(scale, SHUT, { Scale = 0.6 })
		tween.Completed:Once(function()
			frame.Visible = false
		end)
		tween:Play()
	end
end

function Session.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local stateEvent = remotes:WaitForChild("SessionState") :: RemoteEvent
	local action = remotes:WaitForChild("SessionAction") :: RemoteEvent
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("LobbyHud")

	local window = find(hud, "SessionSetup")
	local count = find(window, "Body.Content.Players.Count")
	local minus = find(window, "Body.Content.Players.Minus")
	local plus = find(window, "Body.Content.Players.Plus")
	local levels = find(window, "Body.Content.Difficulty.Levels")
	local info = find(window, "Body.Content.Difficulty.Info")
	local toggle = find(window, "Body.Content.Friends.Toggle")
	local openButton = find(window, "Body.OpenButton")
	local close = find(window, "CloseButton")
	local bar = find(hud, "HostBar")
	local barLine = find(bar, "Line")
	local barDetail = find(bar, "Detail")
	local startButton = find(bar, "StartButton")

	local settings = { maxPlayers = 4, difficulty = 1, friendsOnly = false }
	local unlocked = 1

	local function refresh()
		local n = settings.maxPlayers
		count.Text = if n == 1 then "Solo" else `{n} players`
		minus.ImageColor3 = if n > 1 then C.shallowWater else C.locked
		plus.ImageColor3 = if n < SessionRules.MAX_PLAYERS then C.shallowWater else C.locked
		for level = 1, SessionRules.MAX_DIFFICULTY do
			local tile = find(levels, `Level{level}`)
			local open = level <= unlocked
			tile.ImageColor3 = if open then C.shallowWater else C.locked
			find(tile, "Label").Visible = open
			find(tile, "Lock").Visible = not open
			find(tile, "Ring").Visible = level == settings.difficulty
		end
		-- Difficulty no longer scales water or Raindrops (the map replaces it, Task 4).
		info.Text = "Normal water  -  x1 Raindrops"
		toggle.ImageColor3 = if settings.friendsOnly then C.speedTag else C.locked
		find(toggle, "Label").Text = if settings.friendsOnly then "ON" else "OFF"
	end

	for _, b in { minus, plus, toggle, openButton, close, startButton } do
		juice(b)
	end
	minus.Activated:Connect(function()
		settings.maxPlayers = math.max(1, settings.maxPlayers - 1)
		refresh()
	end)
	plus.Activated:Connect(function()
		settings.maxPlayers = math.min(SessionRules.MAX_PLAYERS, settings.maxPlayers + 1)
		refresh()
	end)
	for level = 1, SessionRules.MAX_DIFFICULTY do
		local tile = find(levels, `Level{level}`)
		juice(tile)
		tile.Activated:Connect(function()
			if level <= unlocked then
				settings.difficulty = level
				refresh()
			end
		end)
	end
	toggle.Activated:Connect(function()
		settings.friendsOnly = not settings.friendsOnly
		refresh()
	end)
	openButton.Activated:Connect(function()
		action:FireServer("open", table.clone(settings))
	end)
	close.Activated:Connect(function()
		action:FireServer("cancel")
		show(window, false)
	end)
	startButton.Activated:Connect(function()
		action:FireServer("start")
	end)

	stateEvent.OnClientEvent:Connect(function(state)
		local kind = state.kind
		if kind == "configure" then
			unlocked = math.max(1, state.unlocked)
			settings.difficulty = math.min(settings.difficulty, unlocked)
			refresh()
			show(window, true)
			show(bar, false)
		elseif kind == "hosting" or kind == "member" then
			show(window, false)
			barLine.Text = if kind == "hosting" then "YOUR SESSION" else `{string.upper(state.host)}'S SESSION`
			barDetail.Text = `{state.count}/{state.max} players - Difficulty {state.difficulty}{if state.friendsOnly then " - Friends" else ""}`
			startButton.Visible = kind == "hosting"
			show(bar, true)
		elseif kind == "launching" then
			show(window, false)
			barLine.Text = "STARTING..."
			startButton.Visible = false
			show(bar, true)
		else
			show(window, false)
			show(bar, false)
		end
	end)
	refresh()
end

return Session
