# Handoff: scene-referred tone mapper

**Status:** prototyped in `Lumina Edit v20.dc.html` (browser preview only). The native pipeline still ends in a clamp. Toggle in the prototype: **⇧T** switches between *tone mapper* (default) and *Lightroom-style (clamped)*.

## Why
- The current native pipeline (`rules-v1.json`, `outputTransform`) clamps to 0–1 and then encodes sRGB. Anything brighter than white is thrown away instead of rolled off.
- Exposure and highlights act **per channel**. Bright skin drifts yellow and bright skies drift cyan.
- The held-out error is worst in the bright deciles: 3.3–4.7 ΔE above L* 60, against 1.9 in the shadows.

## Target pipeline (native: `LookMath`, `LookKernels`, `lookmath.py` change together)
1. **RAW → linear, unclamped.** The working space is extended linear sRGB. Rebuild clipped channels first; check Core Image's RAW options before writing our own.
2. **White balance**, then **Exposure as a plain linear gain** with no curve.
3. **Highlights / Shadows**: local exposure in log space. The existing relative-to-photo masks stay.
4. **Display transform** (replaces the clamp):
   - inset matrix (sRGB → AgX working space)
   - `v = (log2(max(x,1e-10)) − min) / (max − min)`, clamp to 0–1
   - sigmoid (the AgX default-contrast polynomial)
   - outset matrix
   - display encode (≈ γ 2.2 / sRGB)
5. **Slider mapping into the transform**:
   - **Whites** moves `max`, **Blacks** moves `min`. They're no longer separate curves.
   - **Contrast** is the sigmoid's slope around middle grey: `v' = mid + (v − mid)·k`.
   - The **Tone curve** runs after the display transform (display-referred), as now.

## Constants used in the prototype
- Inset (rows): `0.842479 0.078434 0.079224 / 0.042328 0.878469 0.079166 / 0.042376 0.078434 0.879143`
- Outset (rows): `1.196879 −0.098021 −0.099030 / −0.052897 1.151903 −0.098961 / −0.052972 −0.098043 1.151074`
- Sigmoid: `15.5x⁶ − 40.14x⁵ + 31.96x⁴ − 6.868x³ + 0.4298x² + 0.1191x − 0.00232`
- Native log window: `min −12.47393`, `max +4.026069` stops (scene-linear input).
- Prototype window: `min −10`, `max +1` plus a power fit that holds mid-grey. The preview JPEGs are already display-referred, so this one is **for the browser only, do not port**.
- Slider ranges in the prototype: Whites ±1.5 stops on `max`, Blacks ±2.5 stops on `min`, Contrast slope ×(1 ± 0.6).

Source: Troy Sobotka's AgX and the minimal-AgX GLSL write-ups. **Verify the licence of whichever write-up the constants are taken from before shipping.** RapidRAW is AGPL: ideas only, cited in a comment, never code.

## How the prototype does it (so it can be read, not copied)
- An SVG filter `#lum-agx` runs with `color-interpolation-filters="linearRGB"`, so the browser linearises for us:
  1. `feColorMatrix` (inset)
  2. `feComponentTransfer` with a 256-entry table holding gain → log window → contrast → sigmoid, combined
  3. `feColorMatrix` (outset)
  4. γ 2.2
- Exposure, Contrast, Whites and Blacks are removed from the CSS filter approximation and live in that table. Highlights and Shadows stay as before.
- The histogram re-maps through the same table, so it matches the photo.

## Acceptance (from the project rules)
- Held-out set must stay within **+0.05 median / +0.10 p95 ΔE** of the baseline (2.32 / 7.82).
- Score by brightness decile. Expect gains above L* 60 and possible losses in the mids.
- If the better-looking mapper costs more than the tolerance, the owner decides between "matches Lightroom" and "looks best". The tolerance is the owner's to change.

## Order of work
1. Sigmoid display transform in place of the clamp, as a setting in the rules file. Nothing else changes.
2. Score it by decile and show before/after on high-range frames (the Teton sunsets).
3. If it holds, move Exposure's per-channel curve into the mapper and refit the stages.
4. Then tools the edits actually use: dehaze (15 of 109), texture (9), profiles (6), tone curve, HSL.
