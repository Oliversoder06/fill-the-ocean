-- The honeycomb's data (client/Honeycomb): the layout (shared/Honeycomb), every upgrade by id with
-- its view, and the team's state as shared/Honeycomb reads it, from the server's attributes (Hud).
-- Only what TAB sells has a price (Items.tabOffer; a gate: Areas.gateOffer): an item's first level
-- is bought at its stand or built on a plot.
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

export type Info = { upgrade: Comb.Upgrade, viewId: string }
local infos: { [string]: Info } = {}
for _, viewId in { "main", table.unpack(layout.order) } do
	for _, upgrade in Comb.upgrades(layout, viewId) do
		infos[upgrade.id] = { upgrade = upgrade, viewId = viewId }
	end
end
HoneycombData.infos = infos

-- How full the ocean is (0..1, the server's Fill attribute).
function HoneycombData.fill(): number
	local fill = ReplicatedStorage:GetAttribute("Fill")
	return if type(fill) == "number" then fill else 0
end

-- The team's state now.
function HoneycombData.read(): Comb.View
	local snap = Hud.snapshot()
	local levels = Hud.levels(0) :: { [string]: number }
	local gatesOpen, fill = Hud.gatesOpen(), HoneycombData.fill()
	local items = {}
	for _, item in Config.items do
		local bought = if item.kind == "building" then snap.buildings[item.id] elseif Items.owned(snap.items, item.id) then snap.items.itemLevels[item.id] else nil
		items[item.id] = if bought then bought + 1 else 0
	end
	return {
		levels = levels,
		items = items,
		openAreas = Areas.open(gatesOpen),
		wallet = Hud.wallet(),
		price = function(link: Comb.Link): number?
			if link.kind == "gate" then
				local area = Areas.byId(Config, link.areaId)
				return if Areas.gateOffer(Config, gatesOpen, fill, area.id) == "buy" then Items.price(Config, area.gate.price, snap.teamSize) else nil
			end
			local level, status = Items.tabOffer(Config, levels, snap.items, snap.buildings, link.id, snap.openAreas, Ladder.helps(Config, levels, link.id))
			return if status == "buy" then Items.price(Config, level.cost, snap.teamSize) else nil
		end,
		reachable = function(id: string): boolean
			return Items.reachable(Config, snap.items, { Items.get(Config, id).area })[1] ~= nil
		end,
	}
end

-- Attributes a hex's state reads, besides Wallet and Fill (shared/Honeycomb.state through read).
function HoneycombData.readsState(name: string): boolean
	return name == "TeamSize"
		or name == "Owned"
		or name == "GatesOpen"
		or name:sub(1, 6) == "Level_"
		or name:sub(1, 10) == "ItemLevel_"
		or name:sub(1, 14) == "BuildingLevel_"
end

-- Whether buying `link` gets something new: a track's first level, a new tool model or an area.
function HoneycombData.firstBuy(link: Comb.Link): boolean
	if link.kind == "gate" then
		return true
	elseif link.kind ~= "track" then
		return false
	elseif link.level == 1 then
		return true
	end
	local levels = (Config.track(link.id) :: Config.Track).levels
	return link.id == "tool" and levels[link.level].model ~= levels[link.level - 1].model
end

return HoneycombData
