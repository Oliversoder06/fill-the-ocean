-- The whole map played by a team of identical players, for tuning (tools/simulate prints it,
-- tests/Simulator.spec checks the targets). Every formula comes from the game's own pure modules;
-- this file only adds the player (where they walk, what they pick, what they buy) and the averages
-- below for what happens in the place rather than in a module.
-- The team plays in steps: one hand trip (Ladder.tripSeconds), a stretch of Garden Hose, or one vehicle
-- loop, whichever earns the team most (automation included); staff and buildings pour all the time.
-- The wallet is the team's and every price the team's (Items.price); the ocean is the team's
-- (Water.litresAt with the team size).
-- Buying: the next gate as soon as it is on sale (the Jetpack Tank first for Cloud Catcher, which
-- needs it); otherwise the thing with the shortest wait plus payback (coins short / income + price /
-- the income it adds), but while saving for it anything affordable that pays itself back sooner (or
-- within PATIENCE) first; things that add nothing modelled (Hold to Scoop) once they cost under a
-- minute of income. Each buy takes a little time away from the hands.
local Areas = require("../../common/Areas")
local Items = require("../../common/Items")
local AreaRules = require("../src/shared/AreaRules")
local Boosts = require("../src/shared/Boosts")
local BuildingRules = require("../src/shared/BuildingRules")
local Config = require("../src/shared/Config")
local Ladder = require("../src/shared/Ladder")
local StaffRules = require("../src/shared/StaffRules")
local VehicleRules = require("../src/shared/VehicleRules")
local Water = require("../src/shared/Water")

