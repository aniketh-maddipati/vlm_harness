# Lumina build-stability baseline

Date: 2026-09-21
Untouched baseline: `375afe10535acc2fb3981ed4c5ae3ae25eb0a554`
Verified result: `1ce1d3dd294995f01aaa91e1bd4be49b173a5081`

This document distinguishes local Linux evidence, hosted macOS evidence, and
blocked lanes. A cached build is not recorded as a clean-build pass.

## Environments

| Environment | OS | Xcode / Swift | Architecture | Use |
|---|---|---|---|---|
| Cursor Cloud | Ubuntu, Linux 6.12.94+ | unavailable | x86_64 | FAST and static audits only |
| Hosted clean gate | macOS 15.7.9 (24G830) | Xcode 16.4; Swift 6.1.2, Swift-5 language mode | arm64 | clean Debug/Release builds and tests |

No self-hosted Mac was connected to the Cloud run. Local Gates B–F were
therefore `PLATFORM-UNAVAILABLE`, not pass.

## Baseline gates before edits

| Gate | Command / evidence | Result | Classification |
|---|---|---|---|
| A — FAST | `python3 Scripts/harness/run.py fast` | `INCOMPLETE`, 40/41; `progressive_render_architecture` failed | **PRE-EXISTING** — reproduced on the clean untouched baseline |
| B — compile ledger | `bash Scripts/compile_check.sh` | exit 2 on Linux | **PLATFORM BLOCKED** |
| B — hosted compile ledger | workflow run `35563704639` | `xcode_compile: OK`, with restored DerivedData | PASS, but not clean-build proof |
| C — clean Debug | no pre-existing CI command | not run | **UNKNOWN / PLATFORM BLOCKED** |
| D — build-for-testing | hosted `compile-logic` | compiled app and both test bundles, with restored DerivedData | PASS, cached |
| E — all logic tests | hosted `compile-logic` | 193 executed, 1 failure, 0 skipped/crashes/hangs; 1.353 s test execution | **PRE-EXISTING** — same source assertion as Gate A |
| F — delete DerivedData and repeat | no pre-existing CI command | not run | **UNKNOWN / PLATFORM BLOCKED** |

The failing assertion searched source text for the prose fragment
`must never demosaic RAW`. The implementation still rejected RAW paths, but a
comment line wrap made both FAST and XCTest red. The guard itself was already
asserted separately.

## Project and scheme census

- `Lumina.xcodeproj` uses object version 77 and filesystem-synchronized root
  groups for `Lumina`, `LuminaLogicTests`, `LuminaUITests`, and `DesignTokens`.
- No missing or duplicate explicit file references were found. Source and
  resource build phases intentionally rely on synchronized groups.
- `Lumina` builds the app plus both test bundles for testing.
- `LuminaLogicTests` uses `TEST_HOST` / `BUNDLE_LOADER` against `Lumina.app`.
- The default `Lumina` test action uses `P0Fast`, with `P0Stress` and
  `P0Visual` available explicitly.
- Test plans contain no retry, repetition, or quarantine settings.
- `EditingProbeTests` compiles but is not selected by a UI test plan. This is a
  coverage gap, not a compile failure; it was not changed in this task.
- Swift language mode is 5.0, default actor isolation is `MainActor`, and the
  deployment target is macOS 14.0 for all targets.
- Shipping `Lumina` Release defines `LUMINA_SHIPPING_APP`. Baseline
  `LuminaPlayground` Release did not.

### Configuration identity matrix

| Target | Configuration | `DEBUG` | `LUMINA_SHIPPING_APP` | `LUMINA_WORKBENCH` | Harness intent |
|---|---|---:|---:|---:|---|
| `Lumina` | Debug | yes | no | no | development/UI-test/lab harness available |
| `Lumina` | Release | no | yes | no | shipping app; all harness runners excluded |
| `LuminaPlayground` | Debug | yes | no | yes | development workbench and harness |
| `LuminaPlayground` | Release | no | yes | no | shipping-like compile identity; no harness/lab runners |

The Playground scheme uses Debug for launch, profile, and archive. Playground
Release is therefore a build-coherence check, not a second workbench product.
The project-setting fix changed only the number of
`LUMINA_SHIPPING_APP` target conditions from one to two; `DEBUG` and
`LUMINA_WORKBENCH` condition counts did not change.

**Invariant:** every app Release configuration is shipping-fenced; only
Playground Debug has workbench capability.

## Generated sources and build inputs

| Generated output | Source of truth | Command | Baseline |
|---|---|---|---|
| `DesignTokens/HiFiTokens.generated.swift` | `design/tokens.yaml` | `python3 Scripts/harness/codegen/tokens_codegen.py --check` | current |
| `artifacts/harness/tokens.hash` | `design/tokens.yaml` | same generator | current |
| constitution coverage JSON/Markdown | contract and artifact registries | `generate_constitution_coverage.py --check` | current |
| `LuminaBuildManifest.json` | git/build settings/tokens | `write_build_manifest.py` | generated per build; ignored |

