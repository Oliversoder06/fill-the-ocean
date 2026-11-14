# Analytics and Funnels Build Plan

> **For agentic workers:** follow `AGENTS.md`. Do the tasks in order. Steps use checkbox (`- [ ]`)
> syntax. Run every command and compare it to its `Expected:` line. Stop at **Owner step**s.

**Goal:** the game answers "when and why do players quit, and did this build help?" with two sinks:
Roblox's AnalyticsService (funnels, custom events, economy — the dashboards) and our own
session-record DataStore (the raw rows Roblox never gives you), read by `lune run tools/analytics`.
The architecture is ported from the owner's previous game (press poop); its hard-won rules are
baked in below as constraints, not suggestions.

**As built (2026-11-13), where it differs from the tasks below** (the reference is `docs/analytics.md`):
- The rules live in `common/Analytics.luau` itself (no `AnalyticsRules`): pure modules may not
  require each other.
- Both places send through one non-pure `common/TelemetryCore.luau` (the only AnalyticsService
  caller, the record writer, funnel saves, server error counts); each place's `Telemetry.luau` only
  supplies its facts. C1's record is wired in from the start.
- Honeycomb_v1's middle step is `Viewed` (an upgrade's card showed: hover or select), not
  `Selected`: a mouse click buys without selecting.
- Tool_v1's steps are `Level1` … `Level24` (tool levels bought; the spoon is level 0).
- `StaffHired` became `ItemBought` (every stand item, staff included).
- The lobby needs no `Telemetry` remote: lobby facts are all server-side. Only gameplay's project
  file changed.

**Scope (owner, 2026-11-13):** the full port — Phase A (gameplay funnels + events + economy),
Phase B (lobby steps + client telemetry), Phase C (session record + report). Team passive income
(staff, buildings) is flushed to **one present member** with its own reason tag.

## Carried-over rules (never break these)
1. **One config names everything** (`common/Analytics.luau`); the senders refuse any name not on
   the list — a typo becomes a warning, not a new chart. **Names are permanent**: renaming a step
   mixes data, renaming a funnel or event starts it empty. Version funnels (`_v1`, `_v2`), never
   edit their steps (onboarding excepted: steps may only be cut from the end or appended).
2. **Analytics never throws into gameplay.** Every public Telemetry function catches its own
   errors and `warn`s (never silently — the no-swallowing rule still holds). Delete the Telemetry
   files and the game plays identically.
3. **One-time funnels count NEW players only.** A player enters on their first-ever profile load;
   progress lives in their profile so rejoins continue. A save that predates the funnel never
   enters it (a veteran walking in at step 7 would credit Roblox steps 1–6).
4. **Steps are never skipped**: a step is sent only while its fact is true AND every step before
   it was sent. Out-of-order players wait at the missing step. (Counts are right; per-step
   timings on one-time funnels are not.)
5. **Onboarding ends at the first turn of the core loop.** Nothing optional goes in it — a
   skippable step holds every later step hostage.
6. **Every field value comes from a short fixed list** in the config — never a name, raw number,
   or anything a client typed. Numbers are banded. Roblox allows ~8,000 distinct field
   combinations/day, then files everything as "Other". Platform/OS/age/payer are built-in
   breakdowns; never spend a field on them.
7. **Custom fields work only on step 1 of a recurring funnel** (Roblox reads filters from step 1).
8. **Rate budget:** Roblox allows 120 + 20×players events/min/server and silently drops the rest.
   Spend at most 60%; reserve 30% of that for protected events (funnel steps, economy,
   SessionEnd), so a flood can never crowd them out. Held-back events `warn`.
9. **The client decides nothing.** The server takes only names it knows, gates each report to one
   per gap, clamps every number, and never puts client text in a Roblox field.
10. **Session record:** one DataStore write per player per session, on leave, after the run save
    queues — never per event. Every event sent to Roblox is also handed to the record, so charts
    and record never disagree. `build` (PlaceVersion) on every row.

