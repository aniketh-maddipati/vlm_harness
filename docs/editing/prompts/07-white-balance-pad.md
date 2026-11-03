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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*White balance (07)*

- **Do:** tap something that should be neutral: done. (W, then tap.)
- **Hands:** hold **W** and drag. A soft field appears under the finger, blue ↔ amber across and green
  ↔ magenta up and down, with a crosshair. Detent at as-shot.
- **Repeat:** stored as "neutral on this kind of thing" (grey card, white shirt). On other photos it is
  re-picked from the same object where it can be found; otherwise the Kelvin move from as-shot carries.
  Video: per shot, before the log transform.
- **Polish:** the field is 120 px at 30 % opacity; the photo stays visible through it.

**Skim (video) mirror.** Skim has temp/tint. Add the W pad and the picker on the viewer frame. For S-Log3 clips the white balance runs before the Rec.709 transform (scene-linear), not on display values. Note it where the stills form differs. LUT-able.
