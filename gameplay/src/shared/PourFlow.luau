--!strict
-- Poured water's trip down an area's channel to the ocean (client/Channels): the LastPour value the
-- server publishes on every accepted pour, where along the channel a wave is, how hard the fill bar
-- pulses when it lands and how the seabed's pour marker fades. Pure: no requires, so Lune tests and
-- Roblox load it the same way.

local PourFlow = {}

-- ReplicatedStorage attribute LastPour (server/Run): "<areaId>@<litres>@<serverTime>".
function PourFlow.encode(areaId: number, litres: number, at: number): string
	return `{areaId}@{litres}@{at}`
end

-- The area id, litres and server time of a LastPour value; nil for anything else.
function PourFlow.decode(value: any): (number?, number?, number?)
	if type(value) ~= "string" then
		return nil, nil, nil
	end
	local a, l, s = value:match("^([^@]+)@([^@]+)@([^@]+)$")
	local areaId, litres, at = tonumber(a), tonumber(l), tonumber(s)
	if not (areaId and litres and at) or areaId < 1 or areaId % 1 ~= 0 or not (litres >= 0 and litres < math.huge) or at ~= at then
		return nil, nil, nil
	end
	return areaId, litres, at
end

function PourFlow.total(lengths: { number }): number
	local sum = 0
	for _, length in lengths do
		sum += length
	end
	return sum
end

-- Where a wave `distance` studs down a path with segment `lengths` is: the segment and the fraction
-- along it, held at the start before it and at the end past it.
function PourFlow.along(lengths: { number }, distance: number): (number, number)
	local left = math.max(0, distance)
	for i, length in lengths do
		if left <= length then
			return i, if length > 0 then left / length else 1
		end
		left -= length
	end
	return #lengths, 1
end

-- The fill bar's pulse (a UIScale) as `litres` reach the ocean: cue.pulseMin for a litre or less up
-- to cue.pulseMax at cue.pulseFullLitres, by orders of magnitude.
function PourFlow.pulse(cue, litres: number): number
	local f = math.clamp(math.log10(math.max(litres, 1)) / math.log10(cue.pulseFullLitres), 0, 1)
	return cue.pulseMin + (cue.pulseMax - cue.pulseMin) * f
end

-- The seabed pour marker's transparency: its own `base` in an empty ocean, gone by `fadeFill`.
function PourFlow.markerTransparency(base: number, fill: number, fadeFill: number): number
	return base + (1 - base) * math.clamp(fill / fadeFill, 0, 1)
end

return PourFlow
