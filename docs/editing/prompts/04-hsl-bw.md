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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Colour: HSL and B&W (04)*

- **Do:** press on a colour in the photo. A short arc of the hue ring appears around the puck, showing
  that colour's band.
  - Drag ↔ slides the colour along its arc (hue).
  - Drag ↕ = saturation; ⇧↕ = luminance.
  - The other pixels of the same band pulse once, so you see what else will change.
- **B&W:** the same press-and-drag ↕ makes that colour's grey lighter or darker, like a coloured filter
  on the lens. The puck shows the filter's colour chip.
- **Repeat:** a hue band is the same on every photo, so it carries naturally. Skin protection is on
  when the band crosses skin.
- **Polish:** the eight colour dots in the panel are the only colour in the UI; the active one gets a
  gold ring.

**Skim (video) mirror.** Skim's Mix already has 8 hue bands, in HSV with round strengths. Replace them with the fitted Oklab bands, so stills and video agree, and add the B&W mix. LUT-able: goes in the shot's `.cube`. ⌥-drag on a colour in the viewer.
