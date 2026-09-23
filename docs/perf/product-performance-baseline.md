# Whole-product performance baseline

Status: **INSTRUMENTATION FOUNDATION — BASELINE NOT FROZEN**. No optimization has been made. This checkpoint can be integrated as opt-in measurement infrastructure; it is not a completed product performance baseline or a UI correctness approval.

The RAW correction was merged by PR #104 into `main` at `a3b7fe751dca3bdffac91015c60a8ecf7c7e9ed2`. Commit `c3f2a89` is an ancestor, not a copied patch. Work is isolated on `codex/product-performance-baseline` in `/private/tmp/lumina-product-performance`. The original Xcode checkout remains on the older Sony branch; its UI route and running process must not be confused with this baseline.

## Measurement plan

Use the normal product root at 1280 × 800 points, same built-in display, AI off, and disposable fixture copies. Compare Debug launched by Xcode with debugger, that exact Debug product launched directly, and Release launched directly. Each run needs a source/dirty-state snapshot and explicit cache declaration. No percentile or pass is carried forward from the prior RAW report as a new whole-product measurement.

`artifacts/perf/product-baseline/preflight.json` records non-sensitive machine and source metadata. Foreground setup samples observed an approximately 8.333 ms display-link target interval; no accepted manual measurement window or configuration comparison exists. ProMotion capability and one setup observation do not establish a fixed refresh rate for future runs.

## Fixtures and isolation

Only explicitly configured paths are used: the eight original filenames from the parity run, `card-clean-500`, `card-clean-2000`, and the approved `mehendi-94` shoot. Original files remain untouched. Disposable copies live at `/private/tmp/lumina-product-performance-evidence/fixtures/`.

The 500-card source failed directory verification because five XMP sidecars had been added. Preserve those originals; build a manifest-only copy and verify it. Disk free space was approximately 30 GiB. Copies use APFS clones to avoid consuming another 28 GB. OS page cache is uncontrolled, and physical cold-I/O is not established. The 2000-card additionally contains repeated photographs per its existing manifest. Its results cannot establish absolute cold-I/O budgets.

## Presentation boundary audit

- `P0RenderInstruments` resolves key events at a display-link callback following mutation. This is an opportunity for presentation, not an acknowledgement that changed content reached glass. Existing wording claiming a universal one-frame bound is not independently proven.
- Before this checkpoint the normal Elastic SwiftUI grid did not attach that instrument. The opt-in root probe now attaches it and observes window-local scroll bounds changes. A silent zero must not be called a pass.
- `DevelopMetalView` now adds opt-in `MTLDrawable.addPresentedHandler` acknowledgement and preserves the separate GPU-completion metric. It still lacks recipe-correlated input-to-presentation measurement.
- `p0.edit.slider_to_pixels` can record when an older image already exists. Do not use it as changed-pixel latency.

Instrumentation changes are separate from behavior changes. Drawable acknowledgement and capture coverage are implemented; input/render identity correlation remains pending. Grid display-link callbacks remain estimates. Any missing measurement stays UNMEASURED.

## Instrumentation usage and limits

Launch an independently built app with `--p0-instruments` and an absolute `LUMINA_PERF_OUTPUT` directory. The flag enables the existing instruments in Debug and Release, adds the current-root display probe, and fixes the instrumented window content size to 1280 × 800 points. The environment variable adds an isolated catalog under `OUTPUT/state` and a utility-queue JSON flush every two seconds to `OUTPUT/live-metrics.json`. Without the flag these additions are disabled; without the output variable no recording file or catalog override is created. Use a fresh output directory for each run; the live JSON is replaced atomically within a run.

`p0.develop.draw_to_drawable_presented` brackets draw start to the drawable's host presentation time. It does not establish which recipe was visible, latency since slider input, or whether a higher-level fallback selected the correct photograph. The blank/skipped metric sample counts are counters; their sentinel value of one is not a measured millisecond latency. A callback that never arrives is not counted as a skipped drawable. Existing GPU-completion samples remain GPU measurements.

`p0.display.target_interval` and `p0.display.callback_interval` capture the existing display-link timing. They do not establish changed grid pixels or actual scrolling-frame presentation. Capture is unbounded and the complete captured arrays are serialized repeatedly; that overhead and memory growth belong to instrumentation, and must be measured separately before accepting long-run product memory results. JSON keys are sampled sequentially, not as one transactional snapshot; it is a live flush, not an exit-complete recording. Other metric keys may remain ring/tail-backed as labelled. No input timestamp/recipe pairing has been added.

`python3 Scripts/perf/sample_process_memory.py --pid PID --out /absolute/new-file.csv` samples only the supplied process, writing RSS and physical footprint separately. Default sampling is 1 Hz for 900 seconds; between-sample peaks can be missed. Kernel lifetime peak footprint is separately labelled and cannot be attributed to a phase without additional evidence. The sampler stops on process exit or detected PID reuse, never terminates a process, and refuses to overwrite its output.

Verified before integration: macOS compile and 510 logic tests (four fixture skips, zero failures), FAST 41/41, a standalone memory-sampler smoke check, and actual opt-in live JSON/display samples. These checks validate instrumentation plumbing, not a complete product performance run. The required exact-candidate merge checkpoint and hosted checks are recorded in the integration PR. Vet was attempted but blocked by absent Anthropic credentials; it did not pass.

## Manual protocol (not yet armed)

Wait for the identified isolated app and recording-ready message. Use the built-in display and fixed window; leave AI off. Start at the top of the specified grid. For 60 seconds, use normal two-finger trackpad glides down the shoot, reverse near the end, and continue until told to stop. Do not use the scrollbar thumb, keyboard paging, or scripted scroll. Record interruptions and unintended interactions. A second identical workflow loop is required for retained-memory comparison.

For the dogfood session, choose actual selects, make technical edits, order the set, and export to the disposable output folder. Record decision time and corrections explicitly; an automated neutral pass cannot substitute for human judgment.

## Current gate status

All new whole-product latency, presentation, memory plateau, AI benefit, and card-to-publishable-set rows are **UNMEASURED** until configuration-specific runs exist. Prior RAW graph parity passed 45 measured cases, and the merge passed both local clean rounds plus GitHub FAST/compile-logic; these are inherited graph correctness evidence only.

The subsequent real UI audit confirmed a separate display-selection failure: intended 90°/270° recipe renders can be rejected by the browse-image aspect guard, while native export rotates correctly. The overall preview/export UI gate therefore FAILS despite the inherited graph parity pass. See `docs/UI_CHECK_REPORT.md` for screenshots, recipe/persistence evidence, missing-source/controls gaps and source locations. Intermediate fidelity remains unobserved and the two-point photo-container height shift reproduced. No correction is included in this instrumentation checkpoint; freeze and rank the baseline before behavior changes.

No top-five ranking is asserted before trace-backed baseline evidence. No P0 correction is authorized by a guessed bottleneck. Required final KPI matrix, run distributions, trace locations, before/after evidence and owner-facing answers will replace this preparation note as measurements become available.
