# Paste into a new Claude / Cursor chat

```markdown
# Keep-sort wireframes — Harrison + Uday

Repo: `/Users/aniketh/vlm_harness`  
**Worktree:** `.claude/worktrees/keep-input-dock-chron` · branch `design/keep-input-dock-chron`  
Read: `design/handoff/wireframes/keep-sort/CONTINUATION.md`, `README.md`, `PLAN-input-dock-chron.md`, `MODEL-EVAL.md`.  
Archetype reference (archive, not live UI): `archive/lumina-minimal-mvp.html` scenes `harrison` + `uday`.

## Live wireframes (do not abandon)

- `import-wf.html` — sensed cards click → Input dock; Drop / AirDrop / Android; Sort now multi-vol handoff
- `keep-wf.html` — union chron axis; Ready N/M; Kept dock; Export package

```bash
cd /Users/aniketh/vlm_harness/.claude/worktrees/keep-input-dock-chron
python3 design/handoff/wireframes/keep-sort/hotserve.py --port 8788
# Import → Sort boom with 2–3 vols enabled
```

### Locked
- No chip strip under Drop; Files not Phone; Rec.709 default for Log; no FCP/ΔE claim in UI
- Stay in `design/handoff/wireframes/keep-sort/` (no app page promote unless asked)

## Two users the wireframes must serve

### Harrison · doc day
- **Sources:** A-cam + B-cam + drone (clocks off; B often −minutes)
- **Job:** one chron stringout of selects → open in Final Cut
- **Wireframe must show:** multi-vol dock → union time axis → Keep → Export as FCP-oriented package / stringout
- **Killer to wire (MVP):** clock shift that sticks + chron stringout of keepers (scene/beat titles optional)
- **Later (not blocking):** match bodies, stabilize, Premiere XML, VFR

### Uday · hike film
- **Sources:** Sony trail card + Mavic (D-Log); phone optional
- **Job:** group by overlook / chapter → Keep steady takes → FCPXML (or MP4 later)
- **Wireframe must show:** cam + drone on one sheet → stacks/chapters on the axis → Keep → Export
- **Killer to wire (MVP):** stack/chapter by place or time-gap (overlook bins)
- **Later (not blocking):** clean-plate remove hikers, match grade, music, direct MP4

Shared spine both need: Place-off-card intent, display-ready Log, Keep, package that “opens in FCP” as wireframe copy (no ΔE).

## Your job

1. Gap the live Import/Sort HTML vs Harrison + Uday killers above (clock-shift stringout; overlook stacks).
2. Implement the smallest wireframe changes so each path is demoable (scene toggle or seeded dumps OK).
3. Spot-check in the browser; update README if grammar changes.

Do not expand into SPC/VC strategy, app native code, or archive rebuilds unless asked. Be direct; keep MVP tight — killers only, polish later.
```
