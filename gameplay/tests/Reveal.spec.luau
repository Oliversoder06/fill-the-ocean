local Reveal = require("../src/shared/Reveal")

local tests = {}

function tests.items_stagger_and_groups_add_a_gap(t)
	local d = Reveal.delays({ 1.1, 1.2, 2.1 })
	t.expectNear(d[1], 0.08, 1e-9)
	t.expectNear(d[2], 0.11, 1e-9)
	t.expectNear(d[3], 0.17, 1e-9) -- 0.11 + stagger + group gap
end

function tests.order_comes_from_the_value_not_the_list(t)
	local d = Reveal.delays({ 2.1, 1.1, 1.2 })
	t.expectNear(d[2], 0.08, 1e-9)
	t.expectNear(d[3], 0.11, 1e-9)
	t.expectNear(d[1], 0.17, 1e-9)
end

function tests.equal_values_appear_together(t)
	local d = Reveal.delays({ 3.1, 3.1, 3.2 })
	t.expectNear(d[1], 0.08, 1e-9)
	t.expectNear(d[2], 0.08, 1e-9)
	t.expectNear(d[3], 0.11, 1e-9)
end

function tests.nothing_to_reveal(t)
	t.expectEq(#Reveal.delays({}), 0)
end

function tests.decorations_finish_with_the_last_item(t)
	local delays, durations = Reveal.plan({ 3.1, 3.2, 4.1, 4.2 })
	t.expectNear(delays[1], 0.08, 1e-9)
	t.expectNear(durations[1], Reveal.ITEM_SECONDS, 1e-9)
	local lastItemEnd = delays[2] + durations[2]
	t.expectNear(lastItemEnd, 0.33, 1e-9)
	t.expectNear(delays[3], 0.08, 1e-9) -- decorations start with the first item
	t.expectNear(delays[4], 0.11, 1e-9)
	t.expectNear(delays[3] + durations[3], lastItemEnd, 1e-9)
	t.expectNear(delays[4] + durations[4], lastItemEnd, 1e-9)
end

function tests.decorations_start_with_the_items_not_the_panels(t)
	local delays, durations = Reveal.plan({ 1.1, 3.1, 3.2, 4.1 })
	t.expectNear(delays[2], 0.14, 1e-9) -- 0.08 + stagger + layer gap
	t.expectNear(delays[4], delays[2], 1e-9)
	t.expectNear(delays[4] + durations[4], delays[3] + durations[3], 1e-9)
end

function tests.decorations_alone_use_normal_timing(t)
	local delays, durations = Reveal.plan({ 4.1 })
	t.expectNear(delays[1], 0.08, 1e-9)
	t.expectNear(durations[1], Reveal.ITEM_SECONDS, 1e-9)
end

function tests.decorations_spin_in_alternate_ways(t)
	t.expectEq(Reveal.spin(1), Reveal.SPIN)
	t.expectEq(Reveal.spin(2), -Reveal.SPIN)
	t.expectEq(Reveal.spin(3), Reveal.SPIN)
end

function tests.whole_shop_finishes_quickly(t)
	-- the shop: 3 panels, 2 tags, 8 items, 4 decorations
	local orders = { 1.1, 1.2, 1.3, 2.1, 2.2, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 4.1, 4.2, 4.3, 4.4 }
	local last = 0
	for _, d in Reveal.delays(orders) do
		last = math.max(last, d)
	end
	if not (last + Reveal.ITEM_SECONDS <= 0.9) then
		error(`the shop takes {last + Reveal.ITEM_SECONDS}s to finish revealing`)
	end
end

return tests
