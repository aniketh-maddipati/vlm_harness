# Lumina P0 — Trustworthy single-photo RAW editing

Checkpoint after culling (`docs/P0_CULLING.md`). Opens a photograph from the contact sheet into an editing surface bound only to `EditRecipe`, with live RAW preview and shared undo.

## Canonical recipe ownership

| Concern | Owner |
|---|---|
| Authoritative edit state | `EditRecipe` on `AssetRecord` via `ShootStore` |
| Live scrub working copy | `P0SessionModel.workingRecipe` (gesture-scoped only) |
| Cull / selection / final order | Untouched by every edit path |
| Undo | `EditMutationCommand` on shared `P0UndoCoordinator` |

Rules:

1. Every exposed control changes `EditRecipe`.
2. Changes affect interactive preview and full-resolution render through the same graph.
3. Changes participate in `valueFingerprint` / intent-domain cache keys.
4. Commits persist through `ShootStore` and survive quit/reopen.
5. One slider/crop gesture → one undo command.
6. No parallel slider-offset source of truth.

## Edit command and undo

```swift
struct EditMutationCommand {
    let assetID: AssetID
    let before: EditRecipe
    let after: EditRecipe
}
```

- Scrub intermediates render live and do **not** push undo.
- Gesture end / navigation / grid return / quit path flushes the pending gesture.
- Reset and crop/rotate are instantaneous undoable mutations.
- ⌘Z pops the shared stack (edit or cull).
- Before (`B` press-and-hold) never mutates recipe or undo.

## Editing surface

Warm-white shell (`Surface.mist` / porcelain), middle-gray photograph matte (`focusMatte`), aspect-fit Metal RAW canvas, Grid return, filmstrip, right adjustment rail, Undo, kept/export count, factual fidelity chip when needed.

Dark treatment stage / Develop Lab chrome is not used on the P0 route.

## Exposed vs deferred controls

### Exposed (honest pixels)

| Section | Controls |
|---|---|
| Light | Exposure, Contrast, Highlights, Shadows |
| Color | Temperature (absolute K when metadata permits), Tint, Vibrance, Saturation |
| Detail | Sharpening*, Noise reduction* (*capability-gated per file) |
| Crop | Original / common ratios, straighten, 90° rotate, direct handles, reset |

### Deferred (schema preserved, not rendered)

Whites, Blacks, Texture, Clarity, Dehaze — stored and fingerprinted for compatibility, **not** exposed in this checkpoint. No UI-only or JPEG-only approximation. Next Metal hardening checkpoint owns honest algorithms.

## RAW fidelity behavior

- `CIRAWFilter` remains the decode / camera-interpretation boundary via `PreparedRawSession`.
- Interactive scrub → settled pause (existing `DevelopRenderScheduler`).
- Latest-generation-wins; stale results never present.
- Metal view replaces pixels in the existing canvas (`DevelopMetalView`).
- Missing originals → cached preview + factual “Original missing” notice; recipe still persists.
- Opening a photo prewarms its session; neighbors are prefetched.

## Measured performance

Instrument keys:

- `p0.edit.slider_to_pixels`
- `p0.edit.interactive_ms`
- `p0.edit.session_prepare_ms`
- `p0.edit.before_warm_ms`
- `p0.edit.nav_to_neighbor_ms`

Plus existing develop scheduler metrics (cache hit/miss, raw-stage hits, stale rejects, queue delay via `os_signpost`).

### Live harness on Sony ARW (`DSC08241.ARW`, Debug, 2026-08-06)

Command: `Lumina.app --p0-edit-harness artifacts/p0-edit`

| Metric | Measured | Target | Notes |
|---|---|---|---|
| Session prepare | 217 ms | — | Capability probe + RAW session |
| Baseline settled render | 279 ms | settled < 150 ms | Miss — full settled bitmap materialization |
| Scrub loop p50 / p95 | 27.0 / 27.1 ms | slider→pixels p95 < 16 ms | Miss — dominated by coalesce+interactive RAW evaluate |
| First visible after scrub start | 27.0 ms | < 16 ms | Same bottleneck |
| Neighbor nav p50 / p95 | 38.4 / 38.4 ms | cached nav < 35 ms | Slight miss on cold-ish neighbor opens |
| Before/After warm | 56 ms | warm switch immediate | Cache populate; subsequent B uses cached CI surfaces |
| Whites/Blacks meanΔ | 0.26 | inert | Treated inert (≪ real controls); not exposed |
| Exposed controls | all changed pixels | required | Exposure/Contrast/HL/Shadows/Temp/Tint/Vibrance/Sat/Crop/Straighten/Rotate90 |

Report: `artifacts/p0-edit/p0_edit_harness_report.json`. Frames under `artifacts/p0-edit/screenshots/`.

Fixture folder available on this Mac: 94 ARWs under `jeevana_mehendi_2026_MATCHED_RAWS` (not 200+).

## Mac live-test instructions

Shoot: `/Users/aniketh/Pictures/jeevana_mehendi_2026_MATCHED_RAWS` (Sony ARW).

1. Open the shoot into the P0 contact sheet.
2. Return / double-click a photograph.
3. Adjust every exposed control; confirm pixels change.
4. Scrub Exposure rapidly ≥ 10 s — no blank/stale canvas.
5. Hold/release B repeatedly.
6. Navigate ≥ 20 neighbors via filmstrip/arrows.
7. Crop a portrait and a landscape; return to grid and reopen.
8. Confirm edited bar appears independently of Keep.
9. Undo an edit without changing cull.
10. Quit and reopen; verify recipes and crops.
11. Resize to 1280×800 — photo stays large; rail does not scroll in ordinary use.
12. Capture screenshots under `artifacts/p0-edit/`.

## Known Metal bottlenecks (next checkpoint)

1. Whites / Blacks / Texture / Clarity / Dehaze — no honest scene-linear algorithm yet.
2. Interactive demosaic still the dominant cost on RawIntent changes (exposure/WB/NR/sharpen).
3. Quarter-turn + fine straighten share one `straightenDegrees` field — dedicated orientation field would clarify export/XMP.
4. Filmstrip thumbs remain uncropped (acceptable); main surface and authoritative output must match.
5. Deeper GPU residency / IOSurface presentation path beyond current CI→Metal drawable.

## Next checkpoint

Deeper Metal hardening: implement trustworthy Whites/Blacks (and optionally clarity/texture), tighten slider-to-photon instrumentation against drawable present, and optional dedicated orientation field — without rewriting the P0 command/recipe boundary.
