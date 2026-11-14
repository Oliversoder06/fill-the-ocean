-- Session pad UI, built in Studio under StarterGui.LobbyHud in the sunbaked-sea style (owner,
-- 2026-11-14: a dry seabed frame round deep-sea rows and chunky tinted buttons). Each button's ready
-- colour is the one it is built with; greyed out is the theme's `locked`. Touching a pad as host
-- opens PadScreen, a full-screen cover like gameplay's honeycomb (LobbyHud.PadCover darkens and
-- Lighting.PadBlur blurs the world; Stats and Admin step aside) with two columns: Create Party (map
-- pager with a water-drop pip per map, full for the shown one, a ??? badge on a coming-soon map;
-- party size with a person icon per member; the friends-only OFF / ON switch, whose Knob slides; and
-- Create, which reads NEW GAME when the team on the pad already has a save on that map; a coming-soon
-- map greys every control out and ignores presses) and Saved Runs (one card per saved run, cloned from
-- its hidden CardTemplate, with Load Game and Delete). Questions (New Game, Delete, and Start finding the team's
-- save: Continue or Start over) use LobbyHud.Confirm, over everything. HostBar shows the session you
-- are in, the host's Start button and everyone's Leave button (the only way off a pad; PadScreen's
-- CloseButton, labelled BACK, is Leave too); Hint shows while the player isn't on a pad. When the
-- server sends the party ("teleporting") the teleport screen (ReplicatedStorage.Transition,
-- common/Transition) covers the lobby in its look and goes with the teleport (SetTeleportGui); any
-- other state after it (the party stayed: Studio, a failed teleport) opens it again. The server decides
-- everything; this only shows SessionState and sends SessionAction("open" | "leave" | "start" |
-- "load" | "delete" | "continue" | "restart").
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Maps = require(ReplicatedStorage.Common.Maps)
local SessionRules = require(ReplicatedStorage.Common.SessionRules)
local Transition = require(ReplicatedStorage.Common.Transition)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"])
local UiSounds = require(script.Parent.UiSounds)

local player = Players.LocalPlayer
local Session = {}

