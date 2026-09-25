# 0-baseline-handoff

Status: PARTIAL. Prompt 0 owns the bounded assertion and measurement patch. No latency, memory, optical presentation, or human outcome acceptance is claimed.

## Source, ownership and evidence

Accepted predecessor: none (first packet). Released source and fetched `origin/main`: `a6923588dfe3824f3b84556bbcac3d93d8f67876`; assigned worktree started clean and detached at that commit. There was no intervening diff to rebase. Command center explicitly granted exclusive shared-file, build and native ownership to task `01a0cfdf-aef5-7391-a3ff-0c89047a14fc`. No extra checkout was created.

Owned files: `DevelopRenderScheduler`, `RawRenderRequest`, `DevelopMetalView`, `DevelopPresentationMeasurement`, `ProductPerformanceRecording`, `P0SessionModel`, `ElasticFocusView`, `P0EditLiveRunner`, associated presentation tests and the five-site probe mirror. No rendering graph, recipe semantics, cache policy, command/undo, journal or export behavior is changed. The probe adds only an opt-in measurement-enabled flag. Ownership release is recorded with final verification below; successor dispatch belongs to command center.

Consumed evidence lives at `/private/tmp/lumina-ui-ux-evidence/p0/`. Its README identifies standalone Release, bundle `com.lumina.uiuxp0`, PID 31412 (exited), source above, executable `DD/Build/Products/Release/Lumina.app/Contents/MacOS/Lumina`, SHA256 `a3216711273f560cf16812ca976fa78b56e65b833a22ff77e83d3a44a04bf4eb`. Host: Mac16,7, M4 Pro, 24 GiB; macOS 26.5.2/25F84; Xcode 26.6/17F113. Main display telemetry targets 8.333 ms; actual refresh, scale, power, thermals and other process/model state were not frozen. App-cold initially; disk cache uncontrolled. No acceptance condition can be inferred.

Independently read the profiler logs: `open-canvas.trace` completed at 45 seconds; `scrub-valid.trace` at 35 seconds. `scrub-navigation.trace` failed kperf ownership and is INVALID. Its results are excluded. The valid traces establish diagnostic sampling, not video or per-input frame completion.

Consumed artifact SHA256:

| Artifact | SHA256 |
|---|---|
| identity.json | d2e116eb21414c16a3fb2b75ef8849e904bbca3df23fc4bfd6f7813eddb2b22b |
| metrics-final.json | 7475d8811a9a6f7ce9cb1919fe8ddb13d616cd327a3809c7ffeaa79d68103872 |
| sample-summary.json | 7ab152e42289bcbe41cc0a4126d381fcb754647638f0d979c0631e75392073c9 |

All eight RAWs in `raw-eight` were rehashed and match identity.json, byte for byte. That manifest freezes DSC08186/187/190/191/192/193/195/200. It does not establish the full EXIF-orientation/crop matrix. Separate HEIC/JPEG, two real shoots, 403/~2,000 scroll sets, fault fixtures and storage/hardware permutations remain UNMEASURED for this packet; no hash was invented. Original media was not modified.

## Assertion audit: all 53 normal-path checks

The historical run in `UI_CHECK_REPORT.md` remains attributed to `2da4659`; its 50/53 is not a pass for this patch. Current checks below call session APIs. Hosted screenshots omit Metal photograph pixels. Renamed checks report the actual observed boundary.

| Check group (expanded count) | Actual assertion / limitation |
|---|---|
| Open shoot (1) | At least eight session assets within 60 seconds; no chooser or startup percentile |
| Peek cycle (1) | Session peek equals set; no physical Tab proof |
| Open photograph (1) | Inspecting ID equals landscape ID |
| Initial preview (1) | Session image nonnil after fixed 0.4 + 0.6 second waits; no Canvas assertion |
| Drawer (1) | Callback toggles state; removed physical E claim |
| Nine exposed controls (9) | Result fingerprint equals requested mutation; removed unrelated `hasSettings` escape |
| Exposure/WB/look publication (18) | CIImage reference changes within five seconds; renamed to reference replacement, never latest-recipe/presentation proof |
| Two rapid scrub loops (2) | Session image remains nonnil at polls; loop includes 16 ms sleep; not photo latency |
| Two three-second GPU diagnostics (2) | Nonzero GPU-completion sample count and existing metric SLA; not presentation or accepted percentile cohort |
| Shot/yours (1) | Final hand recipe preserved; eight reference-change records do not assert every selected version |
| Before (1) | Recipe and undo count unchanged across callbacks |
| Navigation (1) | Count AND no session-image absence after fixed waits; previously ignored blankAfterWait now fails |
| Focus stability (4) | Session identity, sampled ranks including intermediate and settled, sampled layout edges within one actual backing pixel, published settled dimensions. Intermediate fast-path skip explicitly recorded; no forced delay or proof of drawable tier |
| Crop/rotate (2) | Crop/geometry present in recipe; actual photograph remains separately required |
| Return/reopen inspection (3) | Inspection nil, then crop/geometry fields retained; no process restart |
| Edited mark (1) | Edited and not kept flags |
| Undo (1) | Cull unchanged; does not assert full edit restoration |
| Same-process reload (3) | Exact two recipe fingerprints and cull; removed partial geometry OR escape and quit/reopen claim |

