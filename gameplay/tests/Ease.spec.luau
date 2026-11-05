local Ease = require("../src/shared/Ease")

local tests = {}

function tests.back_out_starts_and_ends(t)
	t.expectNear(Ease.backOut(0, 2), 0, 1e-9)
	t.expectNear(Ease.backOut(1, 2), 1, 1e-9)
end

function tests.back_out_overshoots_once(t)
	t.expectNear(Ease.backOut(0.25, 2), 0.859375, 1e-9)
	t.expectNear(Ease.backOut(0.5, 2), 1.125, 1e-9)
	t.expectNear(Ease.backOut(0.75, 2), 1.078125, 1e-9)
end

function tests.back_out_peak_matches_reference(t)
	t.expectNear(Ease.backOut(5 / 9, 2), 1 + 32 / 243, 1e-9)
end

function tests.back_out_clamps(t)
	t.expectNear(Ease.backOut(-1, 2), 0, 1e-9)
	t.expectNear(Ease.backOut(2, 2), 1, 1e-9)
end

function tests.pop_scales_the_step(t)
	t.expectNear(Ease.pop(0.2, 0.4, 0), 0.2, 1e-9)
	t.expectNear(Ease.pop(0.2, 0.4, 0.14), 0.425, 1e-9)
	t.expectNear(Ease.pop(0.2, 0.4, 1), 0.4, 1e-9)
end

function tests.shake_starts_and_ends_still(t)
	t.expectNear(Ease.shake(0, 4, 6), 0, 1e-9)
	t.expectNear(Ease.shake(1, 4, 6), 0, 1e-9)
	t.expectNear(Ease.shake(2, 4, 6), 0, 1e-9)
end

function tests.shake_fades_out(t)
	t.expectNear(Ease.shake(1 / 16, 4, 6), 6 * 15 / 16, 1e-9) -- first peak
	t.expectNear(Ease.shake(5 / 16, 4, 6), 6 * 11 / 16, 1e-9) -- third peak, smaller
end

return tests
