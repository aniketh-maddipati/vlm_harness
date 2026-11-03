# 10 · Lens: distortion and chromatic aberration

Run the agent loop in `docs/editing/prompts/LOOP.md` for this feature (read it first; it holds the steps, checks, stop rules and finish). Branch `claude/edit-lens-corrections` from origin/main.

**Goal.** Lens distortion and lateral CA corrected from Sony's own EXIF numbers. No lensfun (its database is CC BY-SA, a licence question avoided).

**Now.** Only vignetting, via `LookLensShading` (Sony `VignettingCorrParams`, coefficient `lensShading`).

**Build.**
- Read Sony `DistortionCorrParams` and `ChromaticAberrationCorrParams` (the same parser as shading; check the tags with exiftool on the golden ARWs).
- Distortion is a radial warp, CA a per-channel radial scale. Both go in `geometryPlaced` before crop, so crop and masks stay aligned (`PhotoMasks`). Auto-crop to the valid area.
- **Keys:** `lens:auto` (default on when the tags exist), `dist` (manual ±100), `ca:0|1`.
- **Data:** Lightroom "Base + lens profile" already exists in sweep 1; add AutoLateralCA on and Distortion ±50 manual (sweep 10). Compare geometry with straight-line residuals on architecture frames, not ΔE.
- **UI:** a Lens row in Effects (auto toggle, distortion slider, CA toggle). The facts line says when a lens has no tags.

**Done when.** Straight-line residual ≤ Lightroom's profile on 20 frames; CA fringe width ≤ 0.5 px at the corners; masks and crop stay aligned in tests.

**Depends on:** none.

**UX** (from `docs/editing/UX.md`; this section is the UI spec, and where the UI bullets above differ, it wins). Built on the shared hand kit (prompt 00c: puck, detents with haptics, pinch / rotate / pressure, chrome dim, hover handles, select-then-touch carry, the fan); use its pieces, don't rebuild them. Everything follows UX.md's grammar and polish tokens.

*Lens (10)*

- **Do:** nothing. Corrections apply from the camera's own data; the facts line says `lens ✓`.
- **Hands:** to fix a line that should be straight, press its middle and drag it straight (a bend
  handle). Lumina fits the distortion to that.
- **Repeat:** automatic per lens.
- **Polish:** no panel unless asked; one toggle row.

**Skim (video) mirror.** Check whether Sony XAVC clips carry lens correction data in their NRT XML sidecar (`a7m3-day1` fixtures have sidecars) or in the stream. If they do, preview the correction in Skim and note that Final Cut can't apply it from metadata: preview only, or a native render later. Report what was found; no build if there's no data.
