--!strict
-- Window open timing, matched to the GUI reference clip (gameplay/ref for ai/open gui.mkv): the
-- frame pops in, then its parts appear one after another in layers (panels, tabs, items,
-- decorations), about 30 ms apart. Each part's layer and place come from its number attribute
-- "Reveal" in Studio: the whole part is the layer, the fraction the place in it (3.2 = layer 3,
-- second). Pure, Lune-tested.

local Reveal = {}

Reveal.FRAME_FROM = 0.6 -- the frame starts at 60% of its size
Reveal.FRAME_SECONDS = 0.22
Reveal.LEAD = 0.08 -- the first part starts once the frame is mostly in
Reveal.STAGGER = 0.03
Reveal.GROUP_GAP = 0.03 -- extra pause between layers
Reveal.ITEM_SECONDS = 0.22
Reveal.CLOSE_FROM = 0.85
Reveal.CLOSE_SECONDS = 0.15

-- Start delay for each part, given each part's Reveal value. Parts with the same value appear
-- together (a tile's button and its price row, say).
function Reveal.delays(orders: { number }): { number }
	local indices = {}
	for i in orders do
		table.insert(indices, i)
	end
	table.sort(indices, function(a, b)
		if orders[a] ~= orders[b] then
			return orders[a] < orders[b]
		end
		return a < b
	end)
	local delays = {}
	local t = Reveal.LEAD
	local last: number? = nil
	for _, i in indices do
		local order = orders[i]
		if last and order ~= last then
			t += Reveal.STAGGER
			if math.floor(order) ~= math.floor(last) then
				t += Reveal.GROUP_GAP
			end
		end
		delays[i] = t
		last = order
	end
	return delays
end

Reveal.DECOR_LAYER = 4 -- Reveal values from 4 up are decorations
Reveal.SPIN = 25 -- degrees a decoration turns as it pops in

-- Delays and durations for every part. Items keep their cascade; decorations start alongside the
-- last layer before them (the items, staggered among themselves) and stretch so they all land
-- with the last item.
function Reveal.plan(orders: { number }): ({ number }, { number })
	local itemOrders, itemIndex, decorOrders, decorIndex = {}, {}, {}, {}
	for i, order in orders do
		if math.floor(order) >= Reveal.DECOR_LAYER then
			table.insert(decorOrders, order)
			table.insert(decorIndex, i)
		else
			table.insert(itemOrders, order)
			table.insert(itemIndex, i)
		end
	end
	local delays, durations = {}, {}
	if #itemOrders == 0 then
		for k, d in Reveal.delays(decorOrders) do
			delays[decorIndex[k]], durations[decorIndex[k]] = d, Reveal.ITEM_SECONDS
		end
		return delays, durations
	end
	local itemDelays = Reveal.delays(itemOrders)
	local topLayer = 0
	for _, order in itemOrders do
		topLayer = math.max(topLayer, math.floor(order))
	end
	local first, last = math.huge, 0
	for k, d in itemDelays do
		delays[itemIndex[k]], durations[itemIndex[k]] = d, Reveal.ITEM_SECONDS
		if math.floor(itemOrders[k]) == topLayer then
			first = math.min(first, d)
		end
		last = math.max(last, d + Reveal.ITEM_SECONDS)
	end
	for k, d in Reveal.delays(decorOrders) do
		local start = first + (d - Reveal.LEAD)
		delays[decorIndex[k]] = start
		durations[decorIndex[k]] = math.max(last - start, Reveal.ITEM_SECONDS * 0.5)
	end
	return delays, durations
end

-- Turn for the k-th decoration: alternates direction so they don't all swing the same way.
function Reveal.spin(k: number): number
	return if k % 2 == 1 then Reveal.SPIN else -Reveal.SPIN
end

return Reveal
