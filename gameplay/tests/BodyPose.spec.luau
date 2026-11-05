local BodyPose = require("../src/shared/BodyPose")
local Config = require("../src/shared/Config")

local tests = {}

function tests.every_tool_has_a_carry_style(t)
	local models = { Config.start.toolModel }
	for _, level in (Config.track("tool") :: any).levels do
		table.insert(models, level.model)
	end
	for _, model in models do
		local entry = BodyPose.CARRY[model]
		if not entry then
			error(`no carry style for {model}`)
		end
		t.expectEq(type(BodyPose.STYLES[entry.style]), "table", `{model} style {entry.style}`)
		t.expectEq(type(entry.turn), "number", `{model} turn`)
	end
end

function tests.unknown_tool_is_held_in_hand(t)
	local style, turn = BodyPose.carry("NotATool")
	t.expectEq(style, BodyPose.STYLES.hand)
	t.expectEq(turn, 0)
end

function tests.elbow_bends_into_a_right_triangle(t)
	local along, out, reach = BodyPose.elbow(3, 4, 5)
	t.expectNear(along, 1.8, 1e-9)
	t.expectNear(out, 2.4, 1e-9)
	t.expectNear(reach, 5, 1e-9)
end

function tests.elbow_straightens_when_out_of_reach(t)
	local _, out, reach = BodyPose.elbow(3, 4, 10)
	t.expectNear(reach, 7, 0.01)
	if not (out < 0.1) then
		error(`a straight arm should have no elbow offset, got {out}`)
	end
end

function tests.elbow_clamps_when_too_close(t)
	local _, out, reach = BodyPose.elbow(3, 4, 0.5)
	t.expectNear(reach, 1, 0.01)
	if not (out < 0.2) then
		error(`a folded arm should have almost no elbow offset, got {out}`)
	end
end

function tests.crouch_bends_to_lower_the_hips(t)
	t.expectEq(BodyPose.crouch(0, 1), 0)
	t.expectEq(BodyPose.crouch(0.3, 0), 0)
	t.expectNear(BodyPose.crouch(2 * (1 - math.cos(math.rad(30))), 1), math.rad(30), 1e-9)
end

function tests.stride_bounces_up_as_the_legs_pass(t)
	local bounce, twist = BodyPose.stride(0, 0.5, 1)
	t.expectNear(bounce, BodyPose.BOUNCE, 1e-9)
	t.expectNear(twist, 0, 1e-9)
	bounce, twist = BodyPose.stride(0.5, 0.5, 1)
	t.expectNear(bounce, -BodyPose.BOUNCE, 1e-9)
	t.expectNear(twist, -BodyPose.TWIST, 1e-9)
	bounce, twist = BodyPose.stride(-0.5, 0.5, 0.5)
	t.expectNear(bounce, -BodyPose.BOUNCE / 2, 1e-9)
	t.expectNear(twist, BodyPose.TWIST / 2, 1e-9)
end

function tests.stride_is_still_when_standing(t)
	local bounce, twist = BodyPose.stride(0.3, 0.5, 0)
	t.expectEq(bounce, 0)
	t.expectEq(twist, 0)
	bounce, twist = BodyPose.stride(0.3, 0, 1) -- no swing seen yet
	t.expectNear(bounce, BodyPose.BOUNCE, 1e-9)
	t.expectEq(twist, 0)
end

function tests.heavy_loads_bounce_more_and_waddle(t)
	local bounce, twist, roll = BodyPose.stride(0.5, 0.5, 1, true)
	t.expectNear(bounce, -BodyPose.BOUNCE * BodyPose.HEAVY_BOUNCE, 1e-9)
	t.expectNear(twist, -BodyPose.TWIST, 1e-9)
	t.expectNear(roll, BodyPose.WADDLE, 1e-9)
	_, _, roll = BodyPose.stride(0.5, 0.5, 1, false)
	t.expectEq(roll, 0)
end

function tests.lean_forward_with_speed_and_into_turns(t)
	local pitch, roll = BodyPose.lean(0, 0, 0, false)
	t.expectEq(pitch, 0)
	t.expectEq(roll, 0)
	pitch = BodyPose.lean(16, 16, 0, false)
	t.expectNear(pitch, -16 * BodyPose.LEAN_PER_SPEED, 1e-9)
	pitch, roll = BodyPose.lean(1000, 16, 1000, false)
	t.expectNear(pitch, -BodyPose.LEAN_MAX, 1e-9)
	t.expectNear(roll, BodyPose.ROLL_MAX, 1e-9)
	_, roll = BodyPose.lean(0, 16, 1, false)
	t.expectNear(roll, BodyPose.ROLL_PER_TURN, 1e-9)
end

function tests.lean_ignores_turning_on_the_spot(t)
	local _, roll = BodyPose.lean(0, 0, 3, false)
	t.expectEq(roll, 0)
end

function tests.heavy_loads_lean_back(t)
	local pitch = BodyPose.lean(0, 0, 0, true)
	t.expectNear(pitch, BodyPose.HEAVY_BACK, 1e-9)
end

function tests.look_splits_between_neck_and_waist(t)
	local neck, waist = BodyPose.look(30)
	t.expectNear(neck, math.rad(30) * BodyPose.NECK_SHARE, 1e-9)
	t.expectNear(waist, math.rad(30) * (1 - BodyPose.NECK_SHARE), 1e-9)
	neck, waist = BodyPose.look(-200)
	t.expectNear(neck + waist, -BodyPose.LOOK_MAX, 1e-9)
end

function tests.only_real_falls_dip_on_landing(t)
	t.expectEq(BodyPose.landDip(BodyPose.DIP_FROM_SPEED - 1), 0)
	t.expectNear(BodyPose.landDip(BodyPose.DIP_FROM_SPEED + 10), 10 * BodyPose.DIP_PER_SPEED, 1e-9)
	t.expectEq(BodyPose.landDip(10000), BodyPose.DIP_MAX)
end

function tests.scoop_dip_reaches_down_and_bends_over(t)
	local down, forward, tilt, bend = BodyPose.fromView(0.45, math.rad(-35))
	t.expectNear(down, 0.45 * BodyPose.ACTION_DOWN, 1e-9)
	t.expectNear(forward, 0.45 * BodyPose.ACTION_FORWARD, 1e-9)
	t.expectNear(tilt, math.rad(-35), 1e-9)
	t.expectNear(bend, 0.45 * BodyPose.ACTION_BEND, 1e-9)
end

function tests.pour_lift_raises_without_bending(t)
	local down, forward, tilt, bend = BodyPose.fromView(-0.1, math.rad(-65))
	t.expectNear(down, -0.1 * BodyPose.ACTION_DOWN, 1e-9)
	t.expectEq(forward, 0)
	t.expectNear(tilt, math.rad(-65), 1e-9)
	t.expectEq(bend, 0)
end

return tests
