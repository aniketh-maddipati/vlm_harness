# Lumina harness (CP0)

**Authority:** `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests.  
**Checkpoint:** CP0 — harness upgrade (testing never blocks building).  
**Primary entry:** `bash Scripts/regression.sh {pre-commit|pre-merge|nightly}` — default `pre-commit`. Dispatches to `python3 Scripts/harness/run.py {fast|full|heavy}` and propagates exit codes verbatim.  
**Direct runner:** `python3 Scripts/harness/run.py {fast|full|heavy|watch|all}` — for harness development and `watch`.

A red FULL lane blocks **MERGE**, never **EDITING**. FULL/HEAVY run against a disposable git worktree snapshot when the platform is available.

---

## Lane aliases (`regression.sh` ↔ `run.py`)

Human-facing save/merge/nightly names map to manifest lane ids without renaming either side:

| `regression.sh` | `run.py` | Manifest lane |
|-----------------|----------|---------------|
| `pre-commit` (default) | `fast` | `fast` |
| `pre-merge` | `full` | `full` |
| `nightly` | `heavy` | `heavy` |

No argument to `regression.sh` ≡ `pre-commit`. Exit codes: `0` PASS · `1` FAIL/INCOMPLETE · `2` PLATFORM-UNAVAILABLE.

---

## Budget ceiling (enforced)

Each lane declares `budgetMs` in `Scripts/harness/lanes/manifests.json`. **Total lane elapsed time above the ceiling is a lane FAIL** — not a warning. On breach the runner prints the slowest manifest test ids by measured ms (descending), then the sentence **delete or demote** (never hardware, parallelism, or a raised ceiling). Ceilings: FAST **90000** ms (<90s) · FULL **600000** ms (<10min) · HEAVY **3600000** ms (nightly budget).

**Pre-merge build cache (F04.1):** `Scripts/harness/build_cache.py` stores `xcodebuild build-for-testing` products under `artifacts/harness/build-cache/<source-hash12>-<tokens-hash12>/`. `bash Scripts/regression.sh pre-merge` reuses when source + `design/tokens.yaml` are unchanged.

**Compile rot-guard:** FAST `session_surface` keeps `P0SessionModel.developScheduler` file-private (call sites use `displayedCIImage` / `developFidelity` / `editMetricsLine`). FULL job #1 `xcode_compile` runs `xcodebuild build-for-testing` with `SWIFT_CONTINUE_BUILDING_AFTER_ERRORS=YES` and prints a compact error ledger so one file does not hide the rest. Developers: `bash Scripts/compile_check.sh`. Local `./DD` and `./build` are gitignored.

---

## Allowlist ratchet

FAST manifest id `allowlist_ratchet` fails pre-commit if `artifacts/harness/banned_patterns_allowlist.txt`, `artifacts/harness/magic_number_allowlist.txt`, or `artifacts/harness/orphan_register.txt` carries **more** debt lines (non-blank, non-`#`) than the same file on `origin/main`. Allowlists may shrink; they must not grow without a deliberate baseline change on main.

---

## Shell lint host (bash)

Orchestration shell lints live under `Scripts/harness/lint/*.sh` and are reachable **only** through FAST manifest ids. They must execute on **macOS system bash 3.2+** (Gatekeeper Mac default). They must not use bash 4-only builtins (e.g. `mapfile`). A lint that cannot run on the gating Mac must never contribute a PASS.

---

## Platform split (F2) — language / OS boundary

| Layer | Language / host | Examples |
|-------|-----------------|----------|
| **Orchestration** | **Python** (any host) | runner, lane manifests, lints, codegen freshness, dashboard, golden *bookkeeping*, script/probe *schemas*, numbers ledger writer, HEAVY job registry |
| **App-coupled** | **Swift on macOS Apple Silicon** (REQUIRED) | Probe v2 client + in-app server, `os_signpost` emission, input-script event driver, headless app instances, `HarnessFakeClock` |

**Rule:** any app-coupled component that is not yet live in Swift must carry an explicit `STUB` marker and an `owned-by-CP<N>` (or SPIKE/HEAVY) owner. Unowned stubs = unowned gaps = FAIL.

Swift already in-tree (DEBUG only): `Lumina/Testing/ProbeV2/{StateProbeV2,HarnessFakeClock}.swift`.

### STUB register (app-coupled)

