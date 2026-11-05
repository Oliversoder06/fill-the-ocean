# Scoop Feel Implementation Plan

> **Status (2026-11-05):** built, together with the owner's change from prompts to aim-and-hold
> with sweeps (see the design doc "Core action"). Differences from the plan below: no
> ProximityPrompts; `client/Action.luau` owns input and timing; `Act` remote; `ToolView.pourPose`;
> `Water.scoopAmount` and `Ladder` sweeps; a pour cue in `Cues`; Studio assets (Task 4) were
> created through the Studio MCP. Task 8 (feel review) is still open.

> **For agentic workers:** follow `AGENTS.md`. Do the tasks in order. Steps use checkbox (`- [ ]`)
> syntax. Run every command and compare it to its `Expected:` line.

**Goal:** scooping feels as good as the reference clip `gameplay/ref for ai/pick up water
(animation+vfx).mkv`. The tool sweeps through the water during the hold, a splash bursts on
completion, the tool springs back up with the water in it, and the fill bar springs up instead of
jumping. Other players' scoops are seen and heard too.

**Architecture:** this is the first one-by-one moment from `docs/plans/2026-11-04-polish-roadmap.md`.
It builds only the bulk pieces it needs:
- `Ease` (pure): the spring/overshoot curve, matched to the reference.
- `Cues` (pure): the feel data table and tier scaling.
- `ToolView.scoopPose` (pure): the sweep path.
- `Feel` (client): plays sounds and effects.

`Viewmodel` and `Hotbar` use them. The server is not changed: own feedback starts from the
client's `PromptTriggered`; other players' feedback comes from their replicated `Carried`
attribute. No new remote.

**Tech Stack:** Luau, Rojo, selene, Lune 0.11.1.

**Spec:** roadmap above, the "Reference clips" section. Measured: the bar rises in about 0.13 s,
overshoots about 12% of the step, and settles back over about 0.15 s with no second wobble.
`Ease.backOut` with overshoot 2 over 0.28 s peaks 13.2% over, at 0.156 s.

## Global Constraints
- Work inside `gameplay/`. Only touch the files listed in each task.
- Checks after every task: `selene src` clean, `rojo build -o gameplay.rbxlx` succeeds,
  `lune run tests/run` all pass. Baseline before Task 1: `55 passed, 0 failed`.
- Don't change any existing test. `Ease`, `Cues` and `ToolView` stay pure (no `require`, no `game`).
- Never hard-code colours or image ids in code. Particle colours are set on the emitters in Studio.
- No yields inside `RenderStepped` / `BindToRenderStep`.
- The design rule stands: one hold fills the whole tool and the bar does not climb during the hold.
  The reference's 5-sweep fill is NOT copied; only its feel is.

## Review Focus
1. **Own feedback must not wait for the server.** Splash, sound and lift start on the client's
   `ProximityPromptService.PromptTriggered`. The bar and the tool's water still follow `Carried`
   (server truth). If the server rejects a scoop (rare: walked away mid-hold), you get a splash but
   no water. Accepted.
2. **Others' splashes come only from `Carried` increasing** on another player, never on a decrease
   (pour) or on the local player (no double splash).
3. **The lift (spring back up) must win over hold-end events** for its full `Ease.POP_SECONDS`,
   whatever order `Triggered` and `HoldEnded` arrive in.
