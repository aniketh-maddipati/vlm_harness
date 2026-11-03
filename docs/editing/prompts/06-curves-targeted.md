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

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Curve (06)*

- **Do:** press on the photo and a point drops on the curve at that tone. Drag ↕.
- **Hands:** the curve panel is one 1 px line over the histogram. Points are magnetic to the original
  line (a detent), and double-click removes one.
  - Luma is the default, so curves never shift colour.
  - R, G and B are behind ⌥ on the panel.
- **Repeat:** each point can be stored at its percentile ("the photo's 20 % tone"), so a curve carries
  across exposures.
- **Polish:** no grid; three faint quarter ticks only.

**Skim (video) mirror.** Skim has no curve. Add RGB / Luma curves to its Light section (1D tables in the shader, like its existing `uLut`). LUT-able. Targeted curve by pressing on the viewer.
