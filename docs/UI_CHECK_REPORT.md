# Current Elastic UI verification — 2026-09-23

Later Prompt 0 assertion/measurement work is recorded in [0-baseline-handoff](0-baseline-handoff.md). The findings and 53-check outcome below remain historical evidence for the exact source and binary identified here.

The intended Elastic UI is built and running from the isolated current checkout. **The UI gate fails:** a saved quarter-turn can export correctly while Canvas continues to show the unrotated browse photograph. The RAW graph parity results do not cover this final display-selection error.

No application behavior was changed. Corrections await the parent task's frozen baseline/ranking and file-ownership coordination. This report records observed correctness, not a performance pass.

## Provenance

| Item | Recorded value |
|---|---|
| Source | `2da465901cfb59fac9d5fa98c11472331ab1f26a`, clean at build |
| Verification branch | `codex/ui-check-finish` (created from detached HEAD) |
| Checkout | `/Users/aniketh/.codex/worktrees/9f7e/vlm_harness` |
| Project / scheme / configuration | `Lumina.xcodeproj` / `Lumina` / Debug |
| Bundle override | `PRODUCT_BUNDLE_IDENTIFIER=com.lumina.uicheck` |
| Binary | `/private/tmp/lumina-ui-check-20260923/DD/Build/Products/Debug/Lumina.app/Contents/MacOS/Lumina` |
| Embedded manifest | Build date `2026-09-23T18:00:29Z`; SHA above; contract `6.4-a7-cleanup` |
| Host | macOS 26.5.2 (25F84), Xcode 26.6 (17F113) verified locally; M4 Pro / 24 GiB inherited from parent (sandbox blocked fresh sysctl read) |
| First normal launch | PID 87598, 11:01:26 PDT; `--p0-instruments`; isolated output `…/live` |
| Recovered live launch | PID 88900, 11:05:50 PDT; `--p0-instruments --workbench --card ui-raw-eight --surface table`; output `…/live-recovery` |
| Persistence relaunch | PID 91046, output snapshot start `2026-09-23T18:11:44Z`; same flags except `--surface frame`; same isolated catalog |
| Window | Native window titled `Lumina`, selected by exact app path and unique bundle; instrumented root requests 1280 × 800 points |
| UI fixtures | Eight APFS-cloned RAWs in `/private/tmp/lumina-ui-check-20260923/ui-raw-eight`; separate fresh `harness-raw-eight` for scripted checks |
| Catalog | `/private/tmp/lumina-ui-check-20260923/live-recovery/state/Lumina/projects/ui-raw-eight/shoot.json` |

Catalog `source.originalPath` was inspected before mutation and pointed into this disposable directory. Originals were not edited. One disposable RAW was temporarily moved to `parked/` for missing-source verification, then restored. APFS clones and uncontrolled OS cache do not establish cold disk I/O.

Commit map: `f79ac8f` Elastic shell → `485df48` reconciliation → `110e9c6` model core → `c3f2a89` current-UI RAW correction → `a3b7fe7` PR #104 merge → `2da4659` instrumentation only. Local `origin/main` was `a3b7fe7`. Views/Design/Shell have no diff between merged main and the tested instrumentation commit.

## Why the old UI appeared

The original checkout `/Users/aniketh/vlm_harness` remains on `codex/sony-assist-next` at `6ae17c2`. That revision's `P0RootView` selects `P0ContactSheetView` / `P0GroupingView`. The tested source selects `ElasticRootView` for `.time` / `.focus`.

Read-only process inspection confirmed old PID **64132**, started September 22 at 14:08:40, still running the original checkout's DerivedData binary with `--workbench --card card-clean-500 --surface table`. Parent PID **79895** separately runs its instrumented build. Neither was stopped or controlled. A newly built test app exiting can uncover that older surviving window. Merging source does not replace a running binary. No cache clearing is required to explain the observation.

Reliable isolated launch recipe (normal root, with opt-in instrumentation providing state isolation):

```sh
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath /private/tmp/lumina-ui-check-20260923/DD \
  PRODUCT_BUNDLE_IDENTIFIER=com.lumina.uicheck build
LUMINA_PERF_OUTPUT=/private/tmp/lumina-ui-check-20260923/live \
  /private/tmp/lumina-ui-check-20260923/DD/Build/Products/Debug/Lumina.app/Contents/MacOS/Lumina \
  --p0-instruments
```

