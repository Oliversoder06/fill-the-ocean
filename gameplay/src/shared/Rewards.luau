--!strict
-- Contribution share and the end-of-run reward split.

export type Entry = { id: any, share: number, pouredEveryStage: boolean }

local POT_PER_PLAYER = 100
local GUARANTEED = POT_PER_PLAYER / 2

local Rewards = {}

-- Weighted sum of the player's fraction of each stage's litres. Stages nobody poured in count 0.
function Rewards.shares(weights: { number }, playerLitres: { number }, allLitres: { number }): number
	local share = 0
	for stage, weight in weights do
		local all = allLitres[stage] or 0
		if all > 0 then
			share += weight * (playerLitres[stage] or 0) / all
		end
	end
	return share
end

-- Pot = 100 per player present. Half is 50 each for players who poured in every stage, half by share.
function Rewards.split(players: { Entry }): { [any]: number }
	local shareHalf = GUARANTEED * #players
	local result = {}
	for _, p in players do
		local reward = shareHalf * p.share + (if p.pouredEveryStage then GUARANTEED else 0)
		result[p.id] = math.floor(reward + 0.5)
	end
	return result
end

return Rewards
