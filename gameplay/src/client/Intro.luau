-- The intro cutscene, a scene client/Cutscene plays while Phase is "intro" (from IntroAt). shared/
-- IntroCut is the cut (shots, eyelids, logo, sounds, beats) and shared/IntroClips the bodies'
-- motion. A copy of your avatar walks up the beach on its own walk animation (stepped by the
-- distance walked, so its feet never slide) to the lounger, stretches, sits down on it and lies back
-- (IntroClips.lie). The bacon-hair strolls onto the beach in front of you, sits down and plays in the
-- sand (Story.SandPile). One camera take (a spline) runs from the music's drop into your eyes as they
-- close. The water stands full, then drains (Zones.setFill); the ball (Story.BaconFat, its Straw down
-- to the Puddle) drinks it far out, burps, rolls for the beach and its slope throws him past you over
-- the island (IntroCut.flight). You get up into the game's own first-person view: from
-- IntroCut.handover the camera is the game's (the same view, no cut) and your tool swings up into
-- your hand (Viewmodel.swingIn); play starts at IntroCut.length.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IntroClips = require(ReplicatedStorage.Shared.IntroClips)
local IntroCut = require(ReplicatedStorage.Shared.IntroCut)
local Cutscene = require(script.Parent.Cutscene)
local Hud = require(script.Parent.Hud)
local Viewmodel = require(script.Parent.Viewmodel)

local LIE_BLEND = 0.35 -- seconds your walk takes to settle into the lie-down's first pose
local TURN_BLEND = 0.2 -- seconds the lie-down's stand hands over to its lie (IntroClips.lie)
local SIT_BLEND = 0.25 -- seconds his walk takes to settle into sitting down
local TURN_STUDS = 1.5 -- over your last steps you turn to face the sea, as the lie-down starts
local FAT_LAG = 0.06 -- seconds the camera trails the ball: your head chasing him as he flies past
local BACON_LOW = 2 -- studs under him that "baconLow" aims (your eyes getting heavy)
local PILE_GROW = 3.2 -- seconds his sand pile takes to grow
local DRINK_BOB = { degrees = 1.5, hz = 1.6 } -- the sucking head while he drinks
local NOTICE_SECONDS = 0.3
local BURP_TILT = 14 -- degrees his head goes back on the burp
local BURP_HOP = 0.08 -- of his ball's radius, up and down once
local BURP_SECONDS = 0.45
local STRAW_OUT = 0.95 -- of his ball's radius: how far the straw goes out in front before it bends
local STRAW_DROP = 0.1 -- of his ball's radius: how far it dips on the way out

local v3, show, along, walkedAt = Cutscene.v3, Cutscene.show, Cutscene.along, Cutscene.walkedAt
local SEA = Cutscene.SEA

local Intro = {}

