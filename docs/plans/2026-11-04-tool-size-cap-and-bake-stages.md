# Tool Size Cap and Baked Stages Implementation Plan

> **For agentic workers:** follow `AGENTS.md`. Do the tasks in order. Steps use checkbox (`- [ ]`)
> syntax. Run every command and compare it to its `Expected:` line.

**Goal:** (1) Big tools never cover too much of the screen, in first person or in other players'
hands. (2) The three stages become real parts in the Studio place instead of being built by code
at runtime.

**Architecture:** A new pure module `ToolView` holds the size maths (Lune-tested). `Viewmodel` (client)
and `HeldTools` (server) use it. For the stages, the owner runs the existing builder once in Studio
edit mode and saves. Then `Map.luau` stops building and only checks that the Studio stages have the
parts the game needs.

**Tech Stack:** Luau, Rojo, selene, Lune 0.11.1.

**Spec:** `docs/design/2026-11-04-fill-the-ocean-design.md`, plus the owner's requests on 2026-11-04:
"big tools cover too much of the screen" and "why build the map during play instead of in the map".

## Global Constraints
- Only touch the files listed in each task. Work inside `gameplay/`.
- Checks after every task: `selene src` clean, `rojo build -o gameplay.rbxlx` succeeds,
  `lune run tests/run` all pass.
- Don't change any existing test.

## Review Focus
1. **The Moon (the last tool) in first person** must stay in the lower right and must not exceed 1.7
   studs on its longest side. Pinned by `ToolView` tests in Task 1.
2. **A 14-stud cargo ship in another player's hand** must be scaled down to at most 6 studs. A small
   spoon must NOT be scaled up. Pinned by the `heldScale` tests in Task 1.
3. **Deleting the builder before the stages are saved in the place would delete the map.** Task 2
   orders it so the bake and save are confirmed first.
4. **A stage model missing a part** (for example, someone deletes `PourPoint` in Studio) must fail at
   server start with a clear message naming the stage and the part. Pinned in Task 2, Step 6.

---

### Task 1: Cap tool size (first person and in hand)

**Files:**
- Create: `gameplay/src/shared/ToolView.luau`
- Create: `gameplay/tests/ToolView.spec.luau`
- Modify: `gameplay/tests/run.luau` (add `"ToolView"` to the `SPECS` list, after `"Rewards"`)
- Modify: `gameplay/src/client/Viewmodel.luau` (use `ToolView.viewSize`)
- Modify: `gameplay/src/server/HeldTools.luau` (scale the held clone with `ToolView.heldScale`)

**Interfaces:**
- Produces, in `ToolView` (pure, no requires):
  - `ToolView.VIEW_START = 0.8`, `ToolView.VIEW_MAX = 1.7`, `ToolView.VIEW_GROWTH = 0.85`,
    `ToolView.HELD_MAX = 6`
  - `ToolView.viewSize(tier: number): number` returns
    `VIEW_MAX - (VIEW_MAX - VIEW_START) * VIEW_GROWTH ^ (tier - 1)`.
    Tier 1 = 0.8. It grows with every tier and never reaches 1.7.
  - `ToolView.heldScale(longestSide: number): number` returns `math.min(1, HELD_MAX / longestSide)`.
    It never scales up.
- Consumes: `ToolModels.order(Config)` (already exists) gives the tier index of each tool.

- [ ] **Step 1: Write `gameplay/tests/ToolView.spec.luau`.** Same format as the other specs: it returns a table of
  `function(t)` tests using `t.expectEq` / `t.expectNear`, and requires `"../src/shared/ToolView"`.
  - `first_tool_starts_small`: `t.expectNear(ToolView.viewSize(1), 0.8, 1e-9)`
  - `grows_every_tier`: for tier 2..20, `viewSize(tier) > viewSize(tier - 1)` (error otherwise)
  - `moon_stays_under_cap`: `viewSize(20) < 1.7`, and `t.expectNear(viewSize(20), 1.659, 0.001)`
  - `held_scales_down_big_tools`: `t.expectNear(ToolView.heldScale(14), 6 / 14, 1e-9)`
  - `held_never_scales_up`: `t.expectEq(ToolView.heldScale(1.2), 1)` and `t.expectEq(ToolView.heldScale(6), 1)`
- [ ] **Step 2: Add `"ToolView"` to `SPECS` in `gameplay/tests/run.luau`.** Run `lune run tests/run` inside `gameplay/`.
  Expected: `FAIL ToolView.spec (load): ... could not resolve child component "ToolView"`, and every
  other test passes.
- [ ] **Step 3: Create `gameplay/src/shared/ToolView.luau`** with the constants and the two functions above
  (`--!strict`, a short header comment: "Pure size maths for held tools. Lune-tested.").
- [ ] **Step 4: Run** `lune run tests/run`. Expected: all tests pass, including 5 `ToolView` tests.
- [ ] **Step 5: Use it in `Viewmodel.luau`.**
  - Require `ReplicatedStorage.Shared.ToolView`.
  - Delete the constants `VIEW_SIZE_START` and `VIEW_SIZE_PER_TIER`.
  - In `load`, replace the `viewSize = ...` line with
    `viewSize = ToolView.viewSize(tierOf[modelName] or 1)`.
  - Leave the rest (offset maths, pose, water) unchanged.
