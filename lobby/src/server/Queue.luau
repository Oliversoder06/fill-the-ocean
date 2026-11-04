-- Queue pads: one per difficulty (workspace.Lobby.Pads.Pad1..Pad5, built in Studio). Each pad Model
-- has a "Zone" part, a "Difficulty" attribute and a sign with "Title" and "Status" labels.
-- Players standing on a pad they've unlocked start a countdown; at zero the lobby writes a run
-- ticket and teleports the group (max 10) into a fresh reserved gameplay server.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Difficulty = require(ReplicatedStorage.Common.Difficulty)
local Places = require(ReplicatedStorage.Common.Places)
local Retry = require(ReplicatedStorage.Common.Retry)
local RunTicket = require(ReplicatedStorage.Common.RunTicket)
local Profiles = require(script.Parent.Profiles)

local COUNTDOWN = 15
local MAX_PARTY = 10
local POLL = 0.5
local COOLDOWN = 4 -- after a launch or a failed launch
local ZONE_HEIGHT = 10

local Queue = {}

local notice: RemoteEvent
local pads = {}

local function tell(player: Player, text: string)
	notice:FireClient(player, text)
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
local function occupants(zone: BasePart): { Player }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local characters = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(characters, p.Character)
		end
	end
	params.FilterDescendantsInstances = characters
	local cf = zone.CFrame * CFrame.new(0, ZONE_HEIGHT / 2, 0)
	local found, seen = {}, {}
	for _, part in workspace:GetPartBoundsInBox(cf, zone.Size + Vector3.new(0, ZONE_HEIGHT, 0), params) do
		local player = Players:GetPlayerFromCharacter(part.Parent)
		if player and part.Name == "HumanoidRootPart" and not seen[player] then
			seen[player] = true
			table.insert(found, player)
		end
	end
	return found
end

local function launch(pad, party: { Player })
	pad.launching = true
	pad.status.Text = "Starting..."
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
		local ok, err = RunTicket.write(serverId, { difficulty = pad.difficulty, members = members })
		if ok then
			local options = Instance.new("TeleportOptions")
			options.ReservedServerId = serverId
			ok, err = Retry.run("teleport party", function()
				TeleportService:TeleportAsync(Places.GAMEPLAY, party, options)
			end, 3, 1)
		end
		if not ok then
			warn(`[Queue] launch failed for difficulty {pad.difficulty}: {err}`)
			for _, p in party do
				tell(p, "Couldn't start the run. Please try again.")
			end
		end
	end
	task.wait(COOLDOWN)
	pad.endsAt = nil
	pad.launching = false
end

local function update(pad)
	if pad.launching then
		return
	end
	local here = occupants(pad.zone)
	local party = {}
	local nowHere = {}
	for _, p in here do
		nowHere[p] = true
		if Profiles.unlocked(p) >= pad.difficulty then
			if #party < MAX_PARTY then
				table.insert(party, p)
			elseif not pad.told[p] then
				tell(p, "This run is full (10 players). Try another pad.")
			end
		elseif not pad.told[p] then
			tell(p, `Locked! Beat Difficulty {pad.difficulty - 1} to unlock this.`)
		end
		pad.told[p] = true
	end
	for p in pad.told do
		if not nowHere[p] then
			pad.told[p] = nil -- tell them again next time they step on
		end
	end

	if #party == 0 then
		pad.endsAt = nil
		pad.status.Text = if pad.difficulty == 1 then "Step on to play!" else `Unlock: beat Difficulty {pad.difficulty - 1}`
		return
	end
	pad.endsAt = pad.endsAt or (os.clock() + COUNTDOWN)
	local left = math.max(0, math.ceil(pad.endsAt - os.clock()))
	pad.status.Text = `{#party}/{MAX_PARTY} players   starting in {left}s`
	if left <= 0 then
		task.spawn(launch, pad, party)
	end
end

function Queue.start()
	notice = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Notice")
	local lobby = workspace:FindFirstChild("Lobby")
	local padsFolder = lobby and lobby:FindFirstChild("Pads")
	assert(padsFolder, "workspace.Lobby.Pads is missing (the lobby map lives in the place)")
	for level = 1, Difficulty.MAX do
		local model = padsFolder:FindFirstChild(`Pad{level}`)
		assert(model and model:IsA("Model"), `workspace.Lobby.Pads is missing Pad{level}`)
		local zone, title, status = padParts(model)
		title.Text = `Difficulty {level}`
		table.insert(pads, { difficulty = level, zone = zone, status = status, endsAt = nil, launching = false, told = {} })
	end
	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(`[Queue] teleport failed for {player.Name}: {result} {message}`)
		tell(player, "Teleport failed. Step on the pad again to retry.")
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
