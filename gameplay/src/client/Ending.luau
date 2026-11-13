-- The ending cutscene, a scene client/Cutscene plays while Phase is "ending" (from EndingAt; the
-- server sends everyone to the lobby once it has played). shared/EndCut is the cut and
-- shared/IntroClips the bodies' motion: you lie on the lounger by your full ocean (IntroClips.lie,
-- watching him come); the bacon-hair strolls down to the water's edge on his R6 walk, sits down
-- (IntroClips.sandSit) and dips a straw in (Story.Straw); you get up (the lie-down backwards), march
-- over on your own walk and slap him (IntroClips.slap); he flies off over the sea (EndCut.flown) and
-- is gone under its surface far out. Then black and the logo, held until the lobby takes over.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EndCut = require(ReplicatedStorage.Shared.EndCut)
local IntroClips = require(ReplicatedStorage.Shared.IntroClips)
local IntroCut = require(ReplicatedStorage.Shared.IntroCut)
local Cutscene = require(script.Parent.Cutscene)

local SIT_BLEND = 0.25 -- seconds his walk takes to settle into sitting down
local HANDOVER_BLEND = 0.15 -- seconds the lie hands over to the stand, getting up
local MARCH_BLEND = 0.3 -- seconds the stand hands over to your march
local SLAP_BLEND = 0.15 -- seconds the march hands over to the slap
local TURN_STUDS = 1.2 -- over your last steps you turn to face him
local SEAT_HIPS = 1.5 -- studs over his seat his middle is, sitting: he tumbles about it
local MOUTH = CFrame.new(0, -0.2, -0.5) -- his mouth on his head
local STRAW_THICK = 0.22 -- studs: Story.Straw is the ball's, far too thick for him

local v3, show, along, walkedAt = Cutscene.v3, Cutscene.show, Cutscene.along, Cutscene.walkedAt
local SEA = Cutscene.SEA

local Ending = {}

-- The ending's own pieces: his stroll and seat at the water's edge, the straw, your march, and the
-- clips baked for your body and his.
local function build(s)
	local places = EndCut.places
	local ignore = s.ignore
	s.baconPath = Cutscene.curve(v3(places.baconFrom), v3(places.baconBend), v3(places.baconTo))
	local sitAt = Cutscene.onGround(places.baconTo, ignore)
	s.baconSeat = CFrame.lookAt(sitAt, sitAt + SEA)
	s.strawTo = v3(places.water)
	s.straw = Cutscene.copyPart(s.kit.straw)
	s.straw.Size = Vector3.new(s.straw.Size.X, STRAW_THICK, STRAW_THICK)

	local slapAt = Cutscene.onGround(places.slapAt, ignore)
	s.marchPath = Cutscene.curve(Vector3.new(s.lieRoot.X, 0, s.lieRoot.Z), v3(places.marchBend), slapAt)
	local toHim = sitAt - slapAt
	s.slapFacing = Vector3.new(toHim.X, 0, toHim.Z).Unit
	s.slapRoot = CFrame.lookAt(slapAt + Vector3.new(0, s.rootHeight, 0), slapAt + Vector3.new(0, s.rootHeight, 0) + s.slapFacing)

	-- his flight: tumbling forward about his middle, along the launch's way
	local heading = EndCut.launch.heading
	s.tumbleAxis = Vector3.new(heading[1], 0, heading[2]).Unit:Cross(Vector3.yAxis)
	s.middle = sitAt + Vector3.new(0, SEAT_HIPS, 0)
	s.fromMiddle = CFrame.new(s.middle):Inverse() * s.baconSeat

	task.spawn(function()
		local rootAt = { s.lieRoot.X, s.lieRoot.Y, s.lieRoot.Z }
		local set = IntroCut.places
		local seat = IntroClips.seat(set.cushion, set.recline, rootAt)
		local stand, lie = IntroClips.lie(s.anim.anatomy, seat, IntroClips.watch(places.baconFrom, places.baconTo, rootAt))
		s.slapBaked = Cutscene.bake(s.anim, IntroClips.slap(s.anim.anatomy))
		task.wait()
		s.standBaked = Cutscene.bake(s.anim, stand)
		task.wait()
		s.lieBaked = Cutscene.bake(s.anim, lie)
		task.wait()
		s.sitBaked = Cutscene.bake(s.walkerAnim, IntroClips.sandSit)
	end)
end