| Stub | Path | Owner |
|------|------|-------|
| Grammar event driver + live scripts | `Scripts/harness/probe/run_live_scripts.py` | **CP4** |
| Probe v2 mid-script client | `Scripts/harness/probe/run_live_probe.py` | **CP4** |
| Python grammar oracle (not live) | `Scripts/harness/probe/simulator.py` | **CP4** (oracle only; never app PASS) |
| One-⌘Z-per-gesture live | `Scripts/harness/probe/run_live_undo.py` | **CP4** |
| Count invariants live | `Scripts/harness/probe/run_live_invariants.py` | **CP7** |
| Measured signpost capture | `Scripts/harness/trace/run_live_signposts.py` | **SPIKE A** |
| Chrome pixel golden `--live` | `Scripts/harness/golden/run_chrome_diff.py --live` | **CP1** |
| Parallel headless instances | `Scripts/harness/parallel_instances.py` (non-dry-run) | **HEAVY** |
| HEAVY job bodies (unwired ids) | `Scripts/harness/heavy/run_job.py` (non-delegated jobs) | **HEAVY** |
| RAM tier gate | `Scripts/harness/heavy/ram_tiers.sh` → `--ram-harness` | **HEAVY / W6** — active on macOS |

---

## CI topology (F3)

| Lane | Platform | Linux cloud | macOS AS 14+ |
|------|----------|-------------|--------------|
| **FAST** | `any` | lint / codegen / schema / unit — **may PASS** | same |
| **FULL** | `macos-apple-silicon` | **PLATFORM-UNAVAILABLE** (not PASS) | app-coupled suite |
| **HEAVY** | `macos-apple-silicon` | **PLATFORM-UNAVAILABLE** (not PASS) | nightly / release |

Fleet floor: Apple Silicon, macOS 14+ (`design/mvp-test-plan.md`, D65 / A1). Intel → PLATFORM-UNAVAILABLE.

Lane definitions live in `Scripts/harness/lanes/manifests.json` and are enforced by `Scripts/harness/lanes/host_platform.py` — not tribal knowledge.

Exit codes: `0` PASS · `1` FAIL/INCOMPLETE · `2` PLATFORM-UNAVAILABLE.

---

## Vacuous-green guard (F1)

Each lane declares an expected test inventory (`lanes/manifests.json`). After execution the runner compares executed IDs to the manifest:

- Missing any expected ID → **INCOMPLETE** (never PASS)
- Manifest expects app-coupled tests and **0** ran → **INCOMPLETE** (vacuous-green)
- Summary line always includes counts, e.g.  
  `=== HEAVY PLATFORM-UNAVAILABLE in 12ms (0 app tests executed / 6 expected; 0 orchestration)`

---

## Three lanes

| Lane | Budget | When | Contents |
|------|--------|------|----------|
| **FAST** | <90s | save/commit / `watch` | orchestration only: token/copy/banned/magic lints, contract lints, unit tests, seed **schema** + grammar **oracle** + **oracle↔Swift parity** (orchestration — never app PASS) |
| **FULL** | <10min | pre-merge | macOS AS: live grammar/probe/signpost/⌘Z/invariants/chrome/parallel (+ worktree snapshot). Linux: PLATFORM-UNAVAILABLE |
| **HEAVY** | nightly + release | scheduled | macOS AS: ingest / kill-fuzz / eject / RAM / LR / live grammar-stability. Linux: PLATFORM-UNAVAILABLE |

**Flake policy:** a flaking pre-merge test is fixed same-day or demoted to nightly by a manifest diff — those are the only two moves. FAST **`flake_policy`** reads `TestPlans/*.xctestplan` and fails on test repetition, retry-on-failure, or quarantine tags (none permitted).

Dashboard (optional): `python3 Scripts/harness/dashboard/server.py` → `http://127.0.0.1:8765/`

---

## Numbers ledger honesty (F4)

Acceptance numbers (`open <1s`, crossfade 120ms, settle 200ms, grab 90ms, halo 600ms, slider-to-photon) are written to `artifacts/harness/ledgers/orchestration-only.json` as:

- `mode: orchestration-only`
- `gates_active: false`
- each entry `status: UNMEASURED` (not absent, not PASS)

Gates activate only when a macOS measured run populates samples (`mode: measured`, `gates_active: true`). Fixture sample logs may unit-test the parser; they must not bless a lane.

