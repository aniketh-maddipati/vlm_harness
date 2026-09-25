# Rendering latency & quality — measured research

**Date:** 2026-09-24 · **Branch:** `improve-phone-classification` @ `65ef449` (25 files dirty)
**Status:** RESEARCH. Every number below was measured on this host by a standalone harness,
not by the app. No code change is included. Nothing here is a ratified token or an SLA pass.

**Host:** MacBook Pro `Mac16,7`, Apple M4 Pro, 24 GB, macOS 26.5.2, Swift 6.3.3.
**Build:** standalone `swiftc -O` benches — **not** the app, not Release Lumina. Absolute values
carry that difference; the ratios between rows are what this document argues from.

**Evidence:** `~/LuminaEvidence/render-latency-research-20260924/` — five raw run logs plus the
bench sources that produced them (`src/`). `/private/tmp` is swept; that directory is not.

**Fixtures.**
- Grid/preview tier decodes: the **real** cached tiers of the `card-elastic-v4-stress` shoot,
  403 frames, at `~/Library/Application Support/Lumina/projects/card-elastic-v4-stress/cache/`.
- RAW renders (10 MP): `card-clean-500`. These frames are **3936×2624**, not the 6000×4000 an
  A7 III shoots — the card carries cropped frames. Its RAW numbers are therefore optimistic.
- RAW renders (24 MP): `~/Pictures/jeevana_mehendi_2026_MATCHED_RAWS`, 6000×4000 A7 III frames.
  **The 24 MP table is the one to quote**; the 10 MP table is kept only to show the shape holds.
- Page cache: **warm** in every run (files read once before measuring). Cold I/O is not measured.

---

## 1. The finding that dominates everything else: the settled frame is rendered lazily, inside the draw call

`PreparedRawSession.rawStageSurface` materializes the **interactive** tier into an `MTLTexture`
and deliberately leaves the **authoritative** (settled) tier as the lazy `CIRAWFilter.outputImage`:

```swift
if tier == .interactive, let realized = materializeInteractiveStage(output) { … }
else if tier == .authoritative { didCacheAuthoritativeLazyStage = true }
```
— `Lumina/Develop/PreparedRawSession.swift:214`

`DevelopMetalView.draw(in:)` then walks whatever CIImage it was handed:
`context.startTask(toRender: positioned, to: destination)` (`Lumina/Develop/Lab/DevelopMetalView.swift:212`).
For a settled frame that walk **is the RAW demosaic**, and it happens on the presentation path.

Measured, 6000×4000 A7 III frame, `cacheIntermediates: true`, shared CIContext, 2560×1600
destination (`04-lazy-redraw.txt`):

| Draw | Lazy authoritative graph | Materialized once up front |
|---|---:|---:|
| first draw | **168.4 ms** | 5.4 ms |
| identical repeat draws | 7.0–7.3 ms | 3.5–4.3 ms |
| **after any pan / zoom / resize** | **79.5 – 91.0 ms** | **3.6 – 4.5 ms** |

Read the third row twice. Core Image's intermediate cache absorbs an *identical* redraw, so the
lazy tier looks fine while nothing moves. The moment the geometry transform changes — pan, zoom,
a window resize, a drawable-size change — the cache misses and the full RAW demosaic re-runs
**every frame**. That is ~11 fps on a 120 Hz panel, and it is 20–25× slower than the same pixels
materialized once.

Three consequences worth naming separately:

1. **`p0.edit.promote_settled_ms` understates the truth by roughly 400×.** `raw_force` shows
   `createCGImage` on a full-scale RAW graph returning in **0.3 ms** while rasterizing the same
   graph costs **183.6 ms p50 / 249.7 ms p95** (`03-raw-deferred-vs-forced-24mp.txt`). The
   scheduler's timer brackets the call that returns in 0.3 ms. `docs/perf/product-performance-baseline.md`
   suspected this ("can record when an older image already exists"); this names the mechanism.
2. `DevelopMetalView.updateNSView` sets `view.needsDisplay = true` unconditionally on every
   SwiftUI update, so an unrelated chip or hover costs a 7 ms GPU pass on the lazy tier.
3. This is literally the "lazy rendering on select" concern. It is real and it is one line of
   policy, not an architectural problem: the interactive tier already has the fix.

