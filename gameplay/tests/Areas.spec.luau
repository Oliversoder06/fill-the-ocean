local Areas = require("../../common/Areas")
local Config = require("../src/shared/Config")

local tests = {}

function tests.open_is_the_cove_plus_open_gates(t)
	local open = Areas.open({})
	t.expectEq(open[1], true, "the cove is always open")
	t.expectEq(open[2], nil)
	open = Areas.open({ 2, 3 })
	t.expectEq(open[1], true)
	t.expectEq(open[2], true)
	t.expectEq(open[3], true)
	t.expectEq(open[4], nil)
end

-- The open area ids in order, the cove first, whatever order the save lists the gates in.
function tests.open_ids_sorted_with_the_cove(t)
	local ids = Areas.openIds({})
	t.expectEq(#ids, 1)
	t.expectEq(ids[1], 1)
	local gates = { 3, 2 }
	ids = Areas.openIds(gates)
	t.expectEq(#ids, 3)
	t.expectEq(ids[1], 1)
	t.expectEq(ids[2], 2)
	t.expectEq(ids[3], 3)
	t.expectEq(gates[1], 3, "the save's list is not changed")
end

-- The next gate is the lowest closed one; it goes on sale exactly at its fill point.
function tests.gate_on_sale_at_its_fill(t)
	local id, onSale = Areas.nextGate(Config, {}, 0)
	t.expectEq(id, 2)
	t.expectEq(onSale, false, "not on sale before its fill")
	id, onSale = Areas.nextGate(Config, {}, 0.0699)
	t.expectEq(onSale, false)
	id, onSale = Areas.nextGate(Config, {}, 0.07)
	t.expectEq(id, 2)
	t.expectEq(onSale, true, "on sale exactly at its fill")
	id, onSale = Areas.nextGate(Config, { 2 }, 0.1)
	t.expectEq(id, 3)
	t.expectEq(onSale, false, "gate 3 waits for 22%")
	id, onSale = Areas.nextGate(Config, {}, 0.5)
	t.expectEq(id, 2, "gates open in order: the lowest closed one is next")
	t.expectEq(onSale, true)
	id, onSale = Areas.nextGate(Config, { 2, 3, 4, 5 }, 1)
	t.expectEq(id, nil, "no gate left")
	t.expectEq(onSale, false)
end

function tests.by_id(t)
	t.expectEq(Areas.byId(Config, 1).name, "Cove Well")
	t.expectEq(Areas.byId(Config, 4).name, "Glacier")
	t.expectEq(Areas.byId(Config, 6), nil)
	t.expectEq(Areas.byId(Config, "2" :: any), nil, "ids are numbers")
end

return tests
