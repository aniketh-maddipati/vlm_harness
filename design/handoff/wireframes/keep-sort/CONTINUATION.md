# Continuation — Input dock + chron Sort

**Worktree:** `.claude/worktrees/keep-input-dock-chron`
**Branch:** `design/keep-input-dock-chron`
**Plan:** `PLAN-input-dock-chron.md` (saved copy of the Cursor plan)

## Locked (do not re-litigate)

- No Cards & volumes / `sd*` chip strip under Drop
- Files not Phone; Rec.709 default for Log; no “matches FCP” / ΔE in shipping UI
- Do not pop `stash@{0}` SetsPrecompute unless owner asks

## Done on this branch

- Click-to-enable sensed cards → Input dock
- Drop / AirDrop / Android → dock tiles; Sort now multi-vol handoff
- Sort: union chron axis, Ready N/M, unread→develop, inbound append demo
- README + MODEL-EVAL lock-ins

## Run

```bash
cd /Users/aniketh/vlm_harness/.claude/worktrees/keep-input-dock-chron
python3 design/handoff/wireframes/keep-sort/hotserve.py --port 8788
# → http://127.0.0.1:8788/import-wf.html
```

## Next (iterate)

Polish Input dock UX, inbound demo, Sort fold-bar chips, and any chron/preprocess copy — stay in wireframes under `design/handoff/wireframes/keep-sort/`.
