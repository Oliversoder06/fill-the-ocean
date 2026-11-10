-- The whole map for tuning. Run from gameplay/:
--   lune run tools/simulate [quiet] [team size]   one team's timeline (every buy and gate, each 10%)
--   lune run tools/simulate targets               solo, 2 and 4 players against the Phase 4 targets;
--                                                 errors (exit code 1) when any fails
-- The model is in tools/Simulator.luau (the game's own pure modules plus the player's habits).
local process = require("@lune/process")
local Config = require("../src/shared/Config")
local Items = require("../../common/Items")
local Water = require("../src/shared/Water")
local Simulator = require("./Simulator")

local quiet = table.find(process.args, "quiet") ~= nil
local teamSize = 1
for _, arg in process.args do
	local n = tonumber(arg)
	if n then
		assert(n >= 1 and n % 1 == 0, `team size must be a whole number of players, got {arg}`)
		teamSize = n
	end
end
local ocean = Config.ocean

if table.find(process.args, "targets") then
	local rows, ok = Simulator.targets()
	print(Simulator.formatTargets(rows))
	if not ok then
		error("a Phase 4 target failed (see FAIL above)", 0)
	end
	return
end

print(`== {ocean.name}: team of {teamSize}, {Simulator.money(Water.litresAt(1, ocean, teamSize))} L, first percent {ocean.firstPercent} L, growth {ocean.growth}, prices x{Items.priceScale(Config, teamSize)} ==`)
local result = Simulator.run(teamSize, if quiet then nil else print)
for id, at in result.gateMoney do
	local area = Config.areas[id]
	print(`  {area.name}'s fill reached holding {Simulator.money(at.money)} at {Simulator.money(at.income)}/s (gate {Simulator.money(Items.price(Config, area.gate.price, teamSize))})`)
end
local average = result.total / 10
for band = 1, 10 do
	local at = result.marks[band * 10]
	local span = at - (result.marks[band * 10 - 10] or 0)
	print(string.format("  %s  %3d%%  this 10%%: %s (%.2fx the average)  idle/active %.2f", Simulator.clock(at), band * 10, Simulator.clock(span), span / average, result.idleRatio[band] or 0))
end
print(`  {Simulator.clock(result.total)}  FULL after {#result.buys} buys; first pour {math.floor(result.firstPour)} s`)
