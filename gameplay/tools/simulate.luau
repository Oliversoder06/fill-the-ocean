-- Perfect-player timing check for tuning. Run from gameplay/: lune run tools/simulate
-- One solo player, whole trips (walk to source, scoop sweeps until full, walk back, one quick
-- pour). After each pour they buy upgrades, cheapest affordable first, until nothing is affordable.
-- Uses the game's own modules. Pass "quiet" to print only the stage times.
local process = require("@lune/process")
local Config = require("../src/shared/Config")
local Ladder = require("../src/shared/Ladder")
local Water = require("../src/shared/Water")

local quiet = process.args[1] == "quiet"

local function clock(t: number): string
	return string.format("%d:%02d", t // 60, math.floor(t % 60))
end

local levels = {}
local stats = Ladder.stats(Config, levels)
local money, carried = 0, 0
local runTime = 0

-- The cheapest track this player can buy right now, or nil.
local function cheapest(stageIndex: number)
	local bestTrack, bestLevel = nil, nil
	for _, track in Config.tracks do
		local level, status = Ladder.offer(Config, levels, track.id, stageIndex)
		if status == "buy" and money + 1e-6 >= level.cost and (not bestLevel or level.cost < bestLevel.cost) then
			bestTrack, bestLevel = track, level
		end
	end
	return bestTrack, bestLevel
end

for stageIndex, stage in Config.stages do
	local target = Water.target(stage.waterPerPlayer, 1, 1)
	local current, t = 0, 0
	local walkFirst = Config.tripDistance / 2 -- players start at Spawn, halfway along the path
	print(`\n== {stage.name}: target {target} L ==`)
	while current < target - 1e-6 do
		if carried < stats.capacity then
			t += (walkFirst or Config.tripDistance) / stats.walkSpeed
			while carried < stats.capacity do -- one sweep per actSeconds until the tool is full
				t += stats.actSeconds
				carried += Water.scoopAmount(carried, stats.capacity, stats.sweeps)
			end
			t += Config.tripDistance / stats.walkSpeed
		end
		walkFirst = nil
		local litres = math.min(carried, target - current)
		t += Config.pourSeconds
		carried -= litres
		current += litres
		money += litres * stage.coinsPerLitre * stats.coinBonus
		while true do
			local track, level = cheapest(stageIndex)
			if not track then
				break
			end
			money -= level.cost
			levels[track.id] = (levels[track.id] or 0) + 1
			stats = Ladder.stats(Config, levels)
			if not quiet then
				print(`  {clock(t)}  {level.name or `{track.name} {levels[track.id]}`}`)
			end
		end
	end
	runTime += t
	print(`  {clock(t)}  FULL (target {stage.minutes}:00)`)
end
print(`\nRun total {clock(runTime)} (target 45:00, cards not counted)`)