Missing shoot name is an additional failure-path assertion, not a 54th successful normal-path check. No skip can become a named PASS. Intermediate presentation remains UNMEASURED when polling misses rank 1; controlled authoritative delay is still required. Fixed-wait distributions retain their boundary labels and must not enter P01/P04 acceptance.

## Measurement added

The existing recorder now includes a 512-event bounded selected-image trace with run ID, total and overwritten counts. Input time is sampled before session mutation and explicitly labeled session-callback, not native NSEvent time. Scrub, instantaneous recipe edits, focus and Canvas entry record asset/fingerprint/input ID. Gesture release is a separate callback event. Scheduler captures the matching input before its awaits, then carries request/generation/tier/fallback identity into its publication. Queue and render-return records retain request ID. Cache hits retain new request identity while bypassing render work.

Canvas attaches identity only when the selected CIImage is the exact published object. Browse fallback carries unknown recipe/generation and explicit provenance; Before cache is also explicitly unattributed. This preserves the existing quarter-turn defect and exposes its selection instead of certifying the requested recipe. Metal captures that envelope and a per-draw ID before acquisition, records acquisition separately, submission, GPU completion, and the drawable's host presentedTime. Zero presentedTime is not a latency. Missing callbacks can be located against submissions in retained records; overwritten records cannot establish completeness. Width/height belong to the acquisition event linked by draw ID. No optical assertion is made.

Remaining measurement gaps: native event origin, actual control acknowledgment, Before-cache recipe identity, precise cached image age, full input coalescing classification, quiet matched runs, recorder on/off overhead, persistence across all ring overwrites, and startup boundaries. The legacy latency arrays remain separately unbounded; bounded new tracing does not make the complete recorder memory-safe for acceptance. No scheduler optimization is included.

## Threshold decisions

Preserve v5 opening <1 second carried through v6; process-to-home and folder-to-viewport need separate applicability decisions. Historical `P0_EDITING.md` <16 ms slider/pixels, <150 ms settled and <35 ms cached navigation remain unresolved tighter constraints. Their historical polling/publication boundaries are not interchangeable with selected-recipe drawable acknowledgment. Neither that difference nor the newer proposed 50/300/80 ms budgets authorizes a relaxation. Before acceptance, report both boundaries and obtain an explicit same-boundary ruling if a looser criterion is proposed. No threshold constant was changed.

Scrolling retains >2 actual-refresh-interval gaps below 1% and none >100 ms warm. Memory absolute RSS and physical-footprint caps are TBD for the frozen workload/host: memory PASS prohibited. The existing 64 MB browse-floor cache ceiling is a component budget, not a whole-process cap. RAW graph parity remains 45/45, every case ≤1.5 CIE76 ΔE; historical parity is not current validation.

## Learning and next decision

The image you see can differ from the image the scheduler finished. In the observed quarter-turn case, Canvas chooses the old browse photograph because its aspect differs from the rotated render. Measuring render completion alone would report success even while the old photograph remains visible. The patch tags the actual choice, including unknown fallback identity; packet 1 owns correcting that behavior.

The valid sample implicates comparison warming/materialization (about 1.18 seconds inclusive sampled main-thread work) and synchronous browse fallback construction (about 200 ms). Recorder work is also visible. Inclusive samples overlap and are not input latency; these are ranked hypotheses for 6A's small matched experiments, not established causes of every lag. Priority: (1) correct final selection in packet 1, (2) isolate comparison warming in 6A, (3) measure fallback construction and recorder overhead before broader changes.

Six-interaction coverage: open/Canvas, arrows, exposure/WB and shot/yours have scoped prior diagnostic evidence; controlled Before/After and actual trackpad scroll/reverse do not. Debug-attached/standalone/Release and measurement/recording toggle matrix remains UNMEASURED. The current scoreboard retains all UX01–38/P01–14 statuses; no performance row turns green.

