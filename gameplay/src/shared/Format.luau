--!strict
-- Words and numbers the player reads: money, litres, the fill, and what a stand says. Pure: config,
-- items and areas are passed in, so Lune tests, the server's cards and the client load it the same way.
-- `priceOf` turns a listed price into the team's (common/Items.price); nil shows the listed price.

local Format = {}

type PriceOf = ((number) -> number)?

local function priced(price: number, priceOf: PriceOf): number
	return if priceOf then priceOf(price) else price
end

local SUFFIXES = { "K", "M", "B", "T" }
local EPSILON = 1e-9 -- 0.29 * 1000 is 289.99999999999997; it must still read 29.0%

function Format.short(n: number): string
	if n < 10 then
		return string.format("%.1f", n)
	elseif n < 1000 then
		return tostring(math.floor(n))
	end
	local i = 0
	while n >= 1000 and i < #SUFFIXES do
		n /= 1000
		i += 1
	end
	return string.format("%.1f%s", n, SUFFIXES[i])
end

-- Whole numbers with thousands separators below `upTo`, then the short form.
local function whole(n: number, upTo: number): string
	n = math.floor(n)
	if n >= upTo then
		return Format.short(n)
	end
	local text = tostring(n)
	local count
	repeat
		text, count = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return text
end

-- Money: 12,480 below 100K, then 1.2M.
function Format.money(n: number): string
	return whole(n, 100000)
end

-- Litres: 652,506 below a million, then 2.5M.
function Format.litres(n: number): string
	return whole(n, 1e6)
end

-- How full the ocean is (0..1): "0.04%" below 10% so every pour moves it, then "12.3%". Never rounded up.
function Format.fill(fraction: number): string
	if fraction < 0.1 then
		return string.format("%.2f%%", math.floor(fraction * 10000 + EPSILON) / 100)
	end
	return string.format("%.1f%%", math.floor(fraction * 1000 + EPSILON) / 10)
end

-- A gate's fill as a whole percent: "7%".
function Format.percent(fraction: number): string
	return `{math.round(fraction * 100)}%`
end

function Format.need(price: number, money: number): string
	return `Need {Format.money(price)} (you have {Format.money(money)})`
end

-- How closed `area` opens at the ocean's `fill`: its gate's fill first, then its price.
function Format.gateHint(area, fill: number, priceOf: PriceOf): string
	if fill < area.gate.fill then
		return `fill the ocean to {Format.percent(area.gate.fill)}`
	end
	return `open its gate for {Format.money(priced(area.gate.price, priceOf))}`
end

-- The display name of a track's level `n`: tools have their own, the rest are "<track> <n>".
function Format.levelName(track, n: number, level): string
	if track.id == "tool" then
		return level.name
	end
	return if #track.levels == 1 then track.name else `{track.name} {n}`
end

-- A tool level's name without its tier ("Bucket Lv3" -> "Bucket"), where its level shows beside it.
function Format.toolName(name: string): string
	return (name:gsub(" Lv%d+$", ""))
end

-- A stand's name: cove shop `stand` (Config.stands, an item's `stand`) or else `area`'s own stand.
function Format.standName(config, stand: string?, area): string
	return if stand then config.stands[stand] else `{area.name} Stand`
end

-- A stand prompt's action for Items.standOffer's `item` and `status` (`area`: the item's area).
-- `money` (the team's wallet) nil leaves it out (the prompt, which would otherwise change on every pour).
function Format.standAction(item, status: string, money: number?, area, priceOf: PriceOf): string
	if status == "buy" then
		return `Buy {item.name} ({Format.money(priced(item.price, priceOf))})`
	elseif status == "money" then
		local need = `Need {Format.money(priced(item.price, priceOf))} for the {item.name}`
		return if money then `{need} (the team has {Format.money(money)})` else need
	elseif status == "locked" then
		return `{item.name} opens with {area.name}`
	end
	return "You own everything here"
end

-- The card after a stand press that bought nothing: the prompt's words, plus how a locked item's area opens.
function Format.standCard(item, status: string, money: number, area, fill: number, priceOf: PriceOf): string
	local text = Format.standAction(item, status, money, area, priceOf)
	return if status == "locked" then `{text} ({Format.gateHint(area, fill, priceOf)})` else text
end

-- The sign over a stand (`place`: its name): a title and a line, the item and its price, where it
-- opens, or that everything there is owned.
function Format.standSign(item, status: string, area, place: string, priceOf: PriceOf): (string, string)
	if status == "buy" or status == "money" then
		return item.name, Format.money(priced(item.price, priceOf))
	elseif status == "locked" then
		return item.name, `Opens with {area.name}`
	end
	return place, "Owned"
end

return Format
