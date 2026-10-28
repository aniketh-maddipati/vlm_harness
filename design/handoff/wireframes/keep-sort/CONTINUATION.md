# Continuation — keep-sort wireframes (Harrison + Uday)

**Worktree:** `/Users/aniketh/vlm_harness/.claude/worktrees/keep-input-dock-chron`  
**Branch:** `design/keep-input-dock-chron`  
**Paste prompt:** [`CONTINUATION-PROMPT.md`](CONTINUATION-PROMPT.md)  
**Plan (Input dock — done):** [`PLAN-input-dock-chron.md`](PLAN-input-dock-chron.md)  
**Archetype sketch:** `archive/lumina-minimal-mvp.html` (`harrison`, `uday`)

---

## Locked

- No chip strip under Drop; Files not Phone; Rec.709 default for Log; no FCP/ΔE in shipping UI
- Wireframes only under `design/handoff/wireframes/keep-sort/` unless owner promotes

---

## Done (shared spine)

- Click-enable → Input dock; Drop / AirDrop / Android; Sort now multi-vol handoff
- Sort: union chron, Ready N/M, Kept dock, Export package shell
- README + MODEL-EVAL

```bash
python3 design/handoff/wireframes/keep-sort/hotserve.py --port 8788
```

---

## Consolidated: one product, model-organised

Harrison (A/B-cam + drone, clocks off) and Uday (cam + drone, group by place) are the **same dump with the same needs**, so Sort serves both with models instead of modes. **The scene toggle is gone.** One chronological axis for every docked input, then:

| Need (both users) | How Sort covers it |
|---|---|
| Everything on one time axis | Union chron axis for all docked inputs (existing spine) |
| Clocks agree across bodies | **Auto clock-align** on load — sync model snaps a drifting source onto the axis; pill reads "clocks aligned · N inputs". −/+ chip steppers = manual override |
| Structure that matches the day | **Chapters auto-segment** at a clock-gap threshold (12 min); click a title to rename |
| Keep → package that opens in NLE | **Stringout package** — keeps in time order, chapters listed with kept counts |

**Effort reason (shared):** open the NLE on selects already in time order and grouped, not a flat dump.

**Demo mechanics (wireframe stands the models in):** `HIDDEN_SKEW` is the skew the sync model is told to find (the ssd body stamps +6 min fast; auto-align pulls it back beside the card clips). `state.gapMin` sets the chapter gap. No real sync / segmentation model runs in the wireframe.

---

## Done this pass

1. **Consolidated** the Harrison/Uday scene-toggle demos into one self-organising Sort: removed `SCENES`, the toggle UI, and `?scene=`; one dump covers both users.
2. **Auto clock-align** (`autoAlign()`): estimates + applies a per-source offset a beat after the axis paints; pill reports "clocks aligned · N inputs". Per-source −/+ steppers kept as override.
3. **Chapters always on** (`chapterMap()`): per-clip time-gap binning, renamable titles, listed in Export. Fixed a vet-flagged bug where Export's chapter titles could disagree with the axis (now one shared map).