## Global constraints
- Pure modules (no `require`, no `game`) in `common/`, Lune-tested from `gameplay/tests/`, listed
  in `tests/run.luau`. Config-dependent lists are built by pure functions that TAKE the config
  (the `RunSave.sanitize(raw, config)` pattern), because `common/` may not require gameplay's
  `Config`.
- Both places need the config and rules, so they live in `common/` (already mapped to
  `ReplicatedStorage.Common` in both projects).
- Studio sends nothing to Roblox: `workspace:GetAttribute("StudioEcho")` (or always in Studio)
  prints each event as it would go. The Studio record writes to a `_Studio` store copy. On LIVE,
  user ids in `shared/Admins` are neither sent nor recorded (testers must not pollute charts).
- Checks after every task, in each folder touched: `selene src` (0 errors, 0 warnings),
  `rojo build -o <folder>.rbxlx` succeeds, `gameplay/`: `lune run tests/run` ends `0 failed`.
  For `common/`: copy `gameplay/selene.toml` in, run `selene .`, remove it.

## The names (permanent once live — get them right here)

**Funnels (5 of Roblox's 10; 5 slots reserved):**

| Funnel | Kind | Steps |
|---|---|---|
| Onboarding | built-in one-time | Joined → LobbyLoaded → PartyStarted → RunLoaded → IntroDone → AtWell → FirstScoop → FirstPour → CanAfford → FirstUpgrade |
| Progression_v1 | one-time | Area2 … AreaN (a gate opened while the player was present) → OceanFull |
| Tool_v1 | one-time | Level2 … LevelN (from `Config.tracks.tool`; level 1 is the spoon everyone starts with) |
| Milestones_v1 | one-time | M5 → M10 → … → M100 (`Config.milestones`) |
| Honeycomb_v1 | recurring (per open) | Opened → Selected → Bought; step 1 fields `Source` (Tab/Button/Goal/Key) + `Stage` |

Onboarding notes (owner, 2026-11-13: the funnel follows the first-minute guide, client/Guide's 6
steps, as far as server facts allow; every step is one nobody can skip):
- IntroDone: Phase reached `playing` with the player present (watched, skipped, or joined a run
  whose intro was already seen — always reached).
- AtWell: the player stood within reach of an open area's Source (the 1 s poll). Guide step 1.
- FirstScoop / FirstPour: the player's OWN credited scoop / pour. Guide steps 2–4. "Tool full" is
  NOT a step: a player may pour before full, so it is optional and would hold later steps hostage.
- CanAfford: the team's wallet reached the cheapest on-sale upgrade's price (Items.tabOffer) while
  the player was present — the "Again!" loops between the first pour and the first buy show here.
- FirstUpgrade: the team owns a bought level while the player is present (the guide ends on the
  team's first buy, so a teammate's buy counts; an own-buy step would never complete for many
  team players). "Open upgrades" (guide step 5) is NOT a step for the same reason; Honeycomb_v1
  tracks it.
- The exact guide step comes through Stage (`Guide:1` … `Guide:6`, client-reported, B2) and the
  GuideSkip event, not through funnel steps.

**Custom events:**

| Event | Value | Fields | Answers |
|---|---|---|---|
| SessionEnd | minutes played | Where, Doing, Stage | when/why players quit — once per player per session, both places |
| TripEnd | seconds carrying | Outcome (Poured/Quit), Area, Stage | is the carry loop too long/boring per stage — a trip is carried 0 → >0 → poured (or left) |
| IntroEnd | seconds in | Outcome (Watched/Skipped) | is the intro worth its length |
| GuideSkip | seconds since play started | Step (Guide:1…Guide:6) | which tutorial step people bail from |
| GateOpened | minutes since run start | Area, TeamSize (banded) | the real pacing curve vs `tools/simulate` |
| Milestone | minutes since run start | Index (M5…M100), TeamSize | same, finer |
| Blocked | 1 | Reason (CantAfford/GateLocked/Clogged), Stage | walls; 30 s cooldown per reason per player |
| UpgradeShort | share of price missing (0–1) | Track, Stage | price walls |
| BuildingBuilt / StaffHired / VehicleCalled | 1 | Id, Stage | automation adoption |
| LoadTime | seconds, banded | Place (Lobby/Run), WaitedOn | slow joins |
| SaveUnavailable | 1 | Place | must be 0; these players never come back |
| ClientFps | avg fps, banded | Platform | silent quits on stuttering phones |

**Fixed field lists:** `Stage` = Intro, Guide:1 … Guide:6 (the first-minute guide's step showing,
client-reported through B2; until B2 lands, plain `Guide` while the server sees no bought level),
then fill bands F0, F5 … F95 (the universal third field, on everything). Filtering SessionEnd to
`Guide:*` says which tutorial step people quit on and how long they had played. `Where` = Lobby, Town, Area1…AreaN, None.
`Doing` = Loading, Intro, Scooping, Carrying, Pouring, Driving, Honeycomb, Idle (60 s without
input), Roaming.

**Economy (currency Money, the team wallet; Robux excluded — Monetization pages count those):**
earn reasons Pour, Hose, Vehicle (attributed to the acting player, from `earn`'s `player`), and
Staff, Buildings (no acting player: summed and flushed every `IncomeFlush = 300` s to one present
member, their own reason tags keeping per-player income honest); spend reasons Upgrade, Item,
Gate, Building, StaffHire (attributed to the buyer). Admin/Studio money passes no reason and is
never reported. Amounts clamped below 3.4e38.

---

## Phase A: config, rules, gameplay telemetry

### Task A1: the config and the pure rules
**Why:** everything else refuses names not declared here; the decisions (which steps are due,
which band, what "doing") are pure functions because a wrong answer doesn't throw — it silently
makes the dashboard lie. So they're spec'd.

**Files:** create `common/Analytics.luau`, `common/AnalyticsRules.luau`,
`gameplay/tests/Analytics.spec.luau`; add `"Analytics"` to `tests/run.luau`'s `SPECS`.

**Interfaces (`Analytics`, pure data + builders):**
- `Analytics.ONBOARDING = { "Joined", "LobbyLoaded", "PartyStarted", "RunLoaded", "IntroDone", "AtWell", "FirstScoop", "FirstPour", "CanAfford", "FirstUpgrade" }`.
- `Analytics.GUIDE_STEPS = 6` (client/Guide's `STEPS`; Stage values `Guide:1` … `Guide:6`).
- `Analytics.funnels(config)` returns the custom funnels above, steps built from the config
  (areas, tool levels, milestones), each `{ id, recurring, steps = { string } }`.
- `Analytics.events`: per event, its allowed fields and each field's fixed value list;
  `Analytics.stages(config)`, `Analytics.wheres(config)`, `Analytics.DOING`.
- `Analytics.money`: reason → Roblox transaction-type name; `Analytics.INCOME_FLUSH = 300`.
- `Analytics.bands`: `fps`, `load`, `teamSize` band tables; `Analytics.BUDGET = { share = 0.6,
  protectedShare = 0.3 }`; `Analytics.BLOCKED_COOLDOWN = 30`; `Analytics.IDLE_AFTER = 60`.

**Interfaces (`AnalyticsRules`, pure functions over plain values):**
- `AnalyticsRules.advance(steps, sent: number, facts: { [string]: boolean }): number` — the
  highest step that may be sent now (every step ≤ it true, in order); never skips.
- `AnalyticsRules.bucket(bands, value): string`.
- `AnalyticsRules.stage(introDone, guideStep: number?, fill): string` (`guideStep` nil once the
  guide is done or skipped; 0 = guide up but its step not reported yet → `Guide`) and
  `AnalyticsRules.doing(facts): string` (facts: loading, inIntro, carried, lastActKind,
  lastActAge, driving, honeycombOpen, idleSeconds).
- `AnalyticsRules.budget(spent, playerCount, protected: boolean): boolean` — may this event go
  out this minute.
- `AnalyticsRules.tripOutcome(poured: boolean): string`.

- [ ] Write the tests first: `advance_never_skips`, `advance_waits_at_a_false_step`,
  `funnels_built_from_config_in_order`, `every_field_value_is_listed`, `bucket_edges`,
  `stage_bands_cover_0_to_1`, `doing_prefers_the_specific`, `budget_protects_reserved`,
  `budget_spends_at_most_share`.
- [ ] Run `lune run tests/run`. Expected: the new tests FAIL (modules missing).
- [ ] Implement, run the checks. Expected: `0 failed`; selene clean in `gameplay/` and `common/`.

### Task A2: funnel state in the profile
**Why:** rule 3 — one-time funnel progress must survive rejoins, and a save from before the
funnels must never enter them. The marker is the `funnels` key itself: only a brand-new profile
ever gets `funnels = {}`; a veteran's sanitize leaves it absent, and an absent key means "never
send one-time steps for this player".

**Files:** edit `common/Progress.luau`, `common/PlayerData.luau`; tests in
`gameplay/tests/Progress.spec.luau`.

**Interfaces:**
- `Progress.Data` gains `funnels: { [string]: number }?` (funnel id → highest step sent).
  `sanitize` keeps it only if present and well-formed in the raw (whole numbers ≥ 1).
- `Progress.enterAnalytics(raw): Data` — sets `funnels = {}` only if absent.
- `Progress.advanceFunnels(raw, steps: { [string]: number }): (Data, boolean)` — monotonic max
  merge; a `raw` without the key returns unchanged, false (veterans stay out).
- `PlayerData.load(userId)` returns a third value `isNew: boolean` (the store held nothing).
  Existing callers ignore it; lobby Telemetry (B1) uses it.
- `PlayerData.enterAnalytics(userId)` and `PlayerData.saveFunnels(userId, steps)` (one merge
  write, called once per leave — never per step).

- [ ] Tests first: `funnels_absent_for_old_saves`, `enter_analytics_only_once`,
  `advance_funnels_is_monotonic`, `advance_funnels_ignores_untracked`,
  `sanitize_repairs_bad_funnel_steps`. Expected: FAIL, then implement, then `0 failed`.

### Task A3: the gameplay Telemetry service
**Why:** one file talks to AnalyticsService in gameplay; it's told the moments, polls per-player
state once a second for Doing/Idle, and spends the budget.

**Files:** create `gameplay/src/server/Telemetry.luau`; edit `gameplay/src/server/Run.luau`
(hook calls only — the pattern of `Mechanics`/`Vehicles`: `Run` starts it with hooks and tells it
the moments).

**Interfaces (every public function catches and `warn`s; no-ops in Studio except the echo):**
- `Telemetry.start(hooks)` — hooks: `fill()`, `phase()`, `teamSize()`, `runStartedAt()`,
  `guideStep(player)` (the last step the client reported, B2), `states` access for the 1 s poll.
- Told by `Run` at the exact places that already decide the facts:
  `playerIn(player)` (loads funnel state off-thread, `onPlayerAdded`),
  `scooped(player, areaId)` (`creditScoop` — starts/extends the trip, FirstScoop),
  `poured(player, areaId, litres)` (`creditPour` — ends the trip Poured, FirstPour),
  the 1 s poll also sets AtWell (within reach of an open Source) and CanAfford (wallet ≥ the
  cheapest `Items.tabOffer` price) for present players; IntroDone from `startPlaying` and for
  anyone who joins while `playing`; FirstUpgrade when any track level is bought (`onBuy`) or on
  join if the team already has one,
  `earned(player?, coins, reason)` (`earn` call sites: pour/hose/vehicle pass the player; staff
  and building ticks pass nil and their reason, summed for the 5-minute flush),
  `spent(player, coins, reason, id)` (`onBuy`, `openGate`, and the Build/Staff paths),
  `bought(player, id)` (FirstUpgrade for every present member + Honeycomb_v1 Bought + BuildingBuilt/StaffHired/VehicleCalled
  by id kind), `gateOpened(areaId)` (Progression_v1 for every tracked member present + the event),
  `milestone(index)` (`checkMilestones`), `levels(trackId, level)` (Tool_v1),
  `introEnded(skipped, seconds)` (`endIntro`), `runLoaded()` (`startPlaying`),
  `blocked(player, reason)` (the refusal paths in `onBuy`/`openGate`, with `UpgradeShort` when
  the wallet was the reason), `saveUnavailable()` (a failed `openRun` load),
  `playerOut(player)` (`PlayerRemoving` + `BindToClose`: SessionEnd with Where/Doing/Stage, the
  trip's Quit if carrying, the ClientFps event from the last client report (B2), the one
  `PlayerData.saveFunnels` write).
- Honeycomb_v1 Opened/Selected need the client's word: deferred to B2's remote; until then the
  funnel sends only Bought (a complete funnel with one reached step is valid; the earlier steps
  arrive with B2). *(If the owner prefers, swap: hold the whole funnel until B2.)*
- Economy: `LogEconomyEvent` with the mapped transaction types, only when a reason is named.
- The 1 s poll keeps each player's `doing` facts fresh (`AnalyticsRules.doing`), the minute
  budget, and the income flush clock.

- [ ] Implement; wire the `Run.luau` calls (surgical: one line per moment, next to the fact).
- [ ] Run the checks in `gameplay/` and `common/`. Expected: selene 0/0, build OK, `0 failed`.
- [ ] Studio echo: play in Studio, scoop, pour, buy, leave. Expected: `[Telemetry]` echo lines
  for IntroDone/AtWell/FirstScoop/FirstPour/CanAfford/FirstUpgrade (a fresh profile), TripEnd, SessionEnd, the money moves —
  and nothing sent (Studio).
- [ ] **Owner step:** publish gameplay, play a run live with a non-admin test account, check
  Creator Hub → Analytics → "View Events" shows the events arriving.

---

## Phase B: lobby steps and client telemetry

### Task B1: lobby Telemetry
**Why:** the first three onboarding steps happen before the teleport; a first visit that never
leaves the lobby must still produce Joined/LobbyLoaded and a SessionEnd.

**Files:** create `lobby/src/server/Telemetry.luau`; edit `lobby/src/server/Profiles.luau`
(pass `isNew` through from `PlayerData.load`), `lobby/src/server/Queue.luau` (one call before
`TeleportAsync`), `lobby/src/server/init.server.luau` (start it).

- Joined: on a first-ever profile load (`isNew`): `PlayerData.enterAnalytics`, then step 1.
- LobbyLoaded: when `DataReady` is set. PartyStarted: just before the party teleports.
- SessionEnd (Where=Lobby, Doing=Loading/Idle/Roaming, Stage=F0), LoadTime (join → DataReady,
  banded, WaitedOn=Data). SaveUnavailable on a failed load.
- [ ] Run the checks in `lobby/` and `common/`. Expected: clean. Studio echo as in A3.

### Task B2: the client report remote
**Why:** FPS, load time and the honeycomb's Opened/Selected only the client knows; rule 9 governs
the trust.

**Files:** edit `gameplay/default.project.json` and `lobby/default.project.json` (add a
`Telemetry` RemoteEvent) and the `remote(...)` list in `Run.start`; create
`gameplay/src/client/Telemetry.luau` (started from `init.client.luau`); edit
`gameplay/src/client/Honeycomb.luau` (two fire lines: opened with its Source, selected),
`gameplay/src/client/Guide.luau` (one line where `shownStep` changes, one in Skip);
`gameplay/src/server/Telemetry.luau` takes the reports.

- Client sends only names from a fixed list: `fps` (a 60 s summary; measurement starts when the
  intro/loading ends, not at boot), `load` (seconds to playable, what it waited on from a fixed
  list), `hcOpen` (source), `hcSelect`, `guide` (the step 1–6 client/Guide shows, sent on change;
  0 when it hides) and `guideSkip` (from Guide's Skip; the server sends GuideSkip with the last
  reported step), `warn`/`error` (first 5 distinct each, 160 chars — held
  for the record in C1, counted until then). Server gates each name to one per gap, clamps every
  number, drops unknown names with a `warn`.
- Honeycomb_v1 Opened/Selected now send (server-side, from the gated reports), completing A3.
- [ ] **Owner step:** restart `rojo serve` in both folders (the project files changed), save and
  publish both places.
- [ ] Run the checks in both folders. Expected: clean; Studio echo shows Opened→Selected→Bought
  and a ClientFps line on leave.

---

## Phase C: the session record and the report

### Task C1: the record (pure core + writers)
**Why:** the second sink — per-player raw sessions with build number and an event trail; the only
way to answer "did this build help?" and to read one player's whole story.

**Files:** create `common/AnalyticsRecord.luau` (pure) and `gameplay/tests/AnalyticsRecord.spec.luau`
(add to `SPECS`); extend both places' `Telemetry.luau` with the writer.

**Interfaces (`AnalyticsRecord`, pure):**
- `AnalyticsRecord.FORMAT = 1` (bump whenever a field changes meaning).
- `AnalyticsRecord.session(facts)` — one row: when, seconds, build, new, platform, fps detail,
  load, where/doing on leave, furthest onboarding step, progress snapshot (fill, wallet band,
  areas open), counts (trips, pours, litres banded, buys, blocked), errors/warnings (from B2),
  and the `trail` (`{ t, k, v, f }` per funnel step, event and money move, in order).
- `AnalyticsRecord.add(trail, entry)` with the trim: past 400 rows keep the first 40 and every
  milestone (funnel steps, buys, gates, milestones, errors); filler drops oldest-first.
- `AnalyticsRecord.push(record, session)` — keeps the last 25 sessions, drops older, enforces
  the DataStore size by trimming trails first.
- Writer: DataStore `AnalyticsSessions_v1` (Studio: `AnalyticsSessions_v1_Studio`), key
  `u_<userId>`, ONE `UpdateAsync` per player on leave, `task.spawn`ed after the run save queues
  (analytics never spends the budget a save needed), through `common/Retry`. Server
  errors/warnings (`LogService`) → key `errors_<build>`, per-message counts, flushed every 10 min.
- [ ] Tests first: `trail_keeps_milestones_past_400`, `record_keeps_last_25`,
  `session_row_shape`, `format_stamped`. Expected: FAIL → implement → `0 failed`; checks clean
  in all three folders.

### Task C2: `lune run tools/analytics`
**Why:** nobody reads raw DataStore rows; the report is what actually gets run after a release.

**Files:** create `gameplay/tools/analytics.luau` (Open Cloud via `@lune/net`, env
`ROBLOX_API_KEY_DATASTORE`) and `gameplay/tools/AnalyticsReport.luau` (pure formatting/stats over
plain rows); `gameplay/tests/AnalyticsReport.spec.luau` against synthetic players (add to `SPECS`).

- Prints, split by `--build N`: first-visit length, share gone within 60 s / 180 s (what Roblox
  ranks on), D1/D7 return (only players whose window has passed), onboarding reach step by step,
  where/doing first visits ended, devices + fps bands, trips by Outcome, Honeycomb
  Opened→Selected→Bought, gate/milestone pace vs `tools/simulate`'s prediction, errors and
  warnings by player count. `lune run tools/analytics player <id>` prints one player's sessions
  minute by minute from the trail.
- [ ] Tests first (synthetic rows: a bouncer, a D1 returner, an error case). Expected: FAIL →
  implement → `0 failed`.
- [ ] **Owner step:** create an Open Cloud API key (DataStore read, gameplay universe), set
  `ROBLOX_API_KEY_DATASTORE`, run `lune run tools/analytics` a day after the next release.

### Task C3: document it
**Files:** create `docs/analytics.md`: the names table, the field discipline, the diagnostic
playbook (traffic → broken → onboarding → core loop (TripEnd by Outcome) → progression pace →
session ends → economy → SaveUnavailable = 0), and the verification method (StudioEcho, View
Events, the `_Studio` store). Add Telemetry to the code maps in `AGENTS.md` and `CLAUDE.md`.
- [ ] Checks in every touched folder. Expected: clean. Done.
