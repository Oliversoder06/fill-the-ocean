# Handoff: how to continue building Fill the Ocean

Read this first in every new session. Then read CLAUDE.md, AGENTS.md and
`docs/plans/2026-11-05-save-the-ocean.md` (the build plan; its "Phase N tasks" sections are the to-do list).

## Where things are (2026-11-09)
- `main` has everything: Phase 1 (saved runs), Phase 2 (areas) and Phase 3a (buy-at-stand + backpacks).
  The owner's checkout `C:/RobloxDev/games/fill the ocean` is on `main`; Rojo serves it to Studio
  (gameplay port 34675, lobby 34674), so whatever is on `main` runs in Studio.
- **Next: Phase 3b (gadgets)**, then 3c (area mechanics), 3d (vehicles), 3e (buildings), 3f (staff), then
  Phases 4-9 (each needs its step-by-step tasks written into the plan first).
- Phase 2 leftovers (do with 3b or later): per-area ambience/music, guide hint toward the next gate, a
  gate-burst VFX.
- Owner decisions D1-D9 in the plan: use the defaults, never change one.

## Owner's preferences (follow them)
- Use as FEW tokens as possible: few agents, short prompts, no big workflows (the Workflow tool may
  be off). The owner hit the 5-hour limit twice.
- Don't ask the owner to place things or make design choices; decide yourself ("you know better").
- Work in batches. After each batch: merge, play test, report briefly, then ask whether to continue.
- Don't push to GitHub unless asked. Committing and fast-forwarding `main` is fine.
- Plain, short reports.

## How to build one batch (the process that worked)
1. **Worker (one Agent, general-purpose, run in background).** It makes its own worktree:
   `git -C "C:/RobloxDev/games/fill the ocean" worktree add "C:/RobloxDev/games/fto-<id>" -b phaseN/<id> main`.
   The worktree MUST be at `C:/RobloxDev/games/fto-<id>` (that depth makes the Rojo path
   `../../../shared` resolve to `C:/RobloxDev/shared`). Never edit or switch the main checkout.
   Prompt contents: what to read (CLAUDE.md, AGENTS.md, the plan's batch section), the exact job, the
   files it owns, rules (tests first for pure logic, never weaken tests, no swallowed errors, surgical, no
   duplication, server-authoritative, no Roblox Studio tools: list Studio needs under "studioSteps"
   with exact paths), the checks, commit message ending
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, "return briefly".
2. **Reviewer (one fresh Agent, review only).** Give it the brief, the worktree, `git diff main...<branch>`,
   what to look hard at (exploits, saves, races, no duplication), the checks; return pass/fail +
   defects as file:line, problem, fix. One fix round: SendMessage the defects back to the worker.
3. **Studio steps (one Agent, the ONLY one allowed to use Roblox Studio MCP tools)**, run in parallel
   with the review. Rules to give it: edit mode, never edit scripts, never delete (move to
   `ServerStorage.PhaseNRemoved`), never publish, owner's CLAUDE.md camera rule, max 2 min per check,
   sunbaked-sea style (sunny orange #FFB23F, navy #1B2A3A, cream #FFF1C9, shallow water #3FA9E0,
   teal #2FC7B0), clone existing UI pieces, verify every path with execute_luau.
4. **Merge:** in the main checkout `git merge --ff-only phaseN/<id>` (only after the Studio pieces the code
   asserts exist, or the HUD breaks).
5. **Lead play test (you, directly with Studio MCP, no agent):** see below. Fix small things yourself.
6. Report to the owner and remind them to save the place in Studio (File > Save to Roblox).

## Checks (each with `timeout 110`; never wait more than 2 minutes on one)
- gameplay/: `selene src`, `rojo build -o gameplay.rbxlx` (delete output), `lune run tests/run` ("0 failed").
- lobby/: `selene src`, `rojo build -o lobby.rbxlx`.
- common/: copy `gameplay/selene.toml` in, `selene .`, delete the copy.

## Play testing in Studio (lead)
- `list_roblox_studios` (ids change when Studio reopens), `start_stop_play`, `execute_luau` on
  Server/Client, `user_keyboard_input`, `user_mouse_input`, `screen_capture` (no camera positions, or
  unlock the camera after with the CLAUDE.md fix), `get_console_output` for errors.
- Test helpers (workspace attributes, Studio only): `StudioMoney` (coins to everyone), `StudioFill`
  (fraction 0-1). Admin remote: `ReplicatedStorage.Remotes.Admin:FireServer(0.5)` jumps the fill.
- Aiming: the camera ignores PivotTo in first person. To face something, place the character so the
  camera's current LookVector points at it: `pos = target - flat(LookVector) * 8`.
- Proximity prompts only show when the part is in front of the camera (same trick), then hold E.
- Scoop: stand ~9 studs from a Source facing it, hold E 1.5 s. Pour: the empty ocean needs aiming at
  the seabed (stand at e.g. (60,3,-52) facing -Z or lower).
- Studio play writes to the real DataStores (owner's profile has test data; a finished Studio save
  is replaced by a fresh one automatically).
- Watch the console: ignore the known lines (asset 203785492, Atmos plugin); anything else is a bug.

## Scoring (1-10 per line; the lower of yours and a fresh judge's counts if a judge is used)
- Logic: saves can't be loaded by the wrong team or two servers; autosave on timer/leave/close;
  nothing exploitable from the client.
- Feel: scoop, pour, coins, shop, sound, music, lighting work as before.
- Map: matches the planner; nothing floating, no gaps or empty areas.
- UX: a new player knows what to do within 60 s; works at phone size; sunbaked-sea style.
- Code: surgical, no swallowed errors, no duplication, tests never weakened.
8 = all checks pass and no defect a player would notice. Last scores (Phase 1): Logic 8, Feel 8,
Map 8, UX 7.5, Code 8.

## Batch 3b brief (ready to use)
Gadgets from the plan's Phase 3 list, one per area: Water Gun (1, pour from up to 30 studs),
Garden Hose (2, clip to a tap by each pour spot, pour continuously while within reach), Heat Gloves
(3, no steam knockback, hot pools fill faster), Ice Pick (4, fewer hits per ice block), Jetpack Tank
(4, short flights, needed to reach Cloud Catcher), Cloud Net (5, catch a drifting cloud from range).
Add them to `Config.items` (kind "gadget"), sold at their area's stand, levelled in TAB (Gear tab,
already built), used from the hotbar. Heat Gloves / Ice Pick / Cloud Net only matter once 3c adds
steam, ice and clouds: build their stats now and their effect in 3c. Studio: placeholder models in
`ReplicatedStorage.ToolModels.Gadgets`, gear tiles for the new items, taps by each pour spot.

## Known debt
Stages.blend still has pool/lake scenes; client WaitForChild calls without timeouts; three map
textures owned by user 62763090 not the group; a spoon + backpack needs ~50 scoops to fill
(Phase 4 tuning); the simulator doesn't model backpacks; per-area music missing; item tiles show
the "unknown" icon until icons are drawn.