**Proposal R1 — materialize the authoritative tier too.** Reuse `materializeInteractiveStage`
for `.authoritative`. Cost: one rasterize (120–184 ms) on a background tier, once, where it is
already async. Benefit: pan/zoom/resize on a settled frame goes 80–91 ms → 3.6–4.5 ms per frame.
Memory cost is a bounded texture per resident stage, and `rawStageCache` already evicts.

**Proposal R2 — make the promote metric honest.** Have `renderNow(.settled)` record the time to
*rasterized pixels*, not the time to a returned lazy CIImage. Until R1 lands the current key is
not a latency and should not be quoted as one.

---

## 2. Selection does not need a two-rung RAW promote at all

Measured on 24 MP frames, `createCGImage` + forced rasterize, warm process
(`03-raw-deferred-vs-forced-24mp.txt`):

| CIRAWFilter config | total to rasterized pixels (p50) | output px |
|---|---:|---|
| `draft=F scale=1.00` | 183.9 ms | 6000×4000 |
| `draft=F scale=0.70` | 121.0 ms | 4200×2800 |
| `draft=F scale=0.50` | 113.4 ms | 3000×2000 |
| `draft=T scale=0.50` | 109.8 ms | 3000×2000 |
| `draft=F scale=0.35` | 107.0 ms | 2100×1400 |
| **`draft=T scale=0.35` (what ships on the interactive rung)** | **96.2 ms** | 2100×1400 |

Two things fall out:

**Draft mode is not buying speed.** `draft=T` vs `draft=F` at the same scale is
**96.2 vs 107.0 ms** — 10 ms, ~10%. On the 10 MP card it is 42.0 vs 44.6 ms, ~6%
(`02-raw-sweep-fixture-10mp.txt`). Apple's draft demosaic costs real sharpness and noise
character for a tenth of a rung. It is currently on for the tier the user looks at *first*, which
is the rung most likely to be mistaken for the photograph.

**`scaleFactor` barely moves the floor.** 0.35 → 0.50 costs 6 ms; 0.35 → 0.70 costs 14 ms. The
demosaic happens at sensor resolution regardless; scale only affects the output resample. So the
current design — a cheap small rung, a 40 ms sleep, then an expensive big rung — spends
`96 + 40 + ~145 = ~280 ms` and shows the reader **three different pictures** (browse JPEG →
draft RAW → settled RAW) to save ~25 ms over rendering the good one directly.

**Proposal R3 — collapse the promote to one rung for the common case.** Render once at
`draft=F`, `scaleFactor` sized to the actual drawable (`scale≈0.70` covers a 2560-px drawable at
1.15× headroom), materialized per R1: **~121 ms, one pixel swap, no quality step.** Keep the
second rung only when the drawable genuinely needs >0.70 (deep zoom, 4K/5K external panel), where
it is a real upgrade rather than a re-render of the same thing at the same visible sharpness.

The browse JPEG still lands first (§3), so time-to-*a*-photograph is unchanged; what changes is
that the photograph the reader settles on arrives once, sharp, and never changes character again.

---

## 3. The grid tier is a 1200 px JPEG wearing a 512 px name

`PhotoImageTier.gridMaxPixelSize = 512`, and the grid cache directory is named `grid512`. What is
actually written there is `durableGridLongEdge = 1200`
(`ContactSheetPreparation.swift:411`, `ImportPipeline.swift:312`). On disk, verified:

```
grid512/…jpg   1200×802    ~300 KB     126 MB for 403 frames
preview/…jpg   1600×1069   ~477 KB     200 MB for 403 frames
```

So every grid-tile decode is a 1200 px JPEG decoded down to 512, and every *floor* decode
(`floorLongEdge = 256`) is the **same 1200 px file** decoded down to 256. The floor tier buys
memory, not speed.

Measured over all 403 real cached tiles (`01-decode-tiers.txt`):

| decode | p50 | p95 | max |
|---|---:|---:|---:|
| **grid 512 from the 1200 px tier — what ships** | **3.49 ms** | 4.08 ms | 6.54 ms |
| grid 512 from a real 512 px tier | **0.84 ms** | 0.98 ms | 1.31 ms |
| **floor 256 from the 1200 px tier — what ships** | **2.19 ms** | 2.59 ms | 2.92 ms |
| floor 256 from a real 512 px tier | **0.64 ms** | 0.76 ms | 1.62 ms |
| focused 2400 from the 1600 px preview | 5.70 ms | 7.01 ms | 36.67 ms |

