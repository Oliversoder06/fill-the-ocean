# Provenance

This skill was built on 2026-10-21 and 2026-10-22 in a clean room.

1. It was written from this studio's own behaviour specification (`SPEC.md` in the folder above,
   sections 3.2, 3.3 and 4: the animation-craft numbers and the motion-lint rules) and from
   general animation and biomechanics craft. The specification records what the motion should do
   and which tells to catch; it contains no third-party code or text. Every module, rule,
   threshold choice and document here was designed and written anew, in our own words.
2. The agent that wrote it never opened, searched for or fetched the open-source project
   adnvli/roblox-cinematic-animation (AGPL-3.0) or anything taken from it.
3. From the sister skill `roblox-cinematics` (same studio, same licence) it took only conventions:
   the test-runner pattern of `tests/run.luau` and the track contract in `runtime/Tracks.luau`,
   which its handlers implement. No code was copied between the two.
4. Roblox engine facts (Motor6D.Transform and when the Animator writes it, AnimationConstraint,
   Bone, the RunService step order, KeyframeSequence and Pose, stud-to-metre units and gravity)
   were taken from Roblox's own documentation on create.roblox.com. Published measurements used for
   tuning (Froude-number gait transitions and Alexander's stride fit, duty factors and phase
   patterns of animal gaits, the speed profile of captured reaching and punching, postural sway of
   people standing still, fighting-game startup and recovery frames) are facts, restated here in
   our own words.
5. Every behaviour was checked by Lune specs written for this skill, including a seeded stress run
   over thousands of generated creatures. Studio checks are listed as a plan in the hand-over.

No third-party code or text is included in this skill.
