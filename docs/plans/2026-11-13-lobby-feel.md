# Lobby Feel Build Plan

> **For agentic workers:** follow `AGENTS.md`. Do the tasks in order. Steps use checkbox (`- [ ]`)
> syntax. Run every command and compare it to its `Expected:` line. Stop at **Owner step**s.

**Goal:** the lobby feels as finished as gameplay without moving its map: it has sound (music,
ambience, footsteps, UI), pads that show their state and react to people, a real 3-2-1 launch,
and a world that moves (palms, waves, gulls, and the bacon-hair drinking the sea on the horizon).

**Scope (owner, 2026-11-13):** A (sound), B (pads react, with a real countdown: the server waits,
leaving cancels), E (the world moves) and E+ (the bacon-hair on the horizon). Not in this plan: a
custom teleport/loading screen and a join camera intro.

**Studio pieces (owner, 2026-11-13):** the agent builds them in the lobby place through the Studio
MCP (`execute_luau`, `insert_asset`); the owner reviews them and saves the place. Nothing is
generated at runtime: the code only finds, clones and moves what the place holds.

**As built (2026-11-14), where it differs from the tasks below:**
- The owner said "do it all, you choose": music **Sail Boat (c)** (1840007459: the longest loop,
  guitar, not a second ukulele next to gameplay's map track), click **PopClick** (123697989378199).
- Meanwhile the other session moved the lobby UI to **sunbaked-sea**, so the pad looks use its keys
  (`shallowWater` free, `toolTag` join me and the countdown, `locked` busy, `foam` launch) and
  `LobbyHud.Countdown` is Nunito Heavy with a 3 px `outline` stroke at 88 px.
- No project-file change: instead of mapping gameplay's `Steps` (a `rojo serve` restart, and the
  live-synced lobby would have crashed until then), `LobbyCues.surface` / `steps.stride` copy it and
  `LobbyCues.spec` holds them equal to gameplay's `Steps`.
- The boardwalk's boards are Plastic: a `Footstep = "wood"` attribute (checked by a short ray per
  step) makes them sound like wood without changing their look.
- `prepare` already returned the teleport screen (`arrival`), so `commit` is its 4th return, and
  the screen for a New Game is the one its erase will leave ("fresh").
- Ripple: no water texture in gameplay's place to reuse, so the Creator Store's "water caustics"
  (decal 6757160735, image 6757160733: white lines on transparency, tinted per state).
- The gull is built from parts (the store's gulls were grey unions that can't flap); the
  bacon-hair is rebuilt from gameplay's `BaconFat` at 1.6x (at 1x the pad signs hide him from the
  spawn), at (-120, -26, -380) facing the spawn.
- Not done here: Studio's save (owner), the published two-player test (Task 10).

## What the lobby has today (surveyed 2026-11-13)
- No `SoundGroup`s, no `ReplicatedStorage.Audio`, no music or ambience; only Roblox's default
  character sounds.
- `workspace.Lobby`: `Decor` (Deck, Path, 26 lantern parts with 13 PointLights, Props, 7 distant
  Mountains, 20 Palm MeshParts, Bounds walls at x ±72 and z -44 / 82, Fence) and `Pads.Pad1..5`
  at x -40..40, z -24, facing the spawn (+Z). Each pad: `Zone`, `Walls`, a `Sign` SurfaceGui
  (`Title`, `Status`), four Neon `Rim` parts, a Glass `Water` part with a `PointLight`, and a
  roof, posts and backboard. No particles anywhere.
- Terrain sea all around the island (water top y ≈ -2); `WaterWaveSize` 0.08 (nearly flat).
  The open horizon is behind the pads (-Z).
- The lifeguard tower's flag is part of the tower mesh, so it can't flutter (left out).
- The gameplay place (same universe) has the sound kit: `ReplicatedStorage.Audio` holds the
  `Music`, `Sfx`, `Ambience` and `Footsteps` SoundGroups (volume 0.5 each) and every sound, and
  `ReplicatedStorage.Vfx` the effects (`ScoopSplash`, `Sparkle`, ...).

