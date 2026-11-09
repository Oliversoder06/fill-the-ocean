--!strict
-- The "next goal" line under the fill bar (client/Goal): the one most useful thing to do next. Pure:
-- the client lists what is on sale and the next gate (with affordability from Items.affords and
-- Hud.offer) and passes the formatters (shared/Format); this picks one and words it.

-- Something on sale now: `place` reads after the name ("at the Tool Shack", "in UPGRADES"), `verb`
-- before it (default "Buy"); `target` is the caller's, returned when this one is picked.
export type Offer = { name: string, cost: number, place: string?, verb: string?, affordable: boolean, target: any }
-- The next closed gate: `fill` it goes on sale at, `onSale` once the ocean is that full.
export type Gate = { name: string, fill: number, price: number, onSale: boolean, affordable: boolean, target: any }
export type Formatters = { money: (number) -> string, fill: (number) -> string, percent: (number) -> string }

local NextGoal = {}

local function placed(offer: Offer): string
	return if offer.place then `{offer.name} {offer.place}` else offer.name
end

-- In order: the dearest offer (an affordable gate on sale counts) `money` pays now; the gate on sale;
-- the cheapest offer still out of reach; the fill the next gate waits for; else just filling.
-- Returns the text and the picked offer's or gate's target (nil for the last).
function NextGoal.pick(offers: { Offer }, gate: Gate?, money: number, fill: number, format: Formatters): (string, any)
	local best: Offer? = nil
	local cheapest: Offer? = nil
	local all = table.clone(offers)
	if gate and gate.onSale then
		table.insert(all, { verb = "Open", name = `the {gate.name} gate`, cost = gate.price, affordable = gate.affordable, target = gate.target })
	end
	for _, offer in all do
		if offer.affordable then
			if not best or offer.cost > best.cost then
				best = offer
			end
		elseif not cheapest or offer.cost < cheapest.cost then
			cheapest = offer
		end
	end
	if best then
		return `{best.verb or "Buy"} {placed(best)} · {format.money(best.cost)}`, best.target
	elseif gate and gate.onSale then
		return `Open the {gate.name} gate · {format.money(gate.price)} (you have {format.money(money)})`, gate.target
	elseif cheapest then
		return `Next: {placed(cheapest)} · {format.money(cheapest.cost)} (you have {format.money(money)})`, cheapest.target
	elseif gate then
		return `Fill the ocean to {format.percent(gate.fill)} to reach {gate.name} ({format.fill(fill)})`, gate.target
	end
	return "Fill the ocean!", nil
end

return NextGoal
