# Lumina P0 — Trustworthy single-photo RAW editing

Checkpoint after culling (`docs/P0_CULLING.md`). Opens a photograph from the contact sheet into an editing surface bound only to `EditRecipe`, with live RAW preview and shared undo.

Rebased onto current `main` — this checkpoint now sits on top of the P0 UI automation harness (#23) and P0 UX hardening (#24), not on the old `cursor/p0-cull-grammar` stack. `P0SinglePhotoEditor` replaces the former `P0SinglePhotoPlaceholder` as the only single-photo surface; the harness contracts those two PRs introduced (leaf-only accessibility identifiers, forced test reduce-motion, keyboard-ready grid, the `p0.singlePhoto.originalOffline` affordance) are preserved on the real editor.

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

## UI-harness editing contract

The XCUITest harness observes editing through one structured probe field — never screenshots or UI
text:

| Probe field | Meaning |
|---|---|
| `focusedRecipeFingerprint` | `EditRecipe.valueFingerprint` of the focused asset's canonical recipe (nil when nothing is focused) |

It is the existing deterministic fingerprint already used for cache keys and undo's no-op guard, so
it adds no new source of truth. It carries no file paths, no pixel data, and no recipe payload — a
fixed-width digest of the numeric values only. Like the rest of `ProbeSnapshot` it exists solely
under the DEBUG harness (`UITestSupport.isActive`) and is compiled out of Release.

One leaf accessibility identifier drives one representative control:

| Identifier | Element |
|---|---|
| `p0.singlePhoto.exposure` | The Exposure slider (leaf element; `P0EditSlider.identifier`) |

`p0.singlePhoto.image` rides whichever leaf actually presents the photograph — the Metal canvas when
a rendered image exists, the cached preview otherwise — never a container. SwiftUI creates no
accessibility element for a plain `ZStack`, so an identifier placed on one is undiscoverable; the two
carriers are mutually exclusive so `firstMatch` is never ambiguous.

Coverage split, deliberately: `Scripts/p0_edit_test.swift` remains the owner of persistence, crop,
recipe serialization, and command behavior. `LuminaUITests/Flows/EditingProbeTests.swift` proves only
the end-to-end wiring — real Exposure gesture → fingerprint changes → cull unchanged → one undo
restores the exact prior fingerprint → P/X leaves the fingerprint alone. Comparison, batch editing,
export, and AI are out of scope for this checkpoint.

## Measured performance

Instrument keys:

- `p0.edit.slider_to_pixels`
- `p0.edit.interactive_ms`
- `p0.edit.session_prepare_ms`
- `p0.edit.before_warm_ms`
- `p0.edit.nav_to_neighbor_ms`

Plus existing develop scheduler metrics (cache hit/miss, raw-stage hits, stale rejects, queue delay via `os_signpost`).

> **Historical measurements.** Both tables below were recorded on 2026-08-06 against a local Sony
> ARW shoot, before the rebase onto current `main`. They are kept as the measured record for this
> checkpoint; they have **not** been re-measured since the rebase, and the rebase included preview
> and scheduler changes (interactive long edge 1600→1920, settled 3200→4096, grid preview 768→1200,
> gesture-end settle) that would move them. Re-run the harnesses below before quoting these numbers
> as current.
>
> The run evidence (frames, reports) is **not committed** — the frames run to tens of MB each and no
> test consumes them as a reviewed golden, so `artifacts/p0-edit/` and `artifacts/p0-edit-live/` are
> gitignored. Regenerate locally with the commands shown.

### Live harness on Sony ARW (`DSC08241.ARW`, Debug, 2026-08-06 — historical)

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

Writes (locally, gitignored): report `artifacts/p0-edit/p0_edit_harness_report.json`, frames under `artifacts/p0-edit/screenshots/`.

Fixture folder available on this Mac: 94 ARWs under `jeevana_mehendi_2026_MATCHED_RAWS` (not 200+).

### Mac live session (`--p0-edit-live`, 2026-08-06 — historical)

Command:

```bash
open -W -n DerivedData/Build/Products/Debug/Lumina.app --args \
  --p0-edit-live artifacts/p0-edit-live \
  --p0-open /Users/aniketh/Pictures/jeevana_mehendi_2026_MATCHED_RAWS
```

| Checklist item | Result |
|---|---|
| Open 94-photo shoot | Pass |
| Open photograph + RAW preview | Pass |
| Adjust every exposed control | Pass |
| Rapid Exposure scrub ≥10 s | Pass — blankSeen=false, scrub p95 **18.7 ms** |
| Before non-mutating | Pass |
| Navigate 20 neighbors | Pass — nav p95 ~133 ms (cold-ish; target 35 ms missed) |
| Crop landscape + portrait/rotate | Pass |
| Grid return + reopen retains crop | Pass |
| Edited mark independent of Keep | Pass |
| Undo edit leaves cull unchanged | Pass |
| Quit/reopen retains recipe + cull | Pass (preparation saves now merge live cull/recipe) |
| 1280×800 captures | Pass — frames written to `artifacts/p0-edit-live/*.png` |

Writes (locally, gitignored): report `artifacts/p0-edit-live/p0_edit_live_report.json`.

### Automated gates run after the rebase (2026-08-07, warm Mac)

These are the targeted gates this checkpoint is verified by — not the full test plan.

| Gate | Command | Result |
|---|---|---|
| Deterministic edit contracts | `swift Scripts/p0_edit_test.swift` | 29/29 pass · 0.5 s |
| Native logic tests | `bash Scripts/run_p0_ui_tests.sh logic` | 5/5 pass · 2.7 s |
| Editing probe flow | `-only-testing:LuminaUITests/EditingProbeTests` | 1/1 pass · 5.0 s |
| Missing originals | `-only-testing:LuminaUITests/MissingOriginalsTests` | 1/1 pass · 6.3 s |
| UX hardening | `-only-testing:LuminaUITests/UXHardeningTests` | 2/2 pass · 6.3 s |
| Smoke | `bash Scripts/run_p0_ui_tests.sh smoke` | 6/6 pass · 5.0 s |
| Release build | `xcodebuild -configuration Release build` | Succeeds · 40 s · no harness symbols in the binary |

Not run in this pass, by design: `P0Fast`, stress, visual, explorer, and the real-media E2E audit.

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
12. Capture screenshots under `artifacts/p0-edit/` (local only — gitignored).

### Still manual after the rebase

Automation covers the recipe/cull/undo state contract, not perceptual truth. These remain
GUI-only checks on real RAW files and were **not** re-run in this pass:

- RAW orientation and the BGRA8 / display-color-space fix (no milky cast, no upside-down preview).
- 1:1 zoom and pan under the pointer; double-click zoom toggle.
- Elastic filmstrip feel — hover-to-browse, click-to-select, spring scroll.
- Shift+G grouping surface behavior beyond route entry.
- Sustained ≥10 s scrub for blank/stale frames.
- Crop handles and straighten on a real photograph.

## Known Metal bottlenecks (next checkpoint)

1. Whites / Blacks / Texture / Clarity / Dehaze — no honest scene-linear algorithm yet.
2. Interactive demosaic still the dominant cost on RawIntent changes (exposure/WB/NR/sharpen).
3. Quarter-turn + fine straighten share one `straightenDegrees` field — dedicated orientation field would clarify export/XMP.
4. Filmstrip thumbs remain uncropped (acceptable); main surface and authoritative output must match.
5. Deeper GPU residency / IOSurface presentation path beyond current CI→Metal drawable.

## What this checkpoint does not claim

Deeper Metal hardening, grouping intelligence, batch editing, comparison, export, and AI/model
inference are **not** complete. Grouping ships only as a route and surface entry point. The scrub and
navigation latency targets are still missed (see the historical tables above), and no
Lightroom-class latency claim is made.

## Next checkpoint

Deeper Metal hardening: implement trustworthy Whites/Blacks (and optionally clarity/texture), tighten slider-to-photon instrumentation against drawable present, and optional dedicated orientation field — without rewriting the P0 command/recipe boundary.
