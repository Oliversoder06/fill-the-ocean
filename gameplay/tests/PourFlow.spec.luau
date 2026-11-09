local PourFlow = require("../src/shared/PourFlow")
local Cues = require("../src/shared/Cues")

local tests = {}

-- The server's LastPour attribute ("<areaId>@<litres>@<serverTime>") reads back as it was written.
function tests.last_pour_round_trips(t)
	local areaId, litres, at = PourFlow.decode(PourFlow.encode(3, 12.5, 1234.75))
	t.expectEq(areaId, 3)
	t.expectEq(litres, 12.5)
	t.expectEq(at, 1234.75)
	areaId, litres, at = PourFlow.decode(PourFlow.encode(1, 1e20, 0.1))
	t.expectEq(areaId, 1)
	t.expectEq(litres, 1e20, "huge pours survive the text")
	t.expectEq(at, 0.1)
end

function tests.last_pour_rejects_anything_else(t)
	t.expectEq(PourFlow.decode(nil), nil, "no pour yet")
	for _, value in { 5, "", "1@2", "x@1@2", "0@1@2", "1.5@1@2", "2@-1@3", "2@1@3@4", "2@nan@3" } do
		t.expectEq(PourFlow.decode(value), nil, `decode({tostring(value)})`)
	end
end

-- A wave's place along a path of segments: the segment and the fraction along it, held at the ends.
function tests.along_a_path(t)
	local lengths = { 10, 20 }
	t.expectEq(PourFlow.total(lengths), 30)
	local function at(distance: number, segment: number, fraction: number)
		local s, f = PourFlow.along(lengths, distance)
		t.expectEq(s, segment, `segment at {distance}`)
		t.expectNear(f, fraction, 1e-9, `fraction at {distance}`)
	end
	at(-3, 1, 0)
	at(0, 1, 0)
	at(5, 1, 0.5)
	at(10, 1, 1)
	at(15, 2, 0.25)
	at(30, 2, 1)
	at(99, 2, 1)
	local s, f = PourFlow.along({ 0, 10 }, 0)
	t.expectEq(s, 1, "a zero-length segment")
	t.expectEq(f, 1)
end

-- Bigger pours pulse the fill bar more, by orders of magnitude, between the cue's min and max.
function tests.pulse_grows_with_the_pour(t)
	local cue = Cues.channel
	t.expectNear(PourFlow.pulse(cue, 0), cue.pulseMin, 1e-9, "nothing")
	t.expectNear(PourFlow.pulse(cue, 1), cue.pulseMin, 1e-9, "a litre")
	t.expectNear(PourFlow.pulse(cue, cue.pulseFullLitres), cue.pulseMax, 1e-9, "full")
	t.expectNear(PourFlow.pulse(cue, cue.pulseFullLitres * 1000), cue.pulseMax, 1e-9, "capped")
	local mid = PourFlow.pulse(cue, math.sqrt(cue.pulseFullLitres))
	t.expectNear(mid, (cue.pulseMin + cue.pulseMax) / 2, 1e-9, "halfway in orders of magnitude")
end

-- The seabed's pour marker shows as placed while the ocean is empty and is gone by markerFadeFill.
function tests.pour_marker_fades_as_the_ocean_fills(t)
	local fade = Cues.channel.markerFadeFill
	t.expectNear(PourFlow.markerTransparency(0.2, 0, fade), 0.2, 1e-9)
	t.expectNear(PourFlow.markerTransparency(0.2, fade / 2, fade), 0.6, 1e-9)
	t.expectNear(PourFlow.markerTransparency(0.2, fade, fade), 1, 1e-9)
	t.expectNear(PourFlow.markerTransparency(0.2, 1, fade), 1, 1e-9)
end

function tests.channel_cue_is_sane(t)
	local cue = Cues.channel
	t.expectEq(type(cue.wave), "string")
	t.expectEq(cue.waveSpeed > 0, true, "waveSpeed")
	t.expectEq(cue.trickleSpeed > 0 and cue.trickleSpeed < cue.waveSpeed, true, "a trickle is gentler than a wave")
	t.expectEq(cue.pulseMin > 1 and cue.pulseMax > cue.pulseMin, true, "pulses grow")
	t.expectEq(cue.markerFadeFill > 0 and cue.markerFadeFill < 1, true, "markerFadeFill")
	t.expectEq(cue.maxWaves >= 1, true, "maxWaves")
	local splash = cue.splash
	t.expectEq(#splash.splashSounds, 3)
	t.expectEq(type(splash.vfx), "string")
	t.expectEq(splash.pitchMin < splash.pitchMax, true, "splash pitch")
	for _, field in { "splashVolume", "otherVolume" } do
		local v = splash[field]
		t.expectEq(type(v) == "number" and v > 0 and v <= 1, true, `splash {field}`)
	end
end

return tests