**4.2× on the grid tier, 3.4× on the floor tier, for a tier that also shrinks 126 MB → 29 MB.**

Sizing check: the table tile is `ElasticLayout.tile = 168` pt. At 2× that is 336 px tall; a 3:2
landscape tile is 504×336 px. A 512 px long edge is the correct Retina size for it — 1200 is
~5.6× the pixels the tile can show.

**Proposal R4 — write a real 512 tier at ingest** (`grid512` finally meaning what it says), keep
1200 under a different name for the density steps that need it, and point
`BrowsePixelService.Tier.grid` at the 512 file. Prefetch throughput rises by the same 4.2×, which
is the number that decides whether a flick outruns the decode queue.

**Proposal R5 — give the floor tier its own 256 px file.** 0.64 ms vs 2.19 ms. The floor exists
to guarantee *something* is drawable for every frame the viewport can reach; at 0.64 ms per frame
the guarantee gets much cheaper to keep.

Two suspects I checked and **cleared**, so nobody re-litigates them:
- `kCGImageSourceShouldCacheImmediately: false` is **not** causing a deferred main-thread decode
  on the tile path. Thumbnails come back rasterized: forcing a draw afterwards costs 0.21 ms
  (0.30 ms mean) whether the flag is true or false, and the decode p50 is identical either way.
  The flag matters for `CGImageSourceCreateImageAtIndex` (the proxy tier, `maxPixelSize == nil`),
  not for the thumbnail path.
- `Data(mappedIfSafe)` + `CreateWithData` vs `CreateWithURL`: 3.49 vs 3.46 ms. No difference at
  these file sizes. Not worth changing either way.

---

## 4. Exposure across the rungs: small, but consistently a shadow lift

Measured on 15 `card-clean-500` frames — camera embedded preview (what browse shows) vs
`CIRAWFilter` at as-shot neutral, exposure 0 (what promotion shows), both sampled at 256 px and
compared in sRGB luminance (`05-preview-vs-raw-exposure.txt`):

```
mean Δ luminance = +0.0045   (≈ +0.02 EV)
max |Δ|          =  0.0256   (≈ 0.09 EV, 1 frame of 15)
frames with |Δ| > 0.02: 1/15
```

**There is no gross exposure jump on promote**, and that hypothesis should be retired. But the
`p05` column moves the same direction on almost every frame — +0.017, +0.026, +0.027, +0.033,
+0.039, +0.043, +0.049 — which is a **shadow lift**, not an exposure shift. That is Apple's
default `boostShadowAmount` on `CIRAWFilter`, which Lumina never sets. The visible artifact on
select is therefore "the shadows open up and the picture goes slightly milky", layered on top of
the draft-mode softness from §2 — not "it gets brighter".

**Proposal R6 — pin the RAW boost explicitly.** Set `boostAmount` / `boostShadowAmount` to
declared values in `PreparedRawSession.apply(intent:to:tier:scale:)` rather than inheriting
Apple's defaults, and record the choice in `DevelopColorPolicy`. Whatever value is chosen, the
point is that it is *chosen*: today the difference between the browse rung and the RAW rung is
whatever Apple's default happens to be this OS release, which is also a silent
regression risk across macOS updates.

**Proposal R7 — make the rungs agree before they cross-fade.** A cross-fade (§5) between two
images with different shadow response reads as a *lighting change*, which is worse than a hard
cut. R6 and R3 together are what make §5 safe.

---

## 5. Fades: there are none where they are needed, and one rule to follow

`ChapterPlateImage` (`Lumina/Views/P0/ChapterPlateImage.swift:19`) hard-swaps in a `ZStack`:
the well, then the floor image, then the grid image, each replacing the last with no transition.
`LuminaSpringAnimation.crossfade(reduceMotion:durationMs:)` already exists and the contract
already rules a **120 ms warm-in crossfade** (D57, `design/contract-v6.md:260`) — it is simply
not applied on the tile tier upgrade.

The rule that matters, because the naive version makes things feel *slower*:

1. **Pixels already resident at first layout → no animation.** Today's behaviour, and it is
   correct. `ChapterPlateImage` samples residency synchronously in `body` for exactly this
   reason; a fade here would invent 120 ms of latency that the reader is not currently paying.
2. **Well → first pixels → fade in (≈120 ms).** The well was already on screen; a cut from grey
   to photograph is the pop.
3. **Floor (256, soft) → grid (512, sharp) → cross-dissolve, but only if the soft rung has been
   up longer than ~100 ms.** If the upgrade lands inside that window, hard-cut: the reader never
   resolved the soft one, and dissolving between two versions of the same picture that differ
   only in sharpness reads as a focus hunt.
4. **Never fade *out* to empty.** A cross-dissolve needs both layers alive simultaneously. Fading
   the old image down before the new one exists is the flash, and it is what the D57 "final rung
   crossfade is the one sanctioned positive truth signal" ruling is protecting against.
5. Reduced motion: `crossfade(reduceMotion: true, …)` already returns a critically damped
   animation rather than nil — keep that path, do not branch to a hard cut.

Same rule applies to the focus canvas: with R3 there is one swap (JPEG → settled RAW) and it
should cross-dissolve at 120 ms; with R1+R6 the two images finally match closely enough that the
dissolve reads as *resolving* rather than as *relighting*.

---

## 6. Colour management: the browse canvas layer is untagged

`DevelopMetalView` tags its layer and its render destination with the screen's actual colour
space (`Lumina/Develop/Lab/DevelopMetalView.swift:55, 153, 188-200`).

`MetalBrowseCanvas.swift` contains **no colorspace assignment at all** — `metalLayer.colorspace`
is never set, while `MetalPreviewPool.copyIntoPixelBuffer` colour-matches decoded pixels into
`ImagePixelFormat.workingColorSpace` (**sRGB**) and uploads them to a `.bgra8Unorm` texture.
Untagged sRGB-encoded content on a P3/XDR panel is displayed as though it were P3 — more
saturated, with a darker-looking midtone roll. Meanwhile the AppKit tile path
(`Image(nsImage:)`) *is* colour-matched correctly by AppKit.

So up to three renderings of the same photograph can disagree: AppKit tile (matched), Metal
browse canvas (unmatched), develop canvas (matched to screen).

**Proposal R8 — set `metalLayer.colorspace` on `MetalBrowseNSView`** to the same
`view.window?.screen?.colorSpace?.cgColorSpace ?? DevelopColorPolicy.displayColorSpace` the
develop view uses, and re-tag it when the window changes screen. This is a correctness fix with
no measurable cost.

Also noted, not proposed: `metalLayer.displaySyncEnabled = false` on the browse canvas trades
tearing for latency. That is a legitimate choice, but it should be a *recorded* one, because it
also means the browse canvas presents frames the display never shows.

---

## 7. Margins solid, padding elastic — the end-of-scroll pull

Today: `ElasticTableView` is a plain `ScrollView { LazyVStack }` with
`.padding(.horizontal, ElasticLayout.tableGutter)` and `.padding(.vertical, …)` applied **to the
scrolled content** (`Lumina/Views/P0/ElasticTableView.swift:58-84`). Because the padding is
inside the scrolled content, AppKit's own elasticity drags the gutter along with the photographs:
the margin is exactly as stretchy as everything else, which is the opposite of what is wanted.

The target behaviour — rigid margins, a small elastic end cap that resists further the harder it
is pulled, then springs back and signals that the shoot is over:

**a. Take the gutters out of the scrolled content.** Move `.padding(.horizontal, tableGutter)`
onto the `ScrollView` itself (or use `.contentMargins(.horizontal, …, for: .scrollContent)`),
so horizontal gutters are a property of the container, not cargo on the document. Overscroll then
cannot move them.

**b. Own the overscroll amount.** `ElasticScrollInterruption`
(`Lumina/Views/P0/ElasticViewportReveal.swift:110-152`) already finds the `enclosingScrollView`
and observes `willStartLiveScrollNotification`. Extend that same observer to
`NSScrollView.didLiveScrollNotification` + `boundsDidChangeNotification` on the clip view and
read `contentView.bounds.origin.y` against the document bounds. Beyond the ends that value is the
raw overscroll distance.

