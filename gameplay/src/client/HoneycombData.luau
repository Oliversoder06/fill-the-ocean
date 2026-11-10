-- The honeycomb's data (client/Honeycomb): the layout (shared/Honeycomb), every link by key with its
-- chain and category, and the team's state as shared/Honeycomb reads it, from the server's
-- attributes (Hud). Only what TAB sells has a price (Items.tabOffer): an item's first link is bought
-- at its stand or built on a plot.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Comb = require(ReplicatedStorage.Shared.Honeycomb)
local Ladder = require(ReplicatedStorage.Shared.Ladder)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Hud = require(script.Parent.Hud)

local HoneycombData = {}

local layout = Comb.layout(Config)
HoneycombData.layout = layout

export type Info = { link: Comb.Link, chain: Comb.Chain, catId: string }
local infos: { [string]: Info } = {}
for _, catId in layout.order do
	for _, chain in layout.categories[catId].chains do
		for _, link in chain.links do
			infos[link.key] = { link = link, chain = chain, catId = catId }
		end
	end
end
HoneycombData.infos = infos

-- The team's state now.
function HoneycombData.read(): Comb.View
	local snap = Hud.snapshot()
	local levels = Hud.levels(0) :: { [string]: number }
	local items = {}
	for _, item in Config.items do
		local bought = if item.kind == "building" then snap.buildings[item.id] elseif Items.owned(snap.items, item.id) then snap.items.itemLevels[item.id] else nil
		items[item.id] = if bought then bought + 1 else 0
	end
	return {
		levels = levels,
		items = items,
		openAreas = Areas.open(Hud.gatesOpen()),
		wallet = Hud.wallet(),
		price = function(link: Comb.Link): number?
			local id = link.id
			if not id then
				return nil -- a gate
			end
			local level, status = Items.tabOffer(Config, levels, snap.items, snap.buildings, id, snap.openAreas, Ladder.helps(Config, levels, id))
			return if status == "buy" then Items.price(Config, level.cost, snap.teamSize) else nil
		end,
		reachable = function(id: string): boolean
			return Items.reachable(Config, snap.items, { Items.get(Config, id).area })[1] ~= nil
		end,
	}
end

-- Attributes a hex's state reads, besides Wallet (shared/Honeycomb.states through read).
function HoneycombData.readsState(name: string): boolean
	return name == "TeamSize"
		or name == "Owned"
		or name == "GatesOpen"
		or name:sub(1, 6) == "Level_"
		or name:sub(1, 10) == "ItemLevel_"
		or name:sub(1, 14) == "BuildingLevel_"
end

-- The next link after `key` in its chain that isn't a gate, or nil.
function HoneycombData.nextLinkKey(key: string): string?
	local after = false
	for _, link in infos[key].chain.links do
		if after and link.kind ~= "gate" then
			return link.key
		end
		after = after or link.key == key
	end
	return nil
end

-- The first link of a category that isn't a gate.
function HoneycombData.firstLinkKey(catId: string): string
	for _, link in layout.categories[catId].chains[1].links do
		if link.kind ~= "gate" then
			return link.key
		end
	end
	error(`honeycomb: {catId}'s first chain has only gates`)
end

-- Whether buying `link` gets something new: a track's first level or a new tool model.
function HoneycombData.firstBuy(link: Comb.Link): boolean
	if link.kind ~= "track" then
		return false
	elseif link.level == 1 then
		return true
	end
	local levels = (Config.track(link.id :: string) :: Config.Track).levels
	return link.id == "tool" and levels[link.level :: number].model ~= levels[(link.level :: number) - 1].model
end

return HoneycombData
