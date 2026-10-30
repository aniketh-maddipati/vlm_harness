# 06 · Curves: fit regions, luma mode, drag on the photo

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-curves-targeted` from origin/main.

**Goal.** Curve regions (`cDark/cMid/cLight`) fitted to Lightroom's parametric curve, a luma-only point-curve mode, and a targeted curve on the photo.

**Now.** Point curves RGB+R/G/B (`curve*`, Fritsch–Carlson 256-node LUT, `LookMath.curveTables`) are exact. The region sliders are unfitted. No luma-only mode.

**Build.**
- **Sweep 7:** Lightroom's parametric Darks/Shadows/Lights/Highlights at ±50 and the split points, then fit region shapes and strengths.
- **Luma mode:** `curveY` applies the curve to luminance and keeps chroma (Oklab L, or a ratio on RGB), so curves no longer shift saturation. Measure hue and saturation stability against the RGB curve.
- **UI:**
  - The curve editor gets an RGB / Luma / R / G / B selector.
  - **Targeted curve on the photo:** with Curve open, press on the photo. A point appears on the curve at that pixel's tone; drag ↕ moves it. ⇧ fine, double-click removes the point.

**Done when.** Region parity criteria on sweep 7; luma mode: hue drift ≈ 0 and saturation within 2 % on ramps; the gesture works on the canvas and in the image fallback path.

**Depends on:** 00.
