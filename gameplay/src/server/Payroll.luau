-- Coins earned on a tick (the team's buildings, each player's staff) wait here and are paid every
-- PAY_SECONDS, so the coin burst (client/Payout) doesn't fire every second. server/Run also pays
-- out before a player joins or leaves, before its last saves and at the run's end, so no coins
-- wait across those (owed coins belong to players present when they were earned).
local RunService = game:GetService("RunService")

local PAY_SECONDS = 10 -- seconds between paydays

export type Hooks = {
	states: { [Player]: any }, -- server/Run's player states (money)
	publish: (Player) -> (), -- publish a player's money
}

local Payroll = {}

local hooks: Hooks
local owed: { [Player]: number } = {}

-- `coins` for `player`, paid on the next payday.
function Payroll.owe(player: Player, coins: number)
	owed[player] = (owed[player] or 0) + coins
end

-- `coins` split evenly between the players present now (the team's buildings, D2).
function Payroll.share(coins: number)
	local present = {}
	for player in hooks.states do
		table.insert(present, player)
	end
	for _, player in present do
		Payroll.owe(player, coins / #present)
	end
end

-- Pays everything owed now.
function Payroll.payNow()
	for player, coins in owed do
		local state = hooks.states[player]
		if state then
			state.money += coins
			hooks.publish(player)
		else
			warn(`[Payroll] {player.Name} left before being paid {coins} coins (server/Run pays out before removing a player)`)
		end
	end
	table.clear(owed)
end

function Payroll.start(runHooks: Hooks)
	hooks = runHooks
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= PAY_SECONDS then
			since = 0
			Payroll.payNow()
		end
	end)
end

return Payroll
