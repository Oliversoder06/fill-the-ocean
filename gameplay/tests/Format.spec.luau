local Format = require("../src/shared/Format")
local Config = require("../src/shared/Config")

local tests = {}

local function area(id: number)
	for _, a in Config.areas do
		if a.id == id then
			return a
		end
	end
	error(`no area {id}`)
end

local function item(id: string)
	for _, it in Config.items do
		if it.id == id then
			return it
		end
	end
	error(`no item {id}`)
end

function tests.money_has_separators_then_goes_short(t)
	t.expectEq(Format.money(30.7), "30")
	t.expectEq(Format.money(1200.9), "1,200")
	t.expectEq(Format.money(99999), "99,999")
	t.expectEq(Format.money(150000), "150.0K")
end

function tests.short_numbers(t)
	t.expectEq(Format.short(9.5), "9.5")
	t.expectEq(Format.short(120), "120")
	t.expectEq(Format.short(3000), "3.0K")
	t.expectEq(Format.short(1.2e6), "1.2M")
end

function tests.litres_keep_separators_below_a_million(t)
	t.expectEq(Format.litres(12.4), "12")
	t.expectEq(Format.litres(652506), "652,506")
	t.expectEq(Format.litres(2.5e6), "2.5M")
end

-- Below 10% a pour must still move the number: two decimals, never rounded up.
function tests.fill_shows_two_decimals_below_ten_percent(t)
	t.expectEq(Format.fill(0), "0.00%")
	t.expectEq(Format.fill(0.0004), "0.04%")
	t.expectEq(Format.fill(0.02319), "2.31%")
	t.expectEq(Format.fill(0.07), "7.00%")
	t.expectEq(Format.fill(0.099999), "9.99%")
	t.expectEq(Format.fill(0.1234), "12.3%")
	t.expectEq(Format.fill(0.29), "29.0%", "no float drift down to 28.9")
	t.expectEq(Format.fill(1), "100.0%")
end

function tests.percent_is_whole(t)
	t.expectEq(Format.percent(0.07), "7%")
	t.expectEq(Format.percent(0.22), "22%")
end

function tests.need_says_price_and_money(t)
	t.expectEq(Format.need(1200, 30.7), "Need 1,200 (you have 30)")
end

-- How a closed area opens: the fill first, then the gate's price.
function tests.gate_hint(t)
	t.expectEq(Format.gateHint(area(2), 0.01), "fill the ocean to 7%")
	t.expectEq(Format.gateHint(area(2), 0.08), "open its gate for 16,000")
end

function tests.stand_names(t)
	t.expectEq(Format.standName(Config, item("waterGun").stand, area(1)), "Tool Shack")
	t.expectEq(Format.standName(Config, item("backpackTank").stand, area(1)), "Cove Well Stand")
	t.expectEq(Format.standName(Config, item("bigTank").stand, area(2)), "Mountain Spring Stand")
end

-- The stand prompt names the item and its price, or says why a press buys nothing.
function tests.stand_action_texts(t)
	local pack = item("backpackTank")
	t.expectEq(Format.standAction(pack, "buy", 2000, area(1)), "Buy Backpack Tank (1,200)")
	t.expectEq(Format.standAction(pack, "money", 30, area(1)), "Need 1,200 for the Backpack Tank (the team has 30)")
	t.expectEq(Format.standAction(item("fireTruck"), "locked", 30, area(2)), "Fire Truck opens with Mountain Spring")
	t.expectEq(Format.standAction(nil, "owned", 30, nil), "You own everything here")
end

-- The card after a press that bought nothing adds how a locked item's area opens.
function tests.stand_card_texts(t)
	t.expectEq(Format.standCard(item("fireTruck"), "locked", 30, area(2), 0.01), "Fire Truck opens with Mountain Spring (fill the ocean to 7%)")
	t.expectEq(Format.standCard(item("backpackTank"), "money", 30, area(1), 0.01), "Need 1,200 for the Backpack Tank (the team has 30)")
	t.expectEq(Format.standCard(nil, "owned", 30, nil, 0.01), "You own everything here")
end

-- A team sees its own prices (priceOf: common/Items.price for its size) on stands, cards and gate hints.
function tests.stand_texts_show_the_team_price(t)
	local function double(cost: number): number
		return cost * 2
	end
	local pack = item("backpackTank")
	t.expectEq(Format.standAction(pack, "buy", 5000, area(1), double), "Buy Backpack Tank (2,400)")
	t.expectEq(Format.standCard(pack, "money", 30, area(1), 0.01, double), "Need 2,400 for the Backpack Tank (the team has 30)")
	t.expectEq(select(2, Format.standSign(pack, "buy", area(1), "Cove Well Stand", double)), "2,400")
	t.expectEq(Format.gateHint(area(2), 0.08, double), "open its gate for 32,000")
end

-- A track level's name: tools have their own, a one-level track its name, the rest "<track> <n>".
function tests.level_names(t)
	local tool, walk, hold = Config.track("tool") :: any, Config.track("walk") :: any, Config.track("hold") :: any
	t.expectEq(Format.levelName(tool, 3, tool.levels[3]), "Bucket")
	t.expectEq(Format.levelName(walk, 2, walk.levels[2]), "Sneakers 2")
	t.expectEq(Format.levelName(hold, 1, hold.levels[1]), "Hold to Scoop")
end

-- The sign over a stand: the item and its price, where it opens, or that all of it is owned.
function tests.stand_sign_texts(t)
	local title, line = Format.standSign(item("backpackTank"), "money", area(1), "Cove Well Stand")
	t.expectEq(title, "Backpack Tank")
	t.expectEq(line, "1,200")
	title, line = Format.standSign(item("fireTruck"), "locked", area(2), "Fire Station")
	t.expectEq(title, "Fire Truck")
	t.expectEq(line, "Opens with Mountain Spring")
	title, line = Format.standSign(nil, "owned", nil, "Tool Shack")
	t.expectEq(title, "Tool Shack")
	t.expectEq(line, "Owned")
end

return tests
