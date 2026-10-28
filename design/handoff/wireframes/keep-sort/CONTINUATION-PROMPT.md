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

### Visual fidelity — stay wireframe (critical)

Match **existing** `import-wf.html` / `keep-wf.html` look. These are **product wireframes**, not a polished app mock.

- **Ink on paper:** reuse `--ink`, `--mute`, `--bg`, `--line`, `--fill`, `--serif` / `--sans` already on the page. No new palette, gradients, glass, glow, shadows stacks, or illustration.
- **B&W first:** grey/cream/ink only. One functional accent already used (kept green / danger red) — do **not** add more color systems, photo thumbnails, fake Rec.709 previews, or video frames.
- **Tiles = boxes + labels:** empty/grey thumbs, text meta, hairline borders. No stock photos, no blur hashes, no skeuomorphic cards.
- **Type:** existing serif titles + small sans labels. No new fonts, no marketing hero layout.
- **Motion:** none or trivial. No choreographed transitions.
- **Structure over beauty:** if a Harrison/Uday feature needs UI, add the **thinnest** control that proves the grammar (chip, fold bar, titled stack row) — not a new visual language.
- **Do not** restyle the page to look like Lumina Sets/Skim shipping UI, Figma hi-fi, or a dashboard. If you catch yourself polishing, stop and ship the interaction instead.

When unsure: open the current Import page and copy its CSS variables and tile patterns.

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

Do not expand into SPC/VC strategy, app native code, or archive rebuilds unless asked. Be direct; keep MVP tight — killers only. **Prefer ugly-clear wireframe over hi-fi.** If fidelity creeps up, strip back to ink/boxes/labels.
```