local C = Theme.colors
local POP = TweenInfo.new(Theme.motion.openSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHUT = TweenInfo.new(Theme.motion.closeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local NUDGE = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WOBBLE = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
local WOBBLE_DEGREES = 6
local COVER = TweenInfo.new(Theme.motion.openSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BLUR = 18 -- as gameplay's honeycomb (Cues.honeycomb.blur)
local INERT_FADE = 0.5 -- a greyed-out control's words and icons
local SWITCH_FADE = 0.55 -- the Friends switch's word that isn't picked

local inert: { [GuiObject]: boolean } = {} -- greyed-out controls: no hover, no press, no action

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

-- Hover grows, press shrinks (style motion), using each button's "Press" UIScale; both make their
-- sound (client/UiSounds) unless the button is greyed out.
local function juice(button: GuiButton)
	local scale = button:FindFirstChild("Press") :: UIScale?
	if not scale then
		return
	end
	local function to(value: number)
		TweenService:Create(scale, NUDGE, { Scale = if inert[button] then 1 else value }):Play()
	end
	button.MouseEnter:Connect(function()
		to(Theme.motion.hoverScale)
		if not inert[button] then
			UiSounds.hover()
		end
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		to(Theme.motion.pressScale)
		if not inert[button] then
			UiSounds.press()
		end
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
	UiSounds.deny()
	local rest = button.Rotation
	local tween = TweenService:Create(button, WOBBLE, { Rotation = rest + WOBBLE_DEGREES })
	tween.Completed:Once(function()
		button.Rotation = rest
		wobbling[button] = nil
	end)
	tween:Play()
end

-- Fades a control's words and icons; a button's own background stays solid.
local function fade(root: Instance, amount: number)
	local parts = root:GetDescendants()
	table.insert(parts, root)
	for _, part in parts do
		if part:IsA("TextLabel") then
			part.TextTransparency = amount
		elseif part:IsA("UIStroke") then
			part.Transparency = amount
		elseif part:IsA("ImageLabel") then
			part.ImageTransparency = amount
		end
	end
end

-- Greys a button out (theme `locked`, faded words) and makes it ignore the player, or brings it back.
local function setInert(button: ImageButton, on: boolean)
	inert[button] = if on then true else nil
	if on then
		button.ImageColor3 = C.locked
	end
	fade(button, if on then INERT_FADE else 0)
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

local closing: { [GuiObject]: Tween } = {} -- frames shrinking away (show cancels it to reopen)
local function show(frame: GuiObject, visible: boolean)
	-- lihfolk-ignore: findfirstchild-chain (nil-checked below before use)
	local scale = frame:FindFirstChild("Scale") :: UIScale?
	local shutting = closing[frame]
	if shutting then
		if not visible then
			return
		end
		closing[frame] = nil
		shutting:Cancel()
	elseif visible == frame.Visible then
		return
	end
	UiSounds.window(visible)
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
		closing[frame] = tween
		tween.Completed:Once(function()
			if closing[frame] == tween then
				closing[frame] = nil
				frame.Visible = false
			end
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
	local stats = find(hud, "Stats")
	local admin = find(hud, "Admin")

	local screen = find(hud, "PadScreen")
	local screenClose = find(screen, "CloseButton")
	local cover = find(hud, "PadCover")
	local blur = Lighting:FindFirstChild("PadBlur")
	assert(blur and blur:IsA("BlurEffect"), "Lighting is missing PadBlur (a BlurEffect, built in Studio)")
	local shade = cover.BackgroundTransparency -- Studio's value: how dark the cover gets
	cover.BackgroundTransparency = 1
	cover.Visible = false
	blur.Size = 0

	local create = find(screen, "CreateParty")
	local mapCard = find(create, "Body.Map.Card")
	local mapTag = find(mapCard, "Tag")
	local mapTitle = find(mapCard, "MapName")
	local mapInfo = find(mapCard, "Info")
	local mapLock = find(mapCard, "Lock")
	local mapLockText = find(mapCard, "LockText")
	local mapArt = find(mapCard, "Art")
	local prev = find(create, "Body.Map.Prev")
	local nextMap = find(create, "Body.Map.Next")
	local dotRow = find(create, "Body.Map.Dots")
	local dotTemplate = find(dotRow, "Dot")
	local count = find(create, "Body.Players.Count")
	local people = find(create, "Body.Players.People")
	local personTemplate = find(people, "Person")
	local minus = find(create, "Body.Players.Minus")
	local plus = find(create, "Body.Players.Plus")
	local toggle = find(create, "Body.Friends.Toggle")
	local knob = find(toggle, "Knob")
	local switchOff = find(toggle, "Off")
	local switchOn = find(toggle, "On")
	local createButton = find(create, "Body.CreateButton")
	local createLabel = find(createButton, "Label")
	-- the knob sits on OFF as built; ON is that spot mirrored across the switch
	local knobOff = knob.Position
	local knobOn = UDim2.new(1 - knobOff.X.Scale - knob.Size.X.Scale, -knobOff.X.Offset - knob.Size.X.Offset, knobOff.Y.Scale, knobOff.Y.Offset)
	-- ready colours as built in Studio (read before anything greys them out)
	local go = createButton.ImageColor3
	local danger = screenClose.ImageColor3
	local stepColour = minus.ImageColor3
	local trackColour = toggle.ImageColor3
	dotTemplate.Visible = false
	local dots: { ImageLabel } = {}
	for i in Maps.list do
		local dot = dotTemplate:Clone()
		dot.Name = `Dot{i}`
		dot.LayoutOrder = i
		dot.Visible = true
		dot.Parent = dotRow
		dots[i] = dot
	end
	personTemplate.Visible = false
	local persons: { GuiObject } = {}
	for i = 1, SessionRules.MAX_PLAYERS do
		local person = personTemplate:Clone()
		person.Name = `Person{i}`
		person.LayoutOrder = i
		person.Parent = people
		persons[i] = person
	end

	local savedPanel = find(screen, "SavedRuns")
	local empty = find(savedPanel, "Body.Empty")
	local list = find(savedPanel, "Body.List")
	local template = find(list, "CardTemplate")
	template.Visible = false

	local confirm = find(hud, "Confirm")
	local question = find(confirm, "Question")
	local yes = find(confirm, "YesButton")
	local yesLabel = find(yes, "Label")
	local no = find(confirm, "CancelButton")
	local noLabel = find(no, "Label")
	local neutral = no.ImageColor3
	confirm.Visible = false

	local bar = find(hud, "HostBar")
	local barLine = find(bar, "Line")
	local barDetail = find(bar, "Detail")
	local startButton = find(bar, "StartButton")
	local leaveButton = find(bar, "LeaveButton")
	-- a member has no Start: their Leave takes its place
	local leaveSpot, startSpot = leaveButton.Position, startButton.Position

	assert(typeof(screen:GetAttribute("DesignSize")) == "Vector2", "LobbyHud.PadScreen needs a Vector2 attribute DesignSize (built in Studio)")
	assert(typeof(confirm:GetAttribute("DesignSize")) == "Vector2", "LobbyHud.Confirm needs a Vector2 attribute DesignSize (built in Studio)")
	-- Rotating a phone or resizing the window refits the open windows.
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		for _, frame in { screen, confirm } do
			local scale = frame:FindFirstChild("Scale")
			if frame.Visible and scale and scale:IsA("UIScale") then
				scale.Scale = fitOf(frame)
			end
		end
	end)
	local settings = { maxPlayers = 4, mapId = Maps.list[1].id, friendsOnly = false }
	local mapIndex = 1
	local unlocked: { [string]: boolean } = {}
	local runs = {} -- the saved-run cards last sent (SessionRules.savedFor reads mapId and memberIds)
	local padIds: { number } = {} -- who is on the pad, the host first
	local cards: { Instance } = {}
	local onYes: (() -> ())? = nil -- what the open question does on its Yes button
	local onNo: (() -> ())? = nil -- and on its other button (nil: just closes)
	local lastKind = "none"

	-- The teleport screen: a copy of ReplicatedStorage.Transition covers the lobby, and the teleport
	-- takes it along (handed over at the start and again on its still frame, whichever the hop
	-- catches); it opens again if the party stays.
	local screenTemplate = ReplicatedStorage:WaitForChild("Transition", 10)
	assert(screenTemplate and screenTemplate:IsA("ScreenGui"), "ReplicatedStorage is missing Transition (a ScreenGui, built in Studio)")
	local lacking = Transition.missing(screenTemplate)
	assert(not lacking, `ReplicatedStorage.Transition is missing {lacking} (built in Studio)`)
	local leaving: ScreenGui? = nil
	local function leave(state)
		if leaving then
			return
		end
		local gui = screenTemplate:Clone() :: ScreenGui
		gui.Parent = player:WaitForChild("PlayerGui")
		leaving = gui
		Transition.setRun(gui, { mapName = state.mapName, fill = state.fill })
		Transition.out(gui, state.look, function()
			if leaving == gui then
				TeleportService:SetTeleportGui(gui)
			end
		end)
		TeleportService:SetTeleportGui(gui)
	end
	local function stay()
		local gui = leaving
		if gui then
			leaving = nil
			Transition.reveal(gui)
		end
	end
	TeleportService.TeleportInitFailed:Connect(function(failed: Player)
		if failed == player then
			stay()
		end
	end)

	-- safe: Yes loses nothing (Continue), so it isn't red
	local function ask(text: string, yesText: string, fn: () -> (), noText: string?, noFn: (() -> ())?, safe: boolean?)
		question.Text = text
		yesLabel.Text = yesText
		yes.ImageColor3 = if safe then go else danger
		no.ImageColor3 = if safe then C.locked else neutral
		noLabel.Text = noText or "Cancel"
		onYes, onNo = fn, noFn
		show(confirm, true)
	end

	local function closeAsk()
		onYes, onNo = nil, nil
		show(confirm, false)
	end

	-- PadScreen with its cover: the world blurs and darkens behind it, and the HUD around it steps
	-- aside (Admin comes back only for admins, as client/init shows it).
	local screenOpen = false
	local function showScreen(visible: boolean)
		show(screen, visible)
		if visible == screenOpen then
			return
		end
		screenOpen = visible
		stats.Visible = not visible
		admin.Visible = not visible and player:GetAttribute("Admin") == true
		cover.Visible = true
		local info = if visible then COVER else SHUT
		TweenService:Create(blur, info, { Size = if visible then BLUR else 0 }):Play()
		local fadeCover = TweenService:Create(cover, info, { BackgroundTransparency = if visible then shade else 1 })
		fadeCover.Completed:Once(function()
			if not screenOpen then
				cover.Visible = false
			end
		end)
		fadeCover:Play()
	end

	-- The saved run Create would start over (New Game: one save per map per team), or nil.
	local function replaced()
		local i = SessionRules.savedFor(runs, Maps.list[mapIndex].id, SessionRules.newTeam(settings.maxPlayers, padIds))
		return if i then runs[i] else nil
	end

	local function refreshCreate()
		local map = Maps.list[mapIndex]
		local soon = map.comingSoon == true
		local isOpen = not soon and unlocked[map.id] == true
		mapTag.Text = `MAP {mapIndex}`
		mapTitle.Text = if soon then "COMING SOON" else map.name
		mapInfo.Text = `x{map.waterMultiplier} water  ·  +{map.rewardRaindrops} Raindrops`
		mapInfo.Visible = not soon
		mapArt.Visible = isOpen
		mapLock.Image = if soon then Theme.images.unknown else Theme.images.lock
		mapLock.Visible = not isOpen
		mapLockText.Visible = not isOpen and not soon
		if not isOpen and not soon then
			local before = map.unlockedBy and Maps.get(map.unlockedBy)
			mapLockText.Text = `Clear {if before then before.name else "the map before"} to unlock`
		end
		for i, dot in dots do
			dot.Image = if i == mapIndex then Theme.images.pipFull else Theme.images.pipEmpty
		end
		prev.Visible = mapIndex > 1
		nextMap.Visible = mapIndex < #Maps.list
		local n = settings.maxPlayers
		count.Text = tostring(n)
		for i, person in persons do
			person.Visible = i <= n
		end
		minus.ImageColor3 = if n > 1 then stepColour else C.locked
		plus.ImageColor3 = if n < SessionRules.MAX_PLAYERS then stepColour else C.locked
		local friendsOnly = settings.friendsOnly
		toggle.ImageColor3 = trackColour
		knob.ImageColor3 = if friendsOnly then go else danger
		TweenService:Create(knob, NUDGE, { Position = if friendsOnly then knobOn else knobOff }):Play()
		createButton.ImageColor3 = if isOpen then go else C.locked
		createLabel.Text = if soon then "COMING SOON" elseif not isOpen then "LOCKED" elseif replaced() then "NEW GAME" else "CREATE"
		-- a map that isn't out yet: every setting and Create grey out and ignore the player
		for _, control in { minus, plus, toggle, createButton } do
			setInert(control, soon)
		end
		fade(count, if soon then INERT_FADE else 0)
		fade(people, if soon then INERT_FADE else 0)
		if not soon then
			fade(if friendsOnly then switchOff else switchOn, SWITCH_FADE)
		end
	end

	local function fillCard(card: Instance, run)
		find(card, "MapName").Text = if run.mapName ~= "" then run.mapName else "Unknown run"
		find(card, "LastPlayed").Text = playedAgo(run.lastPlayed)
		find(card, "Members").Text = run.members
		local fill = math.clamp(run.fill, 0, 1)
		local fillBar = find(card, "FillBar.Fill")
		fillBar.Size = UDim2.fromScale(fill, 1)
		fillBar.Visible = fill > 0 -- its round ends would show as a sliver at 0
		find(card, "FillBar.Label").Text = `{math.floor(fill * 100)}% full`
		local reason = find(card, "Reason")
		reason.Text = run.reason
		reason.Visible = run.reason ~= ""
		local load = find(card, "LoadButton")
		load.ImageColor3 = if run.canLoad then go else C.locked
		local delete = find(card, "DeleteButton")
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

	for _, b in { screenClose, prev, nextMap, minus, plus, toggle, createButton, yes, no, startButton, leaveButton } do
		juice(b)
	end
	screenClose.Activated:Connect(function()
		action:FireServer("leave")
		closeAsk()
		showScreen(false)
	end)
	leaveButton.Activated:Connect(function()
		action:FireServer("leave")
	end)
	yes.Activated:Connect(function()
		local fn = onYes
		closeAsk()
		if fn then
			fn()
		end
	end)
	no.Activated:Connect(function()
		local fn = onNo
		closeAsk()
		if fn then
			fn()
		end
	end)
	prev.Activated:Connect(function()
		mapIndex = math.max(1, mapIndex - 1)
		refreshCreate()
	end)
	nextMap.Activated:Connect(function()
		mapIndex = math.min(#Maps.list, mapIndex + 1)
		refreshCreate()
	end)
	minus.Activated:Connect(function()
		if inert[minus] then
			return
		end
		settings.maxPlayers = math.max(1, settings.maxPlayers - 1)
		refreshCreate()
	end)
	plus.Activated:Connect(function()
		if inert[plus] then
			return
		end
		settings.maxPlayers = math.min(SessionRules.MAX_PLAYERS, settings.maxPlayers + 1)
		refreshCreate()
	end)
	toggle.Activated:Connect(function()
		if inert[toggle] then
			return
		end
		settings.friendsOnly = not settings.friendsOnly
		refreshCreate()
	end)
	createButton.Activated:Connect(function()
		if inert[createButton] then
			return
		end
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
		if kind == "teleporting" then
			leave(state)
		else
			stay()
		end
		if kind == "replace" then
			-- Create found this team's save on the map (one on nobody's Saved Runs): ask before erasing it
			local chosen = table.clone(settings)
			ask(`Your team already has a saved run on {state.mapName} ({state.percent}% filled). Creating erases it. Start over?`, "Erase and start", function()
				chosen.replace = state.key
				action:FireServer("open", chosen)
			end)
			return
		elseif kind == "existing" then
			-- Start found the team's save on this map: continue it, or (asked again) start over
			local key = state.key
			local function restart()
				ask(`This erases your team's run on {state.mapName} ({state.percent}% filled). Start over?`, "Erase and start", function()
					action:FireServer("restart", key)
				end)
			end
			if state.finished then
				ask(`Your team already filled the ocean on {state.mapName}. Play it again from empty?`, "Start over", function()
					action:FireServer("restart", key)
				end)
			else
				ask(`Your team has a saved run on {state.mapName} ({state.percent}% filled). Continue it?`, "Continue", function()
					action:FireServer("continue", key)
				end, "Start over", restart, true)
			end
			return
		end
		hint.Visible = kind == "none"
		-- a question belongs to the screen it was asked on; Start's question outlives the launch it stopped
		local was = lastKind
		lastKind = kind
		if kind == "choose" then
			unlocked = state.unlocked
			padIds = state.padIds
			refreshSaved(state)
			refreshCreate()
			showScreen(true)
			show(bar, false)
			return
		end
		if was == "choose" or kind == "none" then
			closeAsk()
		end
		showScreen(false)
		if kind == "hosting" or kind == "member" then
			barLine.Text = if kind == "hosting" then "YOUR SESSION" else `{string.upper(state.host)}'S SESSION`
			local detail = `{state.count}/{state.max} players - {state.mapName}`
			if state.saved then
				detail ..= if state.waiting ~= "" then ` - waiting for {state.waiting}` else " - saved run"
			elseif state.friendsOnly then
				detail ..= " - Friends"
			end
			if state.startsOver then
				detail ..= ` - starts over your saved run ({state.startsOver}% filled)`
			end
			barDetail.Text = detail
			startButton.Visible = kind == "hosting"
			leaveButton.Position = if kind == "hosting" then leaveSpot else startSpot
			leaveButton.Visible = true
			show(bar, true)
		elseif kind == "countdown" then
			-- the launch counts down (client/Countdown shows the number); Leave stops it
			barLine.Text = "STARTING..."
			barDetail.Text = "Leave to stop"
			startButton.Visible = false
			leaveButton.Position = startSpot
			leaveButton.Visible = true
			show(bar, true)
		elseif kind == "launching" or kind == "teleporting" then
			barLine.Text = "STARTING..."
			barDetail.Text = state.title or ""
			startButton.Visible = false
			leaveButton.Visible = false
			show(bar, true)
		else
			show(bar, false)
		end
	end)
	hint.Visible = true
	refreshCreate()
end

return Session
