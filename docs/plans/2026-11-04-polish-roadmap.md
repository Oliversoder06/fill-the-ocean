# Polish Roadmap (look and feel)

> High-level roadmap, not an executable plan. Each phase below becomes its own plan in
> `docs/plans/` (with files, steps and `Expected:` lines) before anyone builds it.

**Goal:** the prototype works but feels flat. Make every action feel good in the hands, ears and
eyes, so the slow-to-fast climb from the design is *felt*, not just read off a number.

**Why it is flat today (2026-11-04 audit of `gameplay/src`):**
- No audio at all: no music, ambience, footsteps or action sounds (zero `Sound` uses).
- No particles, no animations. The only motion is a few UI scale tweens (Hud coin pop, Hotbar,
  Shop) plus camera bob/tilt and the viewmodel's dip (scoop) and tip (pour).
- The core action has no payoff: hold, a number changes, the water creeps up. Nothing splashes,
  sounds, or flies to the wallet.
- Polish was a deliberate non-goal of the prototype (design doc: "design -> plain prototype ->
  look and feel"). This roadmap is the "look and feel" phase.

**Spec:** `docs/design/2026-11-04-fill-the-ocean-design.md` (end-of-run sequence, "pour should
look bigger with bigger tools", final push with faster music).

---

## Principles (the bar every phase is judged by)

1. **Polish by frequency.** Scoop/pour happens hundreds of times a run; the stage cutscene three
   times. Effort goes in that order.
2. **Every moment gets several channels.** For each moment decide: sound, world effect, camera,
   UI. A moment with one channel still feels flat.
3. **Scale with the ladder.** A spoon pour is a trickle; a Moon pour is a tidal wave. Sound pitch
   and weight, splash size, shake and toast size all grow with `ToolTier`. This *is* the joke.
4. **The 100th time must still be nice.** Short sounds, random pitch/volume variation, several
   variants per sound, no long effects on repeated actions.
5. **Readable with sound off, readable with eyes closed** (the mute test).
6. **Server owns state, client owns feel.** Feel reacts to attributes the server already publishes.
   Feel code never changes money, water or tools.

## Reference clips (`gameplay/ref for ai/`, measured frame by frame)

The recordings have no usable audio (peak about -47 dB), so sound timing is not captured.
Re-record with game/desktop audio on to get it.

- **Pick up water** (bucket sweep): the hand sweeps the bucket through the water about every
  0.5 s, a white splash bursts at the water, and each sweep adds 20%. The fill bar **springs**:
  it rises over about 0.13 s, overshoots about 12% of the step, then eases back over about 0.15 s
  with no second wobble. That is a single overshoot (`EasingStyle.Back` / an overdamped spring),
  not a bounce.
  - Conflict with our design: the owner settled "one hold fills the whole tool, no meter
    climbing". Keep that. Copy the *feel* instead: one sweep of the viewmodel over the hold, a
    splash on completion, then the bar and water snap up with the same overshoot.
- **Open GUI:** about 0.6 s total, built in layers. Frames are at 30 fps:
  - 0 to 0.1 s: the frame scales up from about 60% while fading in.
  - About 0.13 s: the title tab appears.
  - About 0.2 to 0.25 s: the other tabs appear one by one.
  - About 0.3 to 0.4 s: the inner panels fade in one by one.
  - About 0.4 to 0.6 s: the item icons pop in one by one, 1 to 2 frames (about 40 ms) apart.
  - Last: the decorations around the frame (leaves).

  Close is a quick shrink and fade (under 0.2 s) with no stagger.
- **Collect coins:** physical 3D coins burst out of the source, bounce and settle on the ground,
  then fly into the player. The coin counter ticks up per coin (not in one jump), and a floating
  "+12" appears at the source. One drop takes about 2 to 3 s from burst to the last coin.
  - Ours: coins burst from the basin on pour and fly into the player. The count grows with the
    payout, capped for performance.

## Bulk vs one-by-one

**Bulk** = shared systems built once and used everywhere. They are judged by *consistency*.
Build them first, because the special moments are built from them.
- Motion pieces: the spring/overshoot tween (bars, numbers, pops), number count-up, staggered
  appear, and a shared window open/close (the GUI reference) used by every window.
- UI sounds: hover, click, open, close, error, and "can't afford".
- The toast/notification system (one template, a queue, stacking).
- Footsteps by floor material, ambience beds, the music player with crossfade and ducking, sound
  groups, the volume setting.
- Splash/coin/sparkle effect templates that only change in size and count (driven by `Cues`).
- Lighting and post effects per stage.
- Tier scaling: every tool's scoop and pour uses the same cues, scaled by `ToolTier`.

**One by one** = moments that are either very frequent or memorable. Each gets its own plan,
a reference clip, before/after clips, and owner sign-off before the next one starts.
1. Scoop (viewmodel sweep, splash, bar spring), against the water reference.
2. Pour (splash scaled by tier, basin ripple, water rising with overshoot).
3. Money earned (coins burst out and fly into you, counter ticks per coin), against the coin
   reference.
4. Shop open (the first real use of the shared window motion; tune it until it matches the GUI
   reference, then every other window gets it for free).
5. Purchase and new-tool reveal.
6. Landmark tools only (for example Bathtub, Fire Truck, Cargo Ship, The Moon): a unique pour on
   top of the tier scaling, because these are the joke.
7. Stage "FULL!" and the drain cutscene, the final push, "FINAL DROP!", the Earth explosion, and
   the results podium.

## Architecture (shared by all phases)

- **`gameplay/src/shared/Cues.luau`** (pure, Lune-tested): one data table of every feel cue:
  sound names, volume, pitch range, variants, particle counts, shake strength, and how each scales
  with tool tier. Tuning means editing numbers here, not code. Pure helpers such as
  `Cues.scale(cue, tier)` and `Cues.pitch(cue, rng)` get tests.
- **`gameplay/src/client/Feel.luau`**: plays cues. Watches attribute changes and turns them into
  moments:
  - own `Carried` 0 -> >0 = scooped, >0 -> 0 = poured; `Money` up = earned; `ToolTier` up = bought;
  - other players' `Carried` changes (player attributes replicate to everyone) = their splashes,
    so others' actions are heard and seen **without a new remote**;
  - `ReplicatedStorage` `Phase`, `Stage`, `Fill` = stage moments, music, final push.
  - Hold start/end come from `ProximityPromptService` (as `Viewmodel.luau` already does).
- **Assets are baked in the place, not built at runtime** (project rule):
  - `SoundService` SoundGroups: `Music`, `Sfx`, `Ambience`, `Footsteps` (ducking = lowering a
    group's volume during big moments).
  - `ReplicatedStorage.Audio` (Sounds, named to match `Cues`), `ReplicatedStorage.Vfx`
    (ParticleEmitter/Attachment templates that code clones, like `Results.RowTemplate`).
  - Code asserts every name it needs exists at start ("Audio is missing Splash1"), like `Zones`.
- UI motion uses the theme's motion values (`Kit.UI.Themes["sunbaked-sea"]`); no hard-coded colours.
- Possible new remote (only if needed): a server-sent `Moment` event for things attributes can't
  express cleanly (for example "FINAL DROP by <player>"). Decide per phase; follow the AGENTS.md
  remote checklist (project file, `remote(...)` list, restart `rojo serve`).

## Quality gates (every phase, before calling it done)

- [ ] Checks pass: `selene src`, `rojo build -o gameplay.rbxlx`, `lune run tests/run`.
- [ ] **Reference clip:** the owner records about 20 s of a game with great feel doing the same
      kind of action. Our before/after clip is compared side by side.
- [ ] **Before/after clip** of each moment. If the difference doesn't show in the clip, it isn't done.
- [ ] **Mute test** and **eyes-closed test** pass.
- [ ] **5-minute grind test:** nothing gets annoying (too loud, too long, too samey).
- [ ] **Multiplayer test** (Studio, 3 players): others' actions read but don't drown your own.
- [ ] **Mobile check:** particle counts and sound counts stay within budget; nothing blocks touch UI.
- [ ] Lessons that worked go into `C:\RobloxDev\library\design\README.md` under **Feel**.

---

## Phase 0: Feel foundation (small, unblocks everything)
- `Cues` module plus tests, `Feel` module skeleton, the moment detection above.
- The bulk motion pieces: spring/overshoot, count-up, staggered appear, shared window open/close
  (see "Bulk vs one-by-one").
- Owner: create the SoundGroups, `ReplicatedStorage.Audio` and `ReplicatedStorage.Vfx` folders;
  save the place.
- Owner: gather a reference clip for the core action.
- Done when: a debug print fires for every moment (scoop, pour, earn, buy, phase change) for you
  and for other players.

## Phase 1: Core loop juice (biggest win)
Moments: hold start, scoop complete, carry, pour complete, money earned.
- **Scoop:** a "gloop" sound while holding (rising pitch as the hold fills), a pop when done,
  droplets at the source, the viewmodel snapping up with a little overshoot.
- **Carry:** the viewmodel water sloshes a little with walk speed; drips for big tools.
- **Pour:** a splash sound and a splash at the basin scaled by tier (trickle up to tidal wave), a
  small camera kick for big tools, a basin ripple ring, the water level easing up with a short
  overshoot instead of creeping.
- **Money toast:** "+$1.2K" floats up from the pour and flies into the wallet; the wallet
  counts up and bounces (extend the existing coin pop); coin sound pitch climbs on fast streaks.
  Owner step: build the toast template under `StarterGui.Hud` in the sunbaked-sea style.
- **Others:** quieter 3D splash and sound at their pour spot.

## Phase 2: Movement and world sound
- **Custom footsteps:** mute the default Roblox running sound; play per-material steps (sand,
  tile, grass, wood) timed to `CameraFeel`'s bob, so the sound lands when the camera dips. Heavier
  and slower steps while carrying a big tool.
- **Ambience:** layered beds per stage (pool: distant city and cicadas; lake: wind and birds;
  ocean: gulls, deep wind), plus a faint heat hum that fades as the basin fills (the world comes back
  to life as you fill it).
- **World motion:** heat shimmer and dust over dry ground, which fades as the fill rises (ties in
  with `Mood.luau`'s dry-to-wet blend).

## Phase 3: Music and progression moments
- **Music:** one loop per stage, plus a calmer track for waiting/results; crossfade on stage change;
  duck under big moments. Owner picks tracks from the Creator Store (the licensed music Roblox
  provides is free to use in experiences), with an agreed BPM and mood per stage.
- **Purchase moment:** a sting, the new tool swinging up into the viewmodel, a short screen flash in
  the theme colour, and a shop "BOUGHT!" stamp. Speed upgrades get their own sound (a whoosh).
- **"Next upgrade affordable"** nudge: a soft chime and the Shop button pulsing (the climb
  should pull the player).
- **Fill milestones:** 25/50/75% stingers and a short ripple across the whole basin.

## Phase 4: Stage moments and the finale (from the design's end-of-run list)
- "FULL!" splash, with a crowd cheer for pool/lake.
- Sun drain cutscene between stages (replaces the text card). The angry sun art exists in `art/`.
- **Final push** (last 5% of the ocean): faster music, a glowing meter, the sun gets desperate.
- "FINAL DROP!" callout naming the player (probably needs the `Moment` remote).
- Earth explosion comedy cutscene, the spoon flying past the camera, then the results podium.
- Needs animation and cutscene work in Studio (owner steps); likely split into 2 to 3 plans.

## Phase 5: Map, lighting and ambience pass (mostly Studio, owner-led)
- Start with a **Studio audit**: screenshots from player height at the source, on the path and at
  the basin for each stage, and a written critique (sightlines, landmarks, empty areas, scale).
- Map: a clear path from source to basin with landmarks, dressing along the 80-stud path (dried
  seaweed, cracked mud, stranded boats, shells: the art set already exists), a strong silhouette
  per stage.
- Lighting: tune `Mood.luau` per stage (pool midday, lake golden, ocean dramatic), with the sun
  more visible and threatening as stages advance.
- Optional: third-person scoop/pour animations so other players read clearly (Animation Editor,
  owner step).

## Phase 6: Settings and audio hygiene
- Music/SFX volume sliders (library screen `ui/screens/settings.md`), saved through `common/`
  PlayerData if wanted.
- A cap on how many sounds and particles play at once with 10 players.

---

## Order and sizing

| Phase | Size | Mostly code or Studio | Depends on |
|---|---|---|---|
| 0 Foundation | S | Code | none |
| 1 Core loop | L | Code plus some Studio | 0 |
| 2 Movement and world | M | Code plus audio picks | 0 |
| 3 Music and progression | M | Code plus audio picks | 0 |
| 4 Stage moments and finale | XL | Studio-heavy | 1, 3 |
| 5 Map and lighting | L | Studio | none (can run alongside) |
| 6 Settings | S | Code plus Studio UI | 3 |

Phases 2, 3 and 5 can run in parallel after Phase 0. Phase 1 should land first; it is the one
players feel every 5 to 15 seconds.

## Open questions for the owner
1. Reference games for feel (2 to 3 titles to record clips from)?
2. Music mood per stage: cheerful and bouncy throughout, or rising tension toward the ocean?
3. Should other players' pours be audible everywhere or only nearby (3D falloff distance)?
4. Sound sourcing: Creator Store only, or also custom/AI-generated sounds uploaded through Open
   Cloud (the `.env.local` key)?
5. Is a `Moment` remote acceptable for callouts like "FINAL DROP", or should everything stay
   attribute-driven?