For recovery and repeatable fixture entry, add `FIXTURE_ROOT=/private/tmp/lumina-ui-check-20260923` and `--workbench --card ui-raw-eight --surface table`. This DEBUG deep link calls the real `openFolder` but bypasses the initial chooser; it is not proof of successful initial chooser interaction. Native Recent reopening and opening an empty folder were subsequently exercised.

## Current coverage

PASS is scoped to the evidence column, never an assertion about every frame or every camera.

| Check | Status | Expected / observed evidence |
|---|---|---|
| Correct source, build and opening screen | PASS | Embedded SHA verified; actual window screenshot `01-open.png` |
| Elastic grid, moments, set shelf | PASS | Real photos visible, 8-frame grid and marked set; `02-grid.png`, `04-drawer-before.png` |
| Canvas with actual Metal photograph | PASS | Real screenshot `03-canvas-shot.png`; unlike hosted bitmap captures, photograph is present |
| Initial normal folder chooser | UNMEASURED | First attempt lost native window discovery; recovery used deep link |
| Native Recent reopen / empty-folder chooser | PASS | Recent reopened fixture; empty folder showed 0 frames and disabled Auto (`20-empty-shoot.png`) |
| Exposure/WB/tint/look controls | PASS (harness) / UNMEASURED (pointer) | Nine controls committed through session callbacks. Pointer drags returned `noWindowsAvailable`; no claim of successful live slider scrubs |
| Shot / yours | PASS for observed switches | Explicit tile clicks changed real displayed photo between original and square crop; hand crop survived; `09-shot-after-edit.png`, `10-undo-rotation-restored.png` |
| Auto / yours thumbnail depictions | FAIL | Both tiles remain blank; source explicitly returns no preview path for versions 2/3. Auto inference intentionally not invoked |
| Centered crop | PASS for observed square | 1:1 crop became visible after undoing the quarter turn; `10-undo-rotation-restored.png` |
| Quarter-turn display | FAIL | 90/270 rejected visually; 180 and full turn displayed correctly; native TIFF rotates correctly |
| Off-center crop interaction | FAIL (missing current affordance) | Elastic drawer supports centered presets; no crop drag/latch in current focus view. Engine support is inherited evidence, not a live interaction pass |
| Mark / reject / undo | PASS | P kept first photo; X marked second out; Cmd-Z removed rejection; edit undo preserved kept state |
| Redo | FAIL (requested capability absent) | Cmd-Shift-Z did not restore rejection; coordinator has only a pop-only undo stack, no redo path |
| Next/previous, rapid navigation | PASS for sampled final identity | Navigation returned to DSC08187 with corresponding real photograph. Not a frame-by-frame stale/blank audit |
| Reopen/persistence | PASS for sampled fields | Process restart retained kept first photo, yours provenance and 90° recipe; display defect persisted (`14-reopen-90.png`) |
| Native export | PASS for one saved file / FAIL display agreement | Cmd-E wrote 4000 × 6000 TIFF; normal orientation tag, ROMM RGB; actual pixels rotated while Canvas was not |
| Missing-original preservation | PASS | All 8 assets retained; DSC08200 marked `missing` in catalog; cached photo displayed |
| Missing-original warning | FAIL | Real Canvas shows “as shot” without a visible missing-original warning (`23-missing-original.png`) |
| Empty-state recovery guidance | FAIL (usability gap) | Empty gray table with 0 frames, no body guidance or choose-folder affordance; Cmd-Shift-H still returns Home |
| Promotion geometry | FAIL | Harness reproduced [28,61.5,1064,711] → [28,62.5,1064,709] |
| Intermediate preview presentation | UNMEASURED; harness gate FAIL | Sampled ranks [0,0,0,0,0,2]; rank 1 not observed |
| Scroll, multiselect pointer gestures | UNMEASURED | Native scroll/coordinate tools returned `noWindowsAvailable`; eight-photo fixture also does not establish long-scroll behavior |
| Human 60-second glide / dogfood | UNMEASURED | No recording-ready exclusive window was armed; parent retains coordination |
| Display latency, stable memory, UI smoothness | UNMEASURED | No accepted performance run; other task inventory/build allowed during later correctness checks |

The supplied `/Users/aniketh/Downloads/Lumina Elastic v4.html` was read as local source. Its bundled template confirms the version trio, hidden version column during Develop, ratio/rotation controls, set shelf and export concepts. Browser policy rejected rendering the local file, so pixel-for-pixel HTML/native visual fidelity remains UNMEASURED. Native app title bar and folder chooser are platform differences, not evidence of a stale shell. Blank auto/yours preview plates are an explicitly unfinished native implementation, not intentional visual parity with rendered version previews. The older contract's crop latch/off-center requirement remains distinct from the prototype's preset controls; no authority conflict was silently resolved by changing code.