## Verification and native media

FAST: 41/41 passed (`/private/tmp/p0-fast-final.log`). Required compile: passed (`/private/tmp/p0-compile-final.log`). Full logic suite: 518 tests executed, five skipped, zero failures (`/private/tmp/p0-logic.log`); skips are not passes. Includes six presentation-measurement tests and existing RenderInstrumentSLATests. The unique-bundle native Debug build also passed (`/private/tmp/p0-native-build.log`). Vet was invoked after every code unit; it is BLOCKED by missing Anthropic credentials. Its Codex agentic fallback also failed because the installed CLI's vendor executable is missing (ENOENT, `/private/tmp/p0-vet.log`). These are not successful review results.

Native candidate: baseline SHA plus `/private/tmp/lumina-ui-ux-evidence/p0-implementation/candidate.patch` (SHA256 `13f9205af09c225e8d5121bce6d5be3a78ea6d68195cc606bbc560035cfca4b2`; tracked patch, documentation additions separately committed). Executable `/private/tmp/lumina-p0-implementation-DD/Build/Products/Debug/Lumina.app/Contents/MacOS/Lumina`, binary SHA256 `581c22844c62208dab22d775db96e8b1e08f9b63a1c37ede415ae1d04ac8bc32`, bundle `com.lumina.uiuxp0implementation`, PID **59671**, CGWindow **11474**, bounds x224/y175/1280×832 including title bar. PNG backing size 2560×1664. Standalone Debug, no debugger; measurement and two-second recording enabled; video capture adds uncontrolled overhead. Fresh catalog under `p0-implementation/native/state`; RAWs APFS-cloned into `p0-implementation/raw-eight`. The cloned DSC08186.xmp already contained +1.40 exposure/5300K from the prior diagnostic; this is explicitly not a neutral fixture. No AI invocation. Power/thermal/model/other process conditions uncontrolled. No timing comparison to the older Release trace is valid.

Durable screenshots (actual photograph verified):

- `/private/tmp/lumina-ui-ux-evidence/p0-implementation/before.png`: original aspect, +1.40/5300K, DSC08186. SHA256 `0fa3d356505abfe904a710e6bdbcbfa934cddb5825453f4603f734b1653cbd28`.
- `/private/tmp/lumina-ui-ux-evidence/p0-implementation/after-270.png`: same asset, drawer says 270°, displayed photograph remains landscape. SHA256 `657167b9230bbfdde30d7f2c48fcfea50a2dea53312f4ff584840ab98ed4083f`. This reproduces UX03's failure on the candidate; it is not a before/after fix claim.

Native actions: chooser → disposable folder → Return Canvas → E drawer; R quarter-turn, Cmd-Z, R twice to half-turn, Right/Left, R to 270°, then further quarter-turns back upright; semantic Shot and Yours buttons. Coordinate drag failed `noWindowsAvailable`, so no new pointer scrub is claimed. Keyboard and semantic actions succeeded. Initial chooser typing raced its sheet and was corrected via the exposed path field; no wrong-window interaction was observed.

Video capture **BLOCKED**: exact-window `screencapture -v -V45 -l11474` produced `selection-diagnostic.mov` (45.015 seconds) with black frames at 2 and 25 seconds. A 20-second retry without concurrent screenshot calls, `selection-retry.mov`, contains four decoded black frames and no actual photograph. These files are failed capture evidence, not deliverable demonstration video. CUA screenshot streaming also reported ScreenCaptureKit **-3811** during recording; coordinate drags reported **-10005/noWindowsAvailable** even afterward. PNG capture via exact window succeeded. No system permissions were changed and unrelated windows were not recorded.

`/private/tmp/lumina-ui-ux-evidence/p0-implementation/native-metrics-final.json` has run `311A9366-5365-4AD9-B206-71035BEBBD36`, SHA256 `f49165397781f7401fa0b2f17d2eb6f2afa5ccb06ec12078531e9574765d3e51`: 133 retained events, zero overwritten, 14 callback inputs, 18 drawable acquisitions/submissions/GPU completions/presented-handler callbacks. Seven selected browse fallback and eleven selected render envelopes. Only **two** callbacks have positive host presentedTime; **sixteen are zero and invalid for latency**. Screenshot + selected/submitted fallback evidence supports the quarter-turn diagnosis; zero-time callbacks do not prove presentation. Full-run/missing/coalesced per-interaction analysis is still UNMEASURED. Source packet 1 must distinguish RAW materialization `isFlipped=false` from final Metal destination `isFlipped=true`; neither was changed here.

