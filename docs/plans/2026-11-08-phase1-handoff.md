# Phase 1 handoff (2026-11-08)

## State
- Phase 1 Tasks 1-8 + UX pass are built and reviewed. Final branch: `phase1/ux` (2d6e8c9).
- Owner's checkout `C:/RobloxDev/games/fill the ocean` is DETACHED on 2d6e8c9 so Rojo syncs it to Studio.
  The owner's old uncommitted work is in `git stash` (stash@{0}) and on branch `phase1/base`.
- Worktrees `C:/RobloxDev/games/fto-*` (one per branch; must stay at that depth so `../../../shared` resolves).
  `fto-r2-logic` / `fto-r2-ux` are clean, unused (branches phase1/r2-logic, phase1/r2-ux = 2d6e8c9).
- Nothing merged to main, nothing pushed or published.
- Studio: owner steps done; removed objects are in `ServerStorage.Phase1Removed_2026_11_07` (attr Phase1RemovedFrom).
  Map fixes applied (textures re-uploaded, backdrop lowered, 2 palms). A stopped Studio agent may have made
  partial edits (guide art / spawn rotation): check. OWNER: File > Save to Roblox on the gameplay place.

## Round 2 (same day, later session)
- Branch `phase1/r2-logic` (worktree fto-r2-logic): bb470d3 logic fixes 1-3, 883c450 UX fixes 4-8.
  Owner checkout detached on 883c450. Fixes 1-8 done and play-tested in Studio; 9 and Map not done.
- Fix 2 deviates from the plan: payment is once per run key in the PLAYER's progress
  (Progress.paidRuns, atomic with the Raindrops), not a `paid` list in the run save (that could pay
  twice if the run-save write failed after paying). Lobby Profiles pays owed finished runs on join.
- Studio edits (unsaved until the owner saves): Shop BuyButton/CloseButton.HitPad, GuideMarker.Arrow
  + Vfx.GuideBeam art (rbxassetid://98321197591480 / 74290839834375, art/Guide*.png, library icons.md),
  PourPoint.GuideTarget moved onto floodable seabed (60,-3.5,-64), Spawn + SpawnLocation face the well.
- Still open: spawn sits under the beach umbrella (pole fills the first view: move it, map planner first);
  screen_capture doesn't draw BillboardGuis, so the marker/beam were checked by properties only.

## Scores so far (lower of judge and lead): Logic 7, Feel 7, Map 7, UX 6.5, Code 8. Target 8+.

## Fix list (do these, few agents or inline)
Logic (lobby/src/server/Queue.luau, gameplay/src/server/Run.luau, common/RunSave.luau + tests):
1. Create Party: if the team already has a save on that map, refuse before teleport ("already filled" if
   finished, "load it from Saved Runs" if not). Queue.luau ~393.
2. Ending payout: if saveNow times out (Run.luau ~387) don't assume unfinished; keep a per-member `paid` list
   in the save (sanitize + test) and pay unpaid members on next open/lobby join (also covers clearMap failures, ~381).
3. Studio only: a finished save blocks testing and logs a wrong "needs API access" message. In Studio start a
   fresh save in its place and log it clearly.
UX (gameplay/src/client/*, Guide.luau, Shop.luau, Hud.luau):
4. Guide step 1 shows no direction: GuideMarker Arrow image and GuideBeam texture are empty in Studio. Add art
   (sunbaked-sea: #FFB23F, outline #1B2A3A), point marker/beam at the well, then at a pourable seabed spot.
5. Empty ocean: at the shore "Aim at the water" with no water; at default pitch the aim never hits the slope.
   While the ocean is low and aim misses, hint "Look down at the dry seabed". Don't change pour rules/reach.
6. Shop touch targets < 44 pt on phones (CloseButton, Detail.BuyButton): fix Shop DESIGN_SIZE / enlarge in Studio.
7. Guide "take out your tool" hint: gamepad text (ButtonX) like openText().
8. Spawn faces inland under the umbrella: rotate Ocean.Spawn/SpawnLocation to face the well/sea.
9. Lobby partyIcon / savedRunsIcon / map thumbnails are placeholders.
Map: map review leftovers (aqueduct post clearance near (36,12), headland-cliff joins z -130..-50).

## After fixing
Checks (2-min timeout each): `selene src` + `rojo build` in gameplay/ and lobby/; `lune run tests/run` in
gameplay/ ("0 failed"); common/: copy gameplay/selene.toml in, `selene .`, remove it.
Then set the owner's checkout to the new commit (`git switch --detach <commit>`), playtest in Studio
(gameplay studio id via list_roblox_studios): scoop at well (stand at (60,6,41) facing -Z), pour near
(60,3,-52), TAB shop, buy Cup, Admin remote FireServer(0.5/0.95/1) for fill and ending. Note: Studio play writes
to the real DataStores (owner profile already shows map1 cleared, 225 Raindrops from tests).

## Debt noticed
Water.rescale orphan; Stages.blend still has pool/lake; angry-sun PNG in art/; CLAUDE.md names an old backup;
client WaitForChild calls without timeouts; Hud.REACH duplicates server ACT_REACH; new textures owned by user
62763090, not the group.

Details of earlier results: `C:/Users/lexru/AppData/Local/Temp/claude/2a7cc7c6701c7ee1/bf3d4ff8-b385-4fd7-b599-8a5373a91f61/scratchpad/wf1/`
(judge_round1.json, ux_review_last.json, map_review_last.json, lead_playtest_round1.md, ux_spec.json).
