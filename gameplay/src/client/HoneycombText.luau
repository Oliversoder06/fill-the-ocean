-- The honeycomb's words (client/Honeycomb): category and link names, what a level does, why a link
-- can't be bought here, the Buy button's word, a gate's price or fill, a staff's post. Prices go
-- through Hud.price, numbers through shared/Format and Hud.short.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Comb = require(ReplicatedStorage.Shared.Honeycomb)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local StaffRules = require(ReplicatedStorage.Shared.StaffRules)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Hud = require(script.Parent.Hud)

local short = Hud.short

-- Category display names, in the ring's order (shared/Honeycomb layout.order).
local CATEGORY_NAMES = { tools = "Tools", boosts = "Boosts", gear = "Gear", vehicles = "Vehicles", buildings = "Buildings", staff = "Staff" }

local HoneycombText = {}

function HoneycombText.category(catId: string): string
	return CATEGORY_NAMES[catId]
end

local function scoops(n: number): string
	return if n == 1 then "1 scoop" else `{n} scoops`
end

local function percent(bonus: number): string
	return `+{math.floor((bonus - 1) * 100 + 0.5)}%`
end

-- What a track's level changes, from the stats before and after it. Litres per trip include the
-- worn backpack; scoop counts stay the tool's.
local function effectText(id: string, now: Ladder.Stats, after: Ladder.Stats): string
	if id == "tool" then
		local gear = Hud.items()
		local tripNow, tripAfter = Items.withGear(Config, gear, now).capacity, Items.withGear(Config, gear, after).capacity
		return `{short(tripAfter)} L per trip, {scoops(after.sweeps)} to fill (now {short(tripNow)} L)`
	elseif id == "pickup" then
		return `Fill your tool in {scoops(after.sweeps)} (now {scoops(now.sweeps)})`
	elseif id == "hold" then
		return "Hold the button to keep scooping"
	elseif id == "quick" then
		return `{after.actSeconds}s per scoop (now {now.actSeconds}s)`
	elseif id == "walk" then
		return `Walk speed {after.walkSpeed} (now {now.walkSpeed})`
	end
	return `{percent(after.coinBonus)} coins per litre (now {percent(now.coinBonus)})`
end

local function fillNow(): number
	local fill = ReplicatedStorage:GetAttribute("Fill")
	return if type(fill) == "number" then fill else 0
end

-- A stat in the effect texts: whole numbers under 1000 as they are (6), the rest short (1.6, 3.0K).
local function amount(n: number): string
	return if n == math.floor(n) and n < 1000 then tostring(n) else short(n)
end

-- Effect texts read stats as `stat(name, unit, format)`: the value and its unit ("6 L/s per plot"),
-- and " (now 3)" when the text shows the next level (`was` reads the current one) and it changes.
type Stat = (name: string, unit: string?, format: ((number) -> string)?) -> string
local function statText(read: (string) -> number, was: ((string) -> number)?): Stat
	return function(name, unit, format)
		local show = format or amount
		local value = read(name)
		local before = if was then was(name) else value
		local text = `{show(value)}{unit or ""}`
		return if before ~= value then `{text} (now {show(before)})` else text
	end
end

-- What each gadget does at some level (Config.ItemLevel stats).
local GADGET_EFFECTS = {
	waterGun = function(stat: Stat)
		return `Pours from {stat("range", " studs away")}`
	end,
	gardenHose = function(stat: Stat)
		return `{stat("rate", " L/s")}, reach {stat("reach", " studs")}`
	end,
	heatGloves = function(stat: Stat)
		return `Hot pools {stat("hotFill", "x faster")}`
	end,
	icePick = function(stat: Stat)
		return stat("hits", " hits per block")
	end,
	jetpackTank = function(stat: Stat)
		return `{stat("flightSeconds", "s flight")}, holds {stat("capacity", " L")}`
	end,
	cloudNet = function(stat: Stat)
		return `Catches clouds from {stat("range", " studs")}`
	end,
}

-- What a vehicle does at some level (as GADGET_EFFECTS).
local function vehicleEffect(stat: Stat): string
	return `{stat("tank", " L tank")}, {stat("fillRate", " L/s fill")}`
end

-- What a building does at some level (every building: its litres a second).
local function buildingEffect(stat: Stat): string
	return stat("rate", " L/s per plot")
end

-- What a staff does at some level, by its job (Config.items `job`); how many are hired only once
-- one is.
local function staffEffect(stat: Stat, item, owned: boolean): string
	local who = if owned then `{stat("hires", " hired")}, ` else ""
	if item.job == "area" then
		return `{who}{stat("carry", " L")} every {stat("tripSeconds", "s")} per {item.name}`
	elseif item.job == "truck" then
		return `{who}a tank every {stat("tripSeconds", "s")} per {item.name}`
	end
	return `{who}no clogs, {stat("boost", " output", percent)}`
end