**c. Map raw distance through a rubber band, so it asymptotes.** The standard formulation, which
is what makes a pull feel like resistance rather than travel:

```
stretch(d) = (1 - 1 / (d * c / D + 1)) * D      c ≈ 0.55
```

`D` is the hard cap — the "tiny bit" it can be pulled. Suggested `D ≈ 28–40 pt` (one row gap,
not one row). As `d → ∞`, `stretch → D`: the reader can lean on it forever and it never opens
further, which is the whole signal.

**d. Spend the stretch on an end cap, not on the margins.** Put a zero-height spacer at the top
and bottom of the `LazyVStack` whose height is `basePadding + stretch(d)`. Only that view moves.
`MACOSX_DEPLOYMENT_TARGET = 14.0`, so `onScrollGeometryChange` (macOS 15) is not available — the
AppKit observer in (b) is the portable route, not a workaround.

**e. Return with the existing spring, not a new one.** `LuminaSpringAnimation.placeReturn(reduceMotion:)`
reads the sealed `place_return` duration from `HiFiTokens.Motion` — that is the project's
existing "pulled and let go" motion and reusing it keeps the feel coherent and keeps the F07
spring golden authoritative.

**f. Signal the limit.** At `stretch > 0.8 * D`, bring up an end rule / "end of shoot" hairline
at opacity proportional to `stretch / D`, and fire `LuminaHaptics.alignment()` **once** per
crossing (latch it; clear the latch below 0.5 · D). `alignment` is the right performer here —
it is the "you have reached an edge" feedback, distinct from `decision()` which marks a cull.

**g. Reduced motion:** clamp `D` to 0 and show the end rule on contact instead. The signal
survives; the travel does not.

Contract note: this is new visual behaviour at a frozen surface. Per the project's own authority
rule, the pull distance, the rule opacity curve and the haptic belong in `design/tokens.yaml`
via a constitution session before they ship — the numbers above are **proposals**, exactly like
the `p0.*` budgets in `docs/perf/e2-instrument-proposals.md`.

---

## 8. Ranked, with the measured basis for the rank

| # | Change | Measured effect | Risk |
|---|---|---|---|
| R1 | Materialize the authoritative RAW stage | pan/zoom on a settled frame **80–91 ms → 3.6–4.5 ms/frame**; first draw 168 → 5.4 ms | low — mirrors the interactive tier's existing code |
| R4 | Write a real 512 px grid tier | grid decode **3.49 → 0.84 ms** (4.2×); 126 MB → 29 MB | low — ingest-side, re-derivable |
| R3 | One RAW rung at `draft=F`, drawable-sized | ~280 ms and 3 pictures → ~121 ms and 2; removes the draft-softness rung | medium — changes what the reader sees first |
| R5 | Real 256 px floor tier | floor decode **2.19 → 0.64 ms** (3.4×) | low |
| R8 | Tag the browse Metal layer's colour space | removes a 3-way appearance disagreement | low — correctness |
| R6 | Pin `boostAmount` / `boostShadowAmount` | removes the shadow lift on promote (p05 +0.02…+0.05) | medium — changes rendered output; needs a parity round |
| R2 | Make `promote_settled_ms` measure rasterized pixels | the key stops understating by ~400× | low — instrument only |
| §5 | Tier-upgrade cross-fades under the four rules | perceived smoothness; **unmeasured** | medium — must follow R3/R6 |
| §7 | Rigid gutters + capped elastic end cap | feel; **unmeasured** | medium — frozen surface, needs tokens |

## 9. What this research did **not** measure

- Anything inside the running app. Every number is from a standalone `-O` bench; app numbers will
  differ and R1/R3/R4 must be re-measured in-app before any of them is called a win.
- Cold I/O. Page cache was warm in every run.
- `p0.scroll.frame` end to end. The decode numbers in §3 are a decode floor, not a frame time —
  the same caveat `docs/perf/e1-baseline.md` attaches to its own decode table.
- Memory under the R1 texture policy. Materializing authoritative stages costs VRAM;
  `rawStageCache` eviction needs a measured ceiling before R1 ships.
- Whether any of §5 or §7 actually feels better. Those are claims about perception and need a
  human pass on the workbench, not a bench.

---

## 10. Next steps — one workstream per prompt

