-- Session pads (workspace.Lobby.Pads.Pad1..PadN, built in Studio). Each pad Model has a "Zone" part
-- and a sign with "Title" and "Status" labels. A pad holds one session:
--   empty       the first player to step on becomes host and gets the setup window
--   configuring the host picks max players, difficulty (one they unlocked) and friends-only
--   open        others step on to join (rules in Common.SessionRules); it launches when full or
--               when the host presses Start
-- At launch the lobby writes a run ticket and teleports the party into a fresh reserved gameplay
-- server. Clients only send SessionAction("open" | "cancel" | "start"); everything is checked here.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Difficulty = require(ReplicatedStorage.Common.Difficulty)
local Places = require(ReplicatedStorage.Common.Places)
local Retry = require(ReplicatedStorage.Common.Retry)
local RunTicket = require(ReplicatedStorage.Common.RunTicket)
local SessionRules = require(ReplicatedStorage.Common.SessionRules)
local Profiles = require(script.Parent.Profiles)

local POLL = 0.25
local COOLDOWN = 4 -- after a launch or a failed launch
local ZONE_HEIGHT = 10
local ACTIONS_PER_SECOND = 4
local ACTIONS = { open = true, cancel = true, start = true }

local Queue = {}

type Pad = {
	name: string,
	zone: BasePart,
	title: TextLabel,
	status: TextLabel,
	host: Player?,
	settings: SessionRules.Settings?,
	members: { Player }, -- join order, host included
	declined: { [Player]: boolean }, -- must step off before they can host again
	told: { [Player]: string },
	friends: { [number]: boolean | "pending" }, -- host-friend lookups for this session
	launching: boolean,
}

local remotes: { [string]: RemoteEvent } = {}
local pads: { Pad } = {}
local lastSent: { [Player]: string } = {}
local actionWindow: { [Player]: { start: number, count: number } } = {}

local function tell(player: Player, text: string)
	remotes.Notice:FireClient(player, text)
end

-- Tells a player something once per stay on the pad (the key changes when the reason changes).
local function tellOnce(pad: Pad, player: Player, key: string, text: string)
	if pad.told[player] ~= key then
		pad.told[player] = key
		tell(player, text)
	end
end

local function padParts(model: Model)
	local zone = model:FindFirstChild("Zone")
	local title = model:FindFirstChild("Title", true)
	local status = model:FindFirstChild("Status", true)
	assert(zone and zone:IsA("BasePart"), `{model:GetFullName()} is missing its Zone part`)
	assert(title and title:IsA("TextLabel"), `{model:GetFullName()} is missing its Title label`)
	assert(status and status:IsA("TextLabel"), `{model:GetFullName()} is missing its Status label`)
	return zone, title, status
end

-- Players whose character root is inside the pad's zone box.
local function occupants(zone: BasePart): { [Player]: boolean }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local characters = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(characters, p.Character)
		end
	end
	params.FilterDescendantsInstances = characters
	local found = {}
	local cf = zone.CFrame * CFrame.new(0, ZONE_HEIGHT / 2, 0)
	for _, part in workspace:GetPartBoundsInBox(cf, zone.Size + Vector3.new(0, ZONE_HEIGHT, 0), params) do
		local player = Players:GetPlayerFromCharacter(part.Parent)
		if player and part.Name == "HumanoidRootPart" then
			found[player] = true
		end
	end
	return found
end

local function isMember(pad: Pad, player: Player): boolean
	return table.find(pad.members, player) ~= nil
end

local function padOf(player: Player): Pad?
	for _, pad in pads do
		if isMember(pad, player) then
			return pad
		end
	end
	return nil
end

local function reset(pad: Pad)
	pad.host, pad.settings = nil, nil
	pad.members = {}
	pad.friends = {}
end