- [ ] **Step 6: Use it in `HeldTools.luau`.**
  - Require `ReplicatedStorage.Shared.ToolView`.
  - In `refresh`, right after `local model = ToolModels.get(modelName):Clone()`, add:
    ```lua
    local extents = model:GetExtentsSize()
    local scale = ToolView.heldScale(math.max(extents.X, extents.Y, extents.Z))
    if scale < 1 then
    	model:ScaleTo(scale)
    end
    ```
    (before the `PivotTo` line).
- [ ] **Step 7: Run the checks** inside `gameplay/`: `selene src`, `rojo build -o gameplay.rbxlx`, `lune run tests/run`.
  Expected: `0 errors`/`0 warnings`, the build succeeds, all tests pass.
- [ ] **Step 8: Owner step (Studio play test).** Press Play. In the command bar (Server), run
  `game.Players:GetPlayers()[1]:SetAttribute("ToolName", "The Moon")`. Expected: the first-person
  tool stays in the lower right without covering the view, and the tool welded in the character's
  hand is no longer than 6 studs. Then set it to `"Spoon"`. Expected: small, same as before.

### Task 2: Bake the stages into the place, then stop building them in code

**Files:**
- Modify: `gameplay/src/server/Map.luau`
- Modify: `CLAUDE.md` (Studio section: one line saying the stages now live in the place)

**Interfaces:**
- `Map.ensure(config): Folder` keeps its name and return value, but it no longer builds anything. It
  returns `workspace.Stages` after checking that every stage has its required parts. It errors
  clearly if anything is missing.
- `Map.setFill(stage: Model, fraction: number)` stays exactly as it is.
- The map contract (header comment in `Map.luau`) stays. Each stage Model is named after
  `config.stages[i].name` and has `Spawn`, `Source`, `PourPoint`, `Basin` and `Water` (with a
  number attribute `Depth`). Run, Zones and Hud already rely on these names.

- [ ] **Step 1: Owner step (bake in Studio).**
  - Stop any play test. Make sure Rojo is connected to `gameplay/` (port 34873) so the current code
    is in the place.
  - Make sure `workspace` has no `Stages` folder.
  - Run this in the Studio command bar (edit mode):
    ```lua
    require(game.ServerScriptService.Server.Map).ensure(require(game.ReplicatedStorage.Shared.Config))
    ```
  - Expected: `workspace.Stages` appears with `Pool`, `Lake`, `Ocean`, each with Ground, Basin,
    Wall, Rim, Guard, Water, PourPoint, Source and Spawn parts, and the pool hole is cleared in the
    terrain.
- [ ] **Step 2: Owner step (save).** Save and publish the place. Then confirm `workspace.Stages`
  is still there after reopening the place. **Do not continue until the owner confirms.**
- [ ] **Step 3: Replace the builder in `Map.luau`.**
  - Delete `SPACING`, `WALL`, `SIZES`, `RIM`, the `part` helper and `buildStage`.
  - Keep the `Zones` require and the header contract comment. Change the first header line to:
    "Stages live in the Studio place (workspace.Stages). This module checks them and moves the water."
  - New `Map.ensure`:
    ```lua
    local REQUIRED = { "Spawn", "Source", "PourPoint", "Basin", "Water" }

    function Map.ensure(config): Folder
    	local folder = workspace:FindFirstChild("Stages")
    	assert(folder and folder:IsA("Folder"), "workspace.Stages is missing: build the stages in Studio")
    	for _, stage in config.stages do
    		local model = folder:FindFirstChild(stage.name)
    		assert(model and model:IsA("Model"), `workspace.Stages is missing stage {stage.name}`)
    		for _, partName in REQUIRED do
    			Zones.part(model, partName) -- asserts with the stage and part name
    		end
    		assert(
    			type(Zones.part(model, "Water"):GetAttribute("Depth")) == "number",
    			`Stage {stage.name}: Water needs a number attribute "Depth"`
    		)
    	end
    	return folder
    end
    ```
  - `Map.setFill` is unchanged.
- [ ] **Step 4: Run the checks** inside `gameplay/`: `selene src`, `rojo build -o gameplay.rbxlx`, `lune run tests/run`.
  Expected: clean, the build succeeds, all tests pass.
  (selene may warn that `config` is unused if you typed the code differently; it is used in the loop.)
- [ ] **Step 5: Update `CLAUDE.md`.** In the `## Studio` section, after the line about the map and StarterGui,
  add: "- The stages (`workspace.Stages`: Pool, Lake, Ocean) live in the place. Code only checks them
  (`gameplay/src/server/Map.luau`) and fails at start if a required part is missing."
- [ ] **Step 6: Owner step (Studio play test).**
  - Press Play. Expected: the run starts in the pool exactly as before (scoop, pour, the water
    rises), and the Output shows no errors.
  - Then stop, rename `workspace.Stages.Pool.PourPoint` to `PourPointX`, and press Play.
    Expected: the server errors with `Stage Pool is missing part PourPoint`.
  - Rename it back, and save the place.
