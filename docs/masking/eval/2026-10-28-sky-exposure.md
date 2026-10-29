# Blue skies + exposure — 2026-10-28

One feature family on the parts Lumina already has: the develop's pixels, `LookMath.DisplayMapper`,
`LookMasks.sky`, the exposure / highlights stages and `mask:` locals, plus a clip measurement.
Everything is behind one flag (`Look.skyFeatures`, `LUMINA_SKY=1`, Debug builds and the tools
only; Release is always off). `rules-v1.json` is untouched (`mapper: clamp`). No model, no VLM
call, no fit. Evidence: `~/LuminaEvidence/skyeval/` (renders, masks, sheets; nothing in git).

Code: `Lumina/Sets/Look/LookSky.swift` (Foundation: F1 verdict, F2 meter, F5 target, F6 text),
`LookSkyClip.swift` (Core Image: the clip maps), `LookMath.skyBlue` + kernel `lookSkyBlue` +
`lookmath.sky_blue` (F4, three copies, `make parity-check` compares them), `LookString` (`blu`
inside a `mask:` token, parsed only with the flag), `LookPipeline` (the `blu` pass after the rules'
stages, inside the mask blend). Tools: `Tools/parity/lumina-render` gains `sky`, `diagnose`,
`--sky` / `"sky": true` (the sky mask attached, so `mask:sky/…` renders); `Tools/skyeval/` holds the
scorers. Tests: `LuminaLogicTests/LookSkyTests.swift` (10, pass).

## Phase 0 — inventory

| # | Question | Answer |
|---|---|---|
| 1 | Exposure / highlights / whites | `rules-v1.json:7` order `rawDevelop, camera, exposure, whiteBalance, whitesBlacks, tone, …`. `LookMath.exposure` :121 (scene gain through a sigmoid, `stopsPerUnit` 1.622; above `white` 1.095 a tangent), `whitesBlacks` :154, `toneGain` :236; kernels `lookExposure` / `lookPre` / `lookTone`; numpy `exposure` / `whites_blacks` / `tone_gain`. Keys `ev` (stops, −5…+5, 0.05), `hl` `sh` `wh` `bl` (−100…100). Per-photo value = the look string in the session (`plumbing.js:110` `BY_ID … 'look'`, `SetsShootStore` `session.json`), never XMP |
| 2 | Locals | `mask:<id>/k=v,…` (`LookString.swift:14`), keys `ev con hl sh wh bl vib sat clr` (+ `blu` now, flagged). Ids from `LookMasks.name` — **`sky` exists** (`LookMasks.swift:41`, kind `.sky`). `LookPipeline.apply` :386 re-runs the stage chain with the local's values on the graded image and blends with `CIBlendWithRedMask`; mask raster feathered `0.006 ×` long edge (:527). `lumina-render` never attached masks before today |
| 3 | `LookMasks.sky` | Foundation only, `sky(red:green:blue:)` :394 on sRGB planes ≤ 1024 px (the app feeds the embedded JPEG, `SetsMasks.swift:26`). Gate: Vision scene label in `sky blue_sky cloudy sunset_sunrise rainbow storm` ≥ 0.3. Colour rule `max(blueSky, overcast, sunset)·(1−foliage)` — no blue required, any bright low-chroma smooth area counts; must touch the top 2 % rows; detached patches join by colour. Cost measured today in `lumina-render diagnose` (1024 px develop + Vision + mask): **median 2.1 s** per 24 MP ARW on this Mac (the develop is most of it; the app's path skips it). Failure modes visible in code: white walls / haze / snow / bright water that reach the top edge; dark deep-blue skies (y < 0.08) miss `blueSky`; water joins when its colour is within 0.12 of the sky's. Seen in the sheets: a lake under a bright sky is sometimes taken (row 6 of `f1/sheet.jpg`); a snow field is taken whole (`f34/sheet-clamp.jpg` row 4, DSC06730, "sky 100 %"), so F3/F4 would darken / tint the snow too — the mask's problem, out of scope here |
| 4 | Video | **No** native video path into `LookPipeline`. Skim reads clips through WebKit `<video>`; `SkimTracker` / `SkimPatch` decode frames for tracking only; `SetsMasks.masks(frame:)` runs the stills mask finder on a page-drawn JPEG. So F1–F6 are **stills only**; nothing built for video |
| 5 | White level | Nothing in the app reads `WhiteLevel` / `BlackLevel`; `LookLensShading` is the only ARW tag parser. `CIRAWFilter` exposes no sensor values, but macOS 26 adds `isHighlightRecoveryEnabled` (`CIRAWFilter.h:104`): recovery on vs off differs only where a channel clipped, which is the in-app clip map (`LookSkyClip`). Ground truth for scoring: rawpy with the file's own tag (Sony compressed ARW white 15360, black 512; LibRaw's 16383 is wrong). Today's decode (`boostAmount` 1) ends at ~1.0; EDR 2 lifts a sun shot to 4.5 |
| 6 | XMP on refs | Yes: `parity-personal/xmp-dump.json` carries `Exposure2012` etc. for all 110 edits (92 non-zero), and `parity-bridal-edits/refs.json` carries 314 looks with `ev:`; `parity_personal.py` already parses them |
| 7 | Mapper report | Did not exist on this branch; `docs/masking/eval/` lives on `claude/heal-benchmark` (STATE copied here with one row added). Mapper scored below |