-- Friends-only: is this player friends with the host? Looked up in the background (it yields).
local function hostFriend(pad: Pad, player: Player): boolean?
	local host = pad.host
	if not host then
		return false
	end
	local cached = pad.friends[player.UserId]
	if cached == "pending" then
		return nil
	elseif cached ~= nil then
		return cached :: boolean
	end
	pad.friends[player.UserId] = "pending"
	local hostId = host.UserId
	task.spawn(function()
		local ok, result = pcall(function()
			return player:IsFriendsWith(hostId)
		end)
		if not ok then
			warn(`[Queue] friend check failed for {player.Name}: {result}`)
		end
		if pad.host and pad.host.UserId == hostId then
			pad.friends[player.UserId] = ok and result == true
		end
	end)
	return nil
end

-- What each player's client should show; sent only when it changes.
local function sendState(player: Player, state: { [string]: any })
	local key = HttpService:JSONEncode(state)
	if lastSent[player] ~= key then
		lastSent[player] = key
		remotes.SessionState:FireClient(player, state)
	end
end

local function launch(pad: Pad)
	local settings = pad.settings :: SessionRules.Settings
	local party = table.clone(pad.members)
	pad.launching = true
	pad.title.Text = `Difficulty {settings.difficulty}`
	pad.status.Text = "Starting..."
	for _, p in party do
		sendState(p, { kind = "launching" })
	end
	local members = {}
	for _, p in party do
		table.insert(members, p.UserId)
	end
	if RunService:IsStudio() then
		for _, p in party do
			tell(p, "Teleports only work in the published game. In Studio, test runs in the gameplay place.")
		end
	else
		local serverId = HttpService:GenerateGUID(false)
		local ok, err = RunTicket.write(serverId, { difficulty = settings.difficulty, members = members })
		if ok then
			local options = Instance.new("TeleportOptions")
			options.ReservedServerId = serverId
			ok, err = Retry.run("teleport party", function()
				TeleportService:TeleportAsync(Places.GAMEPLAY, party, options)
			end, 3, 1)
		end
		if not ok then
			warn(`[Queue] launch failed on {pad.name}: {err}`)
			for _, p in party do
				tell(p, "Couldn't start the run. Please try again.")
			end
		end
	end
	task.wait(COOLDOWN)
	-- whoever is still standing here (Studio, failed teleport) must step off before hosting again
	for p in occupants(pad.zone) do
		pad.declined[p] = true
	end
	for _, p in party do
		if p.Parent then
			sendState(p, { kind = "none" })
		end
	end
	reset(pad)
	pad.launching = false
end

local function updateSign(pad: Pad)
	local settings = pad.settings
	if not pad.host then
		pad.title.Text = "Open Pad"
		pad.status.Text = "Step on to host"
	elseif not settings then
		pad.title.Text = "Setting up..."
		pad.status.Text = (pad.host :: Player).DisplayName
	else
		pad.title.Text = `Difficulty {settings.difficulty}`
		pad.status.Text = `{#pad.members}/{settings.maxPlayers}{if settings.friendsOnly then " - Friends" else " - Join!"}`
	end
end