Each block is a self-contained prompt. They are ordered so that earlier ones do not depend on
later ones; **W1–W3 are independent and can run in parallel**, W4 depends on W2, W6 depends on W5.
Every prompt ends at a measurement or a gate, not at "it looks better".

### W0 — arm the in-app measurement first (do this before any fix)
> In `/Users/aniketh/vlm_harness`, the settled RAW tier is a lazy `CIRAWFilter` graph rendered
> inside `DevelopMetalView.draw(in:)`, so `p0.edit.promote_settled_ms` times a call that returns
> in ~0.3 ms while the real 120–184 ms lands on the draw. Add an instrument that measures
> **rasterized** pixels: a new key `p0.edit.settled_rasterize_ms` recorded around a forced
> rasterization of the authoritative stage, plus `p0.develop.draw_walk_ms` separating the CI graph
> walk from drawable acquisition in `DevelopMetalView`. Do not change render behaviour. Declare
> both keys in `LatencyMetrics.declaredSLAms` as PROPOSED per
> `docs/perf/e2-instrument-proposals.md` conventions. Then run the app with `--p0-instruments`
> against `~/Pictures/jeevana_mehendi_2026_MATCHED_RAWS`, select 10 frames, pan each one, and
> report the two new distributions. Baseline for R1.

### W1 — R1: materialize the authoritative RAW stage
> In `Lumina/Develop/PreparedRawSession.swift:214`, the `.authoritative` tier deliberately caches
> the lazy `CIRAWFilter.outputImage` while `.interactive` is materialized into an `MTLTexture` by
> `materializeInteractiveStage`. Measured cost of that choice
> (`~/LuminaEvidence/render-latency-research-20260924/04-lazy-redraw.txt`): pan/zoom on a settled
> 24 MP frame costs 80–91 ms per frame lazy vs 3.6–4.5 ms materialized. Materialize the
> authoritative tier too. Then: (a) put a measured VRAM ceiling on `rawStageCache` and make
> `trimForMemoryPressure` honour it, (b) re-run the W0 instruments and report before/after,
> (c) sample process memory with `Scripts/perf/sample_process_memory.py` across a 20-frame
> selection loop and show the plateau. Ship only if pan latency drops **and** the memory plateau
> is flat.

### W2 — R4/R5: real 512 and 256 ingest tiers
> `PhotoImageTier.gridMaxPixelSize` is 512 and the cache dir is named `grid512`, but
> `ContactSheetPreparation.swift:411` writes `durableGridLongEdge` = **1200** into it, so every
> grid tile decodes a 1200 px JPEG down to 512 and every floor tile decodes the same file down to
> 256. Measured on 403 real cached tiles
> (`~/LuminaEvidence/render-latency-research-20260924/01-decode-tiers.txt`): grid 3.49 ms vs
> 0.84 ms from a true 512 px file (4.2×), floor 2.19 ms vs 0.64 ms (3.4×), and the tier shrinks
> 126 MB → 29 MB for 403 frames. Add genuine 512 px and 256 px tiers at ingest, keep the 1200 px
> tier under an honest name for the density steps that need it, and point
> `BrowsePixelService.Tier.grid` / `.floor` at the new files. Handle migration for shoots that
> already have the old cache. Re-run `Scripts/perf/e1_decode_baseline.swift` and report
> before/after against `docs/perf/e1-baseline.md`.

### W3 — R8: tag the browse Metal layer's colour space
> `MetalBrowseCanvas.swift` never sets `metalLayer.colorspace`, while `MetalPreviewPool`
> colour-matches decoded pixels into sRGB and `DevelopMetalView` tags its layer with the screen's
> actual space. On a P3/XDR panel that makes the browse canvas disagree with both the AppKit tile
> path and the develop canvas. Set the layer colour space the same way `DevelopMetalView` does,
> re-tag on screen change, and prove it: capture the same photograph through all three paths and
> compare sampled sRGB values. Add a logic test pinning that the browse layer is tagged.