## Coordination (read first)
On 2026-11-13 another session was rewriting `lobby/src/client/Session.luau` (the pad screen as a
full-screen cover, `PadCover`, `PadBlur`), `lobby/src/server/Queue.luau` and the lobby place's
`LobbyHud`. This plan adds new modules and only small, named hooks in those files (A5, B4). Before
Task 1 the owner confirms that work is finished; re-read every file a task touches before editing
it, and match functions by name, not by line number.

## Global constraints
- Lobby checks after every task that touches `lobby/` (run inside `lobby/`): `selene src` prints
  `0 errors` and `0 warnings`; `rojo build -o lobby.rbxlx` succeeds.
- Tests: pure modules are Lune-tested from `gameplay/tests/` (run inside `gameplay/`:
  `lune run tests/run`, ends with `passed, 0 failed`). New pure modules: `common/SessionRules`
  (extended) and `lobby/src/shared/LobbyCues.luau` (new, required by its spec as
  `../../lobby/src/shared/LobbyCues`). Both stay pure: no `require`, no `game`, no Roblox types.
- `common/` changed: copy `gameplay/selene.toml` into `common/`, run `selene .`, remove it.
- Every feel number (names, volumes, pitches, speeds, colours as theme keys) lives in
  `LobbyCues`. Colours come from `ReplicatedStorage.Kit.UI.Themes["clear-tide"]` by key.
- Client code finds place pieces with asserted lookups ("... is missing X (built in Studio)") and
  is stream-safe: `StreamingEnabled` is on, so pieces can arrive late or leave.
- Per-frame code writes a property only when its value changed; nothing yields in a frame callback.
- The server publishes pad state as attributes on each pad Model; the client only reads them.
- No new remote. A project-file change means the owner restarts `rojo serve` in `lobby/`.

## File map
| File | New / changed | What |
|---|---|---|
| `lobby/src/shared/LobbyCues.luau` | new, pure | every lobby feel number and the small pure maths (pad looks, countdown number, palm sway, gull paths) |
| `gameplay/tests/LobbyCues.spec.luau` | new | its tests (listed in `tests/run.luau`) |
| `common/SessionRules.luau` | changed | `COUNTDOWN`, `padState` |
| `gameplay/tests/SessionRules.spec.luau` | changed | new tests for `padState` |
| `lobby/default.project.json` | changed | `ReplicatedStorage.GameplayShared.Steps` -> `../gameplay/src/shared/Steps.luau` |
| `lobby/src/client/Sfx.luau` | new | plays a one-shot from `ReplicatedStorage.Audio` (2D, or 3D at a position) |
| `lobby/src/client/Music.luau` | new | the lobby track: fade in, `duck`, `fadeOut` |
| `lobby/src/client/Ambience.luau` | new | the ocean bed |
| `lobby/src/client/Footsteps.luau` | new | third-person steps by floor for everyone; mutes Roblox's `Running` |
| `lobby/src/client/UiSounds.luau` | new | hover, press, deny, window whoosh, toast |
| `lobby/src/client/Pads.luau` | new | pad colours by state, ripple, bubbles, splash on step in/out, launch glow |
| `lobby/src/client/Countdown.luau` | new | the 3-2-1 on screen with ticks, go and cancel |
| `lobby/src/client/World.luau` | new | palm sway, gulls |
| `lobby/src/client/Horizon.luau` | new | the bacon-hair drinking the sea far out |
| `lobby/src/client/init.client.luau` | changed | starts the new modules; toast sound hook |
| `lobby/src/client/Session.luau` | changed | sound hooks in `juice` / `deny` / `show`; the `countdown` state on HostBar |
| `lobby/src/server/Queue.luau` | changed | pad attributes `State` / `LaunchAt`; the countdown inside `launch` |
| `CLAUDE.md`, `AGENTS.md` | changed | the lobby's new place pieces and modules (Task 14) |

---

## Phase A: Sound

