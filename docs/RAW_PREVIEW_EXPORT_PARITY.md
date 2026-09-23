# RAW preview/export parity — current UI integration

## Why the first test showed the old UI

The initial isolated test branch was based on the checked-out `codex/sony-assist-next`
(`6ae17c2`), which also matches `codex/sony-technical-assist`. That branch contains the
RAW correction but predates the merged Elastic UI. After fetch, `origin/main` was
`110e9c6`, containing the shell (#102), UI reconciliation (#101), and model core (#103).
Choosing the research branch as the application integration base was an agent error.

The old runner explicitly instantiated `P0SinglePhotoEditor`, bypassing the normal app
root. Current main's runner instantiates `ElasticFocusView`; its app root routes to
`ElasticRootView`. The launched executable was the isolated test build under
`/private/tmp/lumina-parity-evidence/DD`, not an installed app or stale Xcode output.
There was also an unrelated workbench process, which was left untouched.

Legacy pixel measurements remain render-plane evidence, but legacy UI measurements do
not verify the current UI. In particular, the research branch's four-variant tray is
absent from current main; the product now uses shot/auto/yours versions. The corrected
integration uses `codex/raw-parity-current-ui` based on fetched main, in
`/private/tmp/lumina-raw-parity-current`. No other active developer worktree was modified.

## Correction and scope

Current main already contains the P0 texture orientation correction (`isFlipped = false`).
The small production change carries exposure and explicit Kelvin/tint through
`CIRAWFilter` on both tiers and keys the interactive RAW stage by that intent. It removes
the second, approximate exposure/WB post-operation from the normal RAW path.
`RawDecodeBackendRegistry.mappingVersion` changes from `lumina-ciraw-1` to
`lumina-ciraw-2`, invalidating render keys whose pixel meaning changed.

Exposure/WB changes now invalidate and re-materialize the CIRAWFilter output. Apple may
reuse internal decoder work; the materialization counter cannot distinguish its internal
demosaic reuse from a complete decode. Look-only edits can reuse its
materialized texture. This cost is intentional; restoring the old cache shortcut would
restore incorrect pixels. No Auto Develop behavior or photographic-quality claim is
part of this correction. Recipe mutation, hand-recipe storage and undo are unchanged.

## Measurement method

`DevelopEvalHarnessTests.testSonyPreviewExportContract` compares eight Sony ARWs in
24 reduced-stage cases, plus three ARWs in seven independently named full-export cases:
neutral, exposure, explicit Kelvin/tint, highlights/shadows, off-center crop, 90-degree
rotation, and a combined off-center crop/270-degree rotation. The public interactive
graph uses a 1920-pixel cap; exports are full-resolution encoded ProPhoto TIFFs. TIFFs
are decoded, orientation/crop aspect is checked, then both sides are rendered into sRGB
at matched dimensions (384-pixel comparison scale). The existing tolerance is mean
CIE76 delta E <= 1.5 per case. There is no comparison-only flip correction.

Review JPEGs show preview left and decoded export right; metrics are calculated before
JPEG encoding. Full-resolution temporary TIFFs are removed after comparison. A rapid
24-edit sequence exercises the production scheduler, cancellation, and final-recipe
replacement; final published pixels must match the final recipe within 0.01 delta E.

The live runner mounts `ElasticFocusView`, uses eight copied RAWs and an isolated catalog,
measures edit-to-publication separately from GPU draw duration, then exercises continuous
exposure/WB scrubs and shot/yours switching. Publication timing is polled every 5 ms and
is not GPU completion. The pre-existing Metal metric starts at draw submission and must
not be described as end-to-end slider latency. Cold means a new prepared session / absent
render cache, not a flushed OS disk cache.

## Reproduction

```sh
python3 Scripts/harness/lint/xcode_compile.py --project-root . --derived-data /private/output/DD
python3.12 Scripts/harness/run.py fast
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath /private/output/DD -destination 'platform=macOS,arch=arm64' \
  -only-testing:LuminaLogicTests test-without-building
python3 Scripts/harness/eval/run_raw_parity.py --raw /private/raws \
  --truth /private/truth.json --out /private/new-run \
  --xctestrun /private/output/DD/Build/Products/Lumina_P0Fast_macosx26.5-arm64.xctestrun
/usr/bin/time -l /private/output/DD/Build/Products/Debug/Lumina.app/Contents/MacOS/Lumina \
  --p0-edit-live /private/new-ui-run --p0-open /private/copied-raws
```

The truth file supplies RAW filenames only for this contract; no reference-edit fitting
or model inference is performed. The private runner records source/input SHA-256 hashes.
The UI run uses copied RAWs to prevent test edits from touching the original shoot.

## Harness corrections found during this work

The first current-UI run still used the inherited `endEditGesture` harness callback.
The actual Elastic drawer uses `endDevelopGesture`, which also records hand provenance
and scope propagation. That made the first shot/yours check invalid. The final harness
uses the actual drawer callback and records the UI surface in its report. Fresh copies
are used for the rerun because prior UI runs legitimately wrote XMP to their disposable
RAW copies. The original RAW directory is only read by parity tests.

The existing NSHostingView bitmap captures show chrome but can omit the Metal photograph;
they are not evidence of drawable pixel parity. Use the saved graph/export pairs for
pixel review. The native UI inspection tool timed out; no screenshot-based drawable
parity claim is made.

## Pixel results on current main

The corrected current-main run (`current-after`) passes all 45 parity cases:

| Comparison | Cases | Mean CIE76 delta E | Worst |
|---|---:|---:|---:|
| Interactive versus authoritative reduced stage | 24 | 0.5075 | 0.9074 |
| Interactive versus encoded full-resolution export | 21 | 0.6921 | 0.8945 |

All are below the existing 1.5 threshold. Rapid-edit/cancellation final replacement is
0.0000 delta E against the final requested recipe (one in-flight render recorded as
cancelled). Review pairs include the off-center crop and 90/270-degree cases.

The public interactive graph's 21 cold-session timings at 1920 px: p50 243.45 ms,
p95 278.04 ms, max 320.14 ms. Immediate warm RAW-stage reuse: p50 3.08 ms,
p95 3.31 ms, max 3.39 ms, 21/21 RAW cache hits. These are graph/RAW-stage timings,
not full gesture-to-display latency. Timings vary with machine load; numerical pixels
reproduced identically from the earlier research-branch run.

Private evidence root: `/private/tmp/lumina-parity-evidence/`. The legacy control
(`before`) deliberately restores pre-orientation-fix RAW code and fails all 45 cases;
its 21 export cases average 40.15 delta E, worst 48.51. It is a historical mechanism
check, not the current-main baseline. Current main already has the orientation fix.

The same test matrix on clean current main (`current-before`) fails 16/24 reduced-tier
cases and 9/21 full-export cases. Full-export mean is 4.6646 delta E, worst 20.7726.
Orientation/crop-only cases already pass on main; exposure and explicit WB/tint are the
remaining semantic split. This is the appropriate integration baseline.

## Current Elastic UI costs and remaining gates

Apple M4 Pro / 24 GiB; macOS 26.5.2 and Xcode 26.6. The local model stayed loaded;
no model inference overlapped the accepted performance run (`ui-current-final`).
Mounted 1280x800-point editor, eight fresh copied Sony ARWs, isolated catalog, real
Elastic drawer begin/scrub/end callbacks. Each sequential group has only three samples;
these ranges are not population percentiles.

| UI operation | Edit-to-publication time | RAW-stage materializations |
|---|---:|---:|
| First exposure values | 24.57–34.57 ms | 3/3 |
| Repeated exposure values | 12.70–14.07 ms | 0/3 |
| First WB values | 12.16–28.62 ms | 2/3 (one already warm) |
| Repeated WB values | 12.09–12.98 ms | 0/3 |
| First look-only values | 20.50–22.60 ms | 0/3 |
| Repeated look values | 12.09–12.65 ms | 0/3 |
| Shot/yours version switching | 127.41–172.74 ms | 0/8; all 8 published |

Ten-second exposure scrub: 586 input iterations, 585 RAW-stage materializations,
no blank canvas observed. Ten-second WB scrub: 574 input iterations, 572
materializations, no blank canvas observed. GPU draw p95 was 3.33 ms and 3.16 ms
respectively; these exclude decode and scheduling. The loop p95 of 18.06/17.81 ms
includes the intentional 16 ms sleep and is **not** slider latency. Scheduler evidence
records 396 cancellations and one stale rejection by the end of the WB scrub.

The complete 57.38-second UI run reached 1,064,501,248 bytes peak RSS (1.06 GB) and
4,847,766,120 bytes peak process memory footprint (4.85 GB), measured by `/usr/bin/time -l`.
These are whole-process peaks across open, editing, captures, switching and navigation;
there is no isolated GPU-only memory measurement. The footprint is material and should
not be hidden behind the much smaller RSS figure.

Hand edits survived all shot/yours switches. Before did not mutate recipe/undo; undo
left cull unchanged; persistence/reopen checks passed. No Auto command was evaluated.

**The broader live UI gate is not green.** Two checks remain unresolved, reproduced in
`ui-promotion-diagnostic` without relaxing their assertions:

- Sampled fidelity ranks go from preparing (0) directly to authoritative (2). They are
  nondecreasing, but the existing gate additionally requires observing interactive (1).
  The intermediate state was not sampled; this is not proof that it was displayed.
- The Metal view frame changes from `[28, 61.5, 1064, 711]` to
  `[28, 62.5, 1064, 709]` during promotion. The photo box moves down one point and shrinks
  two points in height. This is consistent with browse/RAW aspect rounding, but the
  cause is not fully proven. The selected identity stays fixed, and authoritative
  pixels reach the 2560-pixel target. No measured export crop/orientation case fails.

This branch establishes measured RAW pixel parity, not an unconditional all-UI pass.
The two promotion checks remain follow-up cases; no UI redesign or invalid RAW-cache
shortcut was used to make the gate appear green.

## Local vision-model review

The user requested a model cross-check. `qwen2.5-vl-3b-instruct` at
`http://localhost:1234/v1/chat/completions` successfully completed a text probe and seven
image-pair reviews, after the performance run. Inputs omitted filenames, before/after
labels, and numerical distances. Requests/responses are retained privately in
`model-review/review.json`. Calls took 2.31–7.06 seconds.

The model missed the obvious upside-down/wrong-region historical control (G), and
claimed an orientation mismatch on a corrected exposure pair (C). It also described
the severe pre-fix WB mismatch only as slight. These results make it unsuitable as the
parity scoring gate on this sample. CIE76 scores are deterministic pixel calculations;
the model's words are supplementary observations, not ground truth or aesthetic scores.

## Verification and delivery

- Final macOS build-for-testing passed.
- 507 logic tests: 4 fixture-gated skips, 0 failures. The separately configured live
  RAW contract passed, including all 45 parity cases and latest-wins pixel replacement.
- Static FAST lane: 41/41 checks passed using Python 3.12.
- Vet was invoked after each code unit but could not review because no provider
  credential is configured. No credential or model configuration was changed.
- No PR, push or merge; the PR/merge-only double cache-free checkpoint was not run.
- No shared process or another developer's active worktree was modified. The extra
  isolated app launched by the timed-out UI inspection was terminated by its exact PID.