4. **Missing Studio assets fail loudly at client start** with the exact name ("Audio is missing
   ScoopSplash2", "Vfx.ScoopSplash needs a number attribute Burst on Drops").
5. **The bar at 100% is clamped**, so its overshoot can't show. That is why the bar also gets a
   `UIScale` pop (Task 7).

---

### Task 1: `Ease` (spring curve)

**Files:**
- Create: `gameplay/src/shared/Ease.luau`
- Create: `gameplay/tests/Ease.spec.luau`
- Modify: `gameplay/tests/run.luau` (add `"Ease"` to `SPECS` after `"ToolView"`)

**Interfaces (pure, no requires):**
- `Ease.POP_SECONDS = 0.28`, `Ease.POP_OVERSHOOT = 2`
- `Ease.backOut(t: number, overshoot: number): number`: clamps `t` to [0, 1], `u = t - 1`, and
  returns `1 + (overshoot + 1) * u^3 + overshoot * u^2`.
- `Ease.pop(from: number, to: number, elapsed: number): number` returns
  `from + (to - from) * Ease.backOut(elapsed / Ease.POP_SECONDS, Ease.POP_OVERSHOOT)`.

- [ ] **Step 1: Write `gameplay/tests/Ease.spec.luau`** (same format as `ToolView.spec.luau`):
  - `back_out_starts_and_ends`: `backOut(0, 2)` near 0 and `backOut(1, 2)` near 1 (tolerance 1e-9).
  - `back_out_overshoots_once`: `backOut(0.25, 2)` near 0.859375, `backOut(0.5, 2)` near 1.125,
    `backOut(0.75, 2)` near 1.078125 (1e-9).
  - `back_out_peak_matches_reference`: `backOut(5 / 9, 2)` near `1 + 32 / 243` (1e-9).
  - `back_out_clamps`: `backOut(-1, 2)` near 0, `backOut(2, 2)` near 1.
  - `pop_scales_the_step`: `pop(0.2, 0.4, 0)` near 0.2, `pop(0.2, 0.4, 0.14)` near 0.425,
    `pop(0.2, 0.4, 1)` near 0.4 (1e-9).
- [ ] **Step 2: Add `"Ease"` to `SPECS` and run** `lune run tests/run`.
  Expected: `FAIL Ease.spec (load): ...` (module missing), ends `55 passed, 1 failed`.
- [ ] **Step 3: Write `Ease.luau`** per the interface.
- [ ] **Step 4: Run the checks.** Expected: `selene src` prints `0 errors`, `0 warnings`; rojo
  build succeeds; tests end `60 passed, 0 failed`.

### Task 2: `Cues` (feel data and tier scaling)

**Files:**
- Create: `gameplay/src/shared/Cues.luau`
- Create: `gameplay/tests/Cues.spec.luau`
- Modify: `gameplay/tests/run.luau` (add `"Cues"` after `"Ease"`)

**Interfaces (pure, no requires):**
- `Cues.SIZE_PER_TIER = 0.08`, `Cues.SIZE_MAX = 2.5`, `Cues.PITCH_PER_TIER = 0.0125`,
  `Cues.PITCH_MIN = 0.75`
- `Cues.size(tier: number): number` = `math.min(SIZE_MAX, 1 + SIZE_PER_TIER * (math.max(tier, 1) - 1))`.
  Bigger tools get bigger splashes.
- `Cues.pitch(tier: number): number` = `math.max(PITCH_MIN, 1 - PITCH_PER_TIER * (math.max(tier, 1) - 1))`.
  Bigger tools sound deeper.
- `Cues.pick(list: { string }, roll: number): string` (roll in [0, 1)) returns
  `list[math.min(#list, math.floor(roll * #list) + 1)]`.
- `Cues.between(min: number, max: number, roll: number): number` = `min + (max - min) * roll`.
- `Cues.scoop` (values are starting points; tuning happens in Task 8 by editing only this table):
  ```
  {
  	holdSound = "ScoopHold", holdVolume = 0.35, holdPitchFrom = 0.9, holdPitchTo = 1.15,
  	splashSounds = { "ScoopSplash1", "ScoopSplash2", "ScoopSplash3" },
  	splashVolume = 0.7, otherVolume = 0.25, pitchMin = 0.92, pitchMax = 1.08,
  	vfx = "ScoopSplash", otherBurstScale = 0.5,
  }
  ```

- [ ] **Step 1: Write `gameplay/tests/Cues.spec.luau`:**
  - `size_grows_and_caps`: `size(1)` = 1, `size(2)` near 1.08, `size(20)` = 2.5, `size(0)` = 1.
  - `pitch_drops_and_floors`: `pitch(1)` = 1, `pitch(9)` near 0.9, `pitch(30)` = 0.75.
  - `pick_covers_every_variant`: with `{ "a", "b", "c" }`: roll 0 -> "a", 0.34 -> "b",
    0.99 -> "c", 1 -> "c".
  - `between_blends`: `between(0.92, 1.08, 0.5)` near 1.0 (1e-9).
  - `scoop_cue_is_sane`: `#Cues.scoop.splashSounds == 3`, `pitchMin < pitchMax`, and every
    volume field (`holdVolume`, `splashVolume`, `otherVolume`) is > 0 and <= 1.
- [ ] **Step 2: Add `"Cues"` to `SPECS` and run the tests.** Expected: `FAIL Cues.spec (load): ...`,
  ends `60 passed, 1 failed`.
- [ ] **Step 3: Write `Cues.luau`.**
- [ ] **Step 4: Run the checks.** Expected: selene clean, build succeeds, `65 passed, 0 failed`.

### Task 3: `ToolView.scoopPose` (the sweep path)

**Files:**
- Modify: `gameplay/src/shared/ToolView.luau` (add next to `viewSize`)
- Modify: `gameplay/tests/ToolView.spec.luau` (add new tests only; don't touch existing ones)

**Interfaces:**
- Constants: `ToolView.SCOOP_WINDUP = 0.2`, `SCOOP_RISE = 0.08`, `SCOOP_DOWN = 0.45`,
  `SCOOP_SIDE = 0.35`, `SCOOP_BACK_TILT = math.rad(10)`, `SCOOP_TILT = math.rad(-35)`.
- `ToolView.scoopPose(progress: number): (number, number, number)` returns `(down, side, tilt)`,
  with `progress` (hold fraction) clamped to [0, 1]. The pose has two parts:
  - **Wind-up** (`p < SCOOP_WINDUP`): `k = p / SCOOP_WINDUP`, `down = -SCOOP_RISE * k`, `side = 0`,
    `tilt = SCOOP_BACK_TILT * k`.
  - **Plunge:** `k = (p - SCOOP_WINDUP) / (1 - SCOOP_WINDUP)`, `s = k * k * (3 - 2 * k)`,
    `down = -SCOOP_RISE + (SCOOP_DOWN + SCOOP_RISE) * s`, `side = -SCOOP_SIDE * s`,
    `tilt = SCOOP_BACK_TILT + (SCOOP_TILT - SCOOP_BACK_TILT) * s`.

  Positive `down` moves the tool down; negative `side` moves it toward the screen centre.

- [ ] **Step 1: Add the tests** (tolerance 1e-9):
  - `scoop_rests_at_start`: `scoopPose(0)` = `0, 0, 0`.
  - `scoop_winds_up`: `scoopPose(0.2)` = `-0.08, 0, math.rad(10)`.
  - `scoop_plunges_smoothly`: `scoopPose(0.6)` = `0.185, -0.175, math.rad(-12.5)`.
  - `scoop_bottom_and_clamps`: `scoopPose(1)` and `scoopPose(1.5)` both = `0.45, -0.35,
    math.rad(-35)`, and `scoopPose(-1)` = `0, 0, 0`.
- [ ] **Step 2: Run the tests.** Expected: the 4 new `ToolView.scoop_*` tests FAIL, ends
  `65 passed, 4 failed`.
- [ ] **Step 3: Implement `scoopPose`.**
- [ ] **Step 4: Run the checks.** Expected: selene clean, build succeeds, `69 passed, 0 failed`.

### Task 4: Studio assets (**Owner step**)

Code can't create these. Build them in the gameplay place, then **save the place**.
No remote changed, so `rojo serve` does not need a restart.

- [ ] `SoundService`: four `SoundGroup`s named `Music`, `Sfx`, `Ambience`, `Footsteps`
  (Volume 0.5 each; only `Sfx` is used in this plan).
- [ ] `ReplicatedStorage.Audio` (Folder) with these `Sound`s, each with `SoundGroup = Sfx`:
  - `ScoopHold`: a short wet slosh/gloop, `Looped = true`. Creator Store searches: "water
    slosh", "bucket water", "gloop".
  - `ScoopSplash1`, `ScoopSplash2`, `ScoopSplash3`: three different short splashes (under
    0.6 s, punchy start). Searches: "small splash", "water splash short". Set
    `RollOffMaxDistance = 90` (others hear them in 3D).
- [ ] `ReplicatedStorage.Vfx` (Folder) with an `Attachment` named `ScoopSplash` holding two
  `ParticleEmitter`s, both `Enabled = false`, each with a number attribute `Burst` (particles per
  splash at tier 1). Match the reference's chunky white splash:
  - `Drops`: round droplet texture, white to light blue (theme `shallowWater` 3FA9E0), Size
    0.3 to 0.6, Speed 12 to 18, SpreadAngle 35, EmissionDirection Top, Acceleration (0, -60, 0),
    Lifetime 0.4 to 0.7, `Burst = 14`.
  - `Mist`: soft white puff, Size 1.5 to 3 over its life, Transparency 0.3 to 1, Speed 3,
    Lifetime 0.3 to 0.5, `Burst = 4`.
- [ ] `StarterGui.Hud.Hotbar.FillBar`: add a `UIScale` named `Pop` (Scale 1).
- [ ] Save the place. Tell the agent the sound ids you picked (for the record).

### Task 5: `Feel` (client: sounds and splashes)

**Files:**
- Create: `gameplay/src/client/Feel.luau`
- Modify: `gameplay/src/client/init.client.luau` (require it; call `Feel.start()` right after
  `Viewmodel.start()`)

**Behaviour:**
- **Start-up checks (fail loudly, outside any render callback):**
  - `ReplicatedStorage:WaitForChild("Audio", 10)` and `"Vfx"` are asserted to exist.
  - Every name in `Cues.scoop` (`holdSound`, `splashSounds`, `vfx`) must exist with the right
    class (`Sound` / `Attachment`).
  - Every Sound must have a `SoundGroup`.
  - Every `ParticleEmitter` under the vfx must have a number `Burst` attribute.
- **Hold sound (own):**
  - On `ProximityPromptService.PromptButtonHoldBegan` for a prompt named `ScoopPrompt`: clone
    `holdSound` into `SoundService` (2D), set `Volume = holdVolume` and `PlaybackSpeed =
    holdPitchFrom`, then play it.
  - Each `RenderStepped` while it plays: `PlaybackSpeed = holdPitchFrom + (holdPitchTo -
    holdPitchFrom) * clamp(progress, 0, 1)`, where `progress = (os.clock() - began) /
    ActSeconds`.
  - On `PromptButtonHoldEnded` or `PromptTriggered`: stop and destroy the sound.
- **Splash (own):** on `ProximityPromptService.PromptTriggered` for `ScoopPrompt`, call
  `splash(prompt.Parent, camera position, own ToolTier, true)`.
- **Splash (others):**
  - For every player except the local one (existing ones and `PlayerAdded`), remember their last
    `Carried`.
  - On `GetAttributeChangedSignal("Carried")`, if the new value > old + 1e-6, call `splash(the
    current stage's Source, their HumanoidRootPart position, their ToolTier, false)`.
  - Skip if they have no character.
  - The current stage is `workspace.Stages[Config.stages[ReplicatedStorage.Stage].name]`, and the
    Source is found with `Zones.part`.
- **`splash(source: BasePart, near: Vector3, tier: number, own: boolean)`:**
  - Point: put `near` in the Source's object space, clamp X and Z to its half-size, and set Y to
    the top surface. This gives the point on the water nearest that player.
  - Clone the vfx Attachment, parent it to `workspace.Terrain` and set `WorldPosition`.
  - For each emitter, scale every `Size` keypoint by `Cues.size(tier)` and call `Emit(math.max(1,
    math.floor(Burst * Cues.size(tier) * (own and 1 or otherBurstScale) + 0.5)))`.
  - Sound: clone `Cues.pick(splashSounds, rng:NextNumber())` and set `PlaybackSpeed =
    Cues.between(pitchMin, pitchMax, rng:NextNumber()) * Cues.pitch(tier)`.
    - Own: parent it to `SoundService` (2D) with `splashVolume`.
    - Others: parent it to the attachment (3D) with `otherVolume`.
  - Clean up the attachment and sound with `task.delay(CLEANUP_SECONDS = 3, ...)`.
- One `Random.new()` per module. No empty `pcall`s.

- [ ] **Step 1: Write `Feel.luau` and wire it in.**
- [ ] **Step 2: Run the checks.** Expected: selene clean, build succeeds, `69 passed, 0 failed`.

### Task 6: Viewmodel sweep and spring lift

**Files:**
- Modify: `gameplay/src/client/Viewmodel.luau`

**Behaviour:**
- Remove `SCOOP_DIP` and `SCOOP_TILT` (replaced by `ToolView` values). Keep `POUR_TILT` and
  `POSE_EASE`; pour is unchanged.
- Track `holdBegan` (`os.clock()`) on `PromptButtonHoldBegan`, and add a `side` pose value next to
  `tilt` and `dip`.
- On `ProximityPromptService.PromptTriggered` for `ScoopPrompt`: `liftAt = os.clock()` and
  `liftFrom = { dip, side, tilt }` (the current pose).
- Pose each frame, in this priority order:
  1. **Lifting** (`os.clock() - liftAt < Ease.POP_SECONDS`): each value = `Ease.pop(liftFrom.x, 0,
     elapsed)`. It overshoots above rest, then settles: the springy lift.
  2. **Holding `ScoopPrompt`**: `dip, side, tilt = ToolView.scoopPose((os.clock() - holdBegan) /
     ActSeconds)`.
  3. **Otherwise**: the existing easing toward the pour tilt (or 0), with `dip` and `side` easing
     to 0.
- Offset becomes `CFrame.new(0.9 + viewSize * 0.25 + side, -0.9 - viewSize * 0.35 - dip, -1.8 -
  viewSize * 0.6)`. The angles are unchanged.
- Update the file's header comment ("dips while scooping" -> "sweeps through the water while
  scooping and springs back up").

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run the checks.** Expected: selene clean, build succeeds, `69 passed, 0 failed`.

### Task 7: Fill bar spring

**Files:**
- Modify: `gameplay/src/client/Hotbar.luau`

**Behaviour:**
- Find `FillBar.Pop` with `Hud.find` (UIScale).
- Keep `shown`, `from`, `to` and `changedAt`. When the target ratio changes, `from = shown` and
  `to = ratio`. Each frame, `shown = math.clamp(Ease.pop(from, to, os.clock() - changedAt), 0,
  1)`. `Fill.Size` uses `shown`; `Fill.Visible` uses `shown > 0`.
- On an increase, set `pop.Scale = 1.08` and tween it to 1 with `TweenInfo.new(Ease.POP_SECONDS,
  Enum.EasingStyle.Back, Enum.EasingDirection.Out)`.
- The label still shows the target percent right away.
- Pours also get the eased decrease (bulk behaviour, wanted).

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run the checks.** Expected: selene clean, build succeeds, `69 passed, 0 failed`.

### Task 8: Feel review (**Owner step**, with the agent tuning `Cues` numbers)

- [ ] Play in Studio. Record 20 s of scooping, and compare it side by side with the reference clip
  (you can send both to the agent for a frame-by-frame breakdown).
- [ ] **Mute test:** the sweep, splash and bar spring read with sound off.
  **Eyes-closed test:** you can hear when a scoop starts and lands.
- [ ] **5-minute grind:** nothing gets annoying. If it does, tune only the `Cues.scoop`, `Ease` or
  `ToolView.SCOOP_*` numbers and rerun the checks. Any tuning that breaks a pinned test is a
  decision for the owner: stop and ask.
- [ ] **Big tool:** give yourself a late tool (StudioDifficulty / WaterScale helpers). The splash
  is clearly bigger and the sound deeper, but not absurd.
- [ ] **3 players** (Studio > Test > 3 players): others' splashes are visible and quieter than
  your own.
- [ ] Sign off, or list what still feels off. That becomes a follow-up task.

**Not verifiable by the agent:** everything in Task 8 (needs a Studio play test), and that the
Studio assets in Task 4 exist (the client asserts at start).
