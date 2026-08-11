# Develop Engine

Technically trustworthy RAW development foundation for Lumina. **Not Lightroom parity.**

## Audit summary (pre-change)

| Area | Prior state |
|---|---|
| Interactive edit | JPEG proxy ≤2048 via `DevelopEngine.render` + Core Image |
| Export | Separate ImageIO demosaic ≤6000 then same CI `apply` |
| Whites / Blacks / Sharpen / NR | Stored on recipe, **not applied** in CI graph |
| Original / Auto / Current | Enum exists; shell mostly shows ungraded browse JPEG |
| Multi-select / batch | None |
| Undo | Decision undo only; ⌘Z for edits was a no-op |
| Color | No documented working space; Metal used DeviceRGB fallback |
| Cancellation | PreviewSpine generation only; develop had ad-hoc task cancel |

Root cause of inaccurate / unresponsive editing: interactive path graded **camera JPEG proxies** while export demosaiced RAW; slider scrub could kick heavy work without a unified generation gate; several recipe fields were cosmetic.

## Ownership

| Concern | Type |
|---|---|
| Canonical persisted recipes | `EditRecipe` (see `docs/P0_CANONICAL_STATE.md`) |
| Taste / XMP adapter (no geometry) | `DevelopRecipe` — superseded for photo persistence |
| Per-frame overrides / shared links | `PhotoEditBinding`, `EditRecipeStore` (lab / batch) |
| Batch staging / commit / undo | `BatchTreatmentSession` |
| Shoot persistence | `ShootStore` → `ShootRecord` |
| RAW render requests | `RawRenderRequest` |
| Preview quality / fidelity labels | `DevelopRenderQuality`, `DevelopFidelityState` |
| Cancellation / stale rejection | `RenderGenerationGate`, `DevelopRenderScheduler` |
| Unified graph + export | `DevelopRenderGraph`, `ExportService` |
| Lab entry | `--develop-lab` → `DevelopLabView` |

## Develop Lab (Phase 1)

```bash
# macOS
open Lumina.xcodeproj
# Scheme args: --develop-lab --develop-raw-dir /path/to/ARW/folder

# Optional layout captures
…/Lumina.app/Contents/MacOS/Lumina --develop-lab --capture-develop-lab artifacts/develop-lab
```

Layout: ~66% leader, two reference frames, aspect-fit, Before/After, 1:1 pan, fidelity chip, histogram from displayed pixels, controls in a side rail (not over the image).

**Live RAW gate:** If no fixture directory is found, the lab reports that live RAW validation is blocked. Set `LUMINA_DEVELOP_RAW_DIR` or `--develop-raw-dir`.

Workbench integration is **intentionally deferred** until the lab passes live-RAW correctness and responsiveness gates on a Mac.

## Operation order (preview ≡ export)

1. Decode (`CIRAWFilter` preferred, else ImageIO demosaic); orientation once  
2. Long-edge downsample (quality cap only)  
3. White balance  
4. Exposure  
5. Highlights / Shadows  
6. Whites / Blacks (tone curve endpoints)  
7. Contrast  
8. Clarity / Texture / Dehaze approximations  
9. Vibrance / Saturation  
10. Noise reduction  
11. Sharpening  
12. Straighten + crop  
13. 1:1 region  
14. Display or export conversion **once**

## Controls

Trusted with documented mappings: Exposure, Temperature, Tint, Highlights, Shadows, Whites, Blacks, Contrast, Straighten, Crop, Noise Reduction, Sharpening.

Approximate (labeled, not LR-identical): Clarity, Texture, Dehaze.

## Batch grammar

- ⌘-click toggles 2–3 photo selection; releasing ⌘ does not clear selection  
- Hold ⌘ → shared action shelf  
- ⌘Return → stage leader recipe onto each selected RAW **independently**  
- Release Return, keep ⌘, Return again → commit  
- Esc → cancel staged; ⌘Z → undo batch as one transaction  
- Auto-repeat ignored; empty selection cannot stage/commit  

## Performance targets (measure on Mac — not claimed)

| Path | Target p95 |
|---|---|
| Cached present | ≤50 ms |
| Settled after scrub | ≤300 ms |
| Warmed switch | ≤80 ms |
| Before/After | ≤50 ms |
| 1:1 region | ≤250 ms |

