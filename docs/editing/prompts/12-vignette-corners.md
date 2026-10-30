# 12 · Vignette: fitted, plus per-corner pull

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-vignette-corners` from origin/main.

**Goal.** Post-crop vignette fitted to Lightroom, and a vignette you shape by pulling any corner.

**Now.**
- `vig`, `vMid`, `vRound`, `vFeather`, `vHl`; native `VignetteForm` with unfitted `stopsPerUnit` / `highlightsPower`.
- `vigDown(corner)` drags the global amount from any corner.

**Build.**
- **Sweep 11:** Amount ±50/±100 at Midpoint 50, Midpoint 0/100, Feather 0/100, Roundness ±100, Highlights 50 at −50; 30 photos. Fit.
- **Per-corner** (beyond Lightroom):
  - keys `vigc:tl,tr,br,bl` (each a weight 0–200 %, default 100), blended smoothly by angle around the centre;
  - `vigx,vigy` (centre offset).
  - Rest = identity with today's vignette.
  - All three copies, plus tests: symmetric at default, monotonic in each corner weight, continuous in angle.
- **UI (hands-on):**
  - Corner handles: drag one corner to change that corner only. ⌥-drag a corner keeps today's behaviour (all four).
  - Drag the centre dot to move it.
  - Edge midpoints drag feather; ⇧-drag a corner sets roundness.
  - Handles show while the Vignette rows are open or while hovering the frame's corners.

**Done when.** Global vignette parity criteria on sweep 11; per-corner: rest renders identical to before (0 ΔE); measured against a radial-mask equivalent for sanity; canvas latency held.

**Depends on:** 00.