---

## Run idempotence

**A no-op run of any lane leaves the tree clean.** A modified file after `run.py {fast|full|heavy}` on an unchanged tree is a bug in the harness, not something to restore by hand — restoring it by hand is how a real evidence change gets mistaken for churn and discarded.

Tracked harness artifacts are **content-addressed**: same inputs, same bytes, no wall-clock field. That is what makes a diff on one of them mean something. When the evidence last changed is the commit date; when a lane last ran is run exhaust — `artifacts/harness/ledgers/latest.json` and `artifacts/harness/runs/*.json`, both ignored (see the evidence-versus-exhaust split in `.gitignore`).

| Artifact | Tracked | Wall-clock field |
|----------|---------|------------------|
| `ledgers/orchestration-only.json` | yes (F4 evidence, `.gitignore` re-includes it) | none |
| `coverage/constitution-coverage.{json,md}` | yes | none |
| `tokens.hash`, `*allowlist*.txt`, `orphan_register.txt`, `goldens/**` | yes | none |
| `ledgers/latest.json`, `runs/*.json`, `dashboard/events.ndjson`, `build-cache/**` | no — exhaust | expected |

---

## Feature drop-in contract

A new feature ships as **data**, not runner changes:

1. **Input script** JSON under `Scripts/harness/scripts/seed/` (schema: `scripts/schema.json`) — event stream, **never recorded coordinates**.
2. **Probe asserts** — declarative `asserts[]` (schema: `probe/schema.json`).
3. **Optional goldens** — `golden/service.py propose` then human `approve` (never auto-bless); keyed by `tokens-hash`.
4. **Optional signpost names** — `trace/acceptance_numbers.json`. Live Swift emitters are not wired yet (`run_live_signposts.py` stays a refusing stub).
5. **Manifest ID** — add the test id to `lanes/manifests.json` (orchestration vs app-coupled).

### Worked example — same-mark clears (v2)

File: `Scripts/harness/scripts/seed/same_mark_clears.json` — schema v2 (`tMs` on every event, no `wait` sleeps).  
FAST runs it through the Python oracle **and** `grammar_oracle_parity` (oracle vs `CullGrammarMachine` mirror).  
FULL on macOS AS runs it through the **live** Swift driver (`run_live_scripts.py`, owned-by-CP4).

---

## Release integrity (F11 — macOS only)

Runs against the **built Release** `Lumina.app`, never Debug. Entry:

```bash
xcodebuild -project Lumina.xcodeproj -target Lumina -configuration Release -arch arm64 build
python3 Scripts/harness/release/f11_hooks_absent.py --app build/Release/Lumina.app
python3 Scripts/harness/release/f11_zero_network.py --app build/Release/Lumina.app
python3 Scripts/harness/release/f11_signature.py --app build/Release/Lumina.app
```

| Check | Script | Pass criterion |
|-------|--------|----------------|
| **F11.1** hooks absent | `f11_hooks_absent.py` | Every harness hook file is `#if DEBUG` fenced; forbidden symbols absent from Release binary (`nm`) |
| **F11.2** zero network | `f11_zero_network.py` | No outgoing-network entitlements; no CFNetwork/Network/NetworkExtension on app binary paths (**app only** — not OS crash reporters; CONFLICT 4 closed / D45) |
| **F11.3** signature | `f11_signature.py` | Developer ID + notarization + **stapled** ticket (`codesign --verify --deep --strict`, `spctl`, `stapler validate`). Signed-but-unstapled **FAIL**. |
| **F11.4** build manifest | `write_build_manifest.py` + `f11_read_manifest.py` | Embeds `LuminaBuildManifest.json` (git sha, tokens hash, fixture manifest version, contract version, build date). Install page / bug reports cite `LuminaBuildManifest.bugReportLine`. |
| **F11.5** shipped rollback | `retain_shipped_artifact.py promote` | Retains `artifacts/release/shipped/previous/Lumina.app` + manifest — rollback is a file copy (D51 / R-I.2). |
| **F11.6** betaDiagnostics null | `f11_a7_expiry.py` | **FAIL** if `betaDiagnostics` is non-null on any wave/beta manifest, or if `BetaDiagnosticsSocket.activeKind` is non-nil (D45/A13). |
| **F11.7** no licensing | `f11_no_licensing.py` | Wave builds: no license/activation/expiry code (D52 / A8; `grammar.beta_licensing: none`). |

