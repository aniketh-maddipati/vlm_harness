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

Each lane declares `budgetMs` in `Scripts/harness/lanes/manifests.json`. **Total lane elapsed time above the ceiling is a lane FAIL** — not a warning. On breach the runner prints the slowest manifest test ids by measured ms (descending), then the sentence **delete or demote**. Ceilings: FAST **90000** ms (<90s) · FULL **600000** ms (<10min) · HEAVY **3600000** ms (nightly budget).

---

## Allowlist ratchet

FAST manifest id `allowlist_ratchet` fails pre-commit if `artifacts/harness/banned_patterns_allowlist.txt` or `artifacts/harness/magic_number_allowlist.txt` carries **more** debt lines (non-blank, non-`#`) than the same file on `origin/main`. Allowlists may shrink; they must not grow without a deliberate baseline change on main.

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

Swift already in-tree (DEBUG only): `Lumina/Testing/ProbeV2/{StateProbeV2,HarnessFakeClock,AcceptanceSignposts}.swift`.

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
| HEAVY job bodies | `Scripts/harness/heavy/run_job.py` | **HEAVY** |

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
| **FAST** | <90s | save/commit / `watch` | orchestration only: token/copy/banned/magic lints, contract lints, unit tests, seed **schema** + grammar **oracle** (STUB) |
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

## Feature drop-in contract

A new feature ships as **data**, not runner changes:

1. **Input script** JSON under `Scripts/harness/scripts/seed/` (schema: `scripts/schema.json`) — event stream, **never recorded coordinates**.
2. **Probe asserts** — declarative `asserts[]` (schema: `probe/schema.json`).
3. **Optional goldens** — `golden/service.py propose` then human `approve` (never auto-bless); keyed by `tokens-hash`.
4. **Optional signpost names** — `trace/acceptance_numbers.json` + Swift `AcceptanceSignposts`.
5. **Manifest ID** — add the test id to `lanes/manifests.json` (orchestration vs app-coupled).

### Worked example — P/X advance

File: `Scripts/harness/scripts/seed/px_advance.json` — see seed file.  
FAST runs it through the **STUB** Python oracle (orchestration).  
FULL on macOS AS runs it through the **live** Swift driver (`run_live_scripts.py`, owned-by-CP4).

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

---

## Seed scripts (5)

| id | Law |
|----|-----|
| `px_advance` | D10 / D59 |
| `same_mark_clears` | D59 |
| `shift_return_return_release` | D60 / D13 |
| `esc_exact_restore` | L5 / D11 |
| `arming_consent` | D24 / D48 |

---

## GAP LIST intake

**Intake source:** `artifacts/harness/coverage/constitution-coverage.md` (and `.json`) — generated by `Scripts/harness/coverage/generate_constitution_coverage.py` from contract D/R headings, `artifact_registry.yaml`, and `shelved_register.yaml`. Every row lists **named artifacts only** (lint id, test name, golden id, script id); `NOT-COVERED` is printed explicitly; shelved register rows read `SHELVED` so an un-shelf shows as a coverage change. Battery column stays empty (F10 gated). Regenerate after registry or contract edits: `python3 Scripts/harness/coverage/generate_constitution_coverage.py --write` then commit; FAST **`constitution_coverage`** runs `--check` on pre-commit.

| Gap | Status | Owner |
|-----|--------|-------|
| `tokens.yaml` → Swift codegen | **Closed in CP0** | CP0 |
| Vacuous-green + platform gates | **Closed in CP0 review** | CP0 |
| Ledger UNMEASURED honesty | **Closed in CP0 review** | CP0 |
| Motion timing *measured* gate | STUB / UNMEASURED until live signposts | **SPIKE A** |
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
| HEAVY live runners | STUB `run_job.py` | **HEAVY** |
| Grammar-stability live corpus | STUB until CP4 driver | **D51 / HEAVY** |
