--!strict
-- The areas: which are open, the next gate, and looking one up. Pure: config is passed in, so Lune
-- tests and Roblox load it the same way. Gates open in order (2, 3, 4, 5); gatesOpen is the save's list.

local Areas = {}

-- The open area ids as a set: the cove (1) plus every open gate.
function Areas.open(gatesOpen: { number }): { [number]: boolean }
	local open = { [1] = true }
	for _, id in gatesOpen do
		open[id] = true
	end
	return open
end

-- The open area ids in order: the cove (1) and every open gate, sorted (the save's list is left as is).
function Areas.openIds(gatesOpen: { number }): { number }
	local ids = table.clone(gatesOpen)
	table.insert(ids, 1)
	table.sort(ids)
	return ids
end

-- The lowest area whose gate is still closed, and whether it is on sale at the ocean's `fill`
-- (0..1). No gate left: nil, false.
function Areas.nextGate(config, gatesOpen: { number }, fill: number): (number?, boolean)
	for _, area in config.areas do
		if area.gate and not table.find(gatesOpen, area.id) then
			return area.id, fill >= area.gate.fill
		end
	end
	return nil, false
end

-- What area `areaId`'s gate is at the ocean's `fill`: "open", "buy" (the next gate, on sale),
-- "fill" (waits for its fill) or "order" (past its fill, but an earlier gate is still closed). The
-- one rule for the gate prompt (server/Run), its sign (client/Gates) and the honeycomb.
export type GateStatus = "open" | "buy" | "fill" | "order"

function Areas.gateOffer(config, gatesOpen: { number }, fill: number, areaId: number): GateStatus
	if table.find(gatesOpen, areaId) then
		return "open"
	end
	local nextId, onSale = Areas.nextGate(config, gatesOpen, fill)
	if nextId == areaId and onSale then
		return "buy"
	end
	return if fill >= Areas.byId(config, areaId).gate.fill then "order" else "fill"
end

-- The honeycomb's id for area `areaId`'s gate: Buy("gate:2", 0) buys it (server/Run).
function Areas.gateId(areaId: number): string
	return `gate:{areaId}`
end

-- The gated area a gate id names; nil for anything else (id may be any remote value).
function Areas.fromGateId(config, id: any)
	local n = if type(id) == "string" then id:match("^gate:(%d+)$") else nil
	local area = if n then Areas.byId(config, tonumber(n)) else nil
	return if area and area.gate then area else nil
end

-- id may be anything (an attribute or remote value); only a listed area's id returns it.
function Areas.byId(config, id: any)
	for _, area in config.areas do
		if area.id == id then
			return area
		end
	end
	return nil
end

return Areas
