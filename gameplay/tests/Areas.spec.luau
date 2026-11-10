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
	id, onSale = Areas.nextGate(Config, {}, 0.1499)
	t.expectEq(onSale, false)
	id, onSale = Areas.nextGate(Config, {}, 0.15)
	t.expectEq(id, 2)
	t.expectEq(onSale, true, "on sale exactly at its fill")
	id, onSale = Areas.nextGate(Config, { 2 }, 0.2)
	t.expectEq(id, 3)
	t.expectEq(onSale, false, "gate 3 waits for 33%")
	id, onSale = Areas.nextGate(Config, {}, 0.5)
	t.expectEq(id, 2, "gates open in order: the lowest closed one is next")
	t.expectEq(onSale, true)
	id, onSale = Areas.nextGate(Config, { 2, 3, 4, 5 }, 1)
	t.expectEq(id, nil, "no gate left")
	t.expectEq(onSale, false)
end

-- One rule for the gate prompt, its sign and the honeycomb's Areas hexes.
function tests.gate_offer_says_what_a_gate_is_now(t)
	t.expectEq(Areas.gateOffer(Config, {}, 0, 2), "fill", "waits for 15%")
	t.expectEq(Areas.gateOffer(Config, {}, 0.15, 2), "buy", "the next gate, on sale at its fill")
	t.expectEq(Areas.gateOffer(Config, { 2 }, 0.5, 2), "open")
	t.expectEq(Areas.gateOffer(Config, {}, 0.2, 3), "fill", "gate 3 waits for 33%")
	t.expectEq(Areas.gateOffer(Config, {}, 0.4, 3), "order", "past its fill, but Mountain Spring is still closed")
	t.expectEq(Areas.gateOffer(Config, { 2 }, 0.4, 3), "buy")
	t.expectEq(Areas.gateOffer(Config, { 2, 3, 4, 5 }, 1, 5), "open")
end

-- The honeycomb buys a gate as Buy("gate:<areaId>", 0); ids come from a remote, so anything else is nil.
function tests.gate_ids_round_trip(t)
	t.expectEq(Areas.gateId(3), "gate:3")
	t.expectEq(Areas.fromGateId(Config, "gate:3").name, "Hot Springs")
	t.expectEq(Areas.fromGateId(Config, Areas.gateId(5)).id, 5)
	t.expectEq(Areas.fromGateId(Config, "gate:1"), nil, "the cove has no gate")
	t.expectEq(Areas.fromGateId(Config, "gate:9"), nil)
	t.expectEq(Areas.fromGateId(Config, "gate:2x"), nil)
	t.expectEq(Areas.fromGateId(Config, "pickup"), nil)
	t.expectEq(Areas.fromGateId(Config, 2), nil)
	t.expectEq(Areas.fromGateId(Config, nil), nil)
end

function tests.by_id(t)
	t.expectEq(Areas.byId(Config, 1).name, "Cove Well")
	t.expectEq(Areas.byId(Config, 4).name, "Glacier")
	t.expectEq(Areas.byId(Config, 6), nil)
	t.expectEq(Areas.byId(Config, "2" :: any), nil, "ids are numbers")
end

return tests