Orchestrator (all F11 checks vs Release app): `python3 Scripts/harness/release/run_f11_release.py --app build/Release/Lumina.app`

Fixture manifest version: `design/fixture-manifest.yaml` (`version` field).

Hook inventory: `Scripts/harness/release/hook_inventory.yaml`.

### F11.1 allowlist — `P0AccessibilityID` (ruling 3)

`P0AccessibilityID` and `ProbeSnapshot` **ship in all configurations** by design. They are the product accessibility identifier namespace and the probe JSON schema — not harness hooks. The XCUITest bundle mirrors IDs via `P0AXID`; logic tests assert parity (`LuminaLogicTests`). Release builds must never activate `UITestSupport.isActive` (set only from DEBUG `UITestLaunch`); the identifier strings alone are inert without activation.

Forbidden in Release: probe v2 server, fake clock, fixture synthesis, `--ui-testing` / `--probe-v2` / `--motion-probe` entry points, S19 Develop Lab playground, F07 display-link tap (when implemented).

---

## State Probe v2

- **Schema:** `Scripts/harness/probe/schema.json`
- **Transport:** Swift `StateProbeV2Server` — DEBUG / `--probe-v2`, loopback only
- **Fake clock:** Swift `HarnessFakeClock` — `#if DEBUG` only; never in Release
- **Python simulator:** STUB oracle only (owned-by-CP4)

---

## Token codegen

```bash
python3 Scripts/harness/codegen/tokens_codegen.py
python3 Scripts/harness/codegen/tokens_codegen.py --check
```

### Magic-number gate (derived)

`Scripts/harness/lint/magic_numbers.sh` derives forbidden UI literals at runtime from `DesignTokens/HiFiTokens.generated.swift` (not a hand list). Excluded by rule: `0`, `1`, small array indices (`2`–`9`), hex literals, and the generated file itself. Debt: `artifacts/harness/magic_number_allowlist.txt`.

### Orphan-symbol gate

`Scripts/harness/lint/orphan_symbols.py` — types under `Lumina/Core`, `Lumina/Design`, `Lumina/Views/Components` with no live wiring (only tests / scan-dir peers / own file). Registered debt: `artifacts/harness/orphan_register.txt` (`# owned-by-CP<N>`). **Dead** symbols (zero external references, e.g. `DecisionDock.swift`) are reported separately — W8 deletes.

### Banned-pattern strict scope

Strict lane: `Lumina/Views/P0`, `Lumina/Design`, `Lumina/ViewModels`, `Lumina/Core`, `Lumina/Services`, `Lumina/Persistence`, `Lumina/Testing/ProbeV2`. Legacy lane unchanged (Workspace / Components / Shell).

---

## Seed scripts (5) — schema v2

All seeds use **schemaVersion 2**: monotonic `tMs` on every event (no wall-clock sleeps; `wait`/`waitProbe` omitted in F02.4 replays). Each script ends with **`grammarExact`** — full grammar snapshot assertion.

| id | Law |
|----|-----|
| `held_is_temporary` | D9 / L2 (hold grammar) |
| `same_mark_clears` | D59 |
| `shift_return_return_release` | D60 / D13 |
| `esc_exact_restore` | D11 / D26 |
| `value_echo_adjustment_only` | D24 / D48 |

FAST **`grammar_oracle_parity`** replays all five through `ProbeSimulator` and the Swift-machine mirror (`grammar_machine.py`); divergence prints both readings and FAILs the lane (orchestration only — never an app-coupled PASS).

---

## Latency fixture verification (manual — macOS)

`card-clean-500` / `card-clean-2000` are cut, not committed (5.1 GiB / ~12 GiB physical). They live
in a working directory, so drift is possible and must be checkable.

**Not wired into FAST or FULL.** Re-hashing `card-clean-500` measured **17.3 s** on an M4 Pro
(5.14 GiB of SHA-256); `card-clean-2000` is ~4× that. Both are far over the <1 s lane budget, so per
E1 Gate 2.4 this is a **named manual command**:

```bash
python3 Scripts/fixtures/verify_latency_card.py ~/Pictures/lumina-fixtures/card-clean-500
python3 Scripts/fixtures/verify_latency_card.py ~/Pictures/lumina-fixtures/card-clean-2000
```

