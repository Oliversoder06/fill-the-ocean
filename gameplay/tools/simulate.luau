-- Perfect-player timing check for tuning. Run from gameplay/: lune run tools/simulate [quiet] [team size]
-- One team (1 player unless a number is passed) fills the one ocean in whole trips, every member in
-- step (walk to source, scoop sweeps until full, walk back, one quick pour), into one wallet. After
-- each pour they first buy the next gate (common/Areas) if it is on
-- sale and affordable, and from then scoop in that area (its pay; sweeps take actSeconds *
-- scoopFactor; the walk stays the same). Then they buy upgrades, cheapest affordable and open level
-- first, until nothing is affordable. Everything costs the team's price (Items.price). Prints the
-- money held when the ocean reaches each gate's fill
-- (gate prices are that rounded down to 2 significant figures), the time each gate opens, the time at every 10%
-- and how long each 10% took against the average.
-- Uses the game's own modules. Pass "quiet" to print only the 10% times.
local process = require("@lune/process")
local Areas = require("../../common/Areas")
local Items = require("../../common/Items")
local Config = require("../src/shared/Config")
local Ladder = require("../src/shared/Ladder")
local Water = require("../src/shared/Water")

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

local function price(cost: number): number
	return Items.price(Config, cost, teamSize)
end

local function clock(t: number): string
	return string.format("%d:%02d:%02d", t // 3600, t % 3600 // 60, math.floor(t % 60))
end

local levels = {}
local stats = Ladder.stats(Config, levels)
local money, carried, carriedValue = 0, 0, 0
local gatesOpen = {}
local area = Config.areas[1] -- where the player scoops: the furthest open area

-- The cheapest track the team can buy right now that changes something (Ladder.helps), or nil.
local function cheapest(areas: number)
	local bestTrack, bestLevel = nil, nil
	for _, track in Config.tracks do
		local level, status = Ladder.offer(Config, levels, track.id, areas)
		if status == "buy" and Ladder.helps(Config, levels, track.id) and Items.affords(money, price(level.cost)) and (not bestLevel or level.cost < bestLevel.cost) then
			bestTrack, bestLevel = track, level
		end
	end
	return bestTrack, bestLevel
end

local target = Water.litresAt(1, ocean, teamSize)
local current, t = 0, 0
local walkFirst = Config.tripDistance / 2 -- players start at Spawn, halfway along the path
local marks = {} -- time at each 10%
local gatesReached = {} -- gate fill points already reported
print(`== {ocean.name}: team of {teamSize}, target {target} L, first percent {ocean.firstPercent} L, growth {ocean.growth}, prices x{Items.priceScale(Config, teamSize)} ==`)
while current < target - 1e-6 do
	if carried < stats.capacity then
		t += (walkFirst or Config.tripDistance) / stats.walkSpeed
		while carried < stats.capacity do -- one sweep per actSeconds until the tool is full
			t += stats.actSeconds * area.scoopFactor
			local litres = Water.scoopAmount(carried, stats.capacity, stats.sweeps)
			carriedValue = Water.mix(carriedValue, litres, ocean.coinsPerLitre * area.payMultiplier)
			carried += litres
		end
		t += Config.tripDistance / stats.walkSpeed
	end
	walkFirst = nil
	-- every member pours the same load at once; the ocean takes what fits
	local litres = Water.pourAmount(carried * teamSize, current, target)
	t += Config.pourSeconds
	local value = if carried > 0 then carriedValue * litres / carried else 0
	carried, carriedValue = 0, 0
	current += litres
	money += value * stats.coinBonus
	local fill = Water.fill(current, ocean, teamSize)
	while #marks < 10 and fill >= (#marks + 1) / 10 - 1e-9 do
		table.insert(marks, t)
		print(`  {clock(t)}  {#marks * 10}%`)
	end
	for _, gated in Config.areas do
		if gated.gate and fill >= gated.gate.fill and not gatesReached[gated.id] then
			gatesReached[gated.id] = true
			print(`  {clock(t)}  {string.format("%5.1f%%", fill * 100)}  reached {gated.name}'s fill holding {math.floor(money)} (gate price {price(gated.gate.price)})`)
		end
	end
	local gateId, onSale = Areas.nextGate(Config, gatesOpen, fill)
	local gate = if gateId then Areas.byId(Config, gateId) else nil
	if gate and onSale and Items.affords(money, price(gate.gate.price)) then
		money -= price(gate.gate.price)
		table.insert(gatesOpen, gate.id)
		area = gate
		print(`  {clock(t)}  {string.format("%5.1f%%", fill * 100)}  GATE {gate.name} opens`)
	end
	while true do
		local track, level = cheapest(Ladder.openAreas(Config, gatesOpen))
		if not track then
			break
		end
		money -= price(level.cost)
		levels[track.id] = (levels[track.id] or 0) + 1
		stats = Ladder.stats(Config, levels)
		if not quiet then
			print(`  {clock(t)}  {string.format("%5.1f%%", fill * 100)}  {level.name or `{track.name} {levels[track.id]}`}`)
		end
	end
end
print(`  {clock(t)}  FULL`)

-- Each 10% against the average: the curve is right when every one is between 0.5x and 2x.
local average = t / 10
local parts = {}
for i, mark in marks do
	table.insert(parts, string.format("%d%% %.2fx", i * 10, (mark - (marks[i - 1] or 0)) / average))
end
print(`Each 10% vs the average {clock(average)}: {table.concat(parts, ", ")}`)