-- The intro's own pieces: your walk up the beach, the bacon-hair's stroll, his seat and sand, the
-- ball out on the seabed with its straw and puddle, and the clips baked for your body and his.
local function build(s)
	local places = IntroCut.places
	local kit = s.kit
	local ignore = s.ignore
	local walkFrom, walkTo = v3(places.walkFrom), v3(places.walkTo)
	s.walkPath = Cutscene.curve(walkFrom, (walkFrom + walkTo) / 2, walkTo)

	s.baconPath = Cutscene.curve(v3(places.baconFrom), v3(places.baconBend), v3(places.baconTo))
	local sitAt, sitAhead = along(s.baconPath, s.baconPath.length)
	sitAt = Vector3.new(sitAt.X, Cutscene.groundAt(sitAt.X, sitAt.Z, ignore), sitAt.Z)
	s.baconSeat = CFrame.lookAt(sitAt, sitAt + sitAhead)
	local pileAt = s.baconSeat * v3(places.sandPile)
	s.pileAt = Vector3.new(pileAt.X, Cutscene.groundAt(pileAt.X, pileAt.Z, ignore), pileAt.Z)
	s.pile = Cutscene.copyPart(kit.pile)
	s.pileSize = kit.pile.Size.X

	-- The ball far out on the seabed with his straw, once the water is gone.
	local fatAt = v3(places.fat)
	s.fatAt = CFrame.lookAt(fatAt, fatAt - SEA) * CFrame.Angles(0, math.rad(places.baconTurn), 0) -- toward the beach, turned
	s.fat = Cutscene.copyStory(kit.fat, false)
	s.fat:PivotTo(s.fatAt)
	s.belly = Cutscene.asset(s.fat, "Belly", "BasePart")
	s.fatRadius = s.belly.Size.Y / 2
	-- his roll for the beach and his flight off it; the model from his middle
	s.flight = IntroCut.flight(s.fatRadius, workspace.Gravity)
	s.rollAxis = Vector3.new(s.flight.hx, 0, s.flight.hz):Cross(Vector3.yAxis)
	s.fromMiddle = CFrame.new(fatAt + Vector3.new(0, s.fatRadius, 0)):Inverse() * s.fatAt
	s.neck = s.fat:FindFirstChild("Neck", true)
	assert(s.neck and s.neck:IsA("Motor6D"), "Story.BaconFat needs a Motor6D Neck (his head turns)")
	s.mouth = s.fat:FindFirstChild("Mouth", true)
	assert(s.mouth and s.mouth:IsA("Attachment"), "Story.BaconFat needs an Attachment Mouth (where the straw goes)")
	s.straw = Cutscene.copyPart(kit.straw) -- a bendy straw: out of his mouth, then down to the puddle
	s.strawDown = Cutscene.copyPart(kit.straw)
	s.puddle = Cutscene.copyPart(kit.puddle)
	s.puddleAt = v3(places.puddle)
	-- where his head turns when he notices you: your eyes on the lounger, in his own axes
	local toEye = s.fatAt:VectorToObjectSpace((v3(places.eye) - s.mouth.WorldPosition).Unit)
	s.lookYaw = math.deg(math.atan2(-toEye.X, -toEye.Z))
	s.lookPitch = math.deg(math.asin(toEye.Y))

	-- Bakes take a few frames each; the slump is needed first, the lie-down from IntroCut.beats.lie.
	task.spawn(function()
		s.slumpBaked = Cutscene.bake(s.anim, IntroClips.slump)
		task.wait()
		local rootAt = { s.lieRoot.X, s.lieRoot.Y, s.lieRoot.Z }
		local seat = IntroClips.seat(places.cushion, places.recline, rootAt)
		local stand, lie = IntroClips.lie(s.anim.anatomy, seat, IntroClips.watch(places.baconFrom, places.baconTo, rootAt))
		s.standBaked = Cutscene.bake(s.anim, stand)
		task.wait()
		s.lieBaked = Cutscene.bake(s.anim, lie)
		task.wait()
		s.sitBaked = Cutscene.bake(s.walkerAnim, IntroClips.sandSit)
		task.wait()
		s.playBaked = Cutscene.bake(s.walkerAnim, IntroClips.sandPlay)
	end)
end