## Defects and smallest proposed corrections

### U1 — P1: intended rotation/crop can be hidden by browse fallback

Reproduction on DSC08186: open Canvas, E, select original ratio, click quarter turn. Wait for settled work. The drawer says 90°, but the large photograph stays unrotated landscape. Export the kept photograph with Cmd-E. The TIFF is portrait, 4000 × 6000, with baked rotated pixels and normal orientation metadata. Reopen preserves the recipe and reproduces the display error.

Rotation ladder: initial 0° correct; 90° wrong (original landscape); 180° correct upside-down landscape; 270° wrong (original landscape); 360° / displayed 0° correct. Screenshots 12, 14–17 record labels and real pixels. A 1:1-plus-90° case also returned to the unrotated landscape; square crop alone displayed.

Source: `Lumina/Views/P0/ElasticFocusView.swift:140` passes the recipe-rendered image and unmodified browse fallback into `OrientedDisplayImage.stablePresent`. `Lumina/Rendering/OrientedDisplayImage.swift:190` compares only portrait/landscape shape and returns fallback whenever they differ. This can reject an intentional quarter-turn, exactly the observed odd/even pattern. Pixel publication and input generation IDs are not exposed by the live UI; no exact per-frame correlation is claimed.

Smallest proposed correction: make promotion validation aware of intended recipe geometry (or ensure both candidates represent that same geometry), preserving identity and sensor-orientation protections. Do not simply delete the guard without tests for portrait EXIF, square rounding, 0/90/180/270, off-center crop, shot/yours, undo and final stale replacement. Add a normal `ElasticFocusView` display/export test; graph-only tests cannot catch this fallback choice. No behavior patch made.

### U2 — P2: missing-source state is invisible while cached photo remains

Temporarily park only disposable DSC08200.ARW, Home → Recent, navigate to DSC08200. Catalog retains it with `source.availability=missing`, while screenshot 23 shows the cached photo and “as shot,” without recovery information. `ElasticFocusView` places a notice only when no image exists; its status bar does not show source availability. Smallest correction: surface the existing availability/recovery fact even with cached pixels. Preserve the cached preview. The RAW was restored after the test.

### U3 — P2: promotion box shifts and intermediate tier not observed

Existing harness reproduced a one-point downward movement and two-point height reduction. In plain language, the photo area subtly resizes while detail arrives. `ElasticFocusView` sizes the Metal leaf from the currently available image extent (or the entire well when absent). An extent/fallback change can therefore change the box. This locates the mechanism but does not prove which particular initial extent caused the rounding difference. Proposed follow-up: log both candidate extents and committed geometry, then stabilize the box for the same requested photo/recipe. Do not treat absent rank 1 as displayed or relax the gate.

### U4 — P2: incomplete controls and accessibility

Auto/yours tiles deliberately lack image paths (`ElasticVersionColumn.swift:37`). Off-center crop and redo have no current native path. The accessibility tree merges nine slider values into one text node, whereas Straighten exposes Increment/Decrement. Parent focus/drawer accessibility identifiers overwrite leaf identifiers, consistent with the existing warning in `docs/P0_UI_AUTOMATION.md`. Proposed work: retain genuine version render ownership, wire the existing geometry/undo mechanisms only after scope approval, and restore leaf accessibility semantics without redesign. Pointer-tool failure itself is not proof of a human input defect.

### U5 — P3: empty folder offers little guidance

Opening a valid empty directory yields 0 frames and an otherwise empty gray table. Add contract-approved recovery copy/action through the existing empty state, not a new modal. Cmd-Shift-H worked.

An investigated concern about undo leaving the cached hand recipe rotated did **not** reproduce as an end-user restoration failure: explicit shot/yours switching retained the undone square-only recipe. Screenshot 10's historical filename is misleading; it shows successful square-only restoration, not resurrected rotation.

## Harness, capture and performance truth

The existing `--p0-edit-live` runner completed **53 checks: 50 passed, 3 failed** on the tested binary with fresh copied RAWs. Failures: initial `displayedCIImage != nil` check after fixed waits; rank-1 requirement; stable photo-container geometry. `navigation.blankAfterWait` was additionally true, even though its named navigation check only checks count. These are session/publication observations: the actual view can still display its browse fallback, so neither establishes a photographed blank screen. The runner calls session methods; labels such as “drawer opens on E” and “quit/reopen” do not prove literal hardware-key or process-restart interactions. Those are separately identified in the live coverage above.