Instrumentation: `DevelopRenderScheduler.metrics` (cache hit/miss, cancel, stale, duration, quality).

## Tests

```bash
python3 Scripts/develop_engine_test.py          # Linux + macOS
swift Scripts/develop_recipe_test.swift         # macOS Swift
bash Scripts/ci/regression.sh [RAW] [JPG]          # macOS full
```

## Known Lightroom differences

See `docs/COLOR_PIPELINE.md` and the “Known differences” section in the delivery report.

---

# Stage 2 — RAW Performance + Lightroom Handoff (delivery report)

Branch `cursor/raw-perf-lr-handoff` (from `origin/cursor/ethereal-ui`). Hardware for all measurements: MacBook Pro, Apple M4 Pro, 24 GB, macOS 26.5.2. Fixture: Sony ILCE-7M3 ARW, 24 MP (6000×4000), `~/Pictures/jeevana_mehendi_2026_MATCHED_RAWS`.

## Architecture: before → after

| Concern | Before (Stage 1) | After (Stage 2) |
|---|---|---|
| RAW decode | `CIRAWFilter(imageURL:)` re-created per render, no parameters applied | `PreparedRawSession` actor per photo: dual filters (draft interactive / authoritative), reused across renders |
| RAW-domain params | None — WB/exposure/NR/sharpen approximated post-demosaic with generic CI filters | Applied on `CIRAWFilter` (`exposure`, `neutralTemperature/Tint` with true as-shot restore, `luminanceNoiseReductionAmount`, `sharpnessAmount`) with per-file capability probing |
| Downscale | Decode full-size then transform-downsample | `CIRAWFilter.scaleFactor` — never decode pixels to throw away |
| Invalidation | One recipe fingerprint invalidated everything | Intent domains: `RawIntent` / `LookIntent` / `GeometryIntent` / `OutputIntent`; look changes reuse the cached RAW-stage surface (20/20 hits measured) |
| Caches | Single CGImage LRU | Stage-aware: RAW sessions+metadata (registry, cap 4), RAW-stage CIImage per session (cap 4), post-look presentation cache (512 MB budget, speculative-first eviction) |
| Scheduling | Per-photo cancel + generation gate | Latest-wins + global interactive limit (2), ≤1 authoritative per photo, serialized export lane, superseded results never publish or enter caches, `os_signpost` intervals (request/evaluate/queueDelay/settlement) |
| Display | `CGImage → NSImage → SwiftUI Image` | `CIImage → CIRenderDestination → MTKView` drawable; one ColorSync conversion to the active display profile at the destination; no CPU bitmap on the live path |
| Memory pressure | None | `DispatchSourceMemoryPressure` ladder: speculative → other-photo surfaces → before/after bitmaps → RAW sessions → `CIContext.clearCaches()` |
| Export TIFF | 8/16-bit float, Adobe RGB/P3 fallback, uncompressed | 16-bit integer ProPhoto (ROMM) RGB, embedded ICC, Adobe Deflate (ZIP), EXIF/GPS carried from RAW |
| XMP sidecar | Whole-file overwrite (destroyed external edits) | `LightroomHandoffService`: node-preserving merge, conflict detection on managed crs fields, atomic replace, SHA-256 receipt (old writer deprecated) |

## Honest control matrix

| Control | Implementation | Status |
|---|---|---|
| Exposure | `CIRAWFilter.exposure` (RAW domain) | Trusted |
| Temperature / Tint | `CIRAWFilter.neutralTemperature/Tint`; 6500 K + 0 = as-shot (camera neutral restored, never forced 6500) | Trusted |
| Noise reduction | `CIRAWFilter.luminanceNoiseReductionAmount` when `isLuminanceNoiseReductionSupported`, else explicit **unsupported** (slider disabled) | Trusted / gated |
| Sharpening | `CIRAWFilter.sharpnessAmount` when supported, else explicit unsupported | Trusted / gated |
| Lens correction | Enabled when `isLensCorrectionSupported` | Trusted / gated |
| Highlights / Shadows | `CIHighlightShadowAdjust`, scene-linear, documented approximation | Trusted (approximation, labeled) |
| Contrast / Vibrance / Saturation | `CIColorControls` / `CIVibrance`, scene-linear | Trusted |
| Crop / Straighten | Normalized geometry post-look | Trusted |
| **Whites / Blacks / Texture / Clarity / Dehaze** | **Disabled — no honest algorithm. Not rendered, not exported, values migrate untouched, UI says so.** | Disabled |

