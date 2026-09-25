# 1-display-handoff

Status: PARTIAL. Bounded code correction and required clean-build/logic/parity checks are complete. Native visual correction is BLOCKED; UX03–06 are not accepted by source inspection. All P rows remain UNMEASURED.

## Foundation and ownership

Accepted predecessor: `9c77ced2109bc00113e6c507633ec56b60df7cbf`, documentation finalization atop `0725f80c2c7614e52b69d26112696ac008c472c9`. The assigned worktree started clean at `a6923588dfe3824f3b84556bbcac3d93d8f67876`; branch `codex/ui-ux-1-display` was created there directly from the accepted predecessor. Refs were fetched; no second checkout was created. Inspected the intervening diff and consumed `docs/0-baseline-handoff.md`.

Packet 1 owns `ElasticFocusView`, `OrientedDisplayImage`, `DevelopRenderScheduler`, `RawRenderRequest`, the display bridge in `ViewModels/P0SessionModel`, and associated selector/architecture tests and lint. `ElasticCanvasLayout` is periphery layout, not the normal focused photograph fit; it does not need changing. Neither RAW materialization (`isFlipped=false`) nor final Metal presentation (`isFlipped=true`) is changed. No canonical recipe, command/undo, journal, sidecar or exporter semantics are changed.

Command center granted native/build/render ownership on release. After the first logic run exited, Packet 1 explicitly released that execution lease temporarily to the command center for a separate quality assessment. Command center explicitly returned it after that assessment stopped. Source ownership remains Packet 1. No accepted timing run occurred.

Consumed predecessor artifacts under `/private/tmp/lumina-ui-ux-evidence/p0-implementation/`:

| Artifact | SHA256 |
|---|---|
| verification.json | f43871bc6bad403494b0a1325024935a1489936f3fd1c1d5c8dce48ce504155b |
| parity/manifest.json | d611dcaf639dca26ff3c857a061b9009e87b30c97f0d3af4c7e814347341b8a7 |
| parity/preview-contract.json | 89f387fcacf45a0e85a363e00adf8f13614b35e7d87edcf3673ead56aa219e52 |
| native-metrics-final.json | f49165397781f7401fa0b2f17d2eb6f2afa5ccb06ec12078531e9574765d3e51 |

P0's actual `before.png`/`after-270.png` and the parity XCTest log/result bundle remain predecessor evidence, not Packet 1 runtime proof. P0's 45/45 RAW results (worst 0.9074209238), two cache-free rounds and 518 tests/five skips/zero failures establish the accepted foundation only. Sixteen of eighteen native presentedTime callbacks were zero and remain excluded from latency. P0's black video attempts remain failed captures, not demonstration video.

## Problem and mechanism

The old Canvas guard compared a newly rendered photograph's portrait/landscape shape with the unchanged browse preview. A legitimate quarter-turn or crop could therefore be rejected even after rendering finished correctly. The user could see 270° in the drawer while the photograph remained landscape.

The production selector now receives asset identity, the exact published recipe and generation independently of opt-in measurements. It compares the candidate's shape with the existing geometry graph applied to the oriented browse reference and the requested recipe. Decoder rounding has a bounded pixel tolerance; opposite sensor shape is still rejected. It does not rotate the candidate again or remove the geometry guard.

While the requested recipe renders, the selector retains only the previously selected same-asset frame, or a same-asset browse fallback. It does not pretend those pixels match the new recipe: the existing `Stale render` copy replaces the settled state word until a matching frame is selected. A valid matching candidate replaces retained pixels immediately; no minimum intermediate duration is imposed. Previously selected layout size is reused across same-geometry tier changes. This stabilizes the outer photograph box; physical rendered edge measurements are still necessary.

The scheduler rechecks cancellation and synchronous request ownership after awaited cache insertion and before publication. The selector also rejects generation regression against its retained frame. An asynchronous browse load checks cancellation/asset identity after its pin await before changing fallback ownership. These are bounded stale-selection corrections, not scheduling optimization.

The existing bounded recorder adds Canvas selection/box records and selected-frame age. A frame's age is not automatically stale duration; reconstruct retention from the requested-recipe event and the replacement event, excluding overwritten/missing records. Rendering identity stays attached to the selected frame, including a retained frame. Before-cache identity remains explicitly unattributed in instrumentation even though its product recipe is known neutral.

For diagnostic delayed-authoritative proof only, Debug plus `--p0-instruments` can set `LUMINA_DISPLAY_TEST_SETTLED_DELAY_MS` (bounded to 5000 ms). This delays uncached settled work before evaluation, not a final image already ready to display. Cache hits bypass it; Release compiles it out. No delayed run belongs in latency acceptance.

## Verification ledger