Rapid exposure and WB callback loops, 18 sequential edit publication checks, eight shot/yours publications, undo/cull independence and serialization/reopen checks passed. Hosted PNGs omit the Metal photo and early grid thumbnails; they are chrome evidence only. Actual CUA captures 02–23 do contain photographs. No captured still establishes zero transient stale/blank frames.

The first chooser lost discovery (`noWindowsAvailable`, then timeouts). A bounded sample of own PID 87598 showed the main run loop and display callbacks, not a proven hang. Restarting only that app and using AX Raise recovered keyboard/semantic actions. Coordinate drags and scroll still failed. ScreenCaptureKit `-3811` occurred intermittently. Export completed despite a later CUA timeout; sample of own PID 88900 again showed its event loop. Shared processes were untouched; no global caches or permissions changed.

No new latency percentile is accepted. The scripted runner includes deliberate sleeps, tail GPU samples and polling; draw completion is not presentation. The opt-in drawable metric lacks input/recipe correlation, and `p0.edit.slider_to_pixels` can fire with an old image. RSS is not physical footprint. Neither snapshot memory nor one export establishes a plateau. Human trackpad scrolling and the three-configuration comparison remain with the parent.

Inherited only: PR #104's 45 measured RAW parity cases passed mean CIE76 ≤1.5 per case (full-export aggregate mean 0.6921, worst 0.8945); previous 507-test clean rounds and instrumentation commit's 510-test run / four skips / no failures. No RAW gate was rerun here because production code was unchanged. No Auto quality or model benefit was evaluated.

## Evidence and commands

Private screenshot/owner-guide root:
`/Users/aniketh/.codex/visualizations/2026/09/23/01a0cf69-9da8-7ff0-b2dc-504518731658/ui-check/`

- `README.md`: annotated screenshot guide; original captures remain unmodified.
- `evidence-manifest.json`: capture file timestamps, hashes and PID/source mapping.
- `01-open.png`, `02-grid.png`, `03-canvas-shot.png`, `04-drawer-before.png`: actual current app.
- `12-rotation-original-aspect.png`, `14-reopen-90.png`, `15-rotation-180.png`, `16-rotation-270.png`, `17-rotation-full-turn.png`: rotation evidence.
- `13-export-90-preview.jpg`: reduced TIFF decode for review, not a screenshot or pixel-parity metric.
- `18-rejected-next.png`, `19-navigation-final-redo.png`, `20-empty-shoot.png`, `23-missing-original.png`: workflow/failure states.
- `harness/`: report and hosted captures, explicitly not drawable evidence.

Full TIFF: `/private/tmp/lumina-ui-check-20260923/export/ui-raw-eight/0001_DSC08186.tif` (149 MiB). Logs, stack samples, copied catalog snapshots, build manifest and harness output: `/private/tmp/lumina-ui-check-20260923/`. Recipe snapshots at 180/270 and final state, plus `missing-original-catalog.json`, preserve observed catalog values. Export-time 90°/no-crop values were read directly and recorded in tool output; the later catalog is not misrepresented as an export-time snapshot.

```sh
cp -cR /private/tmp/lumina-product-performance-evidence/fixtures/raw-eight \
  /private/tmp/lumina-ui-check-20260923/harness-raw-eight
/private/tmp/lumina-ui-check-20260923/DD/Build/Products/Debug/Lumina.app/Contents/MacOS/Lumina \
  --p0-edit-live /private/tmp/lumina-ui-check-20260923/harness \
  --p0-open /private/tmp/lumina-ui-check-20260923/harness-raw-eight
/usr/local/bin/exiftool -ImageWidth -ImageHeight -Orientation -ProfileDescription \
  /private/tmp/lumina-ui-check-20260923/export/ui-raw-eight/0001_DSC08186.tif
```

Build succeeded. Documentation-only changes require no new application compile/logic run; the existing harness was run for the investigation. No merge checkpoint was needed. No application code was edited, so vet's code-unit trigger did not apply; inherited credential-blocked vet is not described as a pass. No push, PR or merge performed.

Remaining gates: fix and verify U1 after baseline prerequisite; actual pointer slider/multiselect/scroll coverage; off-center native crop and redo disposition; presentation-correlated transient audit; human glide/dogfood; reference visual rendering in an allowed viewer. UI ownership can be returned to the parent with these concrete gaps; this is not an all-UI approval.