### W4 — R3: collapse the two-rung RAW promote (needs W2 landed, W0 armed)
> `DevelopRenderScheduler.openPhotograph` renders interactive (`draft=T, scale≈0.35`), sleeps
> 40 ms, then renders settled. Measured on 24 MP frames
> (`~/LuminaEvidence/render-latency-research-20260924/03-raw-deferred-vs-forced-24mp.txt`):
> draft mode saves only 96.2 vs 107.0 ms, and `scaleFactor` 0.35→0.70 costs just 14 ms, so the
> two-rung chain spends ~280 ms and shows three different pictures to save ~25 ms. Prototype a
> single rung: `draft=F`, `scaleFactor` sized to the actual drawable, materialized per W1, with
> the second rung kept only when the drawable needs >0.70. Gate on: time-to-final-pixels, number
> of visible pixel swaps, and a side-by-side of the first-shown rung against today's.

### W5 — R6: pin the RAW boost and establish rung parity
> `PreparedRawSession.apply(intent:to:tier:scale:)` sets exposure, neutral temp/tint, NR and
> sharpness but never `boostAmount` / `boostShadowAmount`, so the RAW rung inherits Apple's
> defaults. Measured against the camera embedded preview on 15 frames
> (`~/LuminaEvidence/render-latency-research-20260924/05-preview-vs-raw-exposure.txt`): mean
> luminance Δ is only +0.0045 (≈ +0.02 EV) — **there is no exposure jump** — but `p05` rises
> +0.02…+0.05 on nearly every frame, i.e. a systematic shadow lift. Pin both boost values
> explicitly, record the choice and its rationale in `DevelopColorPolicy`, and re-run the parity
> bench (`src/tier_parity.swift` in that evidence dir) to show the shadow lift closing. Also run
> the RAW/export parity suite — this changes rendered output, so it needs a full parity round,
> not a spot check.

### W6 — §5: tier-upgrade cross-fades (needs W4 + W5)
> `ChapterPlateImage` hard-swaps well → floor → grid with no transition, while
> `LuminaSpringAnimation.crossfade` exists and D57 rules a 120 ms warm-in crossfade
> (`design/contract-v6.md:260`). Implement the four rules in §5 of
> `docs/perf/rendering-latency-research.md`: no animation when pixels are already resident at
> first layout; 120 ms fade in from the well; cross-dissolve floor→grid only when the soft rung
> has been up >100 ms; never fade out to empty. Keep the existing reduced-motion path. This must
> land **after** W4/W5 — cross-fading two rungs with different shadow response reads as a
> lighting change, which is worse than the hard cut it replaces. Prove it with a screen recording
> of a scroll and a selection, before and after.

### W7 — §7: rigid gutters, capped elastic end cap
> `ElasticTableView` puts `.padding(.horizontal, ElasticLayout.tableGutter)` **inside** the
> scrolled content, so AppKit elasticity drags the gutters along with the photographs. Target:
> rigid margins, and only a small end cap that stretches, resists harder the further it is pulled,
> springs back, and signals the end of the shoot. Follow §7 of
> `docs/perf/rendering-latency-research.md`: move gutters onto the container; extend the existing
> `ElasticScrollInterruption` observer (it already reaches `enclosingScrollView`) to read
> `contentView.bounds.origin.y` past the document bounds; map it through
> `stretch(d) = (1 - 1/(d*c/D + 1)) * D` with `c ≈ 0.55` and `D ≈ 28–40 pt`; spend the stretch on
> a top/bottom spacer only; return with `LuminaSpringAnimation.placeReturn`; reveal an end rule
> above `0.8·D` and fire `LuminaHaptics.alignment()` once per crossing, latched. Deployment target
> is macOS 14, so `onScrollGeometryChange` is unavailable — the AppKit observer is the route.
> `D`, the rule opacity curve and the haptic are **proposals**: route them through a constitution
> session before shipping, per the project's authority rule.

### W8 — verify the whole chain on the real shoot
> After W1–W5 have landed, run the product-performance protocol in
> `docs/perf/product-performance-baseline.md` end to end against
> `~/Pictures/jeevana_mehendi_2026_MATCHED_RAWS` and `card-clean-500`: 60 s scroll glide, a
> 20-frame selection loop with pans, and a dogfood cull. Report `p0.scroll.frame`,
> `p0.key.travel`, the new `p0.edit.settled_rasterize_ms`, and the memory plateau, and replace the
> UNMEASURED rows in that document with real distributions. This is the run that turns §8 of the
> research doc from measured-in-a-bench into measured-in-the-product.