- Initial FAST: 41/41 PASS after updating the architecture lint to require the production recipe-aware selector.
- Initial required compile: PASS (`/private/tmp/p1-compile.log`).
- Initial logic: 522 tests, five skips, one failure (`/private/tmp/p1-logic.log`). Failure was the source assertion for the old scheduler guard spelling. It now requires cancellation plus visible-asset checks and request identity; no behavior assertion was removed. Subsequent source edits require a new compile/run.
- Vet invoked after each code unit. API mode BLOCKED by missing Anthropic credentials; Codex agentic fallback BLOCKED by missing vendor executable (ENOENT). Logs `/private/tmp/p1-vet*.log`. Neither is a review PASS.
- Final required compile PASS (`/private/tmp/p1-compile-final.log`); full logic PASS: 523 tests, five skips, zero failures (`/private/tmp/p1-logic-final.log`). All five new selector tests passed. Latest FAST 41/41 PASS (`/private/tmp/p1-fast-final.log`).
- Unique native Debug build PASS (`/private/tmp/p1-native-build.log`), bundle `com.lumina.uiuxp1`, executable `/private/tmp/lumina-p1-native-DD/Build/Products/Debug/Lumina.app/Contents/MacOS/Lumina`, SHA256 `7a4040f17b0f731ae7fe70ac04eefd445420c2a42418639c8a7fb6eadeec1d52`. Source is accepted predecessor plus this task's patch; final commit identity follows verification.
- Current RAW graph/export parity PASS: 45/45, each ≤1.5 CIE76 ΔE; worst 0.9074209238, latest-wins replacement ΔE 0. Artifact details below.
- Two cache-free rounds PASS on clean committed code, including the repository static, Debug, logic, compile, Release, Playground Release and F11 checks. No separate full media regression or native UI run is claimed.
- Native screenshots/export pairs, delayed-authoritative presentation, transition recordings and 1×/2× physical edge proof remain BLOCKED/UNMEASURED.

The production selector regression matrix covers three source shapes, four quarter-turns, centered/off-center/no crop; wrong asset, wrong recipe, sensor shape, prior same-asset retention, replacement, generation regression and square/tier rounding. Source architecture checks keep the actual Canvas wired to that tested selector. These tests do not establish actual native pixels or 500-transition presentation acceptance.

## Evidence and remaining acceptance

Packet 1 private evidence root: `/private/tmp/lumina-ui-ux-evidence/p1/`. Eight RAWs and existing diagnostic sidecars were APFS-cloned from P0's disposable directory; `fixtures-before.sha256` freezes the copied inputs. Existing sidecars are not neutral and are recorded separately. No original media is edited. App-cold is distinct from disk-cold.

Still required: native rotation/crop/EXIF matrix including Before/Yours, undo and reopen; decoded export agreement; three runs of 500 identity-correlated transitions; delayed and fast-path cohorts; no blank after valid preview; each physical edge at 1×/2×; actual display/refresh/window/hardware conditions; current 45/45 RAW parity each ≤1.5 CIE76 ΔE. Unavailable scale/fixture/capture cases must remain explicitly BLOCKED/UNMEASURED. No source test, still image or GPU completion substitutes for missing presentation proof.

The earlier navigation missing-image diagnostic and unsampled intermediate rank are unresolved. Do not relabel them as passes. A short real native video is only useful if it contains the actual photograph. Two predecessor exact-window screencapture videos were black; repeating that path blindly is not authorized evidence work. No optical input-to-photon or human trust/smoothness outcome is claimed.

Next decision: command center owns integration and ordinary native verification/profiling. The corrected source is ready for that verification, with the visual and timing limits preserved. No push, publication, merge or successor dispatch occurred in this task.

## Native attempt log

The accepted predecessor binary was launched with isolated state under `p1/baseline`, PID78385. CUA bound its unique bundle `com.lumina.uiuxp0implementation`. The folder chooser navigated to the disposable fixture folder, but Open remained disabled after keyboard directory selection. Semantic row clicks did not select; keyboard selection did. CUA returned a tiny white screenshot, not usable photograph evidence. Quit through CUA timed out (-10005); only owned PID78385 was terminated with SIGTERM. No other Lumina process was terminated.

The Packet 1 unique Debug app then launched through LaunchServices with isolated `p1/native` state, PID79157, instrumentation and a 5000 ms diagnostic settled delay. Native binding took approximately 130 seconds; the initial Open surface was accessible. It was quit successfully before catalog preparation; `ps` confirmed PID79157 absent. No candidate photograph capture or latency claim follows from that attempt.

The existing `--p0-edit-live … --p0-open … --p0-instruments` harness was requested to seed a disposable catalog and exercise the real Canvas, bypassing only the chooser. Automatic approval review rejected that launch as a computer-bypass action without explicit trusted-user approval. No workaround was used. The user then explicitly replied “ill approve”; the reviewer nevertheless rejected the retry, stating it treated that reply as untrusted transcript evidence. Both launch requests were denied before execution. The command center instructed no further retry or equivalent route. Harness setup is not a successful native chooser test, and hosted harness PNGs omit Metal pixels.

