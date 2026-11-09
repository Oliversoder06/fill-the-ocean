-- Session pad UI, built in Studio under StarterGui.LobbyHud in the sunbaked-sea style; colours come
-- from the theme. Stepping on a pad as host opens PadScreen, one screen with two panels: Create Party
-- (map pager, party size, friends-only and Create, which reads NEW GAME when the team on the pad
-- already has a save on that map) and Saved Runs (one card per saved run, cloned from its hidden
-- CardTemplate, with Load Game and Delete). New Game and Delete ask first (PadScreen.Confirm).
-- HostBar shows an open session and the host's Start button; Hint shows while the player isn't on a
-- pad. The server decides everything; this only shows SessionState and sends SessionAction("open" |
-- "cancel" | "start" | "load" | "delete").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Maps = require(ReplicatedStorage.Common.Maps)
local SessionRules = require(ReplicatedStorage.Common.SessionRules)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])

local player = Players.LocalPlayer
local Session = {}

local C = Theme.colors
local POP = TweenInfo.new(Theme.motion.openSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHUT = TweenInfo.new(Theme.motion.closeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local NUDGE = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WOBBLE = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
local WOBBLE_DEGREES = 6

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

-- A short wobble on a button that can't do anything right now (the card says why).
local wobbling: { [GuiObject]: boolean } = {}
local function deny(button: GuiObject)
	if wobbling[button] then
		return
	end
	wobbling[button] = true
	local rest = button.Rotation
	local tween = TweenService:Create(button, WOBBLE, { Rotation = rest + WOBBLE_DEGREES })
	tween.Completed:Once(function()
		button.Rotation = rest
		wobbling[button] = nil
	end)
	tween:Play()
end

-- A window's fit to the screen: built at its DesignSize attribute, shrunk to fit the ScreenGui's
-- area (which already leaves out the safe-area insets), never grown. 1 for frames without one.
local function fitOf(frame: GuiObject): number
	local design = frame:GetAttribute("DesignSize")
	local gui = frame:FindFirstAncestorWhichIsA("ScreenGui")
	if typeof(design) ~= "Vector2" or not gui then
		return 1
	end
	local view = gui.AbsoluteSize
	return math.min(view.X / design.X, view.Y / design.Y, 1)
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
	local fit = fitOf(frame)
	if visible then
		scale.Scale = 0.6 * fit
		frame.Visible = true
		TweenService:Create(scale, POP, { Scale = fit }):Play()
	else
		local tween = TweenService:Create(scale, SHUT, { Scale = 0.6 * fit })
		tween.Completed:Once(function()
			frame.Visible = false
		end)
		tween:Play()
	end
end

-- "Played 3h ago" from a save's updatedAt (server time, seconds).
local function playedAgo(at: number): string
	if at <= 0 then
		return "Not played yet"
	end
	local seconds = math.max(0, workspace:GetServerTimeNow() - at)
	if seconds < 60 then
		return "Played just now"
	elseif seconds < 3600 then
		return `Played {math.floor(seconds / 60)}m ago`
	elseif seconds < 86400 then
		return `Played {math.floor(seconds / 3600)}h ago`
	end
	return `Played {math.floor(seconds / 86400)}d ago`
end

function Session.start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local stateEvent = remotes:WaitForChild("SessionState") :: RemoteEvent
	local action = remotes:WaitForChild("SessionAction") :: RemoteEvent
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("LobbyHud")

	local hint = find(hud, "Hint")

	local screen = find(hud, "PadScreen")
	local screenClose = find(screen, "CloseButton")

	local create = find(screen, "CreateParty")
	local mapCard = find(create, "Body.Map.Card")
	local mapTitle = find(mapCard, "MapName")
	local mapInfo = find(mapCard, "Info")
	local mapLock = find(mapCard, "Lock")
	local mapLockText = find(mapCard, "LockText")
	local mapArt = find(mapCard, "Art")
	local prev = find(create, "Body.Map.Prev")
	local nextMap = find(create, "Body.Map.Next")
	local page = find(create, "Body.Map.Page")
	local count = find(create, "Body.Players.Count")
	local minus = find(create, "Body.Players.Minus")
	local plus = find(create, "Body.Players.Plus")
	local toggle = find(create, "Body.Friends.Toggle")
	local createButton = find(create, "Body.CreateButton")
	local createLabel = find(createButton, "Label")

	local savedPanel = find(screen, "SavedRuns")
	local empty = find(savedPanel, "Body.Empty")
	local list = find(savedPanel, "Body.List")
	local template = find(list, "CardTemplate")
	template.Visible = false

	local confirm = find(screen, "Confirm")
	local question = find(confirm, "Question")
	local yes = find(confirm, "YesButton")
	local yesLabel = find(yes, "Label")
	local no = find(confirm, "CancelButton")
	confirm.Visible = false
	yes.ImageColor3 = C.buyCoral
	no.ImageColor3 = C.shallowWater

	local bar = find(hud, "HostBar")
	local barLine = find(bar, "Line")
	local barDetail = find(bar, "Detail")
	local startButton = find(bar, "StartButton")

	assert(typeof(screen:GetAttribute("DesignSize")) == "Vector2", "LobbyHud.PadScreen needs a Vector2 attribute DesignSize (built in Studio)")
	-- Rotating a phone or resizing the window refits the screen while it is open.
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local scale = screen:FindFirstChild("Scale")
		if screen.Visible and scale and scale:IsA("UIScale") then
			scale.Scale = fitOf(screen)
		end
	end)
	local settings = { maxPlayers = 4, mapId = Maps.list[1].id, friendsOnly = false }
	local mapIndex = 1
	local unlocked: { [string]: boolean } = {}
	local runs = {} -- the saved-run cards last sent (SessionRules.savedFor reads mapId and memberIds)
	local padIds: { number } = {} -- who stands on the pad, the host first
	local cards: { Instance } = {}
	local onYes: (() -> ())? = nil -- what the open question does on its Yes button

	local function ask(text: string, yesText: string, fn: () -> ())
		question.Text = text
		yesLabel.Text = yesText
		onYes = fn
		confirm.Visible = true
	end

	local function closeAsk()
		onYes = nil
		confirm.Visible = false
	end

	-- The saved run Create would start over (New Game: one save per map per team), or nil.
	local function replaced()
		local i = SessionRules.savedFor(runs, Maps.list[mapIndex].id, SessionRules.newTeam(settings.maxPlayers, padIds))
		return if i then runs[i] else nil
	end

	local function refreshCreate()
		local map = Maps.list[mapIndex]
		local isOpen = unlocked[map.id] == true
		mapTitle.Text = map.name
		mapInfo.Text = `x{map.waterMultiplier} water  -  +{map.rewardRaindrops} Raindrops`
		mapCard.ImageColor3 = if isOpen then C.shallowWater else C.locked
		mapArt.Visible = isOpen
		mapLock.Visible = not isOpen
		mapLockText.Visible = not isOpen
		if not isOpen then
			local before = map.unlockedBy and Maps.get(map.unlockedBy)
			mapLockText.Text = `Clear {if before then before.name else "the map before"} to unlock`
		end
		page.Text = `{mapIndex}/{#Maps.list}`
		prev.ImageColor3 = if mapIndex > 1 then C.shallowWater else C.locked
		nextMap.ImageColor3 = if mapIndex < #Maps.list then C.shallowWater else C.locked
		local n = settings.maxPlayers
		count.Text = if n == 1 then "Solo" else `{n} players`
		minus.ImageColor3 = if n > 1 then C.shallowWater else C.locked
		plus.ImageColor3 = if n < SessionRules.MAX_PLAYERS then C.shallowWater else C.locked
		toggle.ImageColor3 = if settings.friendsOnly then C.speedTag else C.locked
		find(toggle, "Label").Text = if settings.friendsOnly then "ON" else "OFF"
		createButton.ImageColor3 = if isOpen then C.buyCoral else C.locked
		createLabel.Text = if not isOpen then "LOCKED" elseif replaced() then "NEW GAME" else "CREATE"
	end

	local function fillCard(card: Instance, run)
		find(card, "MapName").Text = if run.mapName ~= "" then run.mapName else "Unknown run"
		find(card, "LastPlayed").Text = playedAgo(run.lastPlayed)
		find(card, "Members").Text = run.members
		local fill = math.clamp(run.fill, 0, 1)
		find(card, "FillBar.Fill").Size = UDim2.fromScale(fill, 1)
		find(card, "FillBar.Label").Text = `{math.floor(fill * 100)}% full`
		local reason = find(card, "Reason")
		reason.Text = run.reason
		reason.Visible = run.reason ~= ""
		local load = find(card, "LoadButton")
		load.ImageColor3 = if run.canLoad then C.buyCoral else C.locked
		local delete = find(card, "DeleteButton")
		delete.ImageColor3 = C.buyCoral
		juice(load)
		juice(delete)
		load.Activated:Connect(function()
			if run.canLoad then
				action:FireServer("load", run.key)
			else
				deny(load)
			end
		end)
		delete.Activated:Connect(function()
			local team = run.teamSize > 1 -- a team run only leaves your list (server/Queue deleteRun)
			ask(
				if team
					then "Leave this team run? It stays saved for the others, but without you they can't load it."
					else "Delete this run? This can't be undone.",
				if team then "Leave" else "Delete",
				function()
					action:FireServer("delete", run.key)
				end
			)
		end)
	end

	local function refreshSaved(state)
		for _, card in cards do
			card:Destroy()
		end
		cards = {}
		runs = state.runs or {}
		local loading = state.runs == nil
		empty.Visible = loading or state.error ~= nil or #runs == 0
		if loading then
			empty.Text = "Loading your runs..."
		elseif state.error then
			empty.Text = state.error
		elseif #runs == 0 then
			empty.Text = "No saved runs yet. Create a party to start one!"
		end
		for i, run in runs do
			local card = template:Clone()
			card.Name = `Run{i}`
			card.LayoutOrder = i
			fillCard(card, run)
			card.Visible = true
			card.Parent = list
			table.insert(cards, card)
		end
	end

	for _, b in { screenClose, prev, nextMap, minus, plus, toggle, createButton, yes, no, startButton } do
		juice(b)
	end
	screenClose.Activated:Connect(function()
		action:FireServer("cancel")
		closeAsk()
		show(screen, false)
	end)
	yes.Activated:Connect(function()
		local fn = onYes
		closeAsk()
		if fn then
			fn()
		end
	end)
	no.Activated:Connect(closeAsk)
	prev.Activated:Connect(function()
		mapIndex = math.max(1, mapIndex - 1)
		refreshCreate()
	end)
	nextMap.Activated:Connect(function()
		mapIndex = math.min(#Maps.list, mapIndex + 1)
		refreshCreate()
	end)
	minus.Activated:Connect(function()
		settings.maxPlayers = math.max(1, settings.maxPlayers - 1)
		refreshCreate()
	end)
	plus.Activated:Connect(function()
		settings.maxPlayers = math.min(SessionRules.MAX_PLAYERS, settings.maxPlayers + 1)
		refreshCreate()
	end)
	toggle.Activated:Connect(function()
		settings.friendsOnly = not settings.friendsOnly
		refreshCreate()
	end)
	createButton.Activated:Connect(function()
		local map = Maps.list[mapIndex]
		if not unlocked[map.id] then
			deny(createButton)
			return
		end
		settings.mapId = map.id
		local run = replaced()
		if not run then
			action:FireServer("open", table.clone(settings))
			return
		end
		local percent = math.floor(math.clamp(run.fill, 0, 1) * 100)
		ask(`This erases your saved run on {map.name} ({percent}% filled). Start over?`, "Erase and start", function()
			action:FireServer("open", { maxPlayers = settings.maxPlayers, mapId = map.id, friendsOnly = settings.friendsOnly, replace = run.key })
		end)
	end)
	startButton.Activated:Connect(function()
		action:FireServer("start")
	end)

	stateEvent.OnClientEvent:Connect(function(state)
		local kind = state.kind
		hint.Visible = kind == "none"
		if kind == "choose" then
			unlocked = state.unlocked
			padIds = state.padIds
			refreshSaved(state)
			refreshCreate()
			show(screen, true)
			show(bar, false)
			return
		end
		closeAsk()
		show(screen, false)
		if kind == "hosting" or kind == "member" then
			barLine.Text = if kind == "hosting" then "YOUR SESSION" else `{string.upper(state.host)}'S SESSION`
			barDetail.Text = `{state.count}/{state.max} players - {state.mapName}{if state.friendsOnly then " - Friends" else ""}`
			startButton.Visible = kind == "hosting"
			show(bar, true)
		elseif kind == "launching" then
			barLine.Text = "STARTING..."
			barDetail.Text = state.title or ""
			startButton.Visible = false
			show(bar, true)
		else
			show(bar, false)
		end
	end)
	hint.Visible = true
	refreshCreate()
end

return Session
