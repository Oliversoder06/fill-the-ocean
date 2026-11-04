# Agent instructions: Fill the Ocean

You are implementing work in a Roblox game (Luau, Rojo). The owner plans with another assistant and
hands you a plan file in `docs/plans/`. Execute it exactly. These rules apply to every task.

## Read first
- `CLAUDE.md`: what the game is, the two places (`lobby/`, `gameplay/`), what Rojo owns, the checks.
  It overrides everything below except the safety rules.
- `docs/design/2026-11-04-fill-the-ocean-design.md`: the design the plans implement.
- The plan you were given. Do one task at a time, in order, step by step.

## How to execute a plan
- Follow each task's steps in order. Where a step says "write the failing test", write it, run it,
  and confirm it FAILS before writing the code.
- Every step with a command has an `Expected:` line. Run the command and compare the real output.
  If it doesn't match, stop and fix the cause. Never change the expected output or the test.
- Use exactly the file paths, names, signatures and values the plan gives. Don't rename things.
- If the plan is wrong or impossible, stop and write down what's wrong and what you'd do instead.
  Don't silently do something else.
- Steps marked **Owner step** are done by the owner in Roblox Studio. Stop there and ask them.
- At the end of each task, list what you changed and paste the check output.

## Hard rules (never break these)
- **Never edit, delete, skip, weaken or special-case a test** to make it pass. If a test looks wrong,
  stop and tell the owner. New tests the plan asks for are fine.
- **No silent error swallowing:** no empty `pcall`, no ignoring errors. Fail loudly with a clear message.
- **No new dependency** (package, tool, plugin) without asking the owner first.
- **Surgical changes:** only change what the task needs. Don't refactor or reformat other code.
  Put new code next to related code, not at the end of a file.
- **Don't touch** `lobby/` unless the plan says so. Don't touch `C:\RobloxDev\shared` (it affects
  every game) unless the plan says so.
- Don't commit or push unless the owner asks.
- Never wait more than 2 minutes on one command. If it hangs, stop it and say so.

## Checks (run inside `gameplay/` after every task that touches it, and show the output)
- `selene src`: must print `0 errors`, `0 warnings`.
- `rojo build -o gameplay.rbxlx`: must succeed.
- `lune run tests/run`: must end with `N passed, 0 failed`.
Say "done" only after all three pass. Also say what you could NOT verify (for example, anything that
needs a Studio play test).

## Roblox rules for this codebase
- Rojo owns code only. The map, terrain and scenery live in the Studio place; the owner saves and
  publishes it in Studio.
- `gameplay/src/shared/` modules that tests cover (Config, Ladder, Water, Rewards, ToolView) must stay
  **pure**: no `require` of other modules, no `game`, no Roblox types, so Lune can run them.
  Lune tests live in `gameplay/tests/*.spec.luau` and are listed in `gameplay/tests/run.luau`.
- Server-authoritative: the server owns money, water, purchases. Validate every remote argument
  (type and allowed values) and rate-limit anything a client can spam.
- `FindFirstChild` results must be nil-checked before use (or use `Zones.part`, which asserts).
- Never yield (`WaitForChild`, `task.wait`) inside `RenderStepped` / `BindToRenderStep` callbacks.
- Write Roblox properties only when the value changes in per-frame code.
- Filling is never automatic: water only moves when the player completes a hold prompt.
- For Roblox API facts, check the LihFolk vault:
  `C:\Users\lexru\.claude\plugins\cache\lihfolk\lihfolk\2.5.0\LihFolk Vault V2\` (search it by keyword).
- The owner's taste and numbers: `C:\RobloxDev\library` (rules in `LIBRARY-RULES.md`).
  Order of authority: this game's `CLAUDE.md` > the library > the LihFolk vault.

## Style
- Luau, tabs, existing naming (PascalCase modules, camelCase locals, UPPER_CASE constants).
- Short comments that say why, not what.
