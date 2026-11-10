-- Coins earned on a tick (the team's buildings and staff) wait here and go into the team's wallet
-- every PAY_SECONDS, so the Wallet attribute doesn't change every second. server/Run also pays out
-- before a player leaves, before its last saves, at the run's end and before an admin reset, so no
-- coins wait across those.
local RunService = game:GetService("RunService")

local PAY_SECONDS = 10 -- seconds between paydays

export type Hooks = {
	pay: (number) -> (), -- coins into the team's wallet (server/Run)
}

local Payroll = {}

local hooks: Hooks
local owed = 0

-- `coins` for the team, paid on the next payday.
function Payroll.owe(coins: number)
	owed += coins
end

-- Pays everything owed now.
function Payroll.payNow()
	if owed > 0 then
		local coins = owed
		owed = 0
		hooks.pay(coins)
	end
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