Exit 0 = every frame matches `checksums.sha256`. Exit 1 = drift, missing, or unexpected files.
Run before quoting any number against these fixtures.

**Re-cut** (seed must be real RAW; the cutter refuses stubs and synthesized JPEGs):

```bash
python3 Scripts/fixtures/cut_latency_card.py --seed <CARD>/DCIM/100MSDCF --out ~/Pictures/lumina-fixtures --card card-clean-500
python3 Scripts/fixtures/cut_latency_card.py --seed <CARD>/DCIM/100MSDCF --out ~/Pictures/lumina-fixtures --card card-clean-2000 --clone
```

**Decode-floor baseline** (`docs/perf/e1-baseline.md`):

```bash
swift Scripts/perf/e1_decode_baseline.swift ~/Pictures/lumina-fixtures/card-clean-500 --json artifacts/perf/e1-decode-card-clean-500.json
```

---

## Workbench (W0) — the polish loop

Edit a view file, see it on real photographs in about a second. Two targets share one source tree:

| Target | Inject linked | `LUMINA_WORKBENCH` | Purpose |
|---|---|---|---|
| `Lumina` | **no** | never defined | the shipping app; workbench compiles to nothing |
| `LuminaPlayground` | yes (Debug) | Debug only | the polish surface |

Everything workbench sits inside `#if DEBUG`, and the Inject seam additionally inside
`#if LUMINA_WORKBENCH`. Release cannot contain it — the shipping target does not link the
package at all, so this is structural, not a dead-stripping argument. `costume_lint` proves the
`#if DEBUG` half in the tree on every FAST run.

### One-time pairing step (manual — human authorization)

The hot loop needs the injection bundle, which is **not** an SPM dependency and is **not**
fetched at build time. Install it once, by hand:

There is **no Homebrew cask** for it (checked: `brew info --cask injectioniii` → no such cask).
Install from the Mac App Store ("InjectionIII"), or download the signed release directly:

```bash
# InjectionIII.app.zip, latest release (5.2.1RC5 at time of writing)
open https://github.com/johnno1962/InjectionIII/releases/latest
```

Unzip to `/Applications`, launch it, grant it access when macOS asks, and point it at this repo
(`File → Open Project…` → the `vlm_harness` directory). Inject loads
`/Applications/InjectionIII.app/Contents/Resources/macOSInjection.bundle` at runtime; with the app
absent, `.workbenchHot()` is inert and the playground still boots and runs normally — the loop is
simply not hot.

This download is a **developer-tool install, not a build-time fetch**: nothing in `xcodebuild`
reaches for it, and D45's no-egress rule is untouched. The only network access the build itself
performs is the one SPM resolution of `Inject` (pinned `exactVersion 1.6.0`, zero transitive
dependencies).

### Deep-link recipes

Run the playground from Xcode (scheme **LuminaPlayground**, which already carries `--workbench`),
or drive the Debug app directly — the launch-argument parser is DEBUG, not workbench-gated, so
both honor it:

```bash
LUMINA=~/Library/Developer/Xcode/DerivedData/Lumina-*/Build/Products/Debug/Lumina.app
open -a $LUMINA --args --workbench --card card-clean-500                        # table at rest
open -a $LUMINA --args --workbench --card card-clean-500 --row 40 --focused     # focused frame in the table
open -a $LUMINA --args --workbench --card card-clean-500 --surface frame --row 12  # single-photo editor
open -a $LUMINA --args --workbench                                              # restore the last deep-link
```

| Flag | Meaning |
|---|---|
| `--workbench` / `--no-workbench` | force the workbench on/off (defaults **on** in LuminaPlayground) |
| `--card <name>` | latency card under `FIXTURE_ROOT` (default `card-clean-500`) |
| `--row N` | 1-based contact-sheet row to scroll to |
| `--focused` | give the row's first photograph focus |
| `--surface table\|frame\|loupe` | which surface to land on |

`FIXTURE_ROOT` (or `LUMINA_FIXTURE_ROOT`) overrides the fixture location; it defaults to
`~/Pictures/lumina-fixtures`. A missing card is **not** a modal and **not** a crash (D35): the app
stays alive wearing a facts-chip that names the path it tried, with the cut command one click away.

