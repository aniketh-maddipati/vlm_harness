# 07 · White balance: pad on the photo

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-white-balance-pad` from origin/main.

**Goal.** White balance as a two-axis pad on the photo, and a better picker.

**Now.**
- Temp/Tint are fitted (2.07/5.66, 1.40/4.11).
- **W** picks white using a stand-in in the page (`pickAt` estimates from position). Plumbing should compute it from the actual pixel.

**Build.**
- **Picker:** `lumina.edit.wbAt(x,y)` reads the pixel (from the rest render or the base, with a 5×5 average), solves `wb`/`tint` so it renders neutral, and returns it. A bridge op, so it needs a row in `TRUST.md`.
- **Pad:** hold **W** and drag anywhere on the photo: x = temperature, y = tint, live on the canvas. Let go to apply; esc cancels. A small crosshair shows the move.
- **Repeat-friendly:** the picked neutral is stored as `wbn:x,y` (relative point) so "same as last" can re-solve WB per photo from the same kind of neutral. This is optional; flag it for prompt 22.

**Done when.** Picker error ≤ 1 ΔE chroma on grey-card shots; the pad drags at canvas latency; HELP updated.

**Depends on:** none.