-- The place, measured or estimated (Lune can't load the map):
local REACH = 12 -- Zones.REACH: scoop and pour reach without gadgets (Zones touches the place)
local PLOTS = 6 -- workspace.Map.Plots.Plot1..6; a building can't be taken down again
local DRIVE_STUDS = 260 -- the Fire Station's refill bays to the truck beach (design doc: Main Street)
local FLIGHT_STUDS = 400 -- the bomber: an area's pool behind the cliffs to the ocean (estimate)
-- The player's habits, averaged:
local CLOUD_DRIFT = 40 -- studs the drifting cloud adds to each leg; the Cloud Net takes off its range - REACH
local STEAM_LOSS = 1.15 -- trip time with vent knockbacks, without Heat Gloves
local FILL_OVERLAP = 0.5 -- share of a vehicle's hydrant fill the player spends scooping by hand
local CLOG_UPTIME = 0.75 -- active: share of the time a building runs unclogged (tapped within a minute or two)
local GUN_SWAP = 1 -- seconds a trip to swap the tool and the Water Gun
local HOSE_STEP = 10 -- seconds a step while the Garden Hose pours
local IDLE_STEP = 10
local BUY_SECONDS = 5 -- a honeycomb buy
local STAND_SECONDS = 20 -- walking to a stand, a plot or a gate and back
local CHEAP_SECONDS = 60 -- things with no modelled gain are bought once they cost this much income
local DECIDE_SECONDS = 60 -- how often the next buy is reconsidered
local PATIENCE = 10800 -- an affordable buy that pays itself back within this is taken rather than saving on
local MOMENT_SECONDS = 60 -- buys this close together count as one buying moment (targets)

export type Buy = { t: number, fill: number, name: string, price: number }
export type Result = {
	teamSize: number,
	total: number, -- seconds to fill the ocean
	marks: { number }, -- seconds at each whole percent 1..100
	buys: { Buy },
	gates: { [number]: number }, -- area id -> seconds when its gate opened
	firstPour: number,
	idleRatio: { number }, -- idle / active coins a second at each 10% (index 1..10)
	gateMoney: { [number]: { money: number, income: number } }, -- at each gate's fill point
}

local Simulator = {}

local function newState(teamSize: number)
	return {
		n = teamSize,
		levels = {} :: { [string]: number },
		team = { owned = {} :: { string }, itemLevels = {} :: { [string]: number } },
		buildings = {} :: { [string]: number },
		plots = {} :: { string },
		gatesOpen = {} :: { number },
		boost = nil :: string?,
		boostEnds = 0,
		boostsPlayed = {} :: { string },
		money = 0,
		current = 0,
		t = 0,
	}
end

type State = typeof(newState(1))

local function copy(s: State): State
	local c = table.clone(s)
	c.levels = table.clone(s.levels)
	c.team = { owned = table.clone(s.team.owned), itemLevels = table.clone(s.team.itemLevels) }
	c.buildings = table.clone(s.buildings)
	c.plots = table.clone(s.plots)
	c.gatesOpen = table.clone(s.gatesOpen)
	return c
end

local function gadget(s: State, id: string, name: string): number?
	return Items.gadgetStat(Config, s.team, id, name)
end

-- The golden spring on average: one open area pays golden.pay for golden.seconds of every
-- delay + seconds, picked evenly among the open areas.
local function golden(s: State): number
	local g = Config.golden
	local share = g.seconds / (AreaRules.goldenDelay(Config, 0.5) + g.seconds)
	return 1 + (g.pay - 1) * share / #Areas.openIds(s.gatesOpen)
end

-- Normal sweeps' litres per sweep at `area`'s best spot: its deeper pool once the rock breaks, or
-- the ice Source's block every few hits.
local function sweepScale(s: State, area): number
	local pick = gadget(s, "icePick", "hits")
	local calls, hits, got = 0, 0, 0
	repeat
		calls += 1
		hits, got = AreaRules.sweep(Config, area, false, hits, pick)
	until got > 0
	local best = got / calls
	if AreaRules.canBreak(Config, s.levels, area.id) then
		best = math.max(best, select(2, AreaRules.sweep(Config, area, true, 0, pick)))
	end
	return best
end

type Option = { kind: string, coins: number, litres: number, step: number, work: number?, area: number?, walk: number? }

-- One player's hand loop at `area` (pouring with the Water Gun from its range when `gun`).
local function hand(s: State, st, area, lifeguard: boolean, gun: boolean): Option
	local hotFill = gadget(s, "heatGloves", "hotFill")
	local act = AreaRules.scoopSeconds(st.actSeconds, area, hotFill)
	local walk = AreaRules.walkSpeed(Config, st.walkSpeed, area.mechanic == "ice") * StaffRules.walkFactor(Config, lifeguard)
	local distance = Config.tripDistance
	if area.mechanic == "cloud" then
		distance += math.max(0, CLOUD_DRIFT - ((gadget(s, "cloudNet", "range") or REACH) - REACH))
	end
	local range = if gun then gadget(s, "waterGun", "range") else nil
	if range then
		distance -= range - REACH
	end
	local trip = Ladder.tripSeconds({ tripDistance = distance, pourSeconds = Config.pourSeconds }, {
		walkSpeed = walk,
		sweeps = st.sweeps / sweepScale(s, area),
		actSeconds = act,
	})
	if area.mechanic == "steam" and not hotFill then
		trip *= STEAM_LOSS
	end
	if range then
		trip += GUN_SWAP
	end
	local pay = Config.ocean.coinsPerLitre * area.payMultiplier * golden(s) * st.coinBonus
	return { kind = "hand", coins = st.capacity / trip * pay, litres = st.capacity / trip, step = trip, work = area.id, area = area.id, walk = walk }
end

-- The team's staff and buildings: coins and litres a second, and the staff's share of the coins.
-- `work`: the area the players work (staff there get the work bonus while `active`). Idle, nobody
-- taps a clogged building.
local function automation(s: State, work: number?, active: boolean): (number, number, number)
	local team = s.team
	local places = Items.reachable(Config, team, Areas.openIds(s.gatesOpen))
	local coins, litres, boosts = 0, 0, {}
	for _, item in Config.items do
		if item.kind ~= "staff" or not Items.owned(team, item.id) then
			continue
		elseif item.job == "plots" then
			table.insert(boosts, Items.stat(team, item, "boost"))
			continue
		end
		-- carriers go where the pay is best: the furthest area the team reaches
		local post = StaffRules.post(Config, item, team.owned, places, if item.job == "area" then places[#places] else nil)
		if post then
			local truck = if item.job == "truck" then StaffRules.truck(Config, post, team.owned) else nil
			local carry = if item.job == "area" then Items.stat(team, item, "carry") else nil
			local rate = StaffRules.rate(item.job, Items.stat(team, item, "hires"), carry, Items.stat(team, item, "tripSeconds"), if truck then Items.stat(team, truck, "tank") else nil)
			rate *= if active and work then StaffRules.bonus(Config, work, 0, post, 0) else 1
			litres += rate
			coins += rate * StaffRules.payPerLitre(Config, Areas.byId(Config, post))
		end
	end
	local scale, keepClear = StaffRules.plumber(boosts)
	local up = if keepClear then 1 elseif active then CLOG_UPTIME else 0
	local made = 0
	for _, id in s.plots do
		local rate = Items.buildingStat(s.buildings, Items.get(Config, id), "rate")
		made += up * BuildingRules.litres(Config, rate, 1, false, scale) + (1 - up) * BuildingRules.litres(Config, rate, 1, true, scale)
	end
	return coins + made * BuildingRules.payPerLitre(Config, Areas.openIds(s.gatesOpen)), litres + made, coins
end

-- What one player can do now: a hand loop per reachable area (with and without the Water Gun),
-- the Garden Hose at each area's tap, the best vehicle's loop.
local function options(s: State): { Option }
	local st = Boosts.apply(Config, Items.withGear(Config, s.team, Ladder.stats(Config, s.levels)), s.boost)
	local places = Items.reachable(Config, s.team, Areas.openIds(s.gatesOpen))
	local lifeguard = if Items.owned(s.team, "lifeguard") then places[#places] else nil
	local list, bestHand = {}, nil
	for _, id in places do
		local area = Areas.byId(Config, id)
		for _, gun in if Items.owned(s.team, "waterGun") then { false, true } else { false } do
			local option = hand(s, st, area, lifeguard == id, gun)
			table.insert(list, option)
			if not bestHand or option.coins > bestHand.coins then
				bestHand = option
			end
		end
	end
	local rate = gadget(s, "gardenHose", "rate")
	if rate then
		-- the hose pours at its tap's area pay; its pours don't count as work for the staff (server/Run)
		for _, id in places do
			local pay = Config.ocean.coinsPerLitre * Areas.byId(Config, id).payMultiplier * golden(s) * st.coinBonus
			table.insert(list, { kind = "hose", coins = rate * pay, litres = rate, step = HOSE_STEP, area = id })
		end
	end
	local vehicle = Items.nextOwned(Config, s.team, "vehicle")
	if vehicle and bestHand then
		local function v(name: string): number
			return Items.stat(s.team, vehicle, name)
		end
		local tank = v("tank")
		local fill = tank / v("fillRate")
		local drive = 2 * (if vehicle.flies then FLIGHT_STUDS else DRIVE_STUDS) / v("speed")
		local spray = if vehicle.flies then 0 else tank / v("sprayRate")
		local cycle = fill + drive + spray
		local payArea = VehicleRules.payArea(vehicle.area, if vehicle.flies then vehicle.area else nil)
		local pay = Config.ocean.coinsPerLitre * Areas.byId(Config, payArea).payMultiplier * st.coinBonus
		local scooped = fill * FILL_OVERLAP
		table.insert(list, {
			kind = "vehicle",
			coins = (tank * pay + bestHand.coins * scooped) / cycle,
			litres = (tank + bestHand.litres * scooped) / cycle,
			step = cycle,
			work = payArea, -- its pours speed up the Firefighters on it (server/Run)
			area = payArea,
		})
	end
	return list
end

-- coins: the team's coins a second, of which `staff` from staff and `buildings` from buildings.
type Income = { coins: number, litres: number, staff: number, buildings: number, step: number, kind: string, area: number?, walk: number? }

-- The team's coins and litres a second: every player at the best option (automation included), or
-- idle: hands still, automation only.
local function income(s: State, active: boolean): Income
	if not active then
		local coins, litres, staff = automation(s, nil, false)
		return { coins = coins, litres = litres, staff = staff, buildings = coins - staff, step = IDLE_STEP, kind = "idle" }
	end
	local best, autos = nil, {}
	for _, option in options(s) do
		local key = option.work or 0
		local auto = autos[key]
		if not auto then
			local coins, litres, staff = automation(s, option.work, true)
			auto = { coins = coins, litres = litres, staff = staff }
			autos[key] = auto
		end
		local total = {
			coins = s.n * option.coins + auto.coins,
			litres = s.n * option.litres + auto.litres,
			staff = auto.staff,
			buildings = auto.coins - auto.staff,
			step = option.step,
			kind = option.kind,
			area = option.area,
			walk = option.walk,
		}
		if not best or total.coins > best.coins then
			best = total
		end
	end
	return best :: Income
end

type Candidate = { name: string, cost: number, delay: number, gate: number?, apply: (State) -> () }

-- Building kinds of later areas the team hasn't built: a plot is kept free for each.
local function reserved(s: State, item): number
	local count = 0
	for _, other in Config.items do
		if other.kind == "building" and other.area > item.area and not Items.teamOwned(s.buildings, other.id) then
			count += 1
		end
	end
	return count
end

-- Everything the team could buy next, money aside.
local function candidates(s: State): { Candidate }
	local list = {}
	local open = Ladder.openAreas(Config, s.gatesOpen)
	for _, track in Config.tracks do
		local level, status = Ladder.offer(Config, s.levels, track.id, open)
		if status == "buy" and Ladder.helps(Config, s.levels, track.id) then
			local n = (s.levels[track.id] or 0) + 1
			table.insert(list, {
				name = level.name or `{track.name} {n}`,
				cost = level.cost,
				delay = BUY_SECONDS,
				apply = function(c)
					c.levels[track.id] = n
				end,
			})
		end
	end
	for _, item in Config.items do
		if item.kind == "building" then
			if item.area <= open and #s.plots + 1 + reserved(s, item) <= PLOTS then
				table.insert(list, {
					name = `{item.name} (plot {#s.plots + 1})`,
					cost = item.price,
					delay = STAND_SECONDS,
					apply = function(c)
						table.insert(c.plots, item.id)
						c.buildings[item.id] = c.buildings[item.id] or 0
					end,
				})
			end
			local level, status = Items.buildingOffer(Config, s.buildings, item.id, open)
			if status == "buy" then
				local n = s.buildings[item.id] + 1
				table.insert(list, {
					name = `{item.name} Lv{n + 1}`,
					cost = level.cost,
					delay = BUY_SECONDS,
					apply = function(c)
						c.buildings[item.id] = n
					end,
				})
			end
		elseif not Items.owned(s.team, item.id) then
			if Items.canBuy(Config, s.team, item.id, open, math.huge, s.n) then
				table.insert(list, {
					name = item.name,
					cost = item.price,
					delay = STAND_SECONDS,
					apply = function(c)
						table.insert(c.team.owned, item.id)
						c.team.itemLevels[item.id] = 0
					end,
				})
			end
		else
			local level, status = Items.nextLevel(Config, s.team, item.id)
			if status == "buy" then
				local n = (s.team.itemLevels[item.id] or 0) + 1
				table.insert(list, {
					name = `{item.name} Lv{n + 1}`,
					cost = level.cost,
					delay = BUY_SECONDS,
					apply = function(c)
						c.team.itemLevels[item.id] = n
					end,
				})
			end
		end
	end
	return list
end

-- The next thing to buy, or nil when nothing helps.
local function choose(s: State, now: Income, fill: number): Candidate?
	local gateId, onSale = Areas.nextGate(Config, s.gatesOpen, fill)
	if gateId and onSale then
		local area = Areas.byId(Config, gateId)
		local needs = if area.needs and not Items.owned(s.team, area.needs) then Items.get(Config, area.needs) else nil
		if needs and Items.canBuy(Config, s.team, needs.id, Ladder.openAreas(Config, s.gatesOpen), math.huge, s.n) then
			return {
				name = needs.name,
				cost = needs.price,
				delay = STAND_SECONDS,
				apply = function(c)
					table.insert(c.team.owned, needs.id)
					c.team.itemLevels[needs.id] = 0
				end,
			}
		end
		return {
			name = `GATE {area.name}`,
			cost = area.gate.price,
			delay = STAND_SECONDS,
			gate = area.id,
			apply = function(c)
				table.insert(c.gatesOpen, area.id)
			end,
		}
	end
	local best, bestScore, bestWait = nil, math.huge, 0
	local affordable = {}
	for _, candidate in candidates(s) do
		local cost = Items.price(Config, candidate.cost, s.n)
		local after = copy(s)
		candidate.apply(after)
		local gain = income(after, true).coins - now.coins
		local wait = math.max(0, cost - s.money) / now.coins
		local score = if gain > now.coins * 1e-9 then wait + cost / gain elseif cost <= now.coins * CHEAP_SECONDS then wait else math.huge
		if score < bestScore then
			best, bestScore, bestWait = candidate, score, wait
		end
		if wait == 0 and gain > now.coins * 1e-9 then
			table.insert(affordable, { candidate = candidate, back = cost / gain })
		end
	end
	-- while saving for the best, anything affordable that pays itself back before then (or within
	-- PATIENCE: players don't sit on coins for long) is bought first
	local filler, fillerBack = nil, math.max(bestWait, PATIENCE)
	for _, option in affordable do
		if option.back < fillerBack then
			filler, fillerBack = option.candidate, option.back
		end
	end
	return filler or best
end

-- Plays the whole map for a team of `teamSize`. `log` (optional) gets one line per buy and gate.
function Simulator.run(teamSize: number, log: ((string) -> ())?): Result
	local s = newState(teamSize)
	local ocean = Config.ocean
	local target = Water.litresAt(1, ocean, teamSize)
	local percents = {}
	for p = 1, 100 do
		percents[p] = Water.litresAt(p / 100, ocean, teamSize)
	end
	local result: Result = { teamSize = teamSize, total = 0, marks = {}, buys = {}, gates = {}, firstPour = 0, idleRatio = {}, gateMoney = {} }
	local now = income(s, true)
	local fill = 0
	local pick = choose(s, now, fill)
	local decidedAt = 0

	-- `dt` seconds at `coins` and `litres` a second; true once the ocean is full.
	local function advance(dt: number, coins: number, litres: number): boolean
		local poured = litres * dt
		local full = s.current + poured >= target - 1e-6
		if full then
			dt *= (target - s.current) / poured
			poured = target - s.current
		end
		local before = fill
		s.t += dt
		s.money += coins * dt
		s.current += poured
		fill = if full then 1 else Water.fill(s.current, ocean, teamSize)
		if result.firstPour == 0 and poured > 0 then
			result.firstPour = s.t
		end
		while #result.marks < 100 and s.current >= percents[#result.marks + 1] - 1e-6 do
			table.insert(result.marks, s.t)
			local p = #result.marks
			if p % 10 == 0 then
				local active = income(s, true)
				result.idleRatio[p // 10] = income(s, false).coins / active.coins
				if log then
					local own = active.coins - active.staff - active.buildings
					log(string.format("  %s  %3d%%  ---- %s/s: %s %.0f%%, staff %.0f%%, buildings %.0f%%; idle %.2f of it", Simulator.clock(s.t), p, Simulator.money(active.coins), active.kind, own / active.coins * 100, active.staff / active.coins * 100, active.buildings / active.coins * 100, result.idleRatio[p // 10]))
				end
			end
		end
		for _, area in Config.areas do
			if area.gate and before < area.gate.fill and fill >= area.gate.fill then
				result.gateMoney[area.id] = { money = s.money, income = income(s, true).coins }
			end
		end
		local milestone = Boosts.crossed(Config.boosts.milestones, before, fill)
		if milestone and fill < 1 then
			for _, kind in Config.boosts.kinds do
				if not table.find(s.boostsPlayed, kind.id) then
					table.insert(s.boostsPlayed, kind.id)
					s.boost, s.boostEnds = kind.id, s.t + Config.boosts.seconds
					break
				end
			end
		end
		return full
	end

	local function reconsider()
		now = income(s, true)
		pick = choose(s, now, fill)
		decidedAt = s.t
	end

	local first = true
	while true do
		local dt = now.step
		if first and now.kind == "hand" then
			dt -= Config.tripDistance / 2 / (now.walk :: number) -- the team starts at Spawn, halfway along
		end
		first = false
		local boostBefore = s.boost
		if advance(dt, now.coins, now.litres) then
			break
		end
		if s.boost and s.t >= s.boostEnds then
			s.boost = nil
		end
		local gateId, onSale = Areas.nextGate(Config, s.gatesOpen, fill)
		local gateDue = gateId and onSale and not (pick and pick.gate == gateId)
		if s.boost ~= boostBefore or gateDue or s.t - decidedAt >= DECIDE_SECONDS then
			reconsider()
		end
		local done = false
		while pick and Items.affords(s.money, Items.price(Config, pick.cost, teamSize)) do
			local price = Items.price(Config, pick.cost, teamSize)
			s.money -= price
			pick.apply(s)
			table.insert(result.buys, { t = s.t, fill = fill, name = pick.name, price = price })
			if pick.gate then
				result.gates[pick.gate] = s.t
			end
			if log then
				log(string.format("  %s  %5.1f%%  %s (%s)", Simulator.clock(s.t), fill * 100, pick.name, Simulator.money(price)))
			end
			-- the hands stop while buying; staff and buildings keep pouring
			local coins, litres = automation(s, nil, true)
			if advance(pick.delay, coins, litres) then
				done = true
				break
			end
			reconsider()
		end
		if done then
			break
		end
	end
	result.total = s.t
	return result
end

function Simulator.clock(t: number): string
	return string.format("%d:%02d:%02d", t // 3600, t % 3600 // 60, math.floor(t % 60))
end

function Simulator.money(n: number): string
	for _, unit in { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		if n >= unit[1] then
			return string.format("%.3g%s", n / unit[1], unit[2])
		end
	end
	return tostring(math.floor(n))
end

export type Row = { name: string, value: string, want: string, ok: boolean }

local function median(list: { number }): number
	local sorted = table.clone(list)
	table.sort(sorted)
	local n = #sorted
	return if n % 2 == 1 then sorted[(n + 1) // 2] else (sorted[n // 2] + sorted[n // 2 + 1]) / 2
end

-- The Phase 4 targets (docs/plans/2026-11-05-save-the-ocean.md, 4a) for a solo run and teams of 2 and 4.
function Simulator.targets(solo: Result?, duo: Result?, quad: Result?): ({ Row }, boolean)
	solo = solo or Simulator.run(1)
	duo = duo or Simulator.run(2)
	quad = quad or Simulator.run(4)
	local rows: { Row } = {}
	local function row(name: string, value: string, want: string, ok: boolean)
		table.insert(rows, { name = name, value = value, want = want, ok = ok })
	end
	local hours = solo.total / 3600
	row("solo total", string.format("%.1f h", hours), "20 h +-2", hours >= 18 and hours <= 22)

	-- gaps between buying moments (buys within MOMENT_SECONDS of the last are one visit to the
	-- honeycomb or a stand: a staff hire and its levels, a gate and what it opens), gates included,
	-- and from the last buy to the end
	local gaps, worst, worstAt = {}, 0, 0
	local last = 0
	local times = {}
	for _, buy in solo.buys do
		table.insert(times, buy.t)
	end
	table.insert(times, solo.total)
	for _, t in times do
		local gap = t - last
		if gap > MOMENT_SECONDS then
			table.insert(gaps, gap)
		end
		if t > 600 and gap > worst then
			worst, worstAt = gap, last
		end
		last = t
	end
	local mid = median(gaps) / 60
	row("buys", `{#solo.buys} in {#gaps} moments`, "-", true)
	row("buy gap median", string.format("%.1f min", mid), "5-10 min", mid >= 5 and mid <= 10)
	row("longest buy gap after 10 min", string.format("%.1f min (from %s)", worst / 60, Simulator.clock(worstAt)), "<= 20 min", worst <= 20 * 60)

	-- each area, gate to gate
	local starts = { 0 }
	for i = 2, #Config.areas do
		starts[i] = solo.gates[i] or math.huge
	end
	for i, area in Config.areas do
		local span = (starts[i + 1] or solo.total) - starts[i]
		local h = span / 3600
		row(`area {i} {area.name}`, if span == span and span < math.huge then string.format("%.2f h", h) else "never", "2.5-5 h", h >= 2.5 and h <= 5)
	end

	-- each 10% of the fill against the average 10%
	local average = solo.total / 10
	local parts, steady = {}, true
	for band = 1, 10 do
		local span = solo.marks[band * 10] - (solo.marks[band * 10 - 10] or 0)
		local ratio = span / average
		steady = steady and ratio >= 0.5 and ratio <= 1.5
		table.insert(parts, string.format("%.2f", ratio))
	end
	row("10% bands vs average", table.concat(parts, " "), "each 0.5-1.5x", steady)
	local perPercent = solo.total / 100 / 60
	row("1% of the fill", string.format("%.1f min", perPercent), "~12 min", true)

	local idle = solo.idleRatio[5]
	row("idle / active at 50%", string.format("%.2f", idle), "0.4-0.6", idle >= 0.4 and idle <= 0.6)
	for _, team in { duo, quad } do
		local ratio = team.total / solo.total
		row(`team of {team.teamSize} total`, string.format("%.1f h (%.2fx solo)", team.total / 3600, ratio), "within 10% of solo", math.abs(ratio - 1) <= 0.1)
	end
	row("first pour", string.format("%.0f s", solo.firstPour), "< 30 s", solo.firstPour < 30)
	local firstBuy = if solo.buys[1] then solo.buys[1].t else math.huge
	row("first buy", string.format("%.0f s", firstBuy), "< 60 s", firstBuy < 60)

	local all = true
	for _, r in rows do
		all = all and r.ok
	end
	return rows, all
end

function Simulator.formatTargets(rows: { Row }): string
	local lines = { "TARGETS" }
	for _, r in rows do
		table.insert(lines, string.format("  %-4s %-30s %-34s %s", if r.ok then "PASS" else "FAIL", r.name, r.value, r.want))
	end
	return table.concat(lines, "\n")
end

return Simulator
