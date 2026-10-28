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
- **Fidelity:** ink/boxes/labels like live Import/Sort — no hi-fi, no photo thumbs, no new palette (see CONTINUATION-PROMPT “Visual fidelity”)

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
| Keep → package that opens in NLE | **Stringout package** — keeps in time order, one timeline, opens in your NLE |

**Effort reason (shared):** open the NLE on selects already in time order, not a flat dump.

**Demo mechanics (wireframe stands the model in):** `HIDDEN_SKEW` is the skew the sync model is told to find (the ssd body stamps +6 min fast; auto-align pulls it back beside the card clips). No real sync model runs in the wireframe.

---

## Done this pass

1. **Consolidated** the Harrison/Uday scene-toggle demos into one self-organising Sort: removed `SCENES`, the toggle UI, and `?scene=`; one dump covers both users.
2. **Auto clock-align** (`autoAlign()`): estimates + applies a per-source offset a beat after the axis paints; pill reports "clocks aligned · N inputs". Per-source −/+ steppers kept as override.
3. **Removed the chapter feature entirely** (owner correction — simplify): no axis chapter headers, no `chapterMap`/binning, no Export chapter list, no rename handler, no `gapMin`/`chapters` state or `.chapter`/`.ch-*`/`.xch` CSS. The axis is just time-stamped runs; the contact sheet keeps the frame.
