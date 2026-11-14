-- The lobby's analytics (docs/analytics.md): the first onboarding steps (Joined and LobbyLoaded at a
-- player's profile load, PartyStarted as their party launches), LoadTime, SaveUnavailable and a
-- SessionEnd for those who leave the game from here (a teleport into a run isn't a quit).
-- common/TelemetryCore sends them and keeps the session record; names come from common/Analytics.
-- A brand-new player (no profile stored yet) is entered into the one-time funnels here, once.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Analytics = require(ReplicatedStorage.Common.Analytics)
local PlayerData = require(ReplicatedStorage.Common.PlayerData)
local Progress = require(ReplicatedStorage.Common.Progress)
local TelemetryCore = require(ReplicatedStorage.Common.TelemetryCore)
local Admins = require(ServerStorage.GameplayShared.Admins)
local Config = require(ServerStorage.GameplayShared.Config)

local POLL = 5 -- seconds between idle checks
local MOVED = 2 -- studs that count as moving

local Telemetry = {}

type Facts = { joined: number, loaded: boolean, activeAt: number, lastPos: Vector3? }

local facts: { [Player]: Facts } = {}
local inParty: (Player) -> boolean -- set by start (server/Queue)

local function onboarding(player: Player, partyStarted: boolean)
	TelemetryCore.advance(player, "Onboarding", { Joined = true, LobbyLoaded = true, PartyStarted = partyStarted })
end

-- A player joined the lobby: their visit starts at once (their profile loads in server/Profiles).
function Telemetry.playerIn(player: Player)
	local now = os.clock()
	facts[player] = { joined = now, loaded = false, activeAt = now, lastPos = nil }
	TelemetryCore.join(player, false, nil)
end

-- server/Profiles loaded the player's progress (`data` nil: it failed with `err`); `isNew`: nothing
-- was stored yet. A new player is entered into the one-time funnels (one write) before Joined goes.
function Telemetry.loaded(player: Player, data: Progress.Data?, isNew: boolean)
	local f = facts[player]
	if not f then
		return
	end
	f.loaded = true
	local seconds = os.clock() - f.joined
	TelemetryCore.event(player, "LoadTime", seconds, { Place = "Lobby", Band = Analytics.bucket(Analytics.BANDS.load, seconds), WaitedOn = "Data" })
	TelemetryCore.note(player, "load", math.round(seconds * 10) / 10)
	if not data then
		TelemetryCore.event(player, "SaveUnavailable", 1, { Place = "Lobby" })
		return
	end
	local funnels = data.funnels
	if isNew and player.UserId > 0 then
		local entered, err = PlayerData.enterAnalytics(player.UserId)
		if not entered then
			warn(`[Telemetry] couldn't enter new player {player.Name} into the funnels: {err}`)
			TelemetryCore.track(player, true, nil)
			return
		end
		funnels = entered.funnels
	end
	TelemetryCore.track(player, isNew, funnels)
	onboarding(player, false)
end

-- The party's run starts: PartyStarted for each member (just before the teleport).
function Telemetry.partyStarted(party: { Player })
	for _, player in party do
		onboarding(player, true)
	end
end

-- The party's teleport went: their leaving the lobby isn't a quit.
function Telemetry.teleported(party: { Player })
	for _, player in party do
		TelemetryCore.teleporting(player)
	end
end

local function leave(player: Player)
	local f = facts[player]
	if not f then
		return
	end
	facts[player] = nil
	local doing = if not f.loaded then "Loading"
		elseif inParty(player) then "Party"
		elseif os.clock() - f.activeAt >= Analytics.IDLE_AFTER then "Idle"
		else "Roaming"
	TelemetryCore.leave(player, { Where = "Lobby", Doing = doing, Stage = "Lobby" }, {
		leave = { where = "Lobby", doing = doing, stage = "Lobby" },
	})
end

local function poll()
	local now = os.clock()
	for player, f in facts do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = if root and root:IsA("BasePart") then root.Position else nil
		if at and (not f.lastPos or (at - f.lastPos).Magnitude >= MOVED) then
			f.lastPos, f.activeAt = at, now
		end
	end
end

-- `partyOf`: whether a player stands in a party on a pad (server/Queue).
function Telemetry.start(partyOf: (Player) -> boolean)
	inParty = partyOf
	TelemetryCore.start({
		place = "Lobby",
		config = Config,
		admins = Admins,
		balance = function()
			return 0
		end,
		farewell = Telemetry.leave,
	})
	Players.PlayerAdded:Connect(Telemetry.playerIn)
	for _, player in Players:GetPlayers() do
		Telemetry.playerIn(player)
	end
	Players.PlayerRemoving:Connect(Telemetry.leave)
	task.spawn(function()
		while true do
			task.wait(POLL)
			local ok, err = pcall(poll)
			if not ok then
				warn(`[Telemetry] poll failed: {err}`)
			end
		end
	end)
end

Telemetry.leave = leave

-- Analytics never breaks the lobby: every call catches its own errors and warns.
for name, fn in Telemetry do
	if name ~= "start" then
		Telemetry[name] = function(...)
			local ok, err = pcall(fn, ...)
			if not ok then
				warn(`[Telemetry] {name} failed: {err}`)
			end
		end
	end
end

return Telemetry