-- Your copy: lying on the lounger watching him come, getting up (the lie-down backwards), marching
-- over to him on your own walk, and the slap.
local function body(s, t: number)
	local b, g = EndCut.beats, EndCut.getUp
	show(s.body, true, s.folder)
	if not (s.slapBaked and s.standBaked and s.lieBaked) then
		s.body:PivotTo(CFrame.new(s.lieRoot))
		return
	end
	if not s.lying then
		-- older handles are written last: the slap over the stand over the lie
		s.slapping = s.anim:play(s.slapBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
		s.standing = s.anim:play(s.standBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
		s.lying = s.anim:play(s.lieBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
		for _, handle in { s.slapping, s.standing, s.lying } do
			handle:setSpeed(0)
		end
	end
	local lain, sat = EndCut.getUpTimes(IntroClips.turnSeconds)
	local lieAt, standAt, standWeight, slapWeight = 0, 0, 0, 0
	local watched = g.lain + math.clamp((t - b.baconFrom) / (b.baconSit - b.baconFrom), 0, 1) * (g.watched - g.lain)
	if t < b.getUp then
		lieAt = watched
	elseif t < lain then
		local u = IntroCut.eased("inOut", (t - b.getUp) / g.scrub)
		lieAt = watched + (g.lain - watched) * u
	elseif t < sat then
		lieAt = g.lain - (t - lain) * g.lie
	else
		standAt = math.max(IntroClips.turnSeconds - (t - sat) * g.turn, g.turnFrom)
		standWeight = math.clamp((t - sat) / HANDOVER_BLEND, 0, 1)
	end
	if t < b.marchFrom then
		s.body:PivotTo(CFrame.new(s.lieRoot)) -- facing the sea, as IntroClips.lie is built
		if s.walkTrack and s.walkTrack.IsPlaying then -- (back before the march: Studio's StudioEndingAt)
			s.walkTrack:Stop(0)
		end
	elseif t < b.slap then
		Cutscene.walk(s, s.marchPath, walkedAt(t, b.marchFrom, b.marchTo, s.marchPath.length), s.slapFacing, TURN_STUDS)
		standAt = g.turnFrom
		standWeight = 1 - math.clamp((t - b.marchFrom) / MARCH_BLEND, 0, 1)
	else
		s.body:PivotTo(s.slapRoot)
		if s.walkTrack and s.walkTrack.IsPlaying then
			s.walkTrack:Stop(SLAP_BLEND)
		end
		slapWeight = math.clamp((t - b.slap) / SLAP_BLEND, 0, 1)
	end
	local lyingWeight = if t < b.marchFrom then 1 else 0
	s.lying:setWeight(lyingWeight)
	s.lying:seek(math.clamp(lieAt, 0, s.lieBaked.length - 1e-3))
	s.standing:setWeight(standWeight)
	s.standing:seek(math.clamp(standAt, 0, s.standBaked.length - 1e-3))
	s.slapping:setWeight(slapWeight)
	s.slapping:seek(math.clamp(t - b.slap, 0, s.slapBaked.length - 1e-3))
end

-- The bacon-hair: strolling down to the water's edge on his own R6 walk, sitting down facing the sea
-- with a straw in the water, then flying off the slap until he is under the sea far out.
local function walker(s, t: number)
	local b = EndCut.beats
	local flying = t >= b.hit
	local tau = t - b.hit
	local offset, tumbled = EndCut.flown(math.max(tau, 0), workspace.Gravity)
	local gone = flying and tau > 0.2 and s.middle.Y + offset[2] < s.strawTo.Y
	show(s.walker, t >= b.baconFrom and not gone, s.folder)
	show(s.straw, t >= b.strawIn and not flying, s.folder)
	if t < b.baconSit then
		local d = walkedAt(t, b.baconFrom, b.baconTo, s.baconPath.length)
		local p, ahead = along(s.baconPath, d)
		local at = Vector3.new(p.X, Cutscene.groundAt(p.X, p.Z, s.ignore), p.Z)
		s.walker:PivotTo(CFrame.lookAt(at, at + ahead))
		if not s.walkerTrack then
			s.walkerTrack = s.walkerAnimator:LoadAnimation(s.kit.baconWalk)
			s.walkerTrack.Looped = true
		end
		if not s.walkerTrack.IsPlaying then
			s.walkerTrack:Play(0, 1, 0)
		end
		if s.walkerTrack.Length > 0 then
			s.walkerTrack.TimePosition = (math.max(d, 0) / IntroClips.walks.bacon.pace) % s.walkerTrack.Length
		end
		if s.sit then -- (back before he sat: Studio's StudioEndingAt)
			s.sit:setWeight(0)
		end
		return
	end
	if s.walkerTrack and s.walkerTrack.IsPlaying then
		s.walkerTrack:Stop(SIT_BLEND)
	end
	if s.sitBaked and not s.sit then
		s.sit = s.walkerAnim:play(s.sitBaked, { loop = false, fadeIn = 0, fadeOut = 0 })
		s.sit:setSpeed(0)
	end
	if s.sit then
		s.sit:setWeight(math.clamp((t - b.baconSit) / SIT_BLEND, 0, 1))
		s.sit:seek(math.min(t - b.baconSit, s.sitBaked.length - 1e-3))
	end
	if flying then
		local turn = CFrame.fromAxisAngle(s.tumbleAxis, -math.rad(tumbled))
		s.walker:PivotTo(CFrame.new(s.middle + v3(offset)) * turn * s.fromMiddle)
	else
		s.walker:PivotTo(s.baconSeat)
		if t >= b.strawIn then
			Cutscene.strawBetween(s.straw, (s.walkerHead.CFrame * MOUTH).Position, s.strawTo)
		end
	end
end

local function frame(s, t: number)
	Cutscene.setWater(s, "full")
	body(s, t)
	walker(s, t)
end

local function subject(): Vector3?
	return nil
end

local function finish(s)
	s.straw:Destroy()
end

local function load(kit)
	kit.straw = Cutscene.asset(kit.story, "Straw", "BasePart")
end

local places = EndCut.places
Ending.def = {
	name = "Ending",
	cut = EndCut,
	phase = "ending",
	at = "EndingAt",
	hold = "StudioEndingAt",
	ground = { IntroCut.places.walkTo, IntroCut.places.stand, places.baconFrom, places.baconBend, places.baconTo, places.marchBend, places.slapAt },
	load = load,
	build = build,
	frame = frame,
	subject = subject,
	finish = finish,
}

-- An admin's preview (client/Admin): the whole ending from now on this client only. Returns why it
-- can't start, or nil.
function Ending.preview(): string?
	return Cutscene.preview(Ending.def)
end

return Ending
