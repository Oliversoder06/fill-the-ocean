-- Perfect-player timing check for tuning. Run from gameplay/: lune run tools/simulate
-- One solo player, whole trips (walk to source, scoop hold, walk back, pour hold), buys the moment
-- they can afford the next offer (catch-up items first). Uses the game's own modules.
local Config = require("../src/shared/Config")
local Ladder = require("../src/shared/Ladder")
local Water = require("../src/shared/Water")

local function clock(t: number): string
	return string.format("%d:%02d", t // 60, math.floor(t % 60))
end

local stats = table.clone(Config.start)
local money, carried = 0, 0
local bought = {}
local runTime = 0

for stageIndex, stage in Config.stages do
	local target = Water.target(stage.waterPerPlayer, 1, 1)
	local current, t = 0, 0
	local walkFirst = Config.tripDistance / 2 -- players start at Spawn, halfway along the path
	print(`\n== {stage.name}: target {target} L ==`)
	while current < target - 1e-6 do
		-- go scoop a full tool unless already full
		if carried < stats.capacity then
			t += (walkFirst or Config.tripDistance) / stats.walkSpeed
			t += stats.actSeconds -- one scoop prompt hold fills the tool
			carried = stats.capacity
			t += Config.tripDistance / stats.walkSpeed
		end
		walkFirst = nil
		local litres = math.min(carried, target - current)
		t += stats.actSeconds -- one pour prompt hold empties the tool
		carried -= litres
		current += litres
		money += litres * stage.coinsPerLitre
		-- buy everything affordable now
		while true do
			local missed = Ladder.missedFromEarlierStages(Config, stageIndex, bought)
			local s, item
			if missed[1] then
				s, item = missed[1].stage, missed[1].item
			else
				s, item = stageIndex, Ladder.nextItem(Config, stageIndex, bought[stageIndex] or 0)
			end
			if not item or money + 1e-6 < item.cost then
				break
			end
			money -= item.cost
			bought[s] = (bought[s] or 0) + 1
			stats = Ladder.apply(stats, item)
			print(`  {clock(t)}  {item.name}`)
		end
	end
	runTime += t
	print(`  {clock(t)}  FULL (target {stage.minutes}:00)`)
end
print(`\nRun total {clock(runTime)} (target 45:00, cards not counted)`)
