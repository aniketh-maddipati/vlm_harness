This document contains NO measurements. Every item is a static observation and a hypothesis. Nothing here is evidence that anything is slow.

# C-prep — Static render hazard inventory

**Session:** PREPARATION for SPIKE C. Not SPIKE C.  
**Tree:** `origin/main` @ `4feea5c6b68dcb8e2a807025bdc517c299f435ec`  
**Host:** Linux · `xcodebuild=MISSING` · therefore PREP, not SPIKE C.  
**Authority:** `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests.  
**Batch 2:** IN FORCE. **Batch 3:** PROPOSED, NOT RATIFIED.  
**This session writes no code and seals nothing.**

Items are grouped by category. They are not ranked. An impact ranking would be a measurement claim wearing prose. SPIKE C ranks by data.

Hypotheses are written as questions the Mac session will answer. Structural cost names a construct (a redraw, an offscreen pass, a decode, a layout invalidation, an unbounded task) and stops.

Prefetching cells the collection view has asked for is not speculative pre-render. Rendering ahead of what the view asked for is speculative pre-render and stays shelved.

---

## Precondition

```
git rev-parse origin/main
4feea5c6b68dcb8e2a807025bdc517c299f435ec

uname -s
Linux

command -v xcodebuild || echo "xcodebuild=MISSING"
xcodebuild=MISSING
```

`git log --oneline -5 origin/main` at fetch:

```
4feea5c fix(spring): wire LuminaSpring F07 seal constants to HiFiTokens.Motion (#59)
e6cd624 strategy(O0): audit W-cascade merge integrity (#58)
dbd4766 build(C3): make a no-op FAST run leave the tree clean (#57)
f2e9ee3 Lightweight footprint: exclude harness from Release and defer P0 develop init (#55)
3f41c93 Clean up harness inventory and repeated scans (#54)
```

---

## Contract citations verified this session

| ID | Where the text lives on this tree | Substance cited |
|----|-----------------------------------|-----------------|
| **D27** | `design/contract-v6.md` L89–96 | Photograph opacity exists only at birth; after birth photographs travel, dim in place, or soften toward sharp. Cross-cites D28. |
| **D28** | `design/contract-v5.md` L228–231 (carried; v6 has no `### D28` heading; v6 L1–40: D1–D40 remain law except named amendments; D28 is not in the amend list) | Elastic in motion, exact at rest; springs travel between quantized states; one gesture → one motion → one spring → dead stop. |
| **D49** | `design/contract-v6.md` L195–200 | Layout quantized everywhere; nothing interpolates at rest; pinch density snaps between named steps. Named density steps beyond current P0 — OPEN for token seal. |
| **R-X.2** | No standalone ruling body in `design/contract-v6.md`. The id appears as the parenthetical on the D49 heading (L195) and as `R-X.2 / D49` on SPIKE B and CP1 in `design/checkpoint-sequence-v6.md` L28–29. | Bound to D49. Open question #7 (L368) is the named-steps token seal — this session does not name the steps. |

`rg -n "### D28|D28 —" design/contract-v6.md` → **0** heading hits. Citation of D28 is the carried v5 paragraph.

Open question #9 (`design/contract-v6.md` L370): “NSCollectionView virtualization of rows/gaps (still open).” Stated in Part 2.E; not answered.

---

## PART 1 — Live render path reachability

Method: read from `LuminaApp` down on this SHA. W8 `design/strategy/legacy-disposition.md` and `Scripts/harness/lint/swift_reachability.py` are leads, not substitutes. Symbol-BFS from `LuminaApp` includes the legacy door’s type names and is **not** the default-launch photograph path.

### Default launch (Release, and Debug without `--develop-lab`)

`Lumina/LuminaApp.swift` L24–36: `WindowGroup` → `P0RootView()`. `DevelopLabView` is compiled only under `#if DEBUG` and shown only when `DevelopLabLauncher.shouldPresentLab` is true. That is not the default launch path.

`Lumina/Views/P0/P0RootView.swift` L10–23: if `session.showLegacyShell` then `P0LegacyShellContainer`; else switch on `session.route`:

| Route | View | Photograph pixels on this route? |
|-------|------|----------------------------------|
| `.open` | `P0OpenView` | No (SF Symbol only; L125) |
| `.contactSheet` | `P0ContactSheetView` | Yes — collection + optional editor overlay |
| `.grouping` | `P0GroupingView` | No |

`P0ContactSheetView` L15–27: `ContactSheetRepresentable` fills the sheet. When `inspectingAssetID` is set, `P0SinglePhotoEditor` is an overlay; the collection remains in the hierarchy at opacity `0` (L19–20).

`P0LegacyShellContainer` (`P0LegacyShellDoor.swift` L3–42) constructs `ProjectViewModel` / `LuminaShellModel` on first door open only. Default launch does not open the door.

### Live photograph-pixel files (later sections apply only to these)

Ingest that writes the JPEGs the sheet reads is included. Chrome-only files on the same routes are listed after, and are **not** inventoried as photograph-pixel hazards.

| File | Role on the default path |
|------|--------------------------|
| `Lumina/LuminaApp.swift` | Scene host → `P0RootView` |
| `Lumina/Views/P0/P0RootView.swift` | Route switch |
| `Lumina/Views/P0/P0ContactSheetView.swift` | Sheet host; `ContactSheetInspectImage`; `ContactSheetRepresentable` |
| `Lumina/Views/P0/ContactSheetCollection.swift` | `NSCollectionView` + `ContactSheetItemView` (`NSImageView`) |
| `Lumina/Views/P0/P0SinglePhotoEditor.swift` | Editor overlay: `DevelopMetalView` or `ContactSheetInspectImage`; filmstrip `ForEach` |
| `Lumina/Views/P0/P0CropControls.swift` | `P0CropOverlay` on the editor photograph when crop section is expanded |
| `Lumina/ViewModels/P0SessionModel.swift` | Focus, density, inspect warm, `ThumbCache.prefetch`, `developScheduler.prewarm` |
| `Lumina/Services/PhotoImageCache.swift` | Cell / inspect / filmstrip decode + memory LRU + prefetch queue |
| `Lumina/Services/PhotoImageCacheBudget.swift` | Named byte ceilings and prefetch width (W6 proposal; not in `tokens.yaml`) |
| `Lumina/Services/ContactSheetPreparation.swift` | P0 ingest; writes `thumbPath` / `gridThumbPath` |
| `Lumina/Services/ProjectStore.swift` | `PreviewExtractor` used by that ingest |
| `Lumina/Develop/DevelopRenderScheduler.swift` | Editor CI surfaces; `prewarm`; `RenderGate` |
| `Lumina/Develop/DevelopRenderGraph.swift` | Shared `CIContext` pair; RAW/proxy graph |
| `Lumina/Develop/DevelopColorPolicy.swift` | `ciContextOptions` |
| `Lumina/Develop/PreparedRawSession.swift` | Per-photo RAW session (editor) |
| `Lumina/Develop/Lab/DevelopMetalView.swift` | Editor drawable: `MTKView` + `CAMetalLayer`. Folder is `Lab/`; **used by `P0SinglePhotoEditor` on the default inspect path** — not lab-gated. |

`P0SessionModel` opens shoots through `ContactSheetPreparation.openFolder` / `openExisting` (L255, L282). It does not call `ImportPipeline`.

`rg` of `PreviewSpine|MetalBrowseCanvas|MetalPreviewPool|StablePhotoView|GradedPhotoView` in `Lumina/Views/P0` and `P0SessionModel.swift` → **0** hits.

### Live chrome on the same routes (no photograph pixels)

`P0OpenView.swift` · `P0GroupingView.swift` · `P0AdjustmentRail.swift` · `P0EditSlider.swift` · `P0KeyRoutingModifier.swift` · `P0EscLadder.swift`. Not inventoried below except where a construct sits on a repeated photograph (`filmstripThumb` is in `P0SinglePhotoEditor` and is inventoried).

### Legacy-reachable (door only — do not measure as the default path)

W8 register in `design/strategy/legacy-disposition.md` still matches the door: `P0LegacyShellDoor.swift` → `ContentViewLegacyHost` → `LuminaShellView` + `ImportLoadingView`. Photograph surfaces behind that door include `ProgressivePhotoWall`, `MetalBrowseCanvas`, `SpeedBrowseViewer`, `ContinuousWorkspaceView`, `TreatmentStageView`, `StablePhotoView`. They are out of scope for Parts 2–3.

### Dead

W8 deleted `DecisionDock.swift` (0 external refs). Still absent on this SHA (`rg -l DecisionDock Lumina` → **0**).

### Disagreements with W8 `legacy-disposition.md` / W8 BUILD_LOG counts

W8 measured branch `cursor/w8-legacy-severance-39dd` (BUILD_LOG 2026-08-13). This SHA is later.

| Claim in W8 register / BUILD_LOG | This tree @ `4feea5c` | Verdict |
|----------------------------------|------------------------|---------|
| Total Swift 151 / 35,064 lines | `swift_reachability.py`: **148** files / **33,029** lines | Count drifted after later merges |
| From `LuminaApp` BFS 127 / 30,189 | **132** / **31,069** | Count drifted |
| Legacy-only 27 / 7,100 | **25** / **6,407** | Count drifted |
| `SKIP_DIRS = {"Develop/Lab"}` in `swift_reachability.py` L15 | `DevelopMetalView` is on the live inspect path (`P0SinglePhotoEditor` L177) but is excluded from the BFS file set | **Disagrees with “from LuminaApp” as a live-pixel census** — BFS under-counts the editor drawable |
| BFS from `LuminaApp` = live path | BFS includes door type names (`ProjectViewModel`, `LuminaShellView`, …) | **Disagrees** — BFS is reachability including the door, not default-launch pixels |
| `surface-sweep.md` (P8 @ `a076644`): no pointer marks; no `LuminaSpring` | This SHA has `PointerCullMarkControl` and `LuminaSpring` / `#59` | Stale prior strategy doc; not a W8 disposition error |

No D/R CONFLICT: nothing in this inventory changes a key, a surface, or a shelf. Open question #7 is left unnamed. Open question #9 is stated, not answered.

---

## PART 2 — Inventory by category (no ranking)

Each item: file · line · construct · structural cost · question for the Mac session.

### A. Cell content path — 5 items

**A1 — Pixel delivery in the sheet cell**  
`Lumina/Views/P0/ContactSheetCollection.swift` L120, L146–150, L330.  
Construct: `ContactSheetItemView` holds a private `NSImageView`; `imageScaling = .scaleProportionallyUpOrDown`; `wantsLayer = true`; assignment is `imageView_.image = img`.  
`rg -n layerContentsRedrawPolicy Lumina --glob '*.swift'` → **0**.  
Structural cost: AppKit image-view bind + layer-backed view. Not `CALayer.contents`. Not SwiftUI `Image` in the cell.  
Question: On a visible-cell bind, does Instruments show a layer contents update, a bitmap redraw, or both? Is the absence of `layerContentsRedrawPolicy` associated with extra redraws when chrome siblings change?

**A2 — Which fidelity rung the cell requests (RUNG QUESTION)**  
Ingest (`ContactSheetPreparation.swift` L376–384): writes browse JPEG at `maxPixelSize: 1600` to `thumbPath`; downscales to `gridThumbPath` at `maxPixelSize: 1200`. Comment at L383 names `768` as the prior grid rung.  
Cell (`ContactSheetCollection.swift` L311–325): comment still says it prefers the 1600 px browse preview over the “768px grid cache”; code prefers `asset.thumbPath ?? asset.gridThumbPath` (1600 path first). Decode `maxPixelSize` is `max(view.bounds.width, 120) * (NSScreen.main?.backingScaleFactor ?? 2)`, then `max(..., 180)` — not a named rung.  
`PhotoImageTier.gridMaxPixelSize = 512` (`PhotoImageCache.swift` L19) is unused by the cell.  
`rg -n '\b(1600|1200|768|512|2400)\b' design/tokens.yaml DesignTokens/HiFiTokens.generated.swift` → **0**.  
Structural cost: one JPEG decode per cell identity at a computed pixel cap; `NSImageView` then scales to the cell frame.  
Question: Is the grid rung mis-sized relative to the cell’s drawn size on a Retina display? Does the cell’s computed cap match the 1600 file, the 1200 file, or neither? (Fidelity judgement of “looks grainy” is SPIKE A’s door — not answered here.)

**A3 — Chrome vs photograph redraw**  
`ContactSheetCollection.swift` L176–179, L228–244.  
Construct: `focusRing`, `markStack`, and `pointerCullStack` are sibling `NSView`s of `imageView_`. `applyChrome` sets `focusRing.layer` border and `imageView_.alphaValue` (0.50 when rejected; D27 dim-in-place). Marks are rebuilt by removing and re-adding arranged subviews (L246).  
Structural cost: chrome mutation on sibling layers; alpha change on the image view; mark-stack subview churn.  
Question: Does a focus/cull chrome update invalidate the photograph’s layer contents, or only the sibling layers?

**A4 — Inspect overlay leaves the collection mounted**  
`P0ContactSheetView.swift` L17–20.  
Construct: collection `opacity` 0 and `allowsHitTesting` false while `P0SinglePhotoEditor` is shown; the representable stays in the `VStack`.  
Structural cost: the collection view remains in the hierarchy; `updateNSViewController` still runs (`P0ContactSheetView.swift` L220–234).  
Question: While opacity is 0, do cells still decode, still receive `reloadData` / chrome refresh, and still produce layer updates?

**A5 — Editor fallback and filmstrip use a different loader**  
`P0ContactSheetView.swift` L166–186 (`ContactSheetInspectImage`): SwiftUI `Image(nsImage:)` after `PhotoImageCache.load(..., maxPixelSize: 2400, allowRAW: false)`.  
Call sites: editor fallback `P0SinglePhotoEditor.swift` L199; filmstrip thumb L326.  
Structural cost: a second decode path (SwiftUI image, fixed 2400 cap) beside the cell’s `NSImageView` path.  
Question: Do filmstrip thumbs and sheet cells share a cache key, or do they decode the same JPEG twice at different caps?

---

### B. Collection view behaviour — 5 items

**B1 — `NSCollectionViewPrefetching`**  
`ContactSheetCollectionController` (`ContactSheetCollection.swift` L366) conforms to `NSCollectionViewDataSource` and `NSCollectionViewDelegate` only.  
`rg -n 'NSCollectionViewPrefetching|cancelPrefetching' Lumina --glob '*.swift'` → **0**.  
`onVisibleRange` exists (L383, L618–621) and is invoked from `willDisplay` and scroll; `ContactSheetRepresentable` never assigns it.  
Structural cost: no protocol-level prefetch/cancel of items the collection asked to prefetch; visible-range callback is unwired.  
Question: Without `NSCollectionViewPrefetching`, which items does the collection ask to populate, and does `willDisplay` alone cover that set? (Asked-for cells are not speculative pre-render.)

**B2 — `reloadData` call sites**  
Live path: **2** sites, both in `ContactSheetCollection.swift` `apply` — L455 and L470 — when item IDs change and the prefix-compatible incremental insert (L460–467) does not apply. Threshold at L453: `oldCount == 0 || abs(newIDs.count - oldCount) > 40 || !prefixOK`.  
Comment at L477: “Cull / focus / selection — chrome only; never reloadData for one-cell decisions.”  
Legacy `PhotoGridView` (reloadData at L77) was deleted; zero callers.  
Structural cost: full data-source reload + async scroll restore (L456–458, L471–473).  
Question: On incremental ingest after the first 40 IDs, which branch runs — `insertItems` or `reloadData` — and does `reloadData` recreate visible `NSImageView`s?

**B3 — `invalidateLayout` triggers**  
Live path: **1** site — `densityColumns` `didSet` at L375 (`updateRowHeight(); layout.invalidateLayout()`). `apply` also assigns `densityColumns` (L447), so every representable update that changes density invalidates.  
Pinch: `handleMagnify` L624–637 accumulates magnification and calls `onDensityDelta` at ±0.25, which is `adjustDensity` (`P0SessionModel.swift` L931–932: clamp 2…12). Each step assignment hits the `didSet`.  
`shouldInvalidateLayout(forBoundsChange:)` L112–114 invalidates when width changes by more than 0.5.  
Legacy `PhotoGridView` (invalidateLayout at L66) was deleted; zero callers.  
Structural cost: layout invalidation of the custom `ContactSheetLayout` (L73–102 rebuilds all attributes).  
Question: During a pinch gesture, how many `invalidateLayout` / `prepare` cycles fire per named density step? (Named step list is open question #7 — not named here.)

**B4 — Density representation vs D49**  
`P0SessionModel.swift` L83 default `densityColumns = 6`; L931–932 and L1057 clamp to `2...12`. `tokens.yaml` `density_snap` (L193–197) is `named_steps_only` with notes “Named step list OPEN.”  
Structural cost: integer column count drives `rowHeight(for:)` (L540–546).  
Question: Does the live integer 2…12 match D49’s “named steps,” or is the token still OPEN (open question #7)? This session does not name the steps.

**B5 — Custom layout attribute set**  
`ContactSheetLayout.prepare` L73–102: `attributes.removeAll(keepingCapacity: true)` then one `NSCollectionViewLayoutAttributes` per item.  
Structural cost: full attribute rebuild on each `prepare`.  
Question: Open question #9 — does this `NSCollectionView` virtualize rows and gaps, or does `prepare` always walk the full `aspects` array? Stated; not answered.

---

### C. Decode and concurrency — 10 items

**C1 — `PhotoImageCache.decode` option flags**  
`PhotoImageCache.swift` L287–299. When `maxPixelSize` is set:

```
kCGImageSourceCreateThumbnailFromImageIfAbsent: false
kCGImageSourceCreateThumbnailFromImageAlways: false
kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
kCGImageSourceCreateThumbnailWithTransform: true
kCGImageSourceShouldCacheImmediately: false
```

Then `CGImageSourceCreateThumbnailAtIndex` **??** `CGImageSourceCreateImageAtIndex(source, 0, nil)` (full image, no options). When `maxPixelSize` is nil: full image only.  
`NSImage(cgImage:size:)` uses `scale: 2` (L304–306).  
Structural cost: a thumbnail attempt that may fall through to a full-frame decode.  
Question: On the 1600 browse JPEGs the cell actually opens, does the thumbnail path return, or does the `??` full-image path run?

**C2 — Ingest `PreviewExtractor` option flags (feeds the live sheet)**  
`ProjectStore.swift` `readEmbeddedThumbnail` L129–135: IfAbsent **false**, Always **false** (embedded only).  
`synthesizeBrowsePreview` L140–145: IfAbsent **true**, Always **true**.  
`ContactSheetPreparation` L376–380 calls `extractBrowsePreview(..., maxPixelSize: 1600, minLongEdge: 800)`. Defaults on the function are 2400 / 2000 (L93–94); the P0 call overrides.  
Structural cost: one ingest-time decode/write per asset (browse) plus an optional second write (grid 1200).  
Question: For the fleet bodies, which origin (`embedded` / `synthesized` / `processed`) does ingest actually write? (Needs real files — see Part 3 fixtures.)

**C3 — Live prefetch call sites (3 constructs)**  
1. `P0SessionModel.setFocus` L807–809: `ThumbCache.shared.prefetch(path)` — default `maxPixelSize: PhotoImageTier.gridMaxPixelSize` (**512**). One path. Deduped by `ThumbCache.warm`. Fan-out bounded by `PhotoImageCacheBudget.prefetchConcurrencyWidth` (**8**, `PhotoImageCacheBudget.swift` L18). Cancellable via `prefetchGeneration` on `endSession` (L95–98).  
2. Cell `loadImage` L321–337: `PhotoImageCache.load` (not `prefetch`) at the cell’s computed cap; `Task` cancelled by `loadToken` on reuse (L340–344).  
3. `ContactSheetInspectImage` L182: `load` at **2400**.  
Cache key is `path@maxPixelSize` (`PhotoImageCache.swift` L73–76).  
Structural cost: three different caps (512 / cell-computed / 2400) on the same file path → up to three cache keys.  
Question: Does the 512 prefetch populate the cell’s key, or does the cell always miss and decode again? Is visible-cell `load` (`.userInitiated` detached, L143) ordered above prefetch (prefetch `load` has no separate priority at L182)?

**C4 — `beginSession` on the P0 path**  
`rg -n beginSession Lumina/Views/P0 Lumina/ViewModels/P0SessionModel.swift` → **0**.  
`SessionCache.beginEditingSession` is called from `ProjectViewModel` (legacy door) and `ProgressivePhotoWall` (legacy).  
Structural cost: P0 uses `PhotoImageCache.shared` memory LRU without a session begin/end; session disk and `endSession` generation bump are unused on the default path.  
Question: Across opening two shoots on P0, does the LRU retain the first shoot’s decodes until byte eviction?

**C5 — Editor neighbor `prewarm`**  
`P0SessionModel.scheduleDebouncedPrewarm` L725–731: `neighborIDs(..., radius: 1)` then `developScheduler.prewarm(photos:recipe:)` with `.neutral`.  
`DevelopRenderScheduler.prewarm` L370–383: `photos.prefix(3)`; index 0 at `.userInitiated`, others `.utility` and `speculative: index > 0`.  
`interactiveLimit = 2` (`DevelopRenderScheduler.swift` L182) via `RenderGate`.  
`cancelExcept(photoID:)` L215–218 cancels other inflight on inspect focus change (L692).  
Structural cost: up to 3 settled RAW renders; 2 of them marked speculative in the presentation cache.  
Question: Did the editor view ask for those neighbor RAW frames, or only for JPEG filmstrip thumbs (`ContactSheetInspectImage`)? If the Metal view asked only for the focused photograph, is neighbor RAW `prewarm` speculative pre-render (shelved)?

**C6 — Ingest concurrency**  
`ContactSheetPreparation.previewConcurrency` L60–62: `min(max(activeProcessorCount * 2, 8), 16)`.  
`extractChunk` L351–404: `withTaskGroup` — one task per index in the chunk; chunked at that concurrency (L407, L423).  
Structural cost: unbounded relative to visible cells (bounded by 8–16 and the chunk, not by what the collection asked for). Ingest writes files; it is not cell pre-render.  
Question: During first paint of the sheet, how many ingest tasks overlap visible-cell `load` tasks?

**C7 — `autoreleasepool` count**  
`rg -n autoreleasepool Lumina --glob '*.swift'` → **5**, all in `PhotoImageCache.swift`: L242 (session-disk read), L252 (session-disk write), L274 (decode outer), L279 (source), L287 (CGImage).  
**0** in `ContactSheetCollection.swift`, `P0SessionModel.swift`, `DevelopRenderGraph.swift`, `DevelopMetalView.swift`, `ProjectStore.swift`.  
Question: On the cell decode path, do the 3 nested pools in `decode` (L274/279/287) bound peak autorelease, or does the `??` full-image fallback still accumulate?

**C8 — `CIContext` construction**  
Live default path: **2** statics in `DevelopRenderGraph.swift` L26–27 (`context`, `exportContext`), both `DevelopColorPolicy.ciContextOptions`. `DevelopMetalView.Renderer` L67 assigns `DevelopRenderGraph.sharedContext` (no new context).  
Lab/harness only (not default launch): `RawHarnessRunner.swift` L140 per-call; `P0EditHarnessRunner.swift` L287 per-call.  
Question: Does the editor path use one long-lived context, or do preview and export contexts both stay alive during inspect?

**C9 — Cell `Task` fan-out**  
`loadImage` L321 starts an unstructured `Task` per identity change. `prepareForReuse` L340–344 invalidates `loadToken` and clears the image. There is no shared semaphore on cell loads (prefetch width 8 does not wrap `load`).  
Structural cost: one unbounded task per newly configured cell (unbounded relative to `prefetchConcurrencyWidth`).  
Question: During a fling across a large sheet, how many cell `load` tasks are in flight at once, and does reuse cancel complete before the next decode starts?

**C10 — Other `CGImageSource` sites**  
`rg -n 'CGImageSourceCreate' Lumina --glob '*.swift'` hits many services (`QualityScorer`, `PhotoScorer`, `AutoDevelop`, `VisionAssist`, `EmbeddingService`, `FaceDetector`, `BlurScorer`, `MetalPreviewPool`, `PreviewSpine`, `MediaFormats`, `DevelopRenderGraph` L372).  
On the live photograph-pixel list, the decode sites that feed pixels are **C1** and **C2** plus `DevelopRenderGraph` RAW (CIRAW / ImageIO at L372). The scorer/embedding sites are not referenced from `P0SessionModel` / P0 views (`rg` of those type names in those files → **0**).  
Question: Confirm at runtime that P0 inspect/sheet never enters `PreviewSpine` / `MetalPreviewPool` decode.

---

### D. Compositing in repeated views — 5 items

Counts are inside repeated photograph views only. A tree-wide count is omitted.

**D1 — Contact-sheet cell (repeated `NSCollectionViewItem`)**  
`ContactSheetItemView`: **0** SwiftUI `clipShape` / `overlay` / `shadow` / `blur` / `GeometryReader` / `compositingGroup`. Corner radius is `CALayer` on the image view (L149–150).  
Structural cost: layer corner rasterization on the image view (offscreen-pass question).  
Question: Does `masksToBounds` + `cornerRadius` on `imageView_` create an offscreen pass per visible cell?

**D2 — Filmstrip thumb (repeated `ForEach`)**  
`P0SinglePhotoEditor.filmstripThumb` L321–351, used from `ForEach` L295–298. Window L380–382: `idx - 14 ..< idx + 15` → up to **29** items.  
Inside that repeated view: `clipShape` **1** (L335) · `overlay` **1** (L336–344) · `shadow` **1** (L346–350) · `scaleEffect` **1** (L345) · `blur` **0** · `GeometryReader` **0** · `compositingGroup` **0**.  
Structural cost: clip + stroke overlay + shadow + scale on each of up to 29 thumbs (offscreen-pass question).  
Question: Does each filmstrip thumb allocate an offscreen pass for clip/shadow/scale?

**D3 — `ContactSheetInspectImage` inside that `ForEach`**  
L326: each thumb loads via `ContactSheetInspectImage` (2400 cap) into a 92×68 frame (L327).  
Structural cost: decode at 2400, layout at 92×68.  
Question: Does the 2400 decode plus `clipped()` (L328) produce a downsample in ImageIO, in SwiftUI, or both?

**D4 — Live blur on fidelity crossfade or birth**  
`rg -n '\.blur\(' Lumina/Views/P0 --glob '*.swift'` → **0**.  
`StablePhotoView.swift` L83 `.blur(radius: birthBlurRadius + upgradeBlur)` is **not** on the live path (Part 1).  
Structural cost on the live path: none observed.  
Question: Confirm at runtime that inspect/sheet birth and fidelity changes do not enter `StablePhotoView` blur.

**D5 — Editor photograph stack (single, not a cell; noted because it sits on the live inspect path)**  
`P0SinglePhotoEditor.photographStage` L158–220: `DevelopMetalView` or `ContactSheetInspectImage`; optional `P0CropOverlay` (`GeometryReader` L159). No `compositingGroup` on P0. `CropOverlayView.swift` L35 `compositingGroup()` is legacy/shared and not referenced from P0.  
Question: Does `P0CropOverlay`’s even-odd fill (`P0CropControls.swift` L166) create an offscreen pass over the Metal view?

---

### E. Layout engine split — 4 items

**E1 — `LazyVGrid` on the live path**  
`rg -n LazyVGrid Lumina --glob '*.swift'` → **5** sites: `ProgressivePhotoWall.swift` L19, L59 · `UncertainAndClusterViews.swift` L352 · `ShootSelectionView.swift` L17 · `TreatmentStageView.swift` L721.  
**0** in `Lumina/Views/P0`.  
Question: Confirm none of those 5 sites appear in a default-launch Instruments trace.

**E2 — `NSCollectionView` on the live path**  
**1** live site: `ContactSheetCollectionView` / `ContactSheetCollectionController` (`ContactSheetCollection.swift` L350, L366).  
Legacy `PhotoGridView` was deleted (zero callers).

**E3 — Filmstrip is not a collection view**  
`P0SinglePhotoEditor.swift` L292–311: `ScrollView` + `HStack` + `ForEach` of up to 29 items. Not `LazyHStack`.  
Structural cost: all windowed thumbs exist as SwiftUI views at once.  
Question: Does the filmstrip instantiate all 29 `ContactSheetInspectImage` tasks when inspect opens?

**E4 — Open question #9 (stated, not answered)**  
`design/contract-v6.md` L370: “v5 open question 3 — NSCollectionView virtualization of rows/gaps (still open).”  
Question for the Mac session (same question; no answer here): Does the live `ContactSheetLayout` virtualize rows and gaps, or does `prepare` always materialize attributes for every asset?

---

### F. Frame pacing and display — 4 items

**F1 — Display-link types**  
`rg -n 'CVDisplayLink|CADisplayLink|CAMetalDisplayLink' Lumina --glob '*.swift'` → **0**.

**F2 — `MTKView` / `CAMetalLayer` on the live path**  
`DevelopMetalView.swift` L19–34, L42–49, L73–123: `MTKView` with `isPaused = true`, `enableSetNeedsDisplay = true`; `CAMetalLayer` colorspace set from the window screen. Draw is `MTKViewDelegate.draw` on `needsDisplay = true` (L49). Not lab-gated: `P0SinglePhotoEditor` L177 constructs it on default inspect.  
`MetalBrowseCanvas.swift` L6–8: `CAMetalLayer` — legacy door only.  
Structural cost: one event-driven Metal draw per `updateNSView`.  
Question: How many `draw(in:)` calls fire per slider scrub / neighbor step? Does `autoResizeDrawable` cause extra draws on window resize?

**F3 — Platform fact (not a recommendation with a number)**  
Apple has largely replaced `CVDisplayLink` with `CADisplayLink`, and `CAMetalDisplayLink` for Metal. This tree uses neither; the live editor uses paused `MTKView` + `setNeedsDisplay`.  
Question: On the Mac session’s OS version, does paused `MTKView` still pace to the display, or only to `setNeedsDisplay`?

**F4 — Multi-display colorspace**  
`DevelopMetalView.updateNSView` L42–47 writes `metalLayer.colorspace` from `view.window?.screen`.  
Question: When the window moves between displays, how many context/layer colorspace changes and redraws occur? (Needs a person and two displays — Part 3.)

---

### G. Tokens and constants — 3 items

**G1 — C1 register**  
`rg -n '^## .*C1|session C1|C1 —' BUILD_LOG.md` → **0**. No session named C1 has landed.  
The widened magic-number gate on this tree is **W1** (`BUILD_LOG.md` 2026-08-13): `Scripts/harness/lint/magic_numbers.py` `SCAN_ROOTS` = `Lumina/Views`, `Lumina/Design`, `Lumina/Shell` only (L14–18). Debt register: `artifacts/harness/magic_number_allowlist.txt` (**276** non-comment rows).  
P0 photograph-view allowlist rows: **26** (`ContactSheetCollection` + `P0ContactSheetView` + `P0SinglePhotoEditor`).  
`Lumina/Services`, `Lumina/ViewModels`, `Lumina/Develop` are **outside** the W1 scan.

**G2 — Decode/rung literals absent from tokens**  
`1600`, `1200`, `768`, `512`, `2400` do not appear in `design/tokens.yaml` or `HiFiTokens.generated.swift`.  
They appear as code constants:

| Literal | File:line | Status |
|---------|-----------|--------|
| 512 | `PhotoImageCache.swift` L19 `gridMaxPixelSize` | Named in code; not a token; used by `ThumbCache.prefetch` default, not by the cell |
| 1600 | `PhotoImageCache.swift` L25; `ContactSheetPreparation.swift` L379 | Named / ingest; not a token |
| 1200 | `ContactSheetPreparation.swift` L384 | Ingest grid write; not a token |
| 768 | comments only (`ContactSheetCollection.swift` L311; `ContactSheetPreparation.swift` L383) | Comment; ingest writes 1200 |
| 2400 | `P0ContactSheetView.swift` L182; `ProjectStore.swift` L93 default | Inspect/filmstrip load; extractor default |
| 800 | `ContactSheetPreparation.swift` L380 `minLongEdge` | Ingest; not a token |
| 8 | `PhotoImageCacheBudget.swift` L18 | Documented W6 budget (awaiting ruling); not a token |
| 48 / 96 / 128 / 256 MiB | `PhotoImageCacheBudget.swift` L8–14 | Documented W6 budget; not a token |
| 2 | `DevelopRenderScheduler.swift` L182 `interactiveLimit` | Code constant; not a token |

**G3 — Other render-path literals on the live pixel files (neither token nor W6 budget)**  
Allowlisted inside W1 scan (not re-derived; see register): `ContactSheetCollection` row math uses `88`, `1.45`, `800` (L541–545); reload threshold `40` (L453); magnify `0.25` (L626); cell decode floors `120` / `180` (L320–324).  
Outside W1 scan: `P0SessionModel` density default `6` and clamp `2...12` (L83, L931); inspect delays `120_000_000` / `90_000_000` ns (L681, L697); neighbor radius `1` (L725). `P0SinglePhotoEditor` filmstrip `92×68`, height `86`, window `14`/`15` (L327, L305, L380–381); 1:1 zoom `2.2` (L179). `PhotoImageCache.decode` scale `2` (L304).  
Question: Which of these must become tokens or documented budgets before SPIKE C changes any of them? (A change without a baseline cannot be evaluated — Part 4.)

---

## PART 3 — Measurement plan

One measurement per inventory item. Instrument · fixture · reading that would confirm or refute. No numbers are claimed here.

| ID | Instrument | Fixture | Reading that settles it |
|----|------------|---------|-------------------------|
| A1 | Core Animation instrument + view debugger | Real contact sheet, one focused cell | Whether `NSImageView` bind updates layer contents; whether chrome-only `applyChrome` marks the image layer dirty |
| A2 | Points of Interest + ImageIO / `os_signpost` on `cache.load` + ruler on cell frame | Same shoot at 2 and 12 columns (do not name steps) | Decode `maxPixelSize` vs cell pixel width vs file long edge (1600 vs 1200). Rung mismatch = those three disagree |
| A3 | Core Animation (color blended / offscreen) | Toggle P/X on the focused cell | Image layer dirty vs sibling-only update |
| A4 | Allocations + signposts `p0.visible_cell_cache` while inspect is open | Open inspect on a 200+ frame shoot | Cell decode / `reloadData` after opacity 0 |
| A5 | Cache-key log (path + maxPixelSize) | Focus a cell, then open inspect | 512 vs cell-cap vs 2400 key hits/misses |
| B1 | Time Profiler on scroll + `indexPathsForVisibleItems` probe | Continuous trackpad scroll (person) | Items configured vs items asked; no protocol prefetch |
| B2 | Signpost around `apply` + `reloadData` | Ingest a folder that grows past 40 IDs | Which branch; whether visible `NSImageView`s are recreated |
| B3 | Layout / Time Profiler during pinch | Pinch through several density integers | `invalidateLayout` / `prepare` count per integer step |
| B4 | Constitution / token read (not a render instrument) | — | Open question #7 — constitution session, not SPIKE C |
| B5 | Time Profiler in `ContactSheetLayout.prepare` + item count | 500-frame real card | Attribute count vs visible item count (open question #9) |
| C1 | ImageIO debug / signpost inside `decode` | 1600 browse JPEG from a real ARW | Thumbnail hit vs `CreateImageAtIndex` fallback |
| C2 | Ingest signposts + file long-edge | Six-body fleet (missing — see below) | Origin per body; written long edge |
| C3 | `PhotoImageCache.prefetchDiagnostics` + cache-key hits | Arrow through 50 cells | Prefetch key 512 vs cell key; inflight `load` vs prefetch |
| C4 | Allocations / trackedMemoryBytes across two P0 opens | Two real shoots | LRU retains shoot 1 after opening shoot 2 |
| C5 | `DevelopRenderScheduler.metrics` + signposts | Inspect + arrow to neighbors | Settled RAW starts for photos whose only on-screen request is a 92×68 JPEG |
| C6 | Thread / signpost during first open | Real card, first paint | Ingest task count vs visible-cell `load` count |
| C7 | Allocations (persistent VM) on decode | Rapid scroll | Peak around `decode` with fallback vs thumbnail-only |
| C8 | Allocations / Core Image | Open inspect, scrub, export | Live context count (1 vs 2) |
| C9 | Thread inflight count on `cache.load` | Fling scroll (person, momentum) | In-flight cell tasks vs visible cells |
| C10 | Time Profiler stack | Default launch sheet + inspect | Presence/absence of `PreviewSpine` / `MetalPreviewPool` frames |
| D1 | Core Animation offscreen-pass overlay | Sheet at rest | Pass per visible cell from corner radius |
| D2 | Core Animation offscreen-pass overlay | Inspect filmstrip | Pass per thumb from clip/shadow/scale |
| D3 | ImageIO + Core Animation | Inspect filmstrip | Where 2400→92×68 happens |
| D4 | Core Animation + view debugger | Birth of a cell; inspect open | No `StablePhotoView` blur on the live path |
| D5 | Core Animation offscreen-pass overlay | Crop section expanded | Pass over Metal from even-odd fill |
| E1 | Time Profiler | Default launch only | Zero `LazyVGrid` frames |
| E2–E3 | View debugger + Allocations | Sheet vs inspect | One `NSCollectionView`; filmstrip view count ≤ 29 |
| E4 | Same as B5 | Same as B5 | Open question #9 |
| F1–F3 | Metal System Trace / GPU | Inspect scrub | `draw(in:)` count per input; no display-link objects |
| F4 | Metal System Trace | Window dragged to a second display (person) | Colorspace set + extra draw |
| G1–G3 | Static (already done) + SPIKE C must not change literals without a baseline | — | — |

### Fixtures that do not yet exist

`design/fixture-manifest.md` §1 names six bodies: `sony-a7iv`, `canon-r6ii`, `nikon-z6iii`, `fujifilm-xt5`, `iphone-proraw`, `iphone-heic`, plus `jpeg-sidecar-pair`. Card images include `card-clean-500`. Synthetic XCUITest ids include `mixed-200`.

Present in this tree:

| Id | On disk | What it actually is |
|----|---------|---------------------|
| Six-body fleet RAW/HEIC | **Absent** | `find` of `*.ARW,*.CR3,*.NEF,*.RAF,*.DNG,*.HEIC` → **1** path |
| `Scripts/harness/fixtures/cp2/jpeg-sidecar-pair/DSC0001.ARW` | Present, **4 bytes**, `file`: ASCII text | Stub, not a camera RAW |
| `DSC0001.JPG` | Present, **4 bytes**, ASCII text | Stub, not a JPEG photograph |
| `card-clean-500` | **Absent** as files | `RamTierHarnessRunner.swift` L31, L117–119 **synthesizes** 500 JPEGs |
| `mixed-200` | **Absent** as files | `UITestFixtures.swift` L11, L29: “small synthesized JPEGs (no Sony RAW)”; RAM harness L24, L117–119 synthesizes 200 JPEGs |

W6’s RAM gate (`RamTierHarnessRunner.synthesizeJPEG`) writes flat JPEGs and still labels the tiers `mixed-200` and `card-clean-500`. A render baseline on those synthetics would repeat that failure: it would not exercise embedded-JPEG size, demosaic, or body-specific preview origin (C2).

### Measurements that cannot be automated

- Continuous trackpad scroll with real momentum (B1, C9). Needs a person at a machine, as SPIKE B needed a person and real photographs.
- Multi-display colorspace / redraw (F4). Needs a person and two displays.

---

## PART 4 — What this session refuses to do

Absence below is refusal, not oversight.

- **No baseline.** No p50 / p95 / hitch ratio / frame-time series. SPIKE C PART 1 owns the baseline, and that baseline must be captured **before** any change from this inventory lands. A change made without a baseline cannot be evaluated and quietly becomes permanent.
- **No percentiles, no hitch ratios.**
- **No impact ranking.** Categories only.
- **No sealed render path.** SPIKE C seals, after measurement.
- **No Tier 2 architecture proposal.** Banked (D46 / D38).
- **No code.** This session owns no code paths.
- **No naming of density steps.** Open question #7 — constitution session.
- **No fidelity judgement** of the 1600 vs 1200 vs 768 rungs. SPIKE A’s door.
- **No un-shelving** of speculative pre-render, multi-select, swim-lanes, or any other register row.

SPIKE C owns each of the above.

---

## UNKNOWN (only measurement or a missing fixture can settle)

1. Whether `ContactSheetLayout.prepare` virtualizes (open question #9).  
2. Whether `CreateThumbnailAtIndex` with IfAbsent/Always false returns on 1600 browse JPEGs, or the full-image fallback runs (C1).  
3. Whether prefetch key `path@512` ever hits a cell load (C3).  
4. Whether the opacity-0 collection still decodes (A4).  
5. Whether neighbor RAW `prewarm` is asked-for or speculative (C5).  
6. Whether P0 ever calls `PhotoImageCache.beginSession` through a path not named in Part 1 (C4) — static read says no.  
7. Written long-edge and origin of ingest JPEGs on real bodies (C2) — fleet files absent.  
8. `draw(in:)` rate of paused `MTKView` under scrub (F2).  
9. Offscreen-pass presence for cell corner radius and filmstrip clip/shadow (D1, D2).  
10. Trackpad-momentum behaviour (B1, C9) — not automatable.  
11. Multi-display behaviour (F4) — not automatable.  
12. Whether existing on-disk shoots still have 768 px grid files despite ingest now writing 1200 (A2) — depends on files not in this tree.

---

## Verify — grep commands and outputs (this SHA)

FAST was not run. C3 owns ledger idempotence; this session does not touch `artifacts/harness/ledgers/orchestration-only.json`.

```
git rev-parse HEAD
4feea5c6b68dcb8e2a807025bdc517c299f435ec

uname -s; command -v xcodebuild || echo "xcodebuild=MISSING"
Linux
xcodebuild=MISSING

rg -n "### D27" design/contract-v6.md
89:### D27 — Motion/fade *(amended by audit frame-F — one-line)*

rg -n "### D28|D28 —" design/contract-v6.md
(no heading)

rg -n "^\*\*D28" design/contract-v5.md
228:**D28. Elasticity: elastic in motion, exact at rest, anchored at the focus.** Springs

rg -n "### D49|R-X\.2" design/contract-v6.md
195:### D49 — Layout quantized everywhere *(R-X.2)*

rg -n "layerContentsRedrawPolicy|NSCollectionViewPrefetching|cancelPrefetching" Lumina --glob '*.swift'
(no matches)

rg -n "CVDisplayLink|CADisplayLink|CAMetalDisplayLink" Lumina --glob '*.swift'
(no matches)

rg -n "reloadData\(" Lumina --glob '*.swift'
Lumina/Views/P0/ContactSheetCollection.swift:455
Lumina/Views/P0/ContactSheetCollection.swift:470

rg -n "invalidateLayout\(" Lumina --glob '*.swift'
Lumina/Views/P0/ContactSheetCollection.swift:375

rg -n "LazyVGrid" Lumina --glob '*.swift'
5 sites, none under Lumina/Views/P0

rg -n "CIContext\(" Lumina --glob '*.swift'
DevelopRenderGraph.swift:26
DevelopRenderGraph.swift:27
RawHarnessRunner.swift:140
P0EditHarnessRunner.swift:287

rg -n "autoreleasepool" Lumina --glob '*.swift'
PhotoImageCache.swift:242, 252, 274, 279, 287   (5)

rg -n '\.blur\(' Lumina/Views/P0 --glob '*.swift'
(no matches)

rg -n '\b(1600|1200|768|512|2400)\b' design/tokens.yaml DesignTokens/HiFiTokens.generated.swift
(no matches)

python3 Scripts/harness/lint/swift_reachability.py
total_files=148 total_lines=33029
from_lumina_app_files=132 from_lumina_app_lines=31069
legacy_only_files=25 legacy_only_lines=6407

find Scripts/harness/fixtures -type f
Scripts/harness/fixtures/cp2/jpeg-sidecar-pair/DSC0001.ARW   (4 bytes, ASCII)
Scripts/harness/fixtures/cp2/jpeg-sidecar-pair/DSC0001.JPG   (4 bytes, ASCII)
Scripts/harness/fixtures/cp2/jpeg-sidecar-pair/DSC0001.xmp
```

### Report

| Metric | Count |
|--------|------:|
| Files on the live photograph-pixel path | **16** |
| Live chrome files (same routes, no photograph pixels) | **6** |
| Items inventoried A / B / C / D / E / F / G | **5 / 5 / 10 / 5 / 4 / 4 / 3** (36) |
| Items marked UNKNOWN | **12** |
| Fixtures missing or stub/synthetic | six-body fleet; `card-clean-500`; `mixed-200`; `jpeg-sidecar-pair` (4-byte stubs) |
