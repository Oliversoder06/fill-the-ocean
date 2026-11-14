-- Coins earned on a tick (the team's buildings and staff) wait here and go into the team's wallet
-- every PAY_SECONDS, so the Wallet attribute doesn't change every second. server/Run also pays out
-- before a player leaves, before its last saves, at the run's end and before an admin reset, so no
-- coins wait across those. Each is owed under its analytics income reason (common/Analytics.MONEY).
local RunService = game:GetService("RunService")

local PAY_SECONDS = 10 -- seconds between paydays

export type Hooks = {
	pay: (number, string) -> (), -- coins into the team's wallet, and their reason (server/Run)
}

local Payroll = {}

local hooks: Hooks
local owed: { [string]: number } = {}

-- `coins` for the team (income `reason`: "Staff", "Buildings"), paid on the next payday.
function Payroll.owe(coins: number, reason: string)
	owed[reason] = (owed[reason] or 0) + coins
end

-- Pays everything owed now.
function Payroll.payNow()
	for reason, coins in owed do
		owed[reason] = nil
		if coins > 0 then
			hooks.pay(coins, reason)
		end
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