local function update(pad: Pad)
	if pad.launching then
		return
	end
	local here = occupants(pad.zone)

	-- People who stepped off or left: drop them; pass host on if needed.
	for i = #pad.members, 1, -1 do
		local p = pad.members[i]
		if not here[p] or not p.Parent then
			table.remove(pad.members, i)
			if p == pad.host then
				local ids = {}
				for _, m in pad.members do
					table.insert(ids, m.UserId)
				end
				local nextId = SessionRules.nextHost(ids, p.UserId)
				pad.host = if nextId then Players:GetPlayerByUserId(nextId) else nil
				if pad.host and pad.settings then
					tell(pad.host, "You're the host now. Press Start when everyone's ready.")
				end
				pad.friends = {}
			end
			if p.Parent then
				sendState(p, { kind = "none" })
			end
		end
	end
	if #pad.members == 0 then
		reset(pad)
	end
	for p in pad.declined do
		if not here[p] then
			pad.declined[p] = nil
		end
	end
	for p in pad.told do
		if not here[p] then
			pad.told[p] = nil
		end
	end

	-- Empty pad: the first eligible player on it hosts and gets the setup window.
	if not pad.host then
		for p in here do
			if not pad.declined[p] and not padOf(p) and p:GetAttribute("DataReady") then
				pad.host = p
				pad.members = { p }
				pad.settings = nil
				pad.told[p] = "host"
				break
			end
		end
	end

	-- Everyone else on the pad: wait while the host sets up, then join if allowed.
	local settings = pad.settings
	for p in here do
		if not isMember(pad, p) and not padOf(p) and not pad.declined[p] then
			if not settings then
				tellOnce(pad, p, "setup", "The host is setting up this session...")
			else
				local friend = if settings.friendsOnly then hostFriend(pad, p) else false
				if friend ~= nil then
					local reason = SessionRules.joinError(settings, #pad.members, friend)
					if reason == "full" then
						tellOnce(pad, p, "full", "This session is full.")
					elseif reason == "friends" then
						tellOnce(pad, p, "friends", "This session is friends only.")
					else
						table.insert(pad.members, p)
						tellOnce(pad, p, "joined", `Joined {(pad.host :: Player).DisplayName}'s session!`)
					end
				end
			end
		end
	end

	-- Tell each member's client what to show.
	for _, p in pad.members do
		if p == pad.host and not settings then
			sendState(p, { kind = "configure", pad = pad.name, unlocked = math.min(Profiles.unlocked(p), Difficulty.MAX) })
		elseif settings then
			sendState(p, {
				kind = if p == pad.host then "hosting" else "member",
				host = (pad.host :: Player).DisplayName,
				count = #pad.members,
				max = settings.maxPlayers,
				difficulty = settings.difficulty,
				friendsOnly = settings.friendsOnly,
			})
		end
	end

	updateSign(pad)
	if settings and SessionRules.isFull(settings, #pad.members) then
		task.spawn(launch, pad)
	end
end

local function rateLimited(player: Player): boolean
	local now = os.clock()
	local w = actionWindow[player]
	if not w or now - w.start >= 1 then
		w = { start = now, count = 0 }
		actionWindow[player] = w
	end
	w.count += 1
	return w.count > ACTIONS_PER_SECOND
end

local function onAction(player: Player, action: unknown, payload: unknown)
	if type(action) ~= "string" or not ACTIONS[action] or rateLimited(player) then
		return
	end
	local pad = padOf(player)
	if not pad or pad.host ~= player or pad.launching then
		return
	end
	if action == "open" and not pad.settings then
		local settings = SessionRules.validate(payload, Profiles.unlocked(player))
		if settings then
			pad.settings = settings
			if settings.maxPlayers == 1 then
				tell(player, "Starting your solo run!")
			end
		else
			tell(player, "Those settings aren't allowed.")
		end
	elseif action == "cancel" and not pad.settings then
		pad.declined[player] = true
		sendState(player, { kind = "none" })
		reset(pad)
	elseif action == "start" and pad.settings then
		task.spawn(launch, pad)
	end
end

function Queue.start()
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	for _, name in { "Notice", "SessionState", "SessionAction" } do
		local r = folder:WaitForChild(name, 10)
		assert(r and r:IsA("RemoteEvent"), `ReplicatedStorage.Remotes is missing {name} (Rojo project; restart rojo serve)`)
		remotes[name] = r
	end
	local lobby = workspace:FindFirstChild("Lobby")
	local padsFolder = lobby and lobby:FindFirstChild("Pads")
	assert(padsFolder, "workspace.Lobby.Pads is missing (the lobby map lives in the place)")
	local models = padsFolder:GetChildren()
	table.sort(models, function(a, b)
		return a.Name < b.Name
	end)
	for _, model in models do
		if model:IsA("Model") then
			local zone, title, status = padParts(model)
			table.insert(pads, {
				name = model.Name,
				zone = zone,
				title = title,
				status = status,
				host = nil,
				settings = nil,
				members = {},
				declined = {},
				told = {},
				friends = {},
				launching = false,
			})
		end
	end
	assert(#pads > 0, "workspace.Lobby.Pads has no pads")
	remotes.SessionAction.OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
		actionWindow[player] = nil
	end)
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(`[Queue] teleport failed for {player.Name}: {result} {message}`)
		tell(player, "Teleport failed. Step on a pad again to retry.")
	end)
	task.spawn(function()
		while true do
			for _, pad in pads do
				update(pad)
			end
			task.wait(POLL)
		end
	end)
end

return Queue