local KIND_EFFECTS = { vehicle = vehicleEffect, building = buildingEffect, staff = staffEffect }

-- What an item does now and after an upgrade `level` (nil: what it does now, or when bought): a
-- backpack's litres, a gadget's, vehicle's, building's or staff's stats.
local function itemEffect(item, level, owned: boolean): string
	local function nowStat(name: string): number
		if not owned then
			return item[name]
		end
		return if item.kind == "building" then Items.buildingStat(Hud.buildings(), item, name) else Items.stat(Hud.items(), item, name)
	end
	if item.kind == "gadget" or KIND_EFFECTS[item.kind] then
		local effect = KIND_EFFECTS[item.kind] or GADGET_EFFECTS[item.id]
		assert(effect, `Honeycomb has no effect text for {item.id}`)
		if level then
			return effect(statText(function(name: string): number
				return level[name]
			end, nowStat), item, owned)
		end
		return effect(statText(nowStat), item, owned)
	end
	local now = nowStat("capacity")
	if level then
		return `Holds {short(level.capacity)} L on your back (now {short(now)} L)`
	end
	return `Holds {short(now)} L on your back`
end

-- The Assign button's text for staff `item` working at `post`.
function HoneycombText.assign(item, post: number?): string
	if item.job == "plots" then
		return "FIXES THE TEAM'S BUILDINGS"
	elseif not post or post == 0 then
		return if item.job == "truck" then "BUY A VEHICLE FIRST" else "..."
	elseif item.job == "truck" then
		local truck = StaffRules.truck(Config, post)
		if truck then
			return `DRIVES THE {truck.name:upper()}`
		end
	end
	return `WORKS AT {Areas.byId(Config, post).name:upper()}`
end

-- How closed `area`'s gate opens, for its hex: the fill it needs, or its price once on sale (true:
-- a price, with the coin).
function HoneycombText.gate(area): (string, boolean)
	if fillNow() < area.gate.fill then
		return `fill {Format.percent(area.gate.fill)}`, false
	end
	return Hud.money(Hud.price(area.gate.price)), true
end

-- The detail's words for a link: why it can't be bought here (nil when it can).
function HoneycombText.reason(link: Comb.Link, st: Comb.HexState, view: Comb.View): string?
	local state = st.state
	local area = Areas.byId(Config, link.areaId)
	if state == "short" then
		return `Need {Hud.money(math.ceil((st.price :: number) - view.wallet))} more`
	elseif Comb.elsewhere(link, st, view) then
		local item = Items.get(Config, link.id)
		if item.kind == "building" then
			return "Build one on a town plot"
		end
		return `{if item.kind == "staff" then "Hire" else "Buy"} it at the {Format.standName(Config, item.stand, area)}`
	elseif state == "gateClosed" or (state == "locked" and not view.openAreas[link.areaId]) then
		return `Opens with {area.name}: {Format.gateHint(area, fillNow(), Hud.price)}`
	elseif state == "locked" and link.kind == "item" and not view.reachable(link.id :: string) then
		return `Needs the {Items.get(Config, area.needs).name}`
	elseif state == "locked" and link.id == "pickup" then
		return "Your tool already fills in one scoop"
	elseif state == "future" then
		return "Buy the level before it first"
	end
	return nil
end

-- The Buy button's word when it can't buy.
function HoneycombText.word(link: Comb.Link, st: Comb.HexState, view: Comb.View): string
	local state = st.state
	if state == "owned" then
		return "OWNED"
	elseif state == "max" then
		return "MAX"
	elseif state == "gateOpen" then
		return "OPEN"
	elseif Comb.elsewhere(link, st, view) then
		return if Items.get(Config, link.id).kind == "building" then "ON A PLOT" else "AT STAND"
	end
	return "LOCKED"
end

function HoneycombText.name(link: Comb.Link): string
	if link.kind == "gate" then
		return `{Areas.byId(Config, link.areaId).name} gate`
	elseif link.kind == "track" then
		local track = Config.track(link.id :: string) :: Config.Track
		return Format.levelName(track, link.level :: number, track.levels[link.level :: number])
	end
	return Items.get(Config, link.id).name
end

-- One line: what the link's level does (a track: against the level before it).
function HoneycombText.effect(link: Comb.Link, view: Comb.View): string
	if link.kind == "gate" then
		return `Opens {Areas.byId(Config, link.areaId).name} and its upgrades`
	elseif link.kind == "track" then
		local before, after = table.clone(view.levels), table.clone(view.levels)
		before[link.id :: string], after[link.id :: string] = (link.level :: number) - 1, link.level :: number
		return effectText(link.id :: string, Ladder.stats(Config, before), Ladder.stats(Config, after))
	end
	local item = Items.get(Config, link.id)
	local level = if (link.level :: number) > 1 then item.levels[(link.level :: number) - 1] else nil
	return itemEffect(item, level, (view.items[item.id] or 0) > 0)
end

return HoneycombText