### Task 1: The lobby's sound kit (Studio, via MCP)
- [ ] **Owner step:** confirm the other lobby session's work is finished (see Coordination).
- [ ] **Owner step:** listen to the three music candidates and pick one (all free, APM, same
  library as gameplay's tracks; "Walking On The Beach" is excluded, it is already gameplay's map
  track):
  1. Happy Forever Ukulele: https://create.roblox.com/store/asset/1839580471
  2. Sail Boat (c), bright acoustic folk, 120 s: https://create.roblox.com/store/asset/1840007459
  3. Charming View Ukulele: https://create.roblox.com/store/asset/1839578771

  Also pick a UI click (preview both; if neither fits, `CoinTick` pitched up is used):
  PopClick https://create.roblox.com/store/asset/123697989378199,
  ui_click_2 https://create.roblox.com/store/asset/110948579458469.
- [ ] In the lobby place (Studio MCP, lobby instance `Save the Ocean (placeId: 131785571407023)`,
  Edit mode) create `ReplicatedStorage.Audio` with SoundGroups `Music`, `Sfx`, `Ambience`,
  `Footsteps` (Volume 0.5 each, as gameplay) and these Sounds (SoundId, Volume, SoundGroup; ids
  and volumes copied from gameplay's `Audio`):

  | Name | SoundId | Volume | Group |
  |---|---|---|---|
  | `MusicLobby` | the owner's pick | 1.0 | Music |
  | `AmbOcean` | 9112751378 | 1.0 | Ambience |
  | `StepWood1` | 103047430053521 | 1.0 | Footsteps |
  | `StepSand1` | 98912102275037 | 1.0 | Footsteps |
  | `StepGrass1..4` | 129956418693357, 78534941650081, 110522236020035, 135037154891351 | 0.65, 1.02, 1.55, 1.02 | Footsteps |
  | `StepStone1..6` | 133325104274958, 93803555891980, 85682518019906, 80346333847986, 140594308250996, 82615619091463 | 0.93, 1.03, 1.69, 1.02, 0.85, 0.89 | Footsteps |
  | `UiClick` | the owner's pick (or 4612374807) | 0.6 | Sfx |
  | `WindowWhoosh` | 123796710194563 | 1.0 | Sfx |
  | `BuyDenied` | 9126267413 | 0.6 | Sfx |
  | `CoinTick` | 4612374807 | 0.6 | Sfx |
  | `ToolUnlock` | 4612374036 | 0.6 | Sfx |
  | `SpeedWhoosh` | 123796710194563 | 0.6 | Sfx |
  | `ScoopSplash1` | 124279162156159 | 0.6 | Sfx |
  | `IntroSlurpFar` | 93204083204062 | 0.55 | Sfx |
  | `IntroBurp` | 6794882849 | 0.9 | Sfx |
- [ ] Verify through MCP: list `ReplicatedStorage.Audio` and print each Sound's `TimeLength`
  after `ContentProvider:PreloadAsync`.
  Expected: every Sound above present with its group, and every `TimeLength` > 0 (a 0 means the
  asset didn't load: stop and report the id).
- [ ] **Owner step:** review `ReplicatedStorage.Audio` and save the place.

### Task 2: `LobbyCues` (sound part)
- [ ] Write the failing test `gameplay/tests/LobbyCues.spec.luau` and add `"LobbyCues"` to the
  `SPECS` list in `gameplay/tests/run.luau`. Tests:
  `every_named_sound_is_a_string` (walks `music`, `ambience`, `steps.surfaces`, `ui` and checks
  each sound name is a non-empty string), `volumes_are_between_0_and_1`,
  `step_surfaces_match_gameplay_steps` (every surface `Steps.surface` can return, `stone`,
  `grass`, `sand` and `wood`, has at least one sound; require `../src/shared/Steps`).
- [ ] Run `lune run tests/run` in `gameplay/`.
  Expected: `FAIL LobbyCues.spec (load)` (the module doesn't exist yet), every other spec passes.
- [ ] Create `lobby/src/shared/LobbyCues.luau` (pure, `--!strict`), modelled on gameplay's
  `shared/Cues.luau`:
  - `music = { track = "MusicLobby", volume = 0.35, fadeSeconds = 2.5, duck = 0.4, outSeconds = 1.2 }`
  - `ambience = { bed = "AmbOcean", volume = 0.45, fadeSeconds = 2.5 }`
  - `steps = { surfaces = { stone = { "StepStone1", ... "StepStone6" }, grass = { "StepGrass1", ... "StepGrass4" }, sand = { "StepSand1" }, wood = { "StepWood1" } }, volume = 0.35, otherVolume = 0.3, pitchMin = 0.95, pitchMax = 1.05, range = 80 }`
  - `ui = { click = "UiClick", clickVolume = 0.4, hoverVolume = 0.12, hoverPitch = 1.4, whoosh = "WindowWhoosh", openVolume = 0.4, closeVolume = 0.3, openPitch = 1.1, closePitch = 0.85, deny = "BuyDenied", denyVolume = 0.5, toastVolume = 0.3, toastPitch = 0.8 }`
- [ ] Run `lune run tests/run`. Expected: ends with `passed, 0 failed`.
- [ ] Lobby checks. Expected: `0 errors`, `0 warnings`; the build succeeds.

### Task 3: Music and ambience
- [ ] `lobby/src/client/Sfx.luau`: `Sfx.play(name: string, volume: number, pitch: number?, at: Vector3?)`.
  It clones `ReplicatedStorage.Audio.<name>` (asserted: exists, is a Sound, has a SoundGroup);
  2D into `SoundService`, or 3D into an Attachment on `workspace.Terrain` at `at`; `Debris`-free
  cleanup on `Ended`. Same pattern as gameplay's one-shots.
- [ ] `lobby/src/client/Music.luau`, modelled on gameplay's `client/Music.luau` with one track:
  fades in from 0 over `fadeSeconds` once started; `Music.duck(seconds)`;
  `Music.fadeOut()` (to 0 over `outSeconds`, used at launch); `Music.resume()` (after a cancelled
  launch). Heartbeat easing as gameplay (snap within 0.005, pause at 0).
- [ ] `lobby/src/client/Ambience.luau`: loops `ambience.bed` at `ambience.volume`, fading in.
- [ ] `init.client.luau`: start `Music` and `Ambience` before `Session.start()`.
- [ ] Lobby checks. Expected: clean, builds.
- [ ] **Owner step:** play test the lobby in Studio (`rojo serve` in `lobby/`, connect on port
  34674). Music and surf fade in; nothing in Output.

### Task 4: Footsteps
- [ ] `lobby/default.project.json`: under `ReplicatedStorage` add a Folder `GameplayShared` with
  `"Steps": { "$path": "../gameplay/src/shared/Steps.luau" }` (gameplay's pure footstep maths).
- [ ] `lobby/src/client/Footsteps.luau`: for every character (yours and others within
  `steps.range`), on Heartbeat add the root's horizontal travel while `FloorMaterial ~= Air`; each
  `Steps.STRIDE` studs plays one step: the surface from
  `Steps.surface(humanoid.FloorMaterial.Name)`, a random variant (never the same twice in a row),
  pitch in `[pitchMin, pitchMax]`; yours 2D at `volume`, others' 3D at their feet at
  `otherVolume`. Mutes Roblox's default `Running` sound in each character's root (Volume 0), as
  gameplay's Footsteps does. Characters added later and respawns are picked up.
- [ ] `init.client.luau`: start `Footsteps`.
- [ ] Lobby checks. Expected: clean, builds (the new `$path` resolves).
- [ ] **Owner step:** restart `rojo serve` in `lobby/` (project file changed), play test: walking
  on the deck sounds like wood, on sand like sand, on grass like grass; no default running sound.

### Task 5: UI sounds
- [ ] `lobby/src/client/UiSounds.luau`: `hover()`, `press()`, `deny()`, `window(open: boolean)`,
  `toast()`, each one `Sfx.play` with the `LobbyCues.ui` numbers (`deny` plays `ui.deny`; `toast`
  plays `ui.click` at `toastPitch`).
- [ ] Hooks (one line each; nothing else in these functions changes):
  - `Session.luau` `juice`: `MouseEnter` -> `UiSounds.hover()` and `MouseButton1Down` ->
    `UiSounds.press()`, both only when the button isn't `inert`.
  - `Session.luau` `deny`: `UiSounds.deny()` when the wobble starts.
  - `Session.luau` `show`: `UiSounds.window(visible)` where the visibility really changes (after
    the early returns).
  - `init.client.luau` notice handler: `UiSounds.toast()`.
- [ ] Lobby checks. Expected: clean, builds.
- [ ] **Owner step:** play test: hover and click every pad-screen button, a locked map's Create
  (deny), open/close the pad screen and Confirm. Each makes its sound once, and greyed-out
  controls stay silent.

## Phase B: Pads react

### Task 6: `padState` and the pad attributes (server)
- [ ] Write the failing tests in `gameplay/tests/SessionRules.spec.luau`:
  `pad_state_open_without_host`, `pad_state_setup_while_host_chooses`,
  `pad_state_party_while_joinable`, `pad_state_closed_when_friends_only_or_full`,
  `pad_state_saved_for_a_saved_team`, `pad_state_counting_beats_everything`,
  `pad_state_launching_beats_the_rest`.
- [ ] Run `lune run tests/run`. Expected: those seven FAIL (`padState` is nil), the rest pass.
- [ ] `common/SessionRules.luau`: add `SessionRules.COUNTDOWN = 3` (seconds from a launch's checks
  to its teleport) and
  `SessionRules.padState(pad: { host: boolean, saved: boolean, maxPlayers: number?, friendsOnly: boolean, count: number, counting: boolean, launching: boolean }): string`.
  It returns, in this order: `"counting"`, `"launching"`, `"open"` (no host), `"saved"`,
  `"setup"` (no `maxPlayers` yet), `"closed"` (friends only, or `count >= maxPlayers`),
  else `"party"`.
- [ ] Run `lune run tests/run`. Expected: ends with `passed, 0 failed`.
- [ ] `Queue.luau`: the `Pad` type and `Queue.start` gain `model: Model` and `counting: boolean`
  (false). Next to `updateSign`, add `publish(pad: Pad, launchAt: number?)`. It sets the model's
  `State` (`SessionRules.padState(...)`) and `LaunchAt` (server time, 0 when none), writing an
  attribute only when its value changed. `updateSign` calls `publish(pad)` at its end. `launch`
  calls it after it sets `pad.launching = true`, and again after it sets it back to false.
- [ ] Lobby and common checks. Expected: clean, builds.

### Task 7: The pads' Studio pieces (via MCP)
- [ ] Look up the water Texture gameplay's channels scroll (`Areas.<Name>.Channel.Water` in the
  gameplay place) and note its id and tile size; if none fits a flat pad, search the Creator Store
  for a free tileable "water caustics" image and show it to the owner first.
- [ ] Lobby place: give each `Pads.PadN.Water` a Texture named `Ripple` (Face Top, the id above,
  Color3 white, Transparency 0.6, StudsPerTile about 6).
- [ ] Lobby place: `ReplicatedStorage.Vfx` (Folder) with copies of gameplay's `ScoopSplash` and
  `Sparkle` (Attachments with their ParticleEmitters, every property and the `Burst` attributes
  copied by MCP from the gameplay instance), and a new `PadBubbles` Attachment: one
  ParticleEmitter `Bubbles` (small soft white circles rising 1-2 studs, Rate 4, Lifetime 1-1.6,
  Color from theme `foam`, LightEmission 0.3), Enabled false.
- [ ] Verify through MCP: five `Ripple` textures, `Vfx.ScoopSplash`, `Vfx.Sparkle`,
  `Vfx.PadBubbles` present. Expected: all present.
- [ ] **Owner step:** look at a pad in Studio and save the place.

### Task 8: `Pads.luau` (looks, ripple, bubbles, splash)
- [ ] Write the failing tests in `LobbyCues.spec`: `every_pad_state_has_a_look` (each of the seven
  `padState` values gives a look with a theme `color` key, `pulseHz >= 0`, `light >= 0`, a boolean
  `bubbles`), `unknown_pad_state_errors`.
- [ ] Run `lune run tests/run`. Expected: those two FAIL, the rest pass.
- [ ] `LobbyCues`: `pads = { rippleSpeed = 0.6, inside = 6.5, splash = "ScoopSplash", splashSound = "ScoopSplash1", splashVolume = 0.5, splashPitch = { 0.9, 1.1 }, bubbles = "PadBubbles" }` and
  `LobbyCues.padLook(state)`:
  - `open`: `owned`, pulse 0, light 1, bubbles on (free pad: inviting cyan)
  - `party`: `guide`, pulse 0.8, light 1.3, bubbles on (join me: slow yellow pulse)
  - `setup`, `closed`, `saved`: `locked`, pulse 0, light 0.5, bubbles off (busy)
  - `counting`: `guide`, pulse 2, light 2, bubbles on
  - `launching`: `text` (white), pulse 0, light 3, bubbles off
  
  Any other state: `error`.
- [ ] Run `lune run tests/run`. Expected: ends with `passed, 0 failed`.
- [ ] `lobby/src/client/Pads.luau`: for each pad Model (asserted `Rim` parts, `Water` with
  `PointLight` and `Ripple`), it eases the Rim and Water colour and the light toward the look for
  its `State` attribute, with the pulse as a brightness/transparency wave. It scrolls `Ripple`, and
  clones `Vfx.PadBubbles` onto `Water` (enabled per look). Every Heartbeat it checks each
  character's root in each pad's `Zone` space (inside = within `pads.inside` on X and Z, as the
  server's `within`). A root that enters bursts `Vfx.ScoopSplash` at its feet with `splashSound`
  (3D at the pad); one that leaves gets a smaller burst.
- [ ] `init.client.luau`: start `Pads`.
- [ ] Lobby checks. Expected: clean, builds.
- [ ] **Owner step:** play test: an empty pad is cyan with bubbles; stepping on splashes; while
  choosing it turns slate; a created party pulses yellow; Leave splashes you out.

### Task 9: The countdown (server)
- [ ] `Queue.luau`, `launch`: `prepare` gets an optional third return, `commit: (() -> string?)?`,
  the irreversible part, run after the countdown; it returns what to tell the party, or nil.
  In `launchParty`, move the `key == replaceKey` block (erase and `Profiles.forgetRun`) out of
  `prepare` into that `commit`. The checks, the `existing` question and `probeLock` stay in
  `prepare`. `launchSaved` has no commit.
- [ ] Next to `launch`, add `countdown(pad: Pad, party: { Player }, title: string): boolean`:
  `endsAt = workspace:GetServerTimeNow() + SessionRules.COUNTDOWN`; `pad.counting = true`;
  `publish(pad, endsAt)`; sends each member `{ kind = "countdown", title = title, endsAt = endsAt }`;
  every 0.1 s sets `pad.status.Text` to `Starting in {n}...`. It returns false (and clears
  `counting`, `publish`) as soon as the members are no longer exactly `party` or any of them left
  the game; true when the time is up.
- [ ] `launch` order: `prepare()` -> if a ticket: `countdown(...)`; a cancel tells the members left
  `Countdown stopped: {name} left.` and ends like a launch that didn't go, but with
  `pad.held = false` (the members changed) -> `commit()` if any (a problem ends it like a failed
  prepare) -> `Telemetry.partyStarted(party)` (moved here from after `prepare`: a cancelled
  countdown is not a started party) -> the teleport as before. After the countdown, members get
  `{ kind = "launching", title = title }` again.
- [ ] `onAction`: while `pad.counting`, `"leave"` is accepted (drop and put out, as now); every
  other action is still ignored while `pad.launching`.
- [ ] Lobby and common checks. Expected: clean, builds.

### Task 10: The countdown on screen (Studio via MCP, then code)
- [ ] Lobby place (MCP): `LobbyHud.Countdown`, a TextLabel centred in the upper third (Visible
  false, BackgroundTransparency 1, theme `title` font, white, `textStroke` stroke, about 120 px)
  with a UIScale `Pop`. Built in the clear-tide style; the owner reviews and saves.
- [ ] Write the failing test in `LobbyCues.spec`: `countdown_number_counts_down_whole_seconds`
  (`countdownNumber(10, 7.0) == 3`, `(10, 7.01) == 3`, `(10, 8.5) == 2`, `(10, 9.99) == 1`,
  `(10, 10) == 0`, `(10, 12) == 0`). Run: it FAILS.
- [ ] `LobbyCues`: `countdown = { tick = "CoinTick", tickVolume = 0.6, tickPitch = 1, tickPitchStep = 0.12, go = "ToolUnlock", goVolume = 0.55, whoosh = "SpeedWhoosh", whooshVolume = 0.5, cancel = "BuyDenied", cancelVolume = 0.4, pop = 1.4 }` and
  `LobbyCues.countdownNumber(endsAt, now)` (`math.max(0, math.ceil(endsAt - now))`). Run the tests.
  Expected: `passed, 0 failed`.
- [ ] `Session.luau`, the state handler: `kind == "countdown"` shows HostBar like `launching` but
  with Leave visible (Start hidden): Line `STARTING...`, Detail `Leave to stop`.
- [ ] `lobby/src/client/Countdown.luau`: listens to `SessionState`. On `countdown` it shows
  `LobbyHud.Countdown`; on each whole-second change of `countdownNumber(endsAt, GetServerTimeNow())`
  the number pops (`Pop` from `countdown.pop` to 1, theme motion easing) with `tick`, whose pitch
  rises by `tickPitchStep` each second. At 0 it plays `go` + `whoosh`, a `Vfx.Sparkle` burst on your
  pad and `Music.fadeOut()`. Any other kind before 0 means cancelled: the number shrinks away,
  `cancel` plays and `Music.resume()`.
- [ ] `Pads.luau`: while a pad's `State` is `counting`, its Water rises up to 0.6 studs by
  `LaunchAt` (and settles back on any other state).
- [ ] Lobby checks. Expected: clean, builds.
- [ ] **Owner step:** Studio play test, solo: Create a 1-player party. 3-2-1 with rising ticks,
  the pad glows and its water rises, go, then the existing "Teleports only work in the published
  game" toast. Again, pressing Leave during the count: it stops, the cancel sound plays, you're
  put out and the music comes back.
- [ ] **Owner step:** published test with 2 players: the count runs on both screens, and the
  joiner pressing Leave at "2" cancels for both. A New Game party whose countdown is cancelled
  keeps its old save (erase now happens after the count). Then a full countdown teleports both.

## Phase E: The world moves

### Task 11: Sea and palms
- [ ] Lobby place (MCP): `Terrain.WaterWaveSize` 0.08 -> 0.2 and `WaterWaveSpeed` 10 -> 12.
  **Owner step:** look from the deck and save (or name other values).
- [ ] Write the failing test in `LobbyCues.spec`: `palm_sway_stays_within_its_angle` (for many `t`
  and seeds, both returned tilts within `palms.degrees` in radians) and
  `palm_sway_differs_by_seed`. Run: FAILS.
- [ ] `LobbyCues`: `palms = { degrees = 1.5, hzMin = 0.18, hzMax = 0.3, range = 300 }` and
  `LobbyCues.sway(t, seed): (number, number)` (two sines per axis, frequency and phase from
  `seed`). Run the tests. Expected: `passed, 0 failed`.
- [ ] `lobby/src/client/World.luau`: every `Decor.Palms` MeshPart present (stream-safe: remember
  each one's first CFrame when it arrives, forget it when it leaves) tilts about its base (bottom
  centre: `CFrame * (0, -Size.Y / 2, 0)`) by `sway(t, index)`; one `workspace:BulkMoveTo` per frame
  for the palms within `palms.range` of the camera.
- [ ] `init.client.luau`: start `World`. Lobby checks. Expected: clean, builds.
- [ ] **Owner step:** play test: palms sway gently, out of step with each other; the sea has waves.

### Task 12: Gulls
- [ ] Lobby place (MCP): `insert_asset` 231589336 ("SeaGulls", Crykee, free: "3 seagulls, no
  scripts"). Check it has no Script, LocalScript or ModuleScript (delete the model and report if it
  does). Move one gull to `ReplicatedStorage.Scenery.Gull` (Model, PrimaryPart set, every part
  Anchored, CanCollide/CanQuery/CanTouch false) and delete the rest. If the model doesn't look
  right, show the owner the Creator Store alternatives before going on.
- [ ] Write the failing test in `LobbyCues.spec`: `gull_paths_stay_in_the_sky` (for many `t`,
  `gullAt(t, i)`'s y stays within `gulls.heightMin..heightMax` and its distance from the centre is
  within `radiusMin..radiusMax`). Run: FAILS.
- [ ] `LobbyCues`: `gulls = { count = 4, centre = { 0, 0, -10 }, radiusMin = 40, radiusMax = 90, heightMin = 35, heightMax = 60, lapSeconds = 30 }`
  and `LobbyCues.gullAt(t, i): (number, number, number, number)` (x, y, z, heading). Each gull
  circles at its own radius, height bob and lap time. Run the tests. Expected: `passed, 0 failed`.
- [ ] `World.luau`: clones `Scenery.Gull` `gulls.count` times into a client folder
  `workspace.LobbyScenery` and pivots each along `gullAt` every frame, banking into the turn.
- [ ] Lobby checks. Expected: clean, builds.
- [ ] **Owner step:** play test: a few gulls circle high over the beach; save the place.

### Task 13: The bacon-hair on the horizon
- [ ] Lobby place (MCP): copy gameplay's `ReplicatedStorage.Story.BaconFat` and `Story.Straw` into
  the lobby's `ReplicatedStorage.Scenery.BaconFat` (one Model; the straw welded from his `Mouth`
  down into the sea). Rebuild every part, mesh, `CharacterMesh`, `Shirt`/`Pants`, `BodyColors` and
  `Decal` from a property dump of the gameplay instances. If a property can't be set from a
  script, stop and ask the owner to copy it (Ctrl+C in the gameplay Studio, Ctrl+V into the lobby
  Studio). Strip `TouchTransmitter`s. Every part Anchored, CanCollide/CanQuery/CanTouch false. Its
  pivot sits where he belongs: on the sea far behind the pads (about `0, -2, -420`), facing the
  lobby (+Z), framed so he shows above the pads from the spawn.
- [ ] `LobbyCues`: `horizon = { slurp = "IntroSlurpFar", slurpVolume = 0.5, burp = "IntroBurp", burpVolume = 0.4, slurpEvery = { 14, 22 }, burpEvery = 3, swell = 0.04, swayDegrees = 2, rollOff = 600 }`
  (data only; the `every_named_sound_is_a_string` test covers its names).
- [ ] `lobby/src/client/Horizon.luau`: clones `Scenery.BaconFat` into `workspace.LobbyScenery` at
  its pivot. He sways slowly about his base. Every `slurpEvery` seconds: a slurp (3D at him,
  `RollOffMaxDistance` = `rollOff`) while his `Belly` swells by `swell` and settles; every
  `burpEvery`-th time a burp with a small hop.
- [ ] `init.client.luau`: start `Horizon`. Run `lune run tests/run` and the lobby checks.
  Expected: `passed, 0 failed`; clean; builds.
- [ ] **Owner step:** play test from the spawn: he is visible on the horizon behind the pads,
  slurping now and then, faint but audible from the deck. Save the place.

## Task 14: Docs
- [ ] `CLAUDE.md` (Studio, the lobby's baked pieces): `ReplicatedStorage.Audio` (groups and
  sounds), `ReplicatedStorage.Vfx` (`ScoopSplash`, `Sparkle`, `PadBubbles`),
  `ReplicatedStorage.Scenery` (`Gull`, `BaconFat`), each pad's `Water.Ripple`,
  `LobbyHud.Countdown`, and the pad attributes `State` / `LaunchAt`.
- [ ] `AGENTS.md`: a short lobby code map (the new client modules, `LobbyCues`, the countdown
  in `Queue.launch`, `SessionRules.padState`).
- [ ] Final checks in `lobby/` and `gameplay/`, and for `common/`.
  Expected: clean, builds, `passed, 0 failed`.

## Not verified by checks (needs play tests)
The mix (music under ambience under UI), 3D roll-off of others' steps and the horizon, the
countdown across two clients and a real teleport (published game only), and phone performance with
the palms, gulls and bubbles running.
