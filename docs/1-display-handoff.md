# 1-display-handoff

Status: PARTIAL; native and parity verification in progress. UX03–06 are not accepted by source inspection. All P rows remain UNMEASURED.

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
- Current parity, regression, two cache-free rounds, native screenshots/export pairs and delayed-authoritative proof: pending.

The production selector regression matrix covers three source shapes, four quarter-turns, centered/off-center/no crop; wrong asset, wrong recipe, sensor shape, prior same-asset retention, replacement, generation regression and square/tier rounding. Source architecture checks keep the actual Canvas wired to that tested selector. These tests do not establish actual native pixels or 500-transition presentation acceptance.

## Evidence and remaining acceptance

Packet 1 private evidence root: `/private/tmp/lumina-ui-ux-evidence/p1/`. Eight RAWs and existing diagnostic sidecars were APFS-cloned from P0's disposable directory; `fixtures-before.sha256` freezes the copied inputs. Existing sidecars are not neutral and are recorded separately. No original media is edited. App-cold is distinct from disk-cold.

Still required: native rotation/crop/EXIF matrix including Before/Yours, undo and reopen; decoded export agreement; three runs of 500 identity-correlated transitions; delayed and fast-path cohorts; no blank after valid preview; each physical edge at 1×/2×; actual display/refresh/window/hardware conditions; current 45/45 RAW parity each ≤1.5 CIE76 ΔE. Unavailable scale/fixture/capture cases must remain explicitly BLOCKED/UNMEASURED. No source test, still image or GPU completion substitutes for missing presentation proof.

The earlier navigation missing-image diagnostic and unsampled intermediate rank are unresolved. Do not relabel them as passes. A short real native video is only useful if it contains the actual photograph. Two predecessor exact-window screencapture videos were black; repeating that path blindly is not authorized evidence work. No optical input-to-photon or human trust/smoothness outcome is claimed.

Next decision: complete bounded verification after the execution lease returns, then give command center the committed patch, precise proof limits and final lease release. No push, publication, merge or successor dispatch is authorized here.

## Native attempt log

The accepted predecessor binary was launched with isolated state under `p1/baseline`, PID78385. CUA bound its unique bundle `com.lumina.uiuxp0implementation`. The folder chooser navigated to the disposable fixture folder, but Open remained disabled after keyboard directory selection. Semantic row clicks did not select; keyboard selection did. CUA returned a tiny white screenshot, not usable photograph evidence. Quit through CUA timed out (-10005); only owned PID78385 was terminated with SIGTERM. No other Lumina process was terminated.

The Packet 1 unique Debug app then launched through LaunchServices with isolated `p1/native` state, PID79157, instrumentation and a 5000 ms diagnostic settled delay. Native binding took approximately 130 seconds; the initial Open surface was accessible. It was quit successfully before catalog preparation; `ps` confirmed PID79157 absent. No candidate photograph capture or latency claim follows from that attempt.

The existing `--p0-edit-live … --p0-open … --p0-instruments` harness was requested to seed a disposable catalog and exercise the real Canvas, bypassing only the chooser. Automatic approval review rejected that launch as a computer-bypass action without explicit trusted-user approval. No workaround was used. The user then explicitly replied “ill approve”; a bounded retry will follow the independent RAW parity run. Harness setup is not a successful native chooser test, and hosted harness PNGs omit Metal pixels.
