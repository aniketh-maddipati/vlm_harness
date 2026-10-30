# 04 · HSL fitted, B&W mixer

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-hsl-bw` from origin/main.

**Goal.** The 8-band HSL mixer fitted to Lightroom, and a real B&W mixer.

**Now.** `hue_*` / `sat_*` / `lum_*` on the page, `mixh/s/l` natively (`LookMath.mixer` ~:481, Oklab bands), with unfitted round per-unit values. B&W is chroma → 0.

**Build.**
- **Sweep 5:** 8 hues × (H ±50, S ±50, L ±50) = 48 presets, on photos that contain each hue. Choose per photo, as sweep 3 does for white balance; a script picks them from hue histograms. Add the B&W mixer positions too (Lightroom's B&W mix per colour at ±50).
- Fit band centres, widths and per-unit strengths. Keep bands a partition (no gaps or double counting between neighbours). Score hue stability outside the band (isolation in hue).
- **B&W:** `bw` plus `bwmix_<colour>` (luminance by hue before chroma → 0).
- **UI:**
  - The Colour section's tabs already exist. Add a B&W tab when `bw` is on.
  - **On-photo gesture:** ⌥-drag on a colour in the photo already moves HSL. Make sure it moves Hue (↔), Saturation (↕) and Luminance (⇧↕) per the active tab, and works for B&W mix too.

**Done when.** Parity criteria per band on sweep 5; isolation: neighbouring hues move ≤ Lightroom's; held-out within tolerance.

**Depends on:** 00.
