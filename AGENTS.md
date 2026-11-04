# Agent instructions: Fill the Ocean

You are implementing work in a Roblox game (Luau, Rojo). Usually the owner plans with another
assistant and hands you a plan file in `docs/plans/`; execute it exactly. Sometimes they ask for a
small change directly (see "Small tasks without a plan"). These rules apply to every task.

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

## Small tasks without a plan
1. Restate the request in one or two lines and list your assumptions. If it is ambiguous (which
   screen? server or client? should others see it?), ask before writing code.
2. Find where it lives with the code map below, and read those files fully before editing.
3. Decide which side owns it: anything that changes money, water, tools or what other players see is
   **server** (`Run.luau`); the client only shows state and sends requests.
4. If it needs anything built in Studio (UI, a part, a remote in the place), say so up front and
   mark it as an Owner step. Code alone can't create it.
5. Make the smallest change that does it, run the checks, then report: what changed, check output,
   what is NOT verified, and any Owner step left (save the place, restart `rojo serve`).

## Code map (gameplay/)
Server (`src/server/`):
- `Run.luau`: the whole run. Phases, per-player state (money, carried, stats, bought items,
  equipped), scoop/pour validation, buying, rewards, publishing attributes. Most gameplay
  changes land here.
- `HeldTools.luau`: puts each player's tool model in their hand so others see it.
- `Map.luau`: checks the baked stages and moves the water.

Client (`src/client/`, all started from `init.client.luau`):
- `Hud.luau`: fills `StarterGui.Hud` (wallet, waiting text, card, results), enables this
  player's prompts, frees the cursor while a window is open. Exposes helpers `Hud.find` (asserting
  path lookup), `Hud.set` (write only on change), `Hud.short` (1.2K), `Hud.money` (12,480).
- `Shop.luau`: the shop window (Tab / gamepad Y / mobile button), next item, coming up, gear.
- `Hotbar.luau`: the one tool slot (1 / gamepad X / click to equip or unequip) and the fill bar.
- `Viewmodel.luau`: first-person tool. `CameraFeel.luau`: first-person camera bob and tilt.
  `Mood.luau`: lighting.

Shared (`src/shared/`, pure unless noted):
- `Config.luau`: every run number (stages, items, prices). Balance changes go here.
- `Ladder.luau`: next item, `upcoming` (what the shop previews; the server's next offer uses it
  too), `kindProgress`, applying an item to stats.
- `Water.luau`, `Rewards.luau`, `ToolView.luau`, `Session.luau`: maths, all Lune-tested.
- `Zones.luau`, `ToolModels.luau`: touch the place (not pure, not tested).

## Server ↔ client contract
The server publishes state as attributes; the client only reads them.
- `ReplicatedStorage` attributes: `Phase` (`waiting`, `playing`, `card`, `saving`, `results`),
  `Stage` (1-3), `Current`, `Target`, `Fill`, `Waiting`, `ReturnAt`, `Difficulty`.
- Player attributes: `Money`, `Carried`, `Capacity`, `WalkSpeed`, `ActSeconds`, `ToolName`,
  `ToolModel`, `ToolTier`, `Equipped`, `NextItemName`, `NextItemCost`, `Bought1`..`Bought3`,
  `Share`.
- Remotes (`ReplicatedStorage.Remotes`, declared in `default.project.json`): `Buy` (no args),
  `Equip` (boolean), `Card` and `Results` (server to client).
- A new attribute: set it in `Run.luau`'s `publish`. A new remote: add it to
  `default.project.json` AND to the `remote(...)` list in `Run.start`, validate its arguments, and
  tell the owner to restart `rojo serve` (a running Rojo does not reload the project file; the
  server errors "missing remote" until then).

## UI
- All UI is built in Studio under `StarterGui.Hud` (Wallet, Hotbar, Shop, Card, Waiting, Results).
  Code never builds new UI (it only clones hidden templates like `Results.RowTemplate`); it finds
  elements by name with `Hud.find` and fills them. Renaming or removing an
  element breaks the client with "Hud is missing ...". New UI elements are an Owner step.
- Look: style `sunbaked-sea` (`C:\RobloxDev\library\ui\styles\sunbaked-sea\style.md`). Colours,
  fonts, image ids, 9-slice settings and motion come from the theme module
  `ReplicatedStorage.Kit.UI.Themes["sunbaked-sea"]` (`C:\RobloxDev\shared\UI\Themes\sunbaked-sea.luau`).
  Never hard-code a colour or image id in game code; read it from the theme.
- The look: a dry cracked-sand frame, wet deep-blue panels, chunky raised pieces with navy outlines,
  Luckiest Guy titles, Fredoka One body text, white text with a navy outline. Tintable images
  (tile, tag, tab, big button) are white; colour them with `ImageColor3` from the theme.
- Windows (anything the player clicks in) must be listed in `Hud.luau`'s `windows` table, so the
  first-person cursor is freed while they are open.
- Tool icons are not drawn yet; slots use the `unknown` image or the tool's 3D model.

## Gotchas (each one has cost time)
- After changing anything in Studio (StarterGui, the map), the owner must **save the place**, or the
  change is lost.
- Uploading images with Open Cloud as `Decal` returns a **decal id**. `ImageLabel.Image` needs the
  image id inside it (load the decal with `InsertService:LoadAsset` and read `Decal.Texture`).
- `ContentProvider:PreloadAsync` reports `Failure` for fresh images when run from a plugin or the
  command bar, even when they work. Check `ImageLabel.IsLoaded` in a play test instead.
- The game is locked first person: `MouseBehavior` is forced to `LockCenter` every frame. To free
  the cursor, override it after the camera runs (see `HudCursor` in `Hud.luau`). Setting
  `GuiButton.Modal` left `MouseBehavior` at `LockCenter` in testing, so don't rely on it.
- Tab opens the shop, so Roblox's player list is disabled in `Shop.luau`. The Board that used to
  show shares is gone.
- Never trust the client: `Equip`, `Buy` and the prompts are all re-checked on the server.

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
- `gameplay/src/shared/` modules that tests cover (Config, Ladder, Water, Rewards, ToolView, Session) must stay
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
