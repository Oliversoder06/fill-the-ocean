-- Session pad UI, built in Studio under StarterGui.LobbyHud in the sunbaked-sea style; colours come
-- from the theme. The host gets the pad menu (PadMenu: Create Party or Saved Runs), the Create Party
-- window (map pager, party size, friends-only) and the Saved Runs panel (one card per saved run,
-- cloned from its hidden CardTemplate, with Load and Leave run). HostBar shows an open session and
-- the host's Start button; Hint shows while the player isn't on a pad. The server decides
-- everything; this only shows SessionState and sends SessionAction("view" | "open" | "cancel" |
-- "start" | "load" | "leave").
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

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
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

	local padMenu = find(hud, "PadMenu")
	local createTile = find(padMenu, "Body.CreateTile")
	local createSub = find(createTile, "Sub")
	local savedTile = find(padMenu, "Body.SavedTile")
	local savedSub = find(savedTile, "Sub")
	local padClose = find(padMenu, "CloseButton")

	local create = find(hud, "CreateParty")
	local mapCard = find(create, "Body.Map.Card")
	local mapTitle = find(mapCard, "MapName")
	local mapInfo = find(mapCard, "Info")
	local mapLock = find(mapCard, "Lock")
	local mapLockText = find(mapCard, "LockText")
	local prev = find(create, "Body.Map.Prev")
	local nextMap = find(create, "Body.Map.Next")
	local page = find(create, "Body.Map.Page")
	local count = find(create, "Body.Players.Count")
	local minus = find(create, "Body.Players.Minus")
	local plus = find(create, "Body.Players.Plus")
	local toggle = find(create, "Body.Friends.Toggle")
	local createButton = find(create, "Body.CreateButton")
	local createLabel = find(createButton, "Label")
	local createBack = find(create, "BackButton")
	local createClose = find(create, "CloseButton")

	local savedWindow = find(hud, "SavedRuns")
	local savedBack = find(savedWindow, "BackButton")
	local savedClose = find(savedWindow, "CloseButton")
	local empty = find(savedWindow, "Body.Empty")
	local list = find(savedWindow, "Body.List")
	local template = find(list, "CardTemplate")
	template.Visible = false

	local bar = find(hud, "HostBar")
	local barLine = find(bar, "Line")
	local barDetail = find(bar, "Detail")
	local startButton = find(bar, "StartButton")

	local windows = { padMenu, create, savedWindow }
	local settings = { maxPlayers = 4, mapId = Maps.list[1].id, friendsOnly = false }
	local mapIndex = 1
	local unlocked: { [string]: boolean } = {}
	local cards: { Instance } = {}
	local confirming: string? = nil -- the card whose "Leave run?" question is open

	-- Shows one window (or none) and hides the others.
	local function open(target: GuiObject?)
		for _, w in windows do
			show(w, w == target)
		end
	end

	local function refreshMenu(state)
		local openMaps = 0
		for _ in unlocked do
			openMaps += 1
		end
		createSub.Text = `{openMaps} of {plural(#Maps.list, "map")} open`
		savedSub.Text = if state.saved == nil
			then "Couldn't load your runs"
			elseif state.saved == 0 then "No saved runs yet"
			else plural(state.saved, "saved run")
	end

	local function refreshCreate()
		local map = Maps.list[mapIndex]
		local isOpen = unlocked[map.id] == true
		mapTitle.Text = map.name
		mapInfo.Text = `x{map.waterMultiplier} water  -  +{map.rewardRaindrops} Raindrops`
		mapLock.Visible = not isOpen
		mapLockText.Visible = not isOpen
		if not isOpen then
			local before = map.unlockedBy and Maps.get(map.unlockedBy)
			mapLockText.Text = `Clear {if before then before.name else "the map before"} first`
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
		createLabel.Text = if isOpen then "CREATE" else "LOCKED"
	end

	local function fillCard(card: Instance, run)
		find(card, "MapName").Text = if run.mapName ~= "" then run.mapName else "Unknown run"
		find(card, "LastPlayed").Text = playedAgo(run.lastPlayed)
		find(card, "Members").Text = run.members
		local fill = math.clamp(run.fill, 0, 1)
		find(card, "FillBar.Fill").Size = UDim2.fromScale(fill, 1)
		find(card, "FillBar.Label").Text = `{math.floor(fill * 100)}% full`
		find(card, "Reason").Text = run.reason
		local load = find(card, "LoadButton")
		load.ImageColor3 = if run.canLoad then C.buyCoral else C.locked
		local leave = find(card, "LeaveButton")
		local confirm = find(card, "Confirm")
		find(confirm, "Question").Text = if run.teamSize > 1
			then "Leave this run? It stays saved for the others, but without you they can't load it any more."
			else "Leave this run? It comes off your list. Starting a solo party on this map again picks it back up."
		confirm.Visible = confirming == run.key
		local yes = find(confirm, "YesButton")
		local no = find(confirm, "NoButton")
		for _, b in { load, leave, yes, no } do
			juice(b)
		end
		load.Activated:Connect(function()
			if run.canLoad then
				action:FireServer("load", run.key)
			end
		end)
		leave.Activated:Connect(function()
			confirming = run.key
			confirm.Visible = true
		end)
		no.Activated:Connect(function()
			confirming = nil
			confirm.Visible = false
		end)
		yes.Activated:Connect(function()
			confirming = nil
			confirm.Visible = false
			action:FireServer("leave", run.key)
		end)
	end

	local function refreshSaved(state)
		for _, card in cards do
			card:Destroy()
		end
		cards = {}
		local runs = state.runs
		empty.Visible = runs == nil or state.error ~= nil or #runs == 0
		if runs == nil then
			empty.Text = "Loading your runs..."
		elseif state.error then
			empty.Text = state.error
		elseif #runs == 0 then
			empty.Text = "No saved runs yet. Create a party to start one!"
		end
		for i, run in runs or {} do
			local card = template:Clone()
			card.Name = `Run{i}`
			card.LayoutOrder = i
			fillCard(card, run)
			card.Visible = true
			card.Parent = list
			table.insert(cards, card)
		end
	end

	for _, b in { createTile, savedTile, padClose, prev, nextMap, minus, plus, toggle, createButton, createBack, createClose, savedBack, savedClose, startButton } do
		juice(b)
	end
	createTile.Activated:Connect(function()
		action:FireServer("view", "create")
	end)
	savedTile.Activated:Connect(function()
		action:FireServer("view", "saved")
	end)
	for _, back in { createBack, savedBack } do
		back.Activated:Connect(function()
			action:FireServer("view", "menu")
		end)
	end
	for _, close in { padClose, createClose, savedClose } do
		close.Activated:Connect(function()
			action:FireServer("cancel")
			open(nil)
		end)
	end
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
		if unlocked[map.id] then
			settings.mapId = map.id
			action:FireServer("open", table.clone(settings))
		end
	end)
	startButton.Activated:Connect(function()
		action:FireServer("start")
	end)

	stateEvent.OnClientEvent:Connect(function(state)
		local kind = state.kind
		hint.Visible = kind == "none"
		if kind == "menu" then
			unlocked = state.unlocked
			refreshMenu(state)
			open(padMenu)
			show(bar, false)
		elseif kind == "create" then
			unlocked = state.unlocked
			refreshCreate()
			open(create)
			show(bar, false)
		elseif kind == "saved" then
			refreshSaved(state)
			open(savedWindow)
			show(bar, false)
		elseif kind == "hosting" or kind == "member" then
			open(nil)
			barLine.Text = if kind == "hosting" then "YOUR SESSION" else `{string.upper(state.host)}'S SESSION`
			barDetail.Text = `{state.count}/{state.max} players - {state.mapName}{if state.friendsOnly then " - Friends" else ""}`
			startButton.Visible = kind == "hosting"
			show(bar, true)
		elseif kind == "launching" then
			open(nil)
			barLine.Text = "STARTING..."
			startButton.Visible = false
			show(bar, true)
		else
			open(nil)
			show(bar, false)
		end
	end)
	hint.Visible = true
	refreshCreate()
end

return Session
