# 13 · Grain

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-grain` from origin/main.

**Goal.** Film grain that looks like grain at every zoom and on export, scored by statistics.

**Build.**
- **Keys:** `grn` (amount 0–100), `grns` (size), `grnr` (roughness).
- **Form:** luminance-weighted (strongest in mids), seeded per photo (so it's stable while dragging and on re-export), and the same at every tier. Grain must scale with output size, not canvas size: define it in photo pixels.
- **Sweep 12:** Amount 25/50/100 × Size 25/75 × Roughness 25/75 on 10 flat and mid-grey photos. **Score by power spectrum and variance per luma band, not ΔE** (grain is random).
- **UI:** Effects ▸ Grain rows. Judged in the loupe; the canvas at fit shows it decimated honestly (say so in the hover text).

**Done when.** Spectrum and per-band variance within 10 % of Lightroom's at each position; canvas ≡ export statistics; deterministic per seed.

**Depends on:** none.