Proxy/JPEG fallback grading (`applyProxyApproximation`) exists only under the **Proxy** fidelity label; the ImageIO path is renamed `renderedFallback` and documented as *not RAW developing*.

## Performance (Release, M4 Pro, 24 MP ARW, forced GPU evaluation)

| Metric | Measured |
|---|---|
| Session prepare (warm process) | 183 ms |
| Interactive cold (RAW-stage miss, 1600 px) | 110–145 ms |
| Interactive scrub, look-only ×20 | p50 3.0–3.4 ms · p95 3.2–3.6 ms · max 3.9 ms · **20/20 RAW-stage cache hits** |
| RawIntent change | correctly misses RAW-stage cache |
| Settled (3200 px, authoritative + bitmap) | 130–153 ms |
| 1:1 region (20% crop) | 8–10 ms |
| Full handoff (24 MP render + 16-bit ProPhoto TIFF encode + XMP + receipt) | 6.0–6.5 s |

Debug-build numbers are in `artifacts/raw-perf/raw_harness_report.json`; Release in `artifacts/raw-perf-release/raw_harness_report.json`.

## Fidelity

Settled preview (display space) vs full export (ProPhoto), both resampled to sRGB 1024 px: MAE R 2.16 / G 0.78 / B 0.72 (8-bit), max channel delta 186 (edge/demosaic-scale differences between draft-scaled preview decode and full-res export decode; see PNG pair in artifacts). Export is **deterministic**: identical TIFF SHA-256 (`4c226111…5ed84d`) across repeated runs *and across Debug/Release builds*.

## Lightroom translation + XMP behavior

Written crs fields (only honestly-mapped ones): `Exposure2012`, `Contrast2012`, `Highlights2012`, `Shadows2012`, `Vibrance`, `Saturation`, `Sharpness`, `LuminanceSmoothing`, `WhiteBalance` (`As Shot`/`Custom` + `Temperature`/`Tint` only when overridden), crop/angle when set. Disabled controls are never emitted. `lumina:` namespace records `MappingVersion`, `RecipeFingerprint`, `WrittenFieldsHash`, `WrittenAt`.

Merge behavior (all verified by harness): fresh **created** → Lumina re-merge **updated** → external edit of a managed field detected as **conflictExternalEdits** with `lumina:LastMergeConflict` stamped, and foreign namespaces/properties preserved through the merge. Writes are atomic (same-dir temp + replace). Receipt JSON carries SHA-256 of TIFF and XMP plus the color space actually used.

exiftool verification of the handoff TIFF: `BitsPerSample 16 16 16 16`, `Compression Adobe Deflate`, `ProfileDescription "ROMM RGB: ISO 22028-2:2013"`, 6000×4000.

**Lightroom Classic gate: blocked** — Classic is not installed on this machine (`/Applications/Adobe Lightroom.app` is the cloud app). Manual procedure: import the RAW + sidecar, confirm develop settings appear and no history is lost; import the TIFF, confirm ProPhoto profile is honored.

## Build & test commands

```bash
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Release build

# Deterministic harness (unit checks + XMP merge + live ARW measurements)
LUMINA_DEVELOP_RAW_DIR=~/Pictures/jeevana_mehendi_2026_MATCHED_RAWS \
  Lumina.app/Contents/MacOS/Lumina --raw-harness artifacts/raw-perf

# Existing regressions (all passing)
swift Scripts/develop_recipe_test.swift
python3 Scripts/develop_engine_test.py
swift Scripts/aspect_geometry_test.swift
swift Scripts/CommandChordTests.swift
```

## Known limits (honest)

- Interactive Metal preview timing is measured via forced bitmap evaluation in the harness; MTKView captures in `--capture-develop-lab` show placeholder spinners because the capture window closes before RAW settle and layer-backed MTKView content is not composited by `cacheDisplay`.
- Highlights/Shadows remain a labeled Core Image approximation, not crs-equivalent.
- 61 MP gates: no 61 MP fixture available — reported as fixture-blocked, not fabricated.
- Histogram reads the small settled bitmap (analysis path), so it updates on settle, not per scrub frame.