Repeated FAST runs did not modify tracked files. Xcode builds generate the
ignored build manifest and task-specific DerivedData only.

## Dependency inventory

| Dependency | Classification | Notes |
|---|---|---|
| Apple Silicon macOS 14+; Xcode 16.4+ | **REQUIRED TO COMPILE AND TEST** | Xcode 16.4 is the verified floor for this project format |
| Python 3 + PyYAML | **REQUIRED TO TEST** | FAST, codegen, registries, and release-source checks |
| `exiftool` | **REQUIRED FOR OPTIONAL INTEGRATION** | metadata, sidecar, and media audits; not needed to compile |
| Inject 1.6.0 package | **REQUIRED TO COMPILE PLAYGROUND** | exact package pin; shipping app does not link it |
| RAW fixture bundle URL/SHA | **REQUIRED FOR OPTIONAL INTEGRATION** | absent secrets mean render-live is blocked/skipped, not pass |
| fixed self-hosted render worker and baselines | **REQUIRED ONLY FOR HEAVY/RELEASE** | nightly performance and full fixture fleet |
| Developer ID, notarization, stapling credentials | **REQUIRED ONLY FOR HEAVY/RELEASE** | signature gate; unavailable credentials may not be called pass |

## Reproduced failures and fixes

### 1. Prose-based RAW browse assertion

- Reproducer: `python3 Scripts/harness/lint/progressive_render_architecture.py`
- Root cause: the ratchet asserted comment wording rather than executable guard
  structure.
- Fix: FAST, XCTest, and E2E now assert
  `guard !rawExtensions.contains(ext) else { return nil }`.
- Regression guard: the existing `progressive_render_architecture` FAST test.

### 2. Playground Release fence mismatch

- Reproducer:
  `python3 Scripts/harness/lint/xcode_compile.py --scheme LuminaPlayground --configuration Release --action build`
- Failure: eight missing symbols (`DevelopLabLauncher` and
  `DevelopLabFixtures`) because non-shipping runners compiled while DEBUG-only
  fixtures did not.
- Root cause: Playground Release defined neither `DEBUG` nor
  `LUMINA_SHIPPING_APP`.
- Fix: define `LUMINA_SHIPPING_APP` for Playground Release.
- Regression guard: FAST `shipping_fence` now checks the Release configuration
  of both app targets.

## Verified state after fixes

Workflow run `35566168557` executed `bash Scripts/build_stability.sh` without
restoring DerivedData. Both rounds removed the task DerivedData directory first.

| Check | Round 1 | Round 2 |
|---|---:|---:|
| FAST | 41/41, 7.741 s | 41/41, 14.709 s |
| clean Debug build | pass | pass |
| build-for-testing | pass | pass |
| complete `LuminaLogicTests` | 193/193, 0 failed, 0 skipped; 1.343 s | 193/193, 0 failed, 0 skipped; 1.549 s |
| compile ledger | 0 errors | 0 errors |
| shipping Release build | pass | pass |
| Playground Release build | pass | pass |
| F11.1 hooks absent | pass | pass |
| F11.2 zero network | pass | pass |
| tracked tree after no-op gates | clean | clean |

The full two-round job took about 15 minutes 22 seconds. Hosted workflow
`fast`, `compile-logic`, and `build-stability` all passed on both push and pull
request events (12 checks total).

## Warning census and remaining debt

The clean run emitted 55 unique warnings (346 repeated emissions across the
multiple builds). Several are explicit Swift-6-mode future errors around
`NSImage`, Metal sendability, actor isolation, and concurrent captures.
Current builds use Swift-5 language mode, so they are warnings rather than
compiler errors. They are real migration debt, but fixing them would cross
multiple runtime owners and was not batched into this stability task.

Other honest limits:

- `python3 Scripts/harness/run.py full` is `PLATFORM-UNAVAILABLE` on Linux
  (0 of 9 app tests). On macOS, FULL still contains named refusing live stubs;
  it is not the hosted merge gate.
- `render-live` remains blocked/skipped when fixture secrets are absent.
- F11 signing/notarization/stapling was not run because release credentials are
  unavailable. F11.1 and F11.2 passed against both built Release apps.
- No flaky logic test was observed across the two clean runs. UI suites were
  compiled, not executed by this build-stability loop.

The core Debug/Release/logic-test path satisfies the two-clean-round criterion.
The repository must not be described as fully green across FULL, live fixtures,
UI automation, and signed release while the explicitly blocked items above
remain.
