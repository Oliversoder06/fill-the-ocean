--!strict
-- Easing for UI and viewmodel motion. Pure, Lune-tested.
-- The pop is matched to the reference clip (gameplay/ref for ai): a fill bar rises in about
-- 0.13 s, overshoots about 12% of the step and settles over about 0.15 s, with no second wobble.

local Ease = {}

Ease.POP_SECONDS = 0.28
Ease.POP_OVERSHOOT = 2 -- peaks 13% past the target, 56% of the way through

-- Back-out: rises past 1 once, then settles on 1. t is clamped to [0, 1].
function Ease.backOut(t: number, overshoot: number): number
	local u = math.clamp(t, 0, 1) - 1
	return 1 + (overshoot + 1) * u * u * u + overshoot * u * u
end

-- A value springing from `from` to `to`, `elapsed` seconds after the change.
function Ease.pop(from: number, to: number, elapsed: number): number
	return from + (to - from) * Ease.backOut(elapsed / Ease.POP_SECONDS, Ease.POP_OVERSHOOT)
end

-- A side-to-side shake that fades out: `cycles` full swings of up to `amplitude` over t in [0, 1].
function Ease.shake(t: number, cycles: number, amplitude: number): number
	if t <= 0 or t >= 1 then
		return 0
	end
	return amplitude * (1 - t) * math.sin(t * cycles * 2 * math.pi)
end

return Ease