No Packet 1 photograph screenshot, native video, or timestamped still sequence was successfully captured. No physical window bounds/display scale were established for these failed attempts. No native geometry/export agreement, blank-free transition count or intermediate presentation is claimed. The existing P0 screenshots remain historical evidence only.

## Final source, binaries and checks

Code commit: **`ceb1c10baa68a2821270f7f1f1923cc899b72d8a`**. This final handoff amendment changes documentation only. The code tree was clean throughout the two-round checkpoint; no source changes occurred after commit. Native/build/render lease was explicitly released to command center after the checkpoint exited at approximately 22:04 UTC on 2026-09-23. Scoped process inspection confirmed no P1 native processes or the owned baseline/parity PIDs remained. No further heavy work or UI control follows that release. All changed-file ownership is released with this final handoff.

`BUILD_STABILITY_DERIVED_DATA=/private/tmp/lumina-p1-stability-DD bash Scripts/build_stability.sh` passed both rounds. Each executed **523 logic tests, five skips, zero failures**. The checkpoint includes FAST 41/41, clean Debug build/build-for-testing, full logic, compile guard, Release, Playground Release and F11 checks. Log: `/private/tmp/p1-build-stability.log`. Hardware environment: arm64, macOS 26.5.2/25F84, Xcode 26.6/17F113, Swift 6.3.3. No controlled power/thermal/refresh/cache condition or performance acceptance follows from a build.

Standalone optimized Release candidate (built, not product-verified):

- Executable: `/private/tmp/lumina-p1-stability-DD/Build/Products/Release/Lumina.app/Contents/MacOS/Lumina`.
- SHA256: `9cdaddc7ef9059c51e7cfabd55ed479c7819fd05fdf922a3099e0e81258c8b4c`.
- Bundle: `com.lumina.app`; build manifest records code SHA `ceb1c10`, Release, build time `2026-09-23T22:03:02Z`. This generic bundle can coexist with other checkouts; downstream native control must positively identify its own process/window.
- Checkpoint Debug executable is in the sibling `Debug` directory; SHA256 `0c23ab157b3b68c3de21c2583a77e6c4659040445cfa08d970adfbff9a8f98b3`.

Current parity used `/private/tmp/lumina-p1-DD/Build/Products/Lumina_P0Fast_macosx26.5-arm64.xctestrun`, XCTest PID79940 and Debug binary SHA256 `868cd2aa03de93ee96a28110d5ee9dc881e87f05cc1b18aa5f0b9cd0bb8990df`. Output directory: `/private/tmp/lumina-ui-ux-evidence/p1/parity/`. Its manifest recorded predecessor HEAD `9c77ced` because the run began before the code commit; **all 266 recorded Swift source hashes match `ceb1c10` exactly**. This correspondence is explicit, not a fabricated measurement at a later SHA. `xcode.log` and `result.xcresult` contain the actual assertion result.

| Artifact | SHA256 |
|---|---|
| parity/manifest.json | 042498b72bc95702b6b806786ed875adec6cc9b7b7b544b9ba80475481056afe |
| parity/preview-contract.json | b0842527443e93c18b6842f4c8fd4f57837a096a6816a646514bb0e0ca8c8492 |
| fixtures-before.sha256 | 9b74e3fda2633962dcb26cd916334be758f73fa70c0ff3a3f2d3a950ab55fdea |

The eight cloned RAW content hashes independently match P0's frozen parity inputs. The current parity suite comprises 24 stage comparisons and 21 encoded-export comparisons. It verifies the existing renderer/exporter, not the final native Canvas choice. Private originals were read only; output artifacts stayed outside git.

Successfully used focused reproduction commands, before the full clean checkpoint:

```sh
python3 Scripts/harness/run.py fast
python3 Scripts/harness/lint/xcode_compile.py --project-root . --derived-data /private/tmp/lumina-p1-DD
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug \
  -derivedDataPath /private/tmp/lumina-p1-DD -destination 'platform=macOS,arch=arm64' \
  -only-testing:LuminaLogicTests test-without-building
```

For private parity reproduction, use `Scripts/harness/eval/run_raw_parity.py` with the frozen RAW/truth inputs from the private manifest, a fresh output directory outside the repository and the corresponding built `.xctestrun`. Preserve the original truth and RAW hashes; do not infer native acceptance from this suite.

Compact machine-readable outcomes are under `/private/tmp/lumina-ui-ux-evidence/p1/verification.json` and `results.csv`. They retain native BLOCKED rows and source/binary correspondence. This task produced no Instruments capture; profiler handoff belongs to command center. Vet remains BLOCKED by credentials and missing agentic CLI executable. No human trust, image-quality preference, responsiveness, memory or optical input-to-photon claim is made.