`--surface loupe` parses but **has no referent in P0 today** — "Space loupe" exists only as footer
copy; Space is bound to `toggleSelectionOfFocused`. It lands on the frame and reports itself in the
chip rather than inventing a surface.

### Watching the boot

`open` swallows stderr, so the workbench also writes to the unified log:

```bash
/usr/bin/log stream --predicate 'subsystem == "com.lumina.workbench"' --level debug
```

It reports the resolved card, whether it exists, the applied deep-link, and the
`launch-to-photographs` reading (recorded through the E1 `LatencyMetrics` capture mode, so it
carries a `Window` like every other emitted row).

### Verify

```bash
python3 Scripts/harness/lint/costume_lint.py     # FAST; both clauses
python3 Scripts/harness/run.py fast              # 39 orchestration checks
xcodebuild -project Lumina.xcodeproj -scheme LuminaPlayground -configuration Debug build
```

Release purity — `P0SessionModel` is the control proving `strings` sees Swift type names in a
stripped binary, so the zero counts mean something:

```bash
REL=~/Library/Developer/Xcode/DerivedData/Lumina-*/Build/Products/Release/Lumina.app/Contents/MacOS/Lumina
for s in InjectConfiguration enableInjection WorkbenchLaunch workbenchHot P0SessionModel; do
  echo "$s -> $(strings -a $REL | grep -c $s)"   # all 0 except P0SessionModel
done
```

---

## GAP LIST intake

**Intake source:** `artifacts/harness/coverage/constitution-coverage.md` (and `.json`) — generated by `Scripts/harness/coverage/generate_constitution_coverage.py` from contract D/R headings, `artifact_registry.yaml`, and `shelved_register.yaml`. Every row lists **named artifacts only** (lint id, test name, golden id, script id); `NOT-COVERED` is printed explicitly; shelved register rows read `SHELVED` so an un-shelf shows as a coverage change. Battery column stays empty (F10 gated). Regenerate after registry or contract edits: `python3 Scripts/harness/coverage/generate_constitution_coverage.py --write` then commit; FAST **`constitution_coverage`** runs `--check` on pre-commit.

| Gap | Status | Owner |
|-----|--------|-------|
| `tokens.yaml` → Swift codegen | **Closed in CP0** | CP0 |
| Vacuous-green + platform gates | **Closed in CP0 review** | CP0 |
| Ledger UNMEASURED honesty | **Closed in CP0 review** | CP0 |
| Motion timing *measured* gate | STUB / UNMEASURED until live signposts | **SPIKE A** |
| F07.4 dead-stop exact (orchestration) | **Closed — SPIKE B seal** (`spring_physics_f07`) | **SPIKE B** |
| F07.5 retarget continuity | **Closed — SPIKE B seal** | **SPIKE B** |
| F07.6 reduced-motion variant | **Closed — SPIKE B seal** | **SPIKE B** |
| Spring trajectory golden (tokens-hash) | **Closed — SPIKE B seal** | **SPIKE B** |
| Grammar scripts *live* | STUB oracle only | **CP4** |
| Golden service bookkeeping | **Closed in CP0** | CP0 |
| Chrome/photo golden *pixels* | STUB `--live` | **CP1** / bodies **CP3** |
| A5 banner spacing drift | Registered | **CP5/CP7** |
| P0OpenView `.alert` | Registered | **CP8** |
| Hover handlers (legacy shell) | Registered | **CP5** |
| ProgressView legacy | Registered | **CP4** |
| Six-body fixtures | Registered | **CP3** |
| Taste-model proof harness | Registered | **D46 / A10** (post wave-one) |
| A7 TestFlight strip | Registered | **1.0** |
| A8 / R-I.3 licensing | Registered | post-test, pre-launch |
| W0 live-injection proof (edit→pixels) | **UNVERIFIED** — InjectionIII.app not installed | **W0 follow-up** |
| LuminaPlayground bundle: no window when launch args present | Registered — boot verified via `Lumina` Debug instead | **W0 follow-up** |
| Costume debt (9 rows, ratcheted) | Registered — `costume_allowlist.txt` | **polish thread** |
| W0 deep-link parser unit tests | Not written — W0 write-set was closed | **W0 follow-up** |
| HEAVY live runners | STUB `run_job.py` | **HEAVY** |
| Grammar-stability live corpus | STUB until CP4 driver | **D51 / HEAVY** |