PID59671 was quit through its own native Cmd-Q; `ps -p 59671` confirmed absent. No PR, push, merge or successor dispatch occurred. Current cache-free checkpoint and parity results follow; they do not clear remaining native/performance acceptance gaps.

Revised live runner: `/private/tmp/lumina-ui-ux-evidence/p0-implementation/harness/p0_edit_live_report.json`, PID60837, same binary; **53 checks, 51 pass, two fail**. Navigation correctly fails on `blankAfterWait=true`. Progressive ranks `[0,0,0,2]` do not sample intermediate; explicit fast-path flag true, intermediate presentation UNMEASURED. Sampled geometry passes at backing scale 2 with four identical container frames, only one session-image aspect sample; this does not replace the prior native defect or prove full promotion geometry. Exact recipe reload assertions pass. Run used `LUMINA_RENDER_STRESS_SECONDS=1` for smoke, so its legacy “3 second” GPU diagnostic has only a one-second capture and cannot establish the named duration; this run is not acceptance. Full-duration capture remains required. Output log: `/private/tmp/p0-live-harness.log`.

## Final verification and ownership release

Code commit **`0725f80c2c7614e52b69d26112696ac008c472c9`** is the reviewed candidate. The final handoff update changes documentation only; the native candidate's product Swift code matches this commit. No optimization is included.

`BUILD_STABILITY_DERIVED_DATA=/private/tmp/lumina-p0-stability-DD bash Scripts/build_stability.sh` **PASS: two clean rounds**, including FAST, Debug clean/build, build-for-testing, 518 logic tests per round (five skipped, zero failures), compile guard, Release, Playground Release, and F11 checks. Log `/private/tmp/p0-build-stability.log`. Exact source at checkpoint: clean 0725f80. Host confirmed macOS26.5.2/25F84, Xcode26.6/17F113, Swift6.3.3, arm64. Debug binary SHA256 `8e59ef9647c060472dadde1e54aeabde10d1766f1220578c4725c8d8c7b77b4c`; Release `68dcccdb82cd3b83eb53b4d85a14aac833b5073041bc8b2a58e648f0b8384387`. Both executables are under the corresponding `Build/Products/{Debug,Release}/Lumina.app/Contents/MacOS/Lumina` in that derived-data directory. These are separate binaries from the earlier native candidate.

Current RAW proof **PASS 45/45, each ≤1.5 CIE76 ΔE** on clean 0725f80 / checkpoint Debug binary, XCTest PID66744. Stage comparisons: 24, worst **0.9074209238**. Encoded full-export comparisons: 21, mean **0.6920500630**, worst **0.8945394194**. Final latest-wins replacement ΔE **0**. This is graph/export correctness, not final Canvas correctness or latency.

Reproduction:

```sh
python3 Scripts/harness/eval/run_raw_parity.py \
  --raw /Users/aniketh/Pictures/lumina-harness/mehendi-94 \
  --truth /Users/aniketh/Pictures/lumina-harness/eval-out/truth.json \
  --out /private/tmp/lumina-ui-ux-evidence/p0-implementation/parity \
  --xctestrun /private/tmp/lumina-p0-stability-DD/Build/Products/Lumina_P0Fast_macosx26.5-arm64.xctestrun
```

Use a fresh output path when reproducing. Originals read-only; all exports go under the output directory. Input eight RAW hashes match the historic parity fixture manifest. Truth SHA256 `7750dec7cd8c86d1ea9efd3ae911f6b325951f096b1c685021e8805de8c130be`. Current `parity/manifest.json` SHA256 `d611dcaf639dca26ff3c857a061b9009e87b30c97f0d3af4c7e814347341b8a7`; `parity/preview-contract.json` SHA256 `89f387fcacf45a0e85a363e00adf8f13614b35e7d87edcf3673ead56aa219e52`. Manifest freezes all Swift source and RAW hashes. `parity/xcode.log` and `parity/result.xcresult` retain the actual assertion result.

Prompt 0 releases shared-file, native and build ownership on delivery of this handoff. Next decision belongs to command center: review this bounded patch, then explicitly release packet 1 against the accepted integration commit. Outstanding: video capture BLOCKED, vet BLOCKED, full native input/presentation/observer matrix UNMEASURED, all P rows UNMEASURED, two current diagnostic harness failures, and the reproduced Canvas fallback defect. No successor is dispatched and no acceptance threshold is relaxed.