-- Your copy, from the drop until your eyes shut: up the beach on your own walk, a tired slump over
-- it, turning to the sea over the last steps; then the lie-down (IntroClips.lie: the stand, then the
-- lie), blended in from the walk's last step.
local function body(s, t: number)
	local b = IntroCut.beats
	local on = t >= b.drop and t < b.swap
	show(s.body, on, s.folder)
	if not on then
		return
	end
	if s.slumpBaked and not s.slump then
		s.slump = s.anim:play(s.slumpBaked, { loop = true, layer = "add", fadeIn = 0, fadeOut = 0 })
	end
	local lying = math.clamp((t - b.lie) / LIE_BLEND, 0, 1)
	if s.slump then
		s.slump:setWeight(1 - lying)
	end
	if t < b.lie then
		if s.standing then -- (back before the lie-down: Studio's StudioIntroAt)
			s.standing:setWeight(0)
			s.lying:setWeight(0)
		end
		Cutscene.walk(s, s.walkPath, walkedAt(t, b.walkFrom, b.walkTo, s.walkPath.length), SEA, TURN_STUDS)
	else
		s.body:PivotTo(CFrame.new(s.lieRoot)) -- facing the sea, as IntroClips.lie starts
		if s.walkTrack and s.walkTrack.IsPlaying then
			s.walkTrack:Stop(LIE_BLEND)
		end
		-- the stand is the older handle, so it is written last: over the lie, fading out at the turn
		if s.standBaked and s.lieBaked and not s.standing then
			s.standing = s.anim:play(s.standBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
			s.standing:setSpeed(0)
			s.lying = s.anim:play(s.lieBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
			s.lying:setSpeed(0)
		end
		if s.standing then
			local into = t - b.lie
			local turned = into - IntroClips.turnSeconds
			s.lying:setWeight(if turned >= 0 then lying else 0)
			s.standing:setWeight(lying * (1 - math.clamp(turned / TURN_BLEND, 0, 1)))
			s.standing:seek(math.clamp(into, 0, s.standBaked.length - 1e-3))
			s.lying:seek(math.clamp(turned, 0, s.lieBaked.length - 1e-3))
		end
	end
end

-- The bacon-hair on the beach, from his stroll in until your eyes shut: walking on his own R6 walk
-- along his curve, slowing to a stop; then he sits down in the sand and plays in it, the pile growing.
local function walker(s, t: number)
	local b = IntroCut.beats
	local on = t >= b.baconFrom and t < b.swap
	show(s.walker, on, s.folder)
	show(s.pile, on and t >= b.baconPlay, s.folder)
	if t < b.baconSit then
		local d = walkedAt(t, b.baconFrom, b.baconTo, s.baconPath.length)
		local p, ahead = along(s.baconPath, d)
		local at = Vector3.new(p.X, Cutscene.groundAt(p.X, p.Z, s.ignore), p.Z)
		s.walker:PivotTo(CFrame.lookAt(at, at + ahead))
		if not on then
			return -- placed all the same: the camera aims ahead of him
		end
		if not s.walkerTrack then
			s.walkerTrack = s.walkerAnimator:LoadAnimation(s.kit.baconWalk)
			s.walkerTrack.Looped = true
		end
		if not s.walkerTrack.IsPlaying then
			s.walkerTrack:Play(0, 1, 0)
		end
		if s.walkerTrack.Length > 0 then
			s.walkerTrack.TimePosition = (d / IntroClips.walks.bacon.pace) % s.walkerTrack.Length
		end
		-- (back before he sat: Studio's StudioIntroAt)
		if s.sit then
			s.sit:setWeight(0)
		end
		if s.play then
			s.play:setWeight(0)
		end
		return
	end
	s.walker:PivotTo(s.baconSeat)
	if not on then
		return
	end
	if s.walkerTrack and s.walkerTrack.IsPlaying then
		s.walkerTrack:Stop(SIT_BLEND)
	end
	if s.sitBaked and not s.sit then
		s.sit = s.walkerAnim:play(s.sitBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
		s.sit:setSpeed(0)
	end
	if s.playBaked and not s.play then
		s.play = s.walkerAnim:play(s.playBaked, { loop = true, fadeIn = 0, fadeOut = 0 })
		s.play:setSpeed(0)
	end
	-- one at a time: the sit ends on the play's first pose (a stopped clip would put the joints back
	-- for a frame, so the other one just weighs nothing)
	local playing = t >= b.baconPlay
	if s.sit then
		s.sit:setWeight(if playing then 0 else math.clamp((t - b.baconSit) / SIT_BLEND, 0, 1))
		s.sit:seek(math.min(t - b.baconSit, s.sitBaked.length - 1e-3))
	end
	if s.play then
		s.play:setWeight(if playing then 1 else 0)
		s.play:seek(math.max(t - b.baconPlay, 0) % s.playBaked.length)
	end
	if playing then
		local grown = IntroCut.eased("out", math.clamp((t - b.baconPlay) / PILE_GROW, 0, 1))
		local size = s.pileSize * (0.45 + 0.55 * grown)
		local rise = size * (0.12 + 0.1 * grown) -- a ball sunk into the sand: only its top shows
		Hud.set(s.pile, "Size", Vector3.one * size)
		Hud.set(s.pile, "CFrame", CFrame.new(s.pileAt + Vector3.new(0, rise - size / 2, 0)))
	end
end

-- The ball, from the swap: drinks the puddle (head down, sucking), looks round at you, burps, rolls
-- for the beach and flies off it (IntroCut.flight).
local function fat(s, t: number)
	local b = IntroCut.beats
	local swapped = t >= b.swap
	local drinking = swapped and t < b.drunk + 0.2
	show(s.fat, swapped, s.folder)
	show(s.straw, drinking, s.folder)
	show(s.strawDown, drinking, s.folder)
	show(s.puddle, swapped and t < b.drunk, s.folder)
	if not swapped then
		return
	end
	-- head: down at the straw (sucking), round to look at you on noticing, back for the burp
	local sipping = -20 + DRINK_BOB.degrees * math.sin(2 * math.pi * DRINK_BOB.hz * t)
	local noticed = IntroCut.eased("out", math.clamp((t - b.notice) / NOTICE_SECONDS, 0, 1))
	local pitch = sipping + (s.lookPitch - sipping) * noticed
	local yaw = s.lookYaw * noticed
	local hop = 0
	if t >= b.burp and t < b.burp + BURP_SECONDS * 2 then
		local u = (t - b.burp) / BURP_SECONDS
		pitch += BURP_TILT * math.sin(math.pi * math.clamp(u / 2, 0, 1))
		hop = BURP_HOP * s.fatRadius * math.sin(math.pi * math.clamp(u, 0, 1))
	end
	s.neck.Transform = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
	-- rolling for the beach, then flying: turned about the run's axis by how far he has rolled
	local x, y, z, turned = IntroCut.ballAt(s.flight, t)
	local turn = CFrame.fromAxisAngle(s.rollAxis, -turned)
	s.fat:PivotTo(CFrame.new(x, y + hop, z) * turn * s.fromMiddle)
	if drinking then
		local left = IntroCut.puddleLeft(t)
		local size = 2 * IntroCut.places.puddleRadius * math.max(left, 0.02)
		s.puddle.Size = Vector3.new(s.puddle.Size.X, size, size)
		s.puddle.CFrame = CFrame.new(s.puddleAt) * CFrame.Angles(0, 0, math.pi / 2)
		-- out of the mouth and forward past the ball, then bent down into the puddle
		local mouth = s.mouth.WorldPosition
		local bend = mouth + s.fatAt.LookVector * s.fatRadius * STRAW_OUT - Vector3.new(0, s.fatRadius * STRAW_DROP, 0)
		Cutscene.strawBetween(s.straw, mouth, bend)
		Cutscene.strawBetween(s.strawDown, bend, s.puddleAt)
	end
end

local function frame(s, t: number, dt: number)
	Cutscene.setWater(s, if t < IntroCut.beats.swap then "full" else "dry")
	body(s, t)
	walker(s, t)
	fat(s, t)
	Cutscene.follow(s, "fat", s.belly.Position, FAT_LAG, dt)
end

-- The intro's own camera subjects: "fat" (the ball's middle) and "baconLow" (a little below the
-- bacon-hair: heavy eyes).
local function subject(s, name: string): Vector3?
	if name == "fat" then
		return s.aim.fat
	elseif name == "baconLow" then
		return s.aim.bacon - Vector3.new(0, BACON_LOW, 0)
	end
	return nil
end

-- The game's view is back: the ball is long gone over the island; the tool swings up into your hand.
local function handover(s)
	show(s.fat, false, s.folder)
	Viewmodel.swingIn()
end

local function finish(s)
	s.fat:Destroy()
	for _, part in { s.pile, s.straw, s.strawDown, s.puddle } do
		part:Destroy()
	end
end

local function load(kit)
	local story = kit.story
	kit.fat = Cutscene.asset(story, "BaconFat", "Model")
	assert(kit.fat.PrimaryPart, "Story.BaconFat needs a PrimaryPart (its pivot is at its feet)")
	kit.pile = Cutscene.asset(story, "SandPile", "BasePart")
	kit.straw = Cutscene.asset(story, "Straw", "BasePart")
	kit.puddle = Cutscene.asset(story, "Puddle", "BasePart")
end

local places = IntroCut.places
Intro.def = {
	name = "Intro",
	cut = IntroCut,
	phase = "intro",
	at = "IntroAt",
	hold = "StudioIntroAt",
	ground = { places.walkFrom, places.walkTo, places.stand, places.baconFrom, places.baconBend, places.baconTo },
	load = load,
	build = build,
	frame = frame,
	subject = subject,
	handover = handover,
	finish = finish,
}

-- An admin's preview (client/Admin): the whole intro from now on this client only. Returns why it
-- can't start, or nil.
function Intro.preview(): string?
	return Cutscene.preview(Intro.def)
end

return Intro
