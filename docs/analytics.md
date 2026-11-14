# Analytics

How the game measures itself: when and why players quit, where the climb stalls, and whether a
release helped. Built from `docs/plans/2026-11-13-analytics.md`.

Two sinks:
1. **Roblox AnalyticsService**: funnels, custom events and the economy, in the Creator Hub dashboards.
2. **The session record**: each player's last 25 place visits in our own DataStore
   (`AnalyticsSessions_v1`, key `u_<userId>`), read with `lune run tools/analytics`. It is the only
   place with the build number per session and a trail of what each player did.

## Where it lives

| File | Job |
|---|---|
| `common/Analytics.luau` | Every name: funnels, steps, events, field values, money reasons, bands, budget, client reports. Also the rules (`advance`, `bucket`, `stage`, `doing`, `allowed`, `checkReport`). Pure, spec'd in `tests/Analytics.spec`. |
| `common/AnalyticsRecord.luau` | The session record's shape: trail trimming, the last 25 sessions, shrinking to fit. Pure, spec'd. |
| `common/TelemetryCore.luau` | The only caller of AnalyticsService, for both places. Checks names, spends the rate budget, echoes in Studio, keeps and writes the record, saves funnel steps, counts server errors. |
| `gameplay/src/server/Telemetry.luau` | The run's facts. `Run`, `Buildings` and `Vehicles` tell it the moments; it polls each player once a second. |
| `gameplay/src/client/Telemetry.luau` | Client reports: fps, device, errors and warnings. `Honeycomb` and `Guide` report through it. |
| `lobby/src/server/Telemetry.luau` | The first onboarding steps, lobby LoadTime, SaveUnavailable and SessionEnd. |
| `gameplay/tools/analytics.luau`, `AnalyticsReport.luau` | The report (Open Cloud pull + pure report, spec'd in `tests/AnalyticsReport.spec`). |

Analytics never breaks the game: every public Telemetry function catches its own errors and warns.

## Rules (never break these)
- **Names are permanent.** Renaming a step mixes data; renaming a funnel or event starts it empty.
  Change a funnel by adding `_v2`, never by editing its steps. Onboarding (Roblox can't version it)
  only gets steps cut from the end or appended.
- **Everything is declared in `common/Analytics`.** The core refuses anything else with a warning.
- **One-time funnels count new players only.** The lobby enters a player whose profile didn't exist
  (`Progress.enterAnalytics`, `funnels = {}`). A profile from before has no `funnels` and never
  enters, so veterans never credit steps they did long ago. Steps sent are saved once per leave
  (`PlayerData.saveFunnels`, a max-merge).
- **Steps are never skipped** (`Analytics.advance`). A false step holds the ones after it. Counts are
  right; timings between one-time steps are not.
- **Field values come from fixed lists**: no names, raw numbers or client text. Numbers are banded.
  Roblox files everything past ~8,000 combinations a day as "Other". Platform, age and payer are
  Roblox's own breakdowns; never spend a field on them.
- **Rate budget**: at most 60% of Roblox's 120 + 20 × players a minute, with 30% of that kept for
  funnel steps, the economy and SessionEnd. Held-back events warn once a minute.
- **The client decides nothing.** Reports are listed names, paced per name, their argument checked.
  Client text only ever goes into the record.
- **Studio sends nothing.** It prints `[Telemetry] ...` for each event (`workspace.StudioEcho = false`
  silences it) and writes records to `AnalyticsSessions_v1_Studio`. On the live game, admins
  (`shared/Admins`) are neither sent nor recorded.

## Funnels (5 of 10)

| Funnel | Kind | Steps |
|---|---|---|
| Onboarding | one-time (built-in) | Joined → LobbyLoaded → PartyStarted → RunLoaded → IntroDone → AtWell → FirstScoop → FirstPour → CanAfford → FirstUpgrade |
| Progression_v1 | one-time | Area2 … Area5 (gate open while present) → OceanFull |
| Tool_v1 | one-time | Level1 … Level24 (tool levels the team bought) |
| Milestones_v1 | one-time | M5 … M100 |
| Honeycomb_v1 | recurring, one per open | Opened (fields Source, Stage) → Viewed → Bought |

Onboarding follows the first-minute guide (`client/Guide`) as far as the server can confirm it.
These are left out because a player can skip them:
- "Tool full": you may pour early.
- "Open upgrades": a teammate may make the first buy.

The exact guide step is in Stage instead. FirstUpgrade is the **team's** first bought level, the same
moment the guide ends.

Roblox keeps only each player's 10 most recent recurring-funnel sessions. Honeycomb totals come from
the record, not the funnel.

## Custom events

| Event | Value | Fields | Answers |
|---|---|---|---|
| SessionEnd | minutes this visit | Where, Doing, Stage | when and why players quit; not sent for a teleport (lobby ↔ run) |
| TripEnd | seconds carrying | Outcome (Poured/Quit), Area, Stage | the core loop: a trip is carried 0 → water → poured or left |
| IntroEnd | seconds in | IntroOutcome (Watched/Skipped) | is the intro worth its length |
| GuideSkip | seconds this visit | Stage | which guide step people bail from |
| GateOpened | minutes of the run's play | Area, TeamSize | the real pace against `tools/simulate` |
| Milestone | minutes of the run's play | Milestone, TeamSize | the same, finer |
| Blocked | 1 | Reason (CantAfford/Locked/GateLocked/NotBuilt), Stage | walls; 30 s cooldown per reason and thing |
| UpgradeShort | share of the price missing | Upgrade, Stage | price walls (a press on a short hex, stand, gate or plot) |
| ItemBought / BuildingBuilt / VehicleCalled | 1 | Item, Stage | gear and automation adoption |
| LoadTime | seconds | Place, Band, WaitedOn | slow joins |
| SaveUnavailable | 1 | Place | **must be 0**; alert on it |
| ClientFps | average fps | Band | stuttering devices (a silent quit) |

**Stage** goes on most events: `Lobby`, `Loading`, `Intro`, `Guide:1` … `Guide:6` while the guide
shows, then fill bands `F0` … `F100`. **Doing** is `Loading`, `Intro`, `Ending`, `Idle` (60 s still),
`Honeycomb`, `Driving`, `Hosing`, `Scooping`, `Pouring`, `Carrying`, `Roaming` or `Party` (lobby pad).

## Economy
One currency, `Coins` (the team's wallet). Robux is left to Roblox's Monetization pages. A money
move is reported only with a named reason; that is the transaction type.
- **Sources** (summed per player, sent every 5 minutes and on leave):
  - Pour, Hose and Vehicle: the acting player's own income.
  - Staff and Buildings: the team's income. It has no player, so it goes out as the present member
    with the lowest user id whose events count (never a live admin; with none present it waits). The
    team's Milestone events go out the same way.
- **Sinks** (sent at once with the item SKU): Upgrade, Item, Gate, Build, BuildingLevel.

Studio money (`StudioMoney`) and admin fill jumps have no reason and never count.

## The session record
One write per player per place visit, on leave. Each session holds:
- `at`, `seconds`, `build` (PlaceVersion), `place`, `new`, `left` (`quit` / `teleport`)
- `device`, `fps`, `load`, `onboarding` (the furthest step), `leave` (where, doing, stage)
- `progress` (fill, wallet, gates, tool, team size, minutes)
- `counts`: scoops, pours, buys, earned, spent
- the client's first 5 distinct `errors` and `warnings`
- `trail`: every step, event and money move `{ t, k, s, v, f }`. Past 400 rows it keeps the first 40
  and every milestone row; filler goes oldest first.

`AnalyticsRecord.FORMAT` is bumped whenever a field changes meaning.

Server errors and warnings are counted per message under `errors_<place>_<build>` (flushed every
10 min).

## Reading it
Set `ROBLOX_API_KEY_DATASTORE` (an Open Cloud key with DataStore list and read on this experience),
then from `gameplay/`:

```
lune run tools/analytics                 # everyone
lune run tools/analytics --build 412     # one release
lune run tools/analytics player 12345    # one player's whole story
lune run tools/analytics errors          # server errors per place and build
```

Add `--studio` for the Studio store and `--limit N` to read fewer players. Run it a day after every
release.

## The playbook (when players fall)
0. Pull the records: `lune run tools/analytics --build <new>` against the previous build.
1. Traffic or game? Creator Hub Acquisition: if impressions fell and play-through held, it's
   discovery.
2. Broken? The Error Report, then `errors` and each session's errors and warnings.
3. New players leaving? The report's "gone within 60 s / 180 s" and onboarding reach, the Onboarding
   funnel's steepest drop, and SessionEnd filtered to Stage `Guide:*` (which guide step they quit on).
4. The core loop? TripEnd by Outcome (many Quit = carrying is a chore at that stage) and TripEnd
   seconds by Area.
5. Progress stalling? Tool_v1, Progression_v1, Milestones_v1, GateOpened and Milestone minutes
   against `lune run tools/simulate`, and UpgradeShort (a high value means a price is out of reach).
6. Where do sessions end? SessionEnd Where × Doing.
7. Economy: sources against sinks by reason.
8. SaveUnavailable = 0, always.

## Verifying a change
- Studio: play, scoop, pour, buy, leave; the Output shows each `[Telemetry]` line as it would go.
- Live: Creator Hub → Analytics → "View Events" shows events arriving within minutes (custom event
  charts take up to a day).
- A new event, field value or step: add it to `common/Analytics` first, or the core warns and drops it.
