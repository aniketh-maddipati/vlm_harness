# Prompt for Cursor: one Auto, from the backend, everywhere

## Why Auto drifts today (root cause)
There are four "Autos" and they disagree:
1. **Native `AutoDevelop.recipe(for:)`** reads RAW ImageStats (scene-linear). It's the only one tuned against the photographer's own edits (LOOPS.md: median |Δexposure| < 0.25 EV against hand-edited XMPs).
2. **The Edit page's `autoOf`** reads the camera's *embedded JPEG*. That JPEG already has the camera's tone curve, its own exposure choices and Sony DRO / Creative Look baked in. Auto then corrects a photo the camera already corrected, so results depend on the camera's picture profile, not on the scene.
3. **Older pages** (Edit v19) used a third formula (`0.5 − p.h`, fixed −22 highlights / +18 shadows). Scene matching and arrival-auto still go through whatever `autoOf` is current.
4. **The render underneath changed** (clamped → AgX in v20, back to clamped now). The same recipe numbers *look* different depending on which render draws them.

Result: the same photo gets different Auto values in the browser, in the app, and from one page version to the next. Even identical values can look different.

**Can we rely on the backend's Auto?** Yes, for the app. It's the only one with RAW data and a fitted, tested formula. The page shouldn't compute Auto at all when the app is there. It should ask.

## Do this (change nothing else)
1. **Bridge:** add `lumina.auto(rel) → Promise<{look:{ev,wb,tint,hl,sh,wh?,bl?,con?}, version:string}|null>`.
   - The values are exactly what AutoDevelop applies, in the Edit page's slider units: `ev` in stops, `wb` in K, `tint` and `hl/sh/wh/bl/con` on the −100…100 scale.
   - The page already calls it (Edit v21 `autoRecipe()`); `version` is shown nowhere yet, so just return it.
   - Add the call to BRIDGE.md and to probe.sh's contract list.
2. **Fixtures for the browser:** write `data/auto-fixtures.js` defining `window.LuminaAutoFixtures = { "DSC06175.ARW": {ev,wb,tint,hl,sh}, … }`. Use AutoDevelop's real output for every sample-shoot file (the RAWs behind uploads/DSC*.jpg) and for the 8 ARW fixtures. Regenerate it whenever AutoDevelop changes (`make auto-fixtures`). Load it in the `<helmet>` of Lumina Edit v21 and Sets v7 with `<script src="data/auto-fixtures.js"></script>`. Add the tag only once the file exists, so the browser never gets a 404.
   - With this file loaded, the browser design shows the **real** Auto, not an estimate.
3. **One Auto for everything:** arrival-auto (`autoArrive`), the A key and scene matching (`matchScene`: ev/wb deltas between two photos) must all use `lumina.auto` (or the fixture) when available. Cache per file + AutoDevelop version.
4. **Render:** keep `rules-v1.json` (Lightroom-match, held-out ΔE 2.32 / 7.82) as the default render. Auto values are tuned against it. Don't re-tune Auto against the AgX preview.
5. **Tests:**
   - The Auto loop in LOOPS.md stays the acceptance gate.
   - Add a probe: for 5 sample files, `lumina.auto` equals the fixture.
   - Add a probe: in the app, the Edit footer says "Auto ·" and never "Auto (estimate)".

## What the page does now (already in Edit v21)
- A asks `lumina.auto` first, then `window.LuminaAutoFixtures`, and only then falls back to its JPEG estimate.
- The footer names the source: "Auto · …" when it's the backend, "Auto · recorded" when it's a fixture, "Auto (estimate) · …" when it's the fallback. That way an estimate can never pass for the real thing.