LM Studio: the brief locks out model calls for these features, so no model was used or loaded.

## Phase 1 — mapper

`rules-mapper-sigmoid.json` = rules-v1 with `outputTransform.mapper: "sigmoid"`, coefficients as
committed (`/Volumes/LuminaFactory/tmp/fits/`). Held-out mehendi, 109 edits of 94 RAWs, 1024 px:

| mapper | median | p95 | report |
|---|---:|---:|---|
| clamp (shipped) | **2.38** | **8.10** | `parity-personal/report/20261028-220758-sky-mapper-clamp` |
| sigmoid | 2.40 | 8.13 | `…/20261028-220927-sky-mapper-sigmoid` |

Δ +0.02 / +0.03: inside the per-change gate (+0.05 / +0.10) and the ceiling (2.42 / 8.07 → p95
8.13 is **0.06 over** the 2026-10-01 ceiling of 7.82 + 0.25, as the clamp baseline already is).
Sky pixels on DSC05860 / DSC06215 / DSC06707 (the sweep's sky frames): see F3/F4 tables, both
mappers. `make parity-check` PASS (worst 0.0021, now including the sky-blue rows).

**Verdict: owner-pick.** The mapper is not what the held-out set measures (it moves ≤ 0.03), so
parity neither adopts nor rejects it; what it buys is shown in F2 below (sky white 10 % → 37 %
under clamp, 0 under sigmoid) and in `f34/sheet-sigmoid.jpg`. It stays in the scratch file.

## Phase 2 — features

Test set for F1 / F3 / F4 / F5: 311 ARWs = the 5 sweep photos + the 156 Death Valley tone photos
+ 150 drawn at random from `/Volumes/T7/CROSS_COUNTRY_2026/RAWS` (812; seed 7). 227 have a sky.
F2: the bridal-shower edits (309, development) and the mehendi edits (94, held-out).
No FiveK subset, no clips at `~/LuminaEvidence/harrison/clips/` (skipped).

### F1 clip diagnosis — ship behind flag

Per photo: the sky mask; `white` = any channel ≥ 0.99 in today's decode; `clipped` = pixels Apple's
decoder changes with highlight recovery on vs off (EDR 2, linear). Verdict: ≥ 2 % of the sky clipped
→ clipped-at-capture, else ≥ 2 % white → recoverable, else fine. Truth: rawpy, ≥ 0.98 × 15360
per Bayer channel, same rule.

| metric | bar | result | |
|---|---|---|---|
| verdict vs RAW truth, 227 sky frames | ≥ 90 % | **227 / 227 = 100 %** | pass |
| sky clip share, app vs RAW | — | median \|Δ\| 0.000, p95 0.024, max 0.104 | |
| contact sheet (30, 10 per class) | owner confirms | `skyeval/f1/sheet.jpg` + `sheet.json` | **owner** |
| cost | — | clip maps 0.43 s (3 decodes at 512 px); mask 2.1 s incl. the 1024 px develop | |

Classes in the set: 162 fine, 34 recoverable, 31 clipped (green channel first in all 31). Without
the macOS 26 switch the verdict is `recoverable` at most and `clipped` is reported as unknown.

### F2 highlight-safe auto exposure — needs work (stopped)

Meter: median linear luma of pixels not sky, not ≥ 0.98, not ≤ 0.0005, in the look-free develop;
the `ev` that puts it on a target L* through the exposure stage's own curve, ±3, 0.05 steps. The
one constant (target L*) was fitted on the bridal edits (43.5) and frozen.

| metric | bar | result | |
|---|---|---|---|
| held-out \|ev − LR Exposure\| | median ≤ 0.33 | **0.44** (p90 1.14) | **fail** |
| development set | — | 0.36 (p90 0.90) | |
| baseline ev 0, held-out | — | 0.38 (p90 0.74) | |
| sky white after the move, 60 sky frames, clamp | not rise | 9.7 % → 37.1 % (35 / 60 rose > 1 pt) | **fail** |
| same, sigmoid | not rise | 0 → 0 (nothing reaches 0.99 by construction) | — |

Why it fails: on the held-out set the photographer's Exposure correlates with the metered midtone
at only r = −0.30 (dev −0.50); after their own move the midtones still spread σ 7 L* (before 6).
A single-number meter does not predict a person's exposure; it sets a *consistent* midtone, which
is F5's job and works there. Not tuned further (the brief says stop).

### F3 sky exposure (local) — ship behind flag

`mask:sky/ev=-1.00` through the existing local mechanism and feather. 80 sky photos, 1024 px.

| metric | bar | clamp | sigmoid | |
|---|---|---|---|---|
| collateral: non-sky pixels (outside a 16 px band) with ΔE > 2 | ≤ 1 % | **0.0 % on 80 / 80** | 0.0 % on 70 / 70 | pass |
| halo: p95 ΔE in the 16 px band outside the mask | report | 4.55 median | 4.64 | |
| sky ΔE (the intended change) | — | 11.6 | 11.7 | |

The halo is the feather itself (12 px of a 2048 px raster) carrying −1 stop; it is where the mask
ends, not a ring beyond it. Horizons, trees and buildings: `f34/sheet-clamp.jpg` rows 1–3
(DSC06707 sun + hills, DSC06215 building, DSC05860 dunes). Sigmoid: 10 of the 80 get no sky mask
under those rules (the gate / colour rule on a darker base render) and render unchanged.

### F4 sky blue — ship behind flag

`mask:sky/blu=60` (0…100). In Oklab, L held. Target hue **257.7°** = the ColorChecker Blue Sky
patch (sRGB 98,122,157); the one sky blue every chart agrees on, and the hue of a clear sky in
sRGB (Macbeth, Pointer). Chroma cap = 40 % of the sRGB gamut at that hue, a triangle through the
cusp (L 0.60, C 0.219), so near-white skies get a pale blue that stays in gamut and blown skies get
almost none. Hue turns fully within 35° of the target and not at all past 70° (greens, oranges,
skin inside a loose mask are untouched); chroma is added only to pixels that turned or are nearly
grey (C < 0.05), never above the cap, so an already-blue sky barely moves.

| metric | bar | clamp | sigmoid | |
|---|---|---|---|---|
| collateral (as F3) | ≤ 1 % | **0.0 %** on 80 / 80 | 0.0 % on 70 / 70 | pass |
| halo p95 | report | 1.89 | 1.84 | |
| sky mean hue shift, fine skies (33) | report | +18.6° toward blue | +18.6° | |
| cyan-band share of sky, fine | report | 10.1 % → 6.9 % | 10.1 % → 4.8 % | |
| sky chroma, fine / recoverable / clipped | report | 8.5→10.4 / 5.3→6.8 / 3.8→3.9 | 7.7→10.1 / 4.4→5.9 / 2.6→2.7 | |
| with F3 −1 stop first, chroma | report | 14.1 / 12.2 / 8.4 | 14.1 / 12.1 / 7.8 | |
| banding, 10-bit: distinct L* codes per sky column, F4 / base | ≈ 1 | 1.00 (all classes) | 1.00 | pass |
| banding, both on: codes ratio; p99 row step L* | report | 1.10–1.46; 1.2 → 2.2 (clipped) | 1.11–1.44; 0.8 → 1.8 | |
| sky ΔE vs Lightroom refs with sky edits | report | **none exist** (mehendi is indoors; DV refs are base exports) | | unscored |

Clipped-at-capture skies: F4 alone leaves them white (chroma +0.1), as it must (no detail to
invent). F3 then F4 gives a smooth pale blue (chroma 8.4, no new banding steps above 2.2 L*). No
cloud, gradient or fill of any kind is synthesised.

### F5 exposure consistency — ship behind flag

Sets = photos within 60 s of each other, ≥ 3 photos, the 12 largest (112 photos). Each photo's
`ev` from F2's meter against the set's median midtone. Midtone measured again on the render
(median L* of every non-sky pixel).

| metric | bar | result | |
|---|---|---|---|
| spread σ of midtone L*, before → after, median over sets | halves | **9.0 → 2.4** (ratio 0.25) | pass |
| sets halved | — | 8 / 12 | |
| hue collateral (mean hue of non-sky colour) | ≈ 0 | 0.21° median, 2.8° worst set | pass |
| WB | report, don't fix | spread of b* per set in `f5/f5.json` (`wbSpreadB`) | |

The 4 sets not halved mix a +3-stop-blown frame with normal ones (set 11: a white frame meters
L* 98, `ev` hits −3 and lands at 57). The 60 s rule is the scorer's, not a product grouping.

### F6 capture tip — needs work (text only)

`LookSky.captureTip`: "Sky was clipped when shot (N % of it). About S stops less exposure would have
kept it." S = p90 of the decoder's recovery lift inside the clipped sky + the margin to 0.9 × white.
No bracketed / ETTR pairs exist on this Mac → **unscored against reality**. Against the RAW
channel-ratio estimate (the brightest unclipped channel scaled by the sky's own ratios): on 44
frames the in-app S is **0.81 stop low** (median; MAD 0.17; app median 0.15 vs 0.98). The decoder
recovers less than the ratios say, consistently, so a fixed offset would fix most of it; not
applied (that is a fit with no truth).

### Video

Not built: Phase 0 found no video ingest into the look pipeline, and no clips at the named path.

## No regression

- All features off → **bit-identical**: 40 held-out looks rendered with a `lumina-render` built from
  `origin/main` and with this checkout's, 16-bit sRGB TIFFs compared byte for byte: 40 / 40 equal
  with `LUMINA_SKY` unset **and** set (`skyeval/identity/identity.json`).
- `make parity-check` PASS (0.0021). `rules-v1.json` unchanged (`mapper: clamp`).
- `python3 Scripts/trust_check.py` all ok; design fixtures pass. XCTest: LookSkyTests 10 / 10,
  LookStringTests, LookMathTests, LookPipelineTests, LookMaskPipelineTests pass (86 tests).
- Held-out parity numbers unchanged (2.38 / 8.10 is the clamp run above, same as before this work).

## Contact sheets (paths)

- F1: `~/LuminaEvidence/skyeval/f1/sheet.jpg` (base | mask + white + clipped overlay), `sheet.json` lists the 30.
- F3 / F4: `~/LuminaEvidence/skyeval/f34/sheet-clamp.jpg`, `sheet-sigmoid.jpg` — base | F3 | F4 | both | LR base export where present.
- Per photo: `skyeval/f1/<stem>/{sky,white,clipped}.png`, `skyeval/f34/<mapper>/render/<stem>__{base,f3,f4,all}.tif`.
- F5 renders `skyeval/f5/render/<stem>__{before,after}.tif`; F2 `skyeval/f2/f2.json`, `skyeval/f2sky/`.

## Recommendation

| | |
|---|---|
| F1 | **ship behind flag** (needs macOS 26 for the clipped class; owner to confirm the 30 labels) |
| F2 | **needs work** — a meter does not predict a photographer's exposure (0.44 > 0.33, worse than ev 0); keep the meter for F5 |
| F3 | **ship behind flag** |
| F4 | **ship behind flag** (target blue and cap are owner choices, below) |
| F5 | **ship behind flag** (grouping is the page's; the clamp at ±3 wants a UI note on blown frames) |
| F6 | **needs work** — text works, estimate biased −0.8 stop vs RAW ratios, no bracketed truth |

## Owner questions

1. Target blue: ColorChecker Blue Sky (257.7°) and a 40 % chroma cap — keep, or a deeper / paler target?
2. Slider ranges: F3 as the existing `ev` inside `mask:sky` (−5…+5) or a dedicated −2…0 "darken sky"? F4 `blu` 0…100.
3. Mapper: sigmoid stays scratch (owner-pick above). Decide before F2 is revisited; F3 / F4 pass under both.
4. F5 in the first release? It works; grouping (selection vs capture time) and the blown-frame clamp are UI decisions.
5. F1 labels: confirm or correct `f1/sheet.jpg`; the three classes' thresholds (2 %) are starting points.
