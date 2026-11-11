-- The honeycomb's card (StarterGui.Hud.Honeycomb.Tooltip, built in Studio; client/Honeycomb shows
-- it by the hovered or selected link): the link's name, its level step, one line of what it does,
-- its price and how to get it (Hint), placed on top of its hex (under it when there is no room
-- above) and kept on the screen. A hired staff's card has AssignButton: the staff moves to its next
-- post (Staff("assign", itemId, areaId), StaffRules.nextPost). Words from client/HoneycombText.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cues = require(ReplicatedStorage.Shared.Cues)
local Comb = require(ReplicatedStorage.Shared.Honeycomb)
local StaffRules = require(ReplicatedStorage.Shared.StaffRules)
local Areas = require(ReplicatedStorage.Common.Areas)
local Items = require(ReplicatedStorage.Common.Items)
local Theme = require(ReplicatedStorage.Kit.UI.Themes["clear-tide"])
local Hud = require(script.Parent.Hud)
local Hex = require(script.Parent.HoneycombHex)
local Text = require(script.Parent.HoneycombText)
local Purchase = require(script.Parent.Purchase)

local colors = Theme.colors
local set = Hud.set
local CUE = Cues.honeycomb

local GAP = 6 -- pixels between the card and the screen's edge
local OVERLAP = 4 -- pixels the card covers its hex's edge, so the mouse moves straight onto it
local BUY_HINT = { mouse = "Click to buy", touch = "Tap to buy", gamepad = "Press A to buy" }

export type Input = "mouse" | "touch" | "gamepad"
export type Card = {
	frame: Frame,
	pulse: UIScale,
	itemName: TextLabel,
	levelText: TextLabel,
	effect: TextLabel,
	hint: TextLabel,
	priceRow: GuiObject,
	price: TextLabel,
	assign: GuiButton,
	assignPress: UIScale,
	assignLabel: TextLabel,
}

local HoneycombCard = {}

-- Where one of the team's staff works (the server's Staff attribute: an area id, 0 for nowhere), or
-- nil until the server has published it.
local function postOf(id: string): number?
	for _, entry in StaffRules.decode(ReplicatedStorage:GetAttribute("Staff")) do
		if entry.id == id then
			return entry.post
		end
	end
	return nil
end

-- The posts staff `item` may work now, as the server checks them (StaffRules.targets).
local function postsOf(item): { number }
	local items = Hud.items()
	return StaffRules.targets(Config, item, items.owned, Items.reachable(Config, items, Areas.openIds(Hud.gatesOpen())))
end

-- The card's parts in Hud.Honeycomb (`root`).
function HoneycombCard.new(root: Instance): Card
	local frame = Hud.find(root, "Tooltip")
	Hud.find(frame, "PriceRow.Coin")
	local card: Card = {
		frame = frame,
		pulse = Hud.find(frame, "Pulse"),
		itemName = Hud.find(frame, "ItemName"),
		levelText = Hud.find(frame, "LevelText"),
		effect = Hud.find(frame, "Effect"),
		hint = Hud.find(frame, "Hint"),
		priceRow = Hud.find(frame, "PriceRow"),
		price = Hud.find(frame, "PriceRow.Price"),
		assign = Hud.find(frame, "AssignButton"),
		assignPress = Hud.find(frame, "AssignButton.Press"),
		assignLabel = Hud.find(frame, "AssignButton.Label"),
	}
	Hud.pressable(card.assign, card.assignPress)
	return card
end

-- The staff `link` stands for if the team has hired it, else nil.
function HoneycombCard.hiredStaff(link: Comb.Link, view: Comb.View)
	local item = if link.kind == "item" then Items.get(Config, link.id) else nil
	return if item and item.kind == "staff" and (view.items[item.id] or 0) > 0 then item else nil
end

-- Shows `link` in state `st` (nil hides the card); the buy hint names `input`'s press.
function HoneycombCard.paint(card: Card, link: Comb.Link?, st: Comb.HexState?, view: Comb.View, input: Input)
	set(card.frame, "Visible", st ~= nil)
	if not (link and st) then
		return
	end
	local state = st.state
	set(card.itemName, "Text", Text.name(link))
	set(card.levelText, "Text", if link.kind == "gate" then "Gate" elseif Comb.elsewhere(link, st, view) then Text.where(link) else Comb.levelText(link, state))
	set(card.effect, "Text", Text.effect(link, view))
	local priced = state == "buy" or state == "short"
	set(card.priceRow, "Visible", priced)
	if priced then
		set(card.price, "Text", Hud.money(st.price :: number))
		set(card.price, "TextColor3", if state == "short" then colors.short else colors.text)
	end
	local words = if state == "buy" then BUY_HINT[input] else Text.reason(link, st, view)
	set(card.hint, "Visible", words ~= nil)
	if words then
		set(card.hint, "Text", words)
		set(card.hint, "TextColor3", if state == "short" then colors.short else colors.text)
	end
	local staff = HoneycombCard.hiredStaff(link, view)
	set(card.assign, "Visible", staff ~= nil)
	if staff then
		set(card.assignLabel, "Text", Text.assign(staff, postOf(staff.id)))
	end
end

-- Puts the card on top of `button` (a hex `halfHeight` pixels tall from its centre on screen),
-- under it when there is no room above, inside `root` (the full-screen cover).
function HoneycombCard.place(card: Card, root: GuiObject, button: GuiObject, halfHeight: number)
	local frame = card.frame
	local size, screen = frame.AbsoluteSize, root.AbsoluteSize
	local centre = button.AbsolutePosition + button.AbsoluteSize / 2 - root.AbsolutePosition
	local half = halfHeight - OVERLAP
	local below = centre.Y - half - size.Y < GAP
	local x = math.clamp(centre.X, size.X / 2 + GAP, math.max(size.X / 2 + GAP, screen.X - size.X / 2 - GAP))
	local y = if below then math.min(centre.Y + half, screen.Y - size.Y - GAP) else centre.Y - half
	set(frame, "AnchorPoint", Vector2.new(0.5, if below then 0 else 1))
	set(frame, "Position", UDim2.fromOffset(math.round(x), math.round(y)))
end

-- A refused press: the card (and its hint) pulses.
function HoneycombCard.pulse(card: Card)
	card.pulse.Scale = CUE.needPulse
	TweenService:Create(card.pulse, TweenInfo.new(CUE.needSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- The hired staff `link` stands for moves to its next allowed post (the server checks it).
function HoneycombCard.assign(card: Card, link: Comb.Link, view: Comb.View, staffRemote: RemoteEvent)
	local item = HoneycombCard.hiredStaff(link, view)
	if not item then
		return
	end
	local now = postOf(item.id)
	local post = StaffRules.nextPost(postsOf(item), now)
	if post and post ~= now then
		Hex.bounce(card.assignPress)
		staffRemote:FireServer("assign", item.id, post)
	else
		Purchase.deny(card.assign)
	end
end

return HoneycombCard
