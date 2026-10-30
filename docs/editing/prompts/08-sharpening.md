# 08 · Sharpening: radius, detail, masking

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-sharpening` from origin/main.

**Goal.** Sharpening that matches Lightroom's four controls and doesn't sharpen noise or halo.

**Now.** `shp` amount only, unfitted (0.01 / radius 1 / threshold 0.01). Plumbing adds `shp:40` at rest.

**Build.**
- **Keys:** `shp`, `shpr` (radius 0.5–3), `shpd` (detail 0–100), `shpm` (masking 0–100, edge mask).
- **Sweep 8:** Sharpness 40/80/150 × Radius 0.5/1/2, plus Detail and Masking at 2 positions each, **scored on 100 % crops** (exports at full size; crop the same regions).
- RAW 9 interplay: sharpening runs after the decoder's own processing; measure both decoders.
- **UI:**
  - Effects ▸ Detail rows.
  - Hold **⌥** while dragging Masking: the canvas shows the edge mask (white = sharpened), as Lightroom does.
  - The loupe (G held) is where sharpening is judged; show it there.

**Done when.** Parity on 100 % crops; halo score ≤ Lightroom's; region tiles vs export ΔE ≤ 0.5.

**Depends on:** 00.
