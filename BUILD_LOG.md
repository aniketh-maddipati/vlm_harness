# Lumina Build Log

One line per session: claim → finding → fix → instrument reading. Read this at the start of every Composer session.

---

## 2026-08-14 — C3 fast-idempotence: a no-op run leaves the tree clean

**Branch:** `cursor/c3-fast-idempotence-b243` · **Base:** `origin/main` @ `f2e9ee3`
**Claim:** A no-op run of any lane leaves the tree clean, and the tracked F4 ledger still moves when its result moves. **37** FAST orchestration checks before and after — this session changes no verdicts.

**Finding (the session's premise did not resolve):** `run.py fast` was **already** idempotent. Measured with the prompt's own sequence: `git status --porcelain` → empty, `run.py fast` → PASS, `git status --porcelain` → empty, `git diff <ledger>` → empty. The churn came from **FULL and HEAVY**, which call `_write_orchestration_ledger()` at `run.py:192` and `run.py:333` — the second on the PLATFORM-UNAVAILABLE path, so a Linux host that cannot run the lane still rewrites the tracked ledger.

**Finding (the class has two members, not one):** of **14** tracked artifacts under `artifacts/harness/`, exactly **2** carried a wall-clock field — `ledgers/orchestration-only.json` (`generated_at`, rewritten by FULL/HEAVY) and `coverage/constitution-coverage.json` (`generated_at`, rewritten by `--write`). The other 12 — allowlists, orphan register, `tokens.hash`, goldens, and `constitution-coverage.md` — are already content-only. `ledgers/latest.json` is untracked exhaust (`.gitignore:36`).

**Finding (nothing read the field):** `generated_at` is written in 4 places and read in **0**. `generate_constitution_coverage.py:262` compares `entries` and `summary` only — the check already excluded the field it was diffing on.

**Disposition — EVIDENCE, not exhaust:** the `.gitignore` re-inclusion is deliberate and documented. `git log -S'!artifacts/harness/ledgers/orchestration-only.json' -- .gitignore` → **`8dacec5` "CP0: harness upgrade (#32)"**, whose body states *"F4: orchestration ledger records acceptance numbers as UNMEASURED"*, codified in HARNESS.md "Numbers ledger honesty (F4)". Ignoring the file would have overridden a documented reason — a STOP condition — so it is made **content-addressed** instead.

**Fix:** drop `generated_at` from `orchestration_ledger()` and from the coverage payload; regenerate both tracked artifacts; delete the now-unused `datetime` import. `evaluate()` keeps its timestamp — its default destination is `ledgers/latest.json`, ignored run exhaust, where a per-run wall clock belongs. HARNESS.md gains a **Run idempotence** section with the evidence-versus-exhaust table so a dirty tree after a run reads as a harness bug, not as normal.

**Instrument reading (Linux — all executed this session):**

| Command | Result |
|---------|--------|
| `git status --porcelain` (arrival) | empty — clean |
| `python3 Scripts/harness/run.py fast` | **PASS** · **37** orchestration · 0 app tests / 0 expected |
| three-run FAST sequence (`status` → `fast` → `status` → `fast` → `status`) | every `status` **empty** |
| `run.py full` ×3, `run.py heavy` ×1 (the former churners) | **CLEAN** after every run |
| `generate_constitution_coverage.py --write` (no-op) | **CLEAN** |
| `python3 Scripts/harness/lint/allowlist_ratchet.py` | **OK** |
| `Scripts/harness/trace/test_trace_parse.py` | **OK** — 3 tests |
| `generate_constitution_coverage.py --check` | **OK** |
| ledger-moves probe: `acceptance_numbers.json` notes edited → regenerate | ledger diff shows the changed note; revert → byte-identical |
| coverage-moves probe: lint id added to `D8` in `artifact_registry.yaml` → `--write` | `.json` and `.md` both show `c3_idempotence_probe`; revert → byte-identical |
| `xcodebuild` | not required — this session touches no Swift |

**Lines:** +26 / −6 across 5 files; of that, harness code +11 / −4 and the two tracked artifacts −1 line each (the timestamp).

---

## 2026-08-13 — W8 legacy-severance: sever live root from legacy shell

**Branch:** `cursor/w8-legacy-severance-39dd`  
**Claim:** Stop constructing `ProjectViewModel` / `LuminaShellModel` on every launch; delete measured-dead code; disposition register for all surviving legacy files (D38 / D40).

**D38 / D40 (grep verified):**

| Ruling | Location | Substance |
|--------|----------|-----------|
| **D38** | `design/contract-v6.md` L328 | Shelved Register — **doors, not deletions** |
| **D40** | `design/contract-v6.md` L125–131 | Legacy quarantined; checkpoint-by-checkpoint retirement via `design/checkpoint-sequence-v6.md` |
| **CP4** | checkpoint-sequence L32 | Retires legacy cull checkpoint — does **not** authorize deleting CP7 propagation surfaces |

**Severance:**

- `P0RootView` — removed eager `@State` legacy models; legacy behind `P0LegacyShellContainer` (`P0LegacyShellDoor.swift`) with lazy construction on first door open.
- **Deleted** `DecisionDock` — **0** external references (incl. tests); hover handler removed (D48). Button styles moved to `Lumina/Views/LuminaButtons.swift`.
- **Disposition register:** `design/strategy/legacy-disposition.md` — every surviving legacy file tagged PORT-TO-P0 / DELETE-AT / KEEP with owning checkpoint.

**Reachability (method: `Scripts/harness/lint/swift_reachability.py`; legacy-only = inventory files with zero P0 type-name refs excl. `P0RootView`):**

| Metric | Before | After |
|--------|-------:|------:|
| Total Swift files (`Lumina/**/*.swift`) | **152** | **151** |
| Total Swift lines | **35,120** | **35,064** |
| From `LuminaApp` (symbol BFS) files / lines | 127 / 30,245* | 127 / 30,189 |
| Legacy-only inventory files / lines | **31 / 10,230** | **27 / 7,100** |

\*Before `from_lumina_app` estimated via same BFS on pre-change tree (legacy models held alive in `P0RootView` `@State`).

After severance, `P0LegacyShellDoor.swift` references `ProjectViewModel`, `LuminaShellModel`, `LuminaShellView`, and `ImportLoadingView` — four files leave the legacy-only set; **CP7 propagation surfaces untouched** (ContinuousWorkspaceView, TreatmentFamilyRow, TreatmentStageView, DockedAdaptChipView, TableRubberBandOverlay, WorkbenchSelection).

**Probe:** added `legacyShellActive` to `ProbeSnapshot` (app + UI test + logic round-trip) for door state under harness only.

**Instrument reading (Linux):**

| Command | Result |
|---------|--------|
| `python3 Scripts/harness/run.py fast` | measured at merge |
| `python3 Scripts/harness/lint/swift_reachability.py --json` | after row above |
| `xcodebuild … build` | **PLATFORM-UNAVAILABLE** (Linux cloud VM) |
| `xcodebuild … LuminaLogicTests` | **PLATFORM-UNAVAILABLE** (Linux cloud VM) |
| `python3 Scripts/harness/run.py full` | **PLATFORM-UNAVAILABLE** partial (no macOS app tests) |

**Live-path behavior:** unchanged on default launch — Open / contact sheet / grouping / edit routes identical; legacy door still via “Legacy shell” on Open surface.

**P8.2 cascade instrument (2026-08-13):** re-run in `design/strategy/surface-sweep.md` §6 — **cascade NOT FINISHED** on `main`; 2/9 rows pass only on isolated W tips; row 3 (persistence roots) unowned by W1–W8.

---

## 2026-08-13 — W6 memory-budget: RAM gate + byte-budgeted caches

**Branch:** `cursor/w6-memory-budget-39dd`  
**Claim:** Build HEAVY RAM tier gate; measure peak RSS; byte-budget `PhotoImageCache`; bound prefetch; autoreleasepool on decode; shared CIContext.

**Ceilings (proposal awaiting contract ruling — not in tokens.yaml):**

| Tier | Bytes |
|------|------:|
| grid @512 | 48 MiB |
| preview @1600 | 96 MiB |
| proxy / unbounded | 128 MiB |
| total LRU table | 256 MiB |
| prefetch width | 8 concurrent |

**Instrument reading (Linux):**

| Command | Result |
|---------|--------|
| `python3 Scripts/harness/run.py fast` | **PASS** 6864ms · 33/33 |
| `python3 Scripts/harness/heavy/run_job.py ram_tier_runs` | **PLATFORM-UNAVAILABLE** exit 2 (Linux) |
| `xcodebuild … LuminaLogicTests` | **PLATFORM-UNAVAILABLE** (Linux cloud VM) |

**Baseline / after (bytes):** macOS `--ram-harness` required — ledger writes to `artifacts/harness/ledgers/ram-tiers.json`. Linux cannot measure; gate script refuses vacuous PASS.

**Latency:** scrub p50 14.5 ms / p95 16.6 ms, settle 191 ms unchanged on Linux (no macOS re-measure this session).

---

## 2026-08-13 — W5 key-routing: one owner and one Esc ladder

**Branch:** `cursor/w5-key-routing-39dd`  
**Claim:** Single P0 live-path keyboard owner; unified Esc ladder; decision keys swallow autorepeat at owner; legacy `CommandHandlingModifier` header corrected.

**Owner:** `P0KeyRoutingModifier` — `addLocalMonitorForEvents` L56–61 · `removeMonitor` L71 · detach L65–67 / L195–197.

**P0EditSlider:** inline `NSEvent.modifierFlags` poll during drag is pointer-local ⌥ fine-adjust — not key routing.

**Pointer parity gaps (rulings needed):** shift-click range select.

**Instrument reading (Linux):**

| Command | Result |
|---------|--------|
| `python3 Scripts/harness/run.py fast` | measured at merge |
| Seed scripts | unchanged |
| `xcodebuild … LuminaLogicTests` | **PLATFORM-UNAVAILABLE** (Linux cloud VM) |

**Live path wired:** `P0RootView.p0KeyRouting(session:)` owns all P0 keys; contact sheet `.onKeyPress` handlers removed. Probe adds `keyRoutingOwner`.

---

## 2026-08-13 — W4 motion-wiring: live path through sealed spring

**Branch:** `cursor/w4-motion-wiring-39dd` · **Base:** `cursor/w1-gate-truth-39dd` @ `8ef67e6`  
**Claim:** Route live-path motion through `LuminaSpring` / `LuminaSpringAnimation`; every `durationMs:` literal on the live path becomes a token read; D27 reduced-motion at wired sites; legacy literals registered as W8 debt. Do not tune spring parameters.

**Judged:** 2026-08-13 (W4 motion-wiring — measured this session).

**TOKEN OWED (interim ms preserved from hand-typed call sites):** `photo_focus` 280 · `route_transition` 240 · `selection_ring` 320 · `develop_reveal` 550 · `fidelity_settle` 220 — version `6.3-motion-wiring`.

**tokens-hash:** `1b1db60f4b927c6ba29f320508ebfe2f427a0eb1d6acef7f64051edff7b7158c` — golden trajectory payload unchanged vs `6.2-motion-seal` hash `666762f7…`.

**Instrument reading (Linux):**

| Command | Result |
|---------|--------|
| `python3 Scripts/harness/codegen/tokens_codegen.py --check` | **PASS** |
| `bash Scripts/harness/lint/magic_numbers.sh` | **PASS** — 95 token literals derived; +32 W8 legacy allowlist rows |
| `python3 Scripts/harness/lint/orphan_symbols.py` | **PASS** — 25 orphans registered; `LuminaSpring*` wired via bridge |
| `python3 Scripts/harness/run.py fast` | measured at merge |
| `test_f07_spring_physics.py` | **PASS** — golden keyed by new hash |
| `xcodebuild … LuminaLogicTests` | **PLATFORM-UNAVAILABLE** (Linux cloud VM) |

**Live path wired:** `P0SinglePhotoEditor` · `P0ContactSheetView` · `P0AdjustmentRail` → `LuminaSpringAnimation.transform` + `HiFiTokens.Motion.*Ms`. Probe adds `reduceMotionActive` (D27).

**Legacy debt (W8):** `artifacts/harness/motion_legacy_allowlist.txt` + 32 magic-number allowlist rows for legacy shell / Workspace / Shell paths.

---

## 2026-08-13 — W3 cull-grammar: ADOPT CullGrammarMachine on P0 live path

**Ruling:** **ADOPT** — `P0SessionModel` routes every cull mark through `CullGrammarMachine`; session owns presentation/persistence only; machine is what the app runs and joins the oracle↔machine parity triangle.

**Branch:** `cursor/w3-cull-grammar-39dd` · **Base:** prior W3 work @ `cdd4f35`  
**Claim:** End dual implementation — headless machine had zero product call sites; P0 duplicated toggle/advance independently.

**Fix:** `applyCullGrammarEvent` installs machine from visible grid, applies `CullGrammarEvent`, syncs marks/focus/order/undo/journal. Pointer targets call `pointerMarkKeep`/`pointerMarkReject` (D47/A3). Single-photo scale suppresses advance after mark. Tests: pointer parity, edit-never-decides.

**Instrument reading:**

| Command | Result |
|---------|--------|
| `grep '### D10' design/contract-v6.md` | **1 hit** — decision keys |
| `grep '### D59' design/contract-v6.md` | **1 hit** — same-mark clears |
| `grep 'D47' design/contract-v6.md` | **A3** pointer cull |
| `python3 Scripts/harness/run.py fast` | measured at merge |
| `xcodebuild … -only-testing:LuminaLogicTests test` | **PLATFORM-UNAVAILABLE** (Linux) |

---

## 2026-08-13 — W3 / CP4: P0 cull advance + pointer marks (D10/D47/A3)

**Branch:** `cursor/w3-cp4-p0-cull-39dd`  
**Claim:** Close W3 cull-machine gaps on the P0 live path — focus advances after keep/reject; D47/A3 pointer ✓/✕ targets on the focused frame only.

**Fix:** `advanceFocusAfterCullMark` after non-undecided marks (D59 same-mark clear stays put). `PointerCullMarkControl` on focused cell only — 44 pt hit (`HiFiTokens.Grammar.pointerCullMarkMinHit`), ✓/P and ✕/X, mouseDown decides (no hover handlers). Probe field `pointerCullTargetsVisible` for F03.1 growth gate.

**Instrument reading (Linux — measured this session):**

| Command | Result |
|---------|--------|
| `grep 'D10' design/contract-v5.md` | **1 hit** (line 97) |
| `grep '### D47' design/contract-v6.md` | **1 hit** — `[● A3]` |
| `grep '### D59' design/contract-v6.md` | **1 hit** |
| `python3 Scripts/harness/run.py fast` | **PASS** at branch tip |
| `xcodebuild … -only-testing:LuminaLogicTests test` | **PLATFORM-UNAVAILABLE** (Linux cloud VM) |

---

## 2026-08-13 — W1 gate-truth: constitutional enforcement widened

**Branch:** `cursor/w1-gate-truth-39dd` · **Base:** `origin/main` @ `83ba118`  
**Claim:** Harness gates read as spot checks — widen banned-pattern strict scope, derive magic numbers from generated tokens, add orphan-symbol gate, stop HEAVY RAM stub reading as covered. Register every hit; do not fix product code.

**Judged:** 2026-08-13 (W1 gate-truth — measured this session).

**Debt delta (exact counts):** orphans found **28** · new magic-number hits **240** · new banned-pattern hits **0**

**Instrument reading (Linux):**

| Command | Result |
|---------|--------|
| `python3 Scripts/harness/run.py fast` | **INCOMPLETE** 12057ms · orchestration **33/34** · `allowlist_ratchet` FAIL (debt vs `origin/main` — expected until merge) |
| `bash Scripts/harness/lint/magic_numbers.sh` | **PASS** — 80 token literals derived |
| `bash Scripts/harness/lint/banned_patterns.sh` | **PASS** — strict scope widened; legacy lane unchanged |
| `python3 Scripts/harness/lint/orphan_symbols.py` | **PASS** — 28 orphans registered, 2 dead (`DecisionDock`) |
| `python3 Scripts/harness/lint/allowlist_ratchet.py` | **FAIL** — magic 243 > 3, orphan 28 > 0 |

**Follow-ups:** W4/`P7` wires `LuminaSpring` · W7 wires `RecoveryFactsChip` · W8 deletes `DecisionDock` · W6 builds `ram_tiers.sh`.

---

**Instrument reading (Linux):**

## 2026-08-13 — F11.6 Batch 2 follow-up: betaDiagnostics null assertion (D45/A13)

**Branch:** `cursor/f11-6-beta-diagnostics-null-39dd`  
**Claim:** Close Batch 2 F11.6 follow-up — harness asserts `betaDiagnostics` is null on every wave/beta build, not an A7 expiry gate at marketing 1.0.

**Finding:** `f11_a7_expiry.py` only FAILed when `marketingVersion >= 1.0` with non-null `betaDiagnostics`; wave builds at 0.x could still embed a TestFlight reporter socket. `BetaDiagnosticsSocket.swift` and `HARNESS.md` still cited withdrawn A7 / TestFlight semantics. Contract D45 `[● A13]` (verified `grep '### D45' design/contract-v6.md`) requires null assertion on all wave/beta builds.

**Fix:** `check_manifest` now FAILs on any non-null `betaDiagnostics` or non-nil `BetaDiagnosticsSocket.activeKind`; updated socket comments, manifest writer cite, HARNESS F11.6/F11.2 rows, manifest id notes; added unit test for 0.1.0 + non-null FAIL.

**Instrument reading (Linux — measured this session):**

| Command | Result |
|---------|--------|
| `grep '### D45' design/contract-v6.md` | **1 hit** — D45 present with `[● A13]` |
| `python3 Scripts/harness/tests/test_f11_release.py` | **PASS** — 5/5 tests |
| `python3 Scripts/harness/release/f11_a7_expiry.py` | **PASS** — `betaDiagnostics: null`, marketing 0.1.0 |
| `python3 Scripts/harness/run.py fast` | **PASS** 6692ms · orchestration **33/33** · `f11_a7_expiry` OK |
| `xcodebuild` | **PLATFORM-UNAVAILABLE** (Linux cloud VM) |

**Follow-up (not this session):** F11.3 staple `.app` on macOS ship host; install-page Batch 2 ITEM 4 operator choice.

---

## 2026-08-13 — P8 operator ruling: wave sequencing (P7 / R3 / P5)

**Branch:** `strategy/p8-surface-sweep`  
**Claim:** Record operator invariants true regardless of P8 measurement — appended to `design/strategy/surface-sweep.md` §5.

**Ruling (verbatim substance):**

1. **P7 moves `tokensHash`** — any DMG cut before P7 embeds stale **`tokensHash`** and **`contractVersion`** in `LuminaBuildManifest.json` (`write_build_manifest.py`). **Re-run R3 before Wave 0.**
2. **Wave 1 gated on P5** — CP2 session where D36 “nothing you did is ever lost” becomes a **test result**, not a claim (`ShootStore` → `shoot.json` violation live on `a076644`).

**Session map:** P7 = SPIKE B seal · R3 = `run_f11_release.py` + manifest embed + promote · P5 = CP2 · Wave 0 = first ship cut · Wave 1 = second wave (P5 gate).

**Instrument reading:** No new commands — ruling is operator-authored; P8 Linux FAST (`a076644`) already shows pre-P7 manifest/hash drift.

---

## 2026-08-13 — P8 surface sweep: existence matrix + checkpoint evidence

**Branch:** `strategy/p8-surface-sweep` · **Base:** `origin/main` @ `a076644`  
**Claim:** Measure-only strategy session — existence matrix (D/R), checkpoint landing (SPIKE A/B, CP1–CP8), sealed vs tuned surfaces, wave-worthy remainder. No code.

**Judged:** 2026-08-13 (P8.1 surface sweep).

**Deliverable:** `design/strategy/surface-sweep.md`

**Instrument reading (Linux — measured this session):**

| Command | Result |
|---------|--------|
| `git rev-parse --short HEAD` | `a076644` |
| `python3 Scripts/harness/run.py fast` | **INCOMPLETE** 5126ms · orchestration **26/27** · FAIL: `banned_patterns`, `contract_v6_presence`, `spring_physics_f07`, `constitution_coverage` |
| `test -f Lumina/Design/LuminaSpring.swift` | **NO** (SPIKE B not on main) |
| `test -f Scripts/harness/tests/test_f07_spring_physics.py` | **NO** |
| `cat artifacts/harness/tokens.hash` | `c8f75e1a3733ee3209699deb0c2d418318a1b65ca47e46507a88929822c9c9a7` (version `6.2-batch2`) |

**Findings (corroborated in tree, not BUILD_LOG alone):**

- Live path: `LuminaApp` → `P0RootView`; legacy shell via `showLegacyShell`.
- CP2 **NOT STARTED:** `ShootStore.saveShoot` → catalog `shoot.json` (D36 violation).
- SPIKE B on main **NOT STARTED**; unmerged `spike/b-motion` @ `cf583f8` has F07 green — not landed.
- Wave-worthy on main: **NO** — macOS automation UNMEASURED, harness red, P0 vs legacy split, Batch 3 unratified.

**Follow-ups recorded in doc:** merge SPIKE B, CP2, Batch 3 ruling, macOS diagnostic — see `design/strategy/surface-sweep.md` §4.
---

## 2026-08-13 — F07 / SPIKE B: motion seal landed (F07.4–F07.6 green)

**Branch:** `spike/b-motion`  
**Claim:** Paste motion-probe export into `design/tokens.yaml` §motion, bump version, codegen + magic-number gate; activate F07.4 / F07.5 / F07.6 against sealed params; golden trajectory keyed by `tokens-hash`; close SPIKE B STUB rows in `HARNESS.md`.

**Judged:** 2026-08-13 (SPIKE B motion physics seal — measured this session).

**Sealed params verbatim (`design/tokens.yaml` §motion, version `6.2-motion-seal`):**

```yaml
  chrome_fade_out:
    value: 250
    unit: ms
    type: ms
  place_return:
    value: 200
    unit: ms
    type: ms
  spring_max_overshoot:
    value: 0.02
    type: opacity
  spring_trajectory_frames:
    value: 40
    type: enum
  spring_trajectory_sample_rate_hz:
    value: 120
    type: enum
  spring_dead_stop_epsilon:
    value: 0.001
    type: opacity
  spring_retarget_continuity_epsilon:
    value: 0.000001
    type: opacity
  spring_reduced_motion_overshoot:
    value: 0
    type: opacity
  travel:
    value: 180
    unit: ms
  stage:
    value: 140
    unit: ms
  lift:
    value: 100
    unit: ms
```

**tokens-hash:** `666762f75cbf7b3a3302b044e89c68641fabd852a911039afc52d1067f557f89`

**Fix:** `LuminaSpring` + Python mirror read sealed tokens only; `HiFiTokens.Motion.*Ms` consumed in `LuminaTokens.Motion` for sealed durations; FAST id `spring_physics_f07`; golden `spring_trajectory_place_return` approved under tokens-hash `666762f75cbf…`.

**Instrument reading (Linux — measured this session):**

| Step | Status |
|------|--------|
| `tokens_codegen.py --check` | **PASS** |
| `spring_physics_f07` (F07.4 dead-stop) | **PASS** (`\|value − 1\| = 0.000452` ≤ ε `0.001` at horizon `0.325s`) |
| F07.5 retarget continuity | **PASS** |
| F07.6 reduced-motion overshoot | **PASS** |
| Trajectory golden | **PASS** (40 samples @ 120Hz) |

**Stale artifacts:** Any build keyed to prior `tokens-hash` (`6.2-batch2` / `7b0c1552…`) — F11.4 manifest, F04.1 build cache, chrome goldens under old hash — require re-measure.
---

## 2026-08-13 — One-off queue recorded (post-cascade)

**Branch:** `main` @ `228175c`

**Claim:** Operator one-off queue after wrap-up cascade — macOS automation diagnostic → CP2 → SPIKE B (S18/S19/seal/S20) → D67 after W3 proposal.

**Finding:** RESUME §6 listed Batch 3 first; operator re-ordered: automation diagnostic (failed twice, gates F04/F07/F11/all flows) before any build session; SPIKE B before artifact hardening because `tokensHash` moves; D67 ratification sequenced after W3 proposal review.

**Fix:** RESUME.md §6 → ONE-OFF QUEUE (four items); §3 next action → automation diagnostic; §7 subordinate “would do next”.

**Instrument reading:** No new macOS run this session — queue is operator-authored, not measured here.

---

## 2026-08-13 — Wrap-up cascade: RESUME + W4 strategy branches (inventory close)

**Branch:** `main` @ `6652c65` · **Worktrees (untracked locally):** `lumina-wt/` → `constitution/batch-3-propagation`, `strategy/s1-mvp-sharpening`

**Claim:** Close W1 inventory / W2 audit / W4 MVP-sharpening cascade with a measured resume note at repo root; no aspirational statements.

**Finding:** Integration tip carries CP7 propagation + P0 editing but FAST pre-commit red on Linux; Batch 3 and S1 strategy docs exist only on unpushed-to-main branches; CONFLICT 2 / macOS FULL / SPIKE B seal / D67 ratification / CP2 chain remain open.

**Fix:** Added `RESUME.md` (six sections: stand, open gates, critical path, do-not-touch, playground rules, next three actions). W4 matrices remain on `strategy/s1-mvp-sharpening`; Batch 3 proposal on `constitution/batch-3-propagation`.

**Instrument reading (Linux — measured this session):**

| Step | Result |
|------|--------|
| `git status` (tracked) | clean @ `6652c65`; untracked `lumina-wt/` only |
| `bash Scripts/regression.sh pre-commit` | **FAIL exit 1** · FAST **INCOMPLETE** ~5050ms · **26/27** orchestration |
| Fail ids | `banned_patterns` (D48 hover `P0SinglePhotoEditor.swift:356`) · `contract_v6_presence` · `spring_physics_f07` (missing `test_f07_spring_physics.py`) · `constitution_coverage` (stale) |
| Open PRs (stale) | #36–#39 F0–F03 — superseded by main; operator close blocked (integration permission) |
| W4 source | `design/strategy/s1-mvp-sharpening.md` @ `ce677f6` — **not on main** |

**Routing:** Operator → Batch 3 ITEM 1 ruling · macOS AS pre-merge FULL measurement · FAST red cleanup before next merge.

---

## 2026-08-12 — Auditor: human-led intent propagation branch (OUTSIDE PROTOCOL)

**Branch:** `human-led-edit-propagation` (worktree `conductor/.../dhaka`) · **Merge-base:** `120c004c903630279c69a2d735a890a4c28831e0` (`origin/main`, Batch 2 proposal #42) · **Tip:** same commit; **~994 LOC uncommitted** working-tree diff only.

**Claim audited:** Photographer-authored Develop change → editable intent group → per-recipient adaptation → Return-release commit; BUILD_LOG asserts 102/102 logic, 29/29 FAST, 31/31 regression, honest live-driver stub ledger.

**Verdict:** **NEVER MERGE.** Auditable material only. Three independent kill classes: (1) **provenance** — build session authored **D67** + Shelved Register rewrite in `design/contract-v6.md` without constitution session; (2) **protocol** — CP7 hero work on ad-hoc branch/worktree with no owning checkpoint session; (3) **law** — cross-row hand selection (`TablePhotographSelection`, gather, rubber-band replace, ⇧-extend) still ships under intent/new names while D17/D29/D38 shelved register on ratified v6 says otherwise; ⇧⏎ ring widen (row→scene→shoot) ships wholesale ripple without ratified un-shelf.

**Instrument reading (auditor re-run):** Logic **102/102 PASS** · FAST **29/29 PASS** (but `spring_physics_f07` demoted from manifest — SPIKE B seal weakened; HARNESS.md honestly re-marked OPEN) · `pre-commit` regression **PASS** (dashboard log write blocked sandbox; exit 0). UI automation timeout (XCTest 1000) and seven live-driver stubs match builder ledger.

**Routing:** Cherry-pick carries under **CP7** after constitution session (if any): Return-release gate, Esc ring narrow, `BatchEditCommand` atomic undo, `IntentBoundaryCorrection` (D33), `LocalIntentPropagationEngine` adaptation math, VoiceOver include/exclude actions, `EditRailLayout` +1 pt tolerance, develop double-apply test. **CUT:** D67 file edits, contract self-ratification, cross-row selection paths, identical `⌘⇧A` set apply, scene-ring banner string absent from copy-contract, FAST demotion without ruling.

**Proceed:** Do not merge branch. Strip D67 from any tree. If hero semantics are wanted, open constitution session for CP7 scope (intent shaping vs D17 row law) then re-implement inside a single CP7 checkpoint session from merge-base.

---

## 2026-08-12 — Batch 2 ratification: distribution & diagnostics (A11–A13)

**Branch:** `constitution/batch-2-distribution` · **PR:** draft — Batch 2 apply  
**Claim:** Apply ratified Batch 2 items only — CONFLICT 4 closure, D66 beta channel, A7 withdrawal; bump tokens; record declined ITEM 4.

**Ratified:**

| Item | Amendment | Applied |
|------|-----------|---------|
| ITEM 1 — CONFLICT 4 option 2 (notarized Developer ID beta) | **A11** / **R-I.4** | `design/build-prompts/INDEX.md` §CONFLICTS; contract Batch 2 header |
| ITEM 2 — D66 beta channel | **A12** | `design/contract-v6.md` D66 |
| ITEM 3 — A7 withdrawal / D45 restore | **A13** | `design/contract-v6.md` D45; scoped-weakening note; A7 visible as withdrawn |

**Declined / deferred:**

| Item | Status |
|------|--------|
| ITEM 4 — install-page copy scope (a / b / c) | **NOT RATIFIED** — no operator choice; no copy home created |

**Instrument readings:**

| Step | Result |
|------|--------|
| `design/tokens.yaml` version | **`6.2-batch2`** (was `6.1-batch1`) |
| `python3 Scripts/harness/codegen/tokens_codegen.py --check` | **PASS** (`tokens-hash=c8f75e1a3733…`) |

**Follow-ups (listed, not built this session):**

- **Install-page spec** — drop dangling `MACOS_RELEASE_READINESS_AUDIT.md` citation; anchor on A11 / D66; add `nothing leaves this Mac` (A13 makes it truthful of wave builds).
- **F11.6** — becomes `betaDiagnostics`-null assertion (F11 branch).
- **F11.3** — must staple the `.app` inside the artifact; a zip cannot carry a ticket; a DMG can.
- **Pre-ratification artifacts** — every build before `6.2-batch2` embeds stale `contractVersion` in F11.4 manifest.
- **ITEM 4** — operator chooses (a) copy-contract distribution section, (b) sibling file, or (c) outside contract.
- **tokens.yaml** — `beta_testflight_crash_reporting` socket stale vs A13; clean on follow-up pass.
- **mvp-test-plan.md** — consent line still cites “D45 / A7”; update on copy pass.
- **Do not merge** contract branch until operator says merge.

---

## 2026-08-12 — F11: release integrity (F11.1–F11.7)

**Branch:** `feature/f11-release-integrity`  
**Claim:** Release-integrity gates — DEBUG hooks absent, zero network, signature, embedded build manifest, shipped rollback retention, A7 expiry, no licensing (D45/A7, D52/A8, D51/R-I.2).

**Embedded manifest (F11.4)** — `Lumina/Resources/LuminaBuildManifest.json` via Xcode Run Script + `write_build_manifest.py`:

```json
{
  "gitSha": "11b9ec4e8c8544439f6cdd260baf01bd91034362",
  "tokensHash": "7b0c1552736eba4c253d4f32bd81f35691f8b4c0ff238e602054729c50e36b36",
  "fixtureManifestVersion": "1.0-mvp-fleet",
  "contractVersion": "6.2-motion-seal",
  "buildDate": "2026-08-12T15:35:36Z",
  "marketingVersion": "0.1.0",
  "betaDiagnostics": null
}
```

Read back: `python3 Scripts/harness/release/f11_read_manifest.py --app build/Release/Lumina.app --check` → **PASS**.

**Instrument readings (macOS — Release `build/Release/Lumina.app`):**

| Check | Result |
|-------|--------|
| F11.1 hooks absent | **PASS** |
| F11.2 zero network | **PASS** |
| F11.3 signature | **FAIL** — ad-hoc; `spctl` rejected; unstapled |
| F11.4 manifest embed/read | **PASS** |
| F11.5 shipped rollback | **Ready** — `retain_shipped_artifact.py promote` |
| F11.6 A7 expiry | **PASS** (wave @ 0.1.0; gate fails at 1.0 + betaDiagnostics) |
| F11.7 no licensing | **PASS** |

**Follow-ups:** Developer ID + notarize + staple (F11.3); first `promote` after signed ship.

---

## 2026-08-12 — F07 / SPIKE B: motion seal + physics gates (F07.4–F07.6)

**Branch:** (working tree)  
**Claim:** Paste motion-probe export into `design/tokens.yaml` §motion, bump version, codegen + magic-number gate; activate F07.4 / F07.5 / F07.6 against sealed params; golden trajectory keyed by `tokens-hash`; close SPIKE B STUB rows in `HARNESS.md`.

**Judged:** 2026-08-12 (SPIKE B motion physics seal).

**Sealed params verbatim (`design/tokens.yaml` §motion, version `6.2-motion-seal`):**

```yaml
  chrome_fade_out:
    value: 250
    unit: ms
    type: ms
  place_return:
    value: 200
    unit: ms
    type: ms
  spring_max_overshoot:
    value: 0.02
    type: opacity
  spring_trajectory_frames:
    value: 40
    type: enum
  spring_trajectory_sample_rate_hz:
    value: 120
    type: enum
  spring_dead_stop_epsilon:
    value: 0.001
    type: opacity
  spring_retarget_continuity_epsilon:
    value: 0.000001
    type: opacity
  spring_reduced_motion_overshoot:
    value: 0
    type: opacity
  travel:
    value: 180
    unit: ms
  stage:
    value: 140
    unit: ms
  lift:
    value: 100
    unit: ms
```

**tokens-hash:** `7b0c1552736eba4c253d4f32bd81f35691f8b4c0ff238e602054729c50e36b36`

**Fix:** `LuminaSpring` + Python mirror read sealed tokens only; `magic_numbers.sh` scans motion sources; FAST id `spring_physics_f07`; golden `spring_trajectory_place_return` approved under tokens-hash.

**Drift (seal not adjusted):** **F07.4** dead-stop for `place_return` at the sealed observation horizon `(spring_trajectory_frames − 1) / spring_trajectory_sample_rate_hz` → `|value − 1| = 0.001105` **>** `spring_dead_stop_epsilon` `0.001`. Build spring sampler has not converged within sealed ε at the SPIKE B window end. F07.5, F07.6, and trajectory golden **PASS**.

**Instrument reading (Linux — measured this session):**

| Step | Status |
|------|--------|
| `tokens_codegen.py --check` | PASS |
| `spring_physics_f07` | **FAIL** (F07.4 drift above) |
| F07.5 / F07.6 / golden | PASS |

---

---

## 2026-08-12 — F04.1 / F04.7: build-for-testing cache + budget breach policy

**Branch:** `feature/f04-fast-lane-hardening` · **PR:** [#40 F04: fast-lane hardening](https://github.com/aniketh-maddipati/vlm_harness/pull/40)  
**Claim:** Land F04.1 stable `derivedDataPath` cache keyed by source hash + tokens hash (reuse / rebuild) and F04.7 budget breach output — slowest manifest ids, then **delete or demote** only.

**Finding:** `regression.sh` rebuilt into `./DerivedData` every pre-merge; budget breach text said `budget` not `ceiling` and did not name slowest ids as manifest test ids explicitly.

**Fix:** `Scripts/harness/build_cache.py` → `artifacts/harness/build-cache/<source12>-<tokens12>/` with manifest · `regression.sh` Phase 2 calls `--ensure-build-for-testing` · `run_p0_ui_tests.sh` shares the same derived path · `lanes/budget_breach.py` + runner hook · unit tests in `tests/test_build_cache.py` and `lanes/test_lane_guards.py`.

**Instrument reading (Linux cloud — measured monolith session):**

| Alias / lane | Entry | Elapsed | Status | App tests executed / expected | Orchestration |
|--------------|-------|---------|--------|-------------------------------|---------------|
| `pre-commit` / FAST | `run.py fast` | **4147 ms** | PASS | **0 / 0** | **25 / 25** |
| `pre-merge` / FULL | `run.py full` | **106 ms** | PLATFORM-UNAVAILABLE | **0 / 7** | **0 / 2** |

**Follow-ups:** macOS pre-merge wall time · first cache hit/miss timings · measured FULL lane when live Swift drivers land (CP4+).

---

## 2026-08-12 — S15 split STOP: F04 fast-lane hardening (resolved — stacked F01–F03)

**Branch:** `feature/f04-fast-lane-hardening` (**DRAFT PR** until A3 gate clears)  
**Claim:** Cherry-pick F04 commits `b4fb0a7`, `7b02485`, `2f0422d`, `1320688` off merge-base `2fca1c1`.

**Resolution:** F01–F03 merged; F04.1–F04.7 cherry-picked with manifest/run conflicts resolved.

---

## 2026-08-12 — F03.4 / F03.5 / F03.6: constitution coverage matrix + probe completeness gate

**Branch:** `feature/f03-probe-coverage` · **PR:** [#39 F03: probe coverage matrix](https://github.com/aniketh-maddipati/vlm_harness/pull/39)  
**Claim:** Land F03.4 explicit D/R → artifact registry, F03.5 FAST `constitution_coverage` freshness gate, F03.6 GAP LIST intake wired to the coverage report.

**Finding:** No honest constitution coverage matrix; GAP LIST had no machine-readable intake tying D/R rows to named lint/logic/flow/golden artifacts; probe lints (F03.1–F03.3) lacked a coverage ledger.

**Fix:** `Scripts/harness/coverage/{generate_constitution_coverage.py,artifact_registry.yaml,shelved_register.yaml}` → `artifacts/harness/coverage/constitution-coverage.{md,json}` · shelved rows (`D29`, `D38`, `D46`, `D32`, `D64`, `D50`, `R-I.3`, `R-A.1`) → `SHELVED` not `NOT-COVERED` · FAST manifest id `constitution_coverage` (`--check`) · `HARNESS.md` GAP LIST intake points at the report.

**Constitution coverage (honest count — low NOT-COVERED would be suspicious):**

| Total | Covered | Shelved | **NOT-COVERED** |
|------:|--------:|--------:|----------------:|
| 82 | 44 | 7 | **31** |

**NOT-COVERED (printed):** `D1`–`D7`, `D12`, `D14`, `D15`, `D17`, `D18`, `D20`–`D22`, `D25`, `D28`, `D30`, `D31`, `D33`, `D34`, `D40`, `D45`, `D49`, `D51`, `D52`, `D55`, `D56`, `D58`, `D62`, `D66`.

**Instrument reading (Linux cloud — measured this session):**

| Alias / lane | `run.py` | Elapsed | Status | App tests executed / expected | Orchestration |
|--------------|----------|---------|--------|-------------------------------|---------------|
| `pre-commit` / FAST (after F03.4–F03.6) | `fast` | **3667 ms** | PASS | **0 / 0** | **22 / 22** |

**Follow-ups:** map NOT-COVERED rows as artifacts land · golden fixture bodies (CP3) · battery column when F10 un-gates · macOS `xcodebuild test` for logic column names.

---

## 2026-08-12 — S15 split STOP: F03 probe coverage (resolved — stacked on F01)

**Branch:** `feature/f03-probe-coverage`  
**Claim:** Cherry-pick F03 commits `8efa3e4`, `b7a98b5` off merge-base `2fca1c1`.

**Resolution:** F01 spine merged; F03.1–F03.6 cherry-picked with manifest/run conflicts resolved (F02-only `grammar_oracle_parity` omitted on this branch).

---

## 2026-08-12 — F02.4 / F02.5: headless grammar replays + oracle parity

**Branch:** `cursor/f0-prompt-factory-cbe0` · **PR:** [#35 F02: headless grammar rung](https://github.com/aniketh-maddipati/vlm_harness/pull/35)  
**Claim:** Land F02.4 (five v2 seed replays with `grammarExact`, no sleeps) and F02.5 (`grammar_oracle_parity` on pre-commit — oracle vs Swift-machine mirror; divergence FAIL with both readings printed).

**Finding:** Seeds mixed partial asserts and included `px_advance` / `arming_consent` outside the F02.4 law roster; no parity gate between Python oracle and `CullGrammarMachine`.

**Fix:** F02.4 five replays (`held_is_temporary`, `same_mark_clears`, `shift_return_return_release`, `esc_exact_restore`, `value_echo_adjustment_only`) · hold/adjust events + `grammarExact` asserts · F02.5 `grammar_machine.py` mirror + `run_scripts.py --parity` · manifest id `grammar_oracle_parity`.

**Instrument reading (Linux cloud — measured this session):**

| Alias / lane | `run.py` | Elapsed | Status | App tests executed / expected | Orchestration |
|--------------|----------|---------|--------|-------------------------------|---------------|
| `pre-commit` / FAST (prior F02.1 baseline) | `fast` | **3105 ms** | PASS | **0 / 0** | **17 / 17** |
| `pre-commit` / FAST (after F02.4/F02.5) | `fast` | **3154 ms** | PASS | **0 / 0** | **18 / 18** |

**Pre-commit delta this session:** +1 orchestration test (`grammar_oracle_parity`, ~166 ms measured step time) · +49 ms total lane wall time vs F02.1 baseline.

**Not built:** **F02.2** (live Swift grammar driver wiring) remains gated on **CP1** per checkpoint sequence — STUB register unchanged for app-coupled grammar.

**Follow-ups:** macOS `xcodebuild test` for `CullGrammarTests` · CP4 live driver · emit F0 prompt pack when `design/build-prompts/` lands.

---

## 2026-08-12 — F02.1: G1 rulings applied (S14 A1 conflict rows)

**Branch:** `feature/f02-headless-grammar-rung`  
**Claim:** Close S14 finding #1 (conflict-blindness) — apply G1 rulings for each CHANGED row; D59 was SAME.

| Row | G1 ruling | Amendment owed (live P0 / shell) |
|-----|-----------|----------------------------------|
| D10 — P/X decide **and advance** | **KEEP** | `P0SessionModel.applyCullToggle` owes focus advance after non-clear mark-set |
| D10 — decision keys never autorepeat | **KEEP** | `P0ContactSheetView` P/X handlers owe autorepeat swallow (shell-owned per machine contract) |
| D47 / A3 — pointer marks parity | **KEEP** | P0 owes ✓/✕ pointer marks wired to the same mark path (A3 un-shelf) |
| D11 / D13 — release never commits | **KEEP** | P0 Return→`openFocusedPhotograph()` is a separate surface; wholesale staging grammar stays headless-only until CP7 |

**D59 same-mark-clears:** SAME — no code change on this branch.

---

## 2026-08-12 — F01: CP0 shell reconciliation

**Branch:** `cursor/f0-prompt-factory-cbe0` · **PR:** [#35 F01: CP0 shell reconciliation](https://github.com/aniketh-maddipati/vlm_harness/pull/35)  
**Claim:** Land F01 CP0-shell rulings (F01.1–F01.7) — single entry point, lint home, enforced budget, bash-3.2 shell lints, allowlist ratchet, HARNESS lane-alias table and shell prose.

**Finding:** Harness had dual lint paths (`Scripts/lint/` plus duplicate Phase 1 in `regression.sh`); `budgetMs` was advisory only; `mapfile` in shell lints broke FAST on macOS system bash 3.2 (see 2026-08-11 Tree compiles entry); debt allowlists could grow silently; HARNESS lacked `pre-commit` / `pre-merge` / `nightly` mapping to `run.py` lanes.

**Fix:** F01.1 `regression.sh` lane dispatch · F01.3 lint home under `Scripts/harness/lint/` · F01.4 budget FAIL + slowest-id listing · F01.5 bash-3.2-safe shell lints · F01.6 `allowlist_ratchet` manifest id · F01.2/F01.7 HARNESS prose (this entry).

**Instrument reading (Linux cloud — measured this session):**

| Alias / lane | `run.py` | Elapsed | Status | App tests executed / expected | Orchestration |
|--------------|----------|---------|--------|-------------------------------|---------------|
| `pre-commit` / FAST | `fast` | **3292 ms** | PASS (exit 0) | **0 / 0** | **17 / 17** |
| `pre-merge` / FULL | `full` | **130 ms** | PLATFORM-UNAVAILABLE (exit 2) | **0 / 7** | **0 / 2** |
| `nightly` / HEAVY | `heavy` | **118 ms** | PLATFORM-UNAVAILABLE (exit 2) | **0 / 6** | **0 / 2** |

**CONFLICT status (prompt-factory headings):**
- **CONFLICT 1 (CP0 shell fragmentation): partially closed** — single entry point (`regression.sh` → `run.py`), lint home via manifest ids only, enforced `budgetMs` ceiling, allowlist ratchet, bash-3.2 shell lints, HARNESS lane-alias table. Remaining shell work rolls to macOS measured FULL/HEAVY (CONFLICT 2).
- **CONFLICT 2 (app-coupled live suite): open** — FULL/HEAVY report PLATFORM-UNAVAILABLE on this host; 0 app-coupled tests executed; live Swift drivers remain STUB-owned (CP4 / CP7 / SPIKE A / HEAVY per STUB register).
- **CONFLICT 4 (prompt factory): open** — `design/build-prompts/` (`INDEX.md` + F01–F13) not yet in tree; F0 factory emit blocked on missing artifacts.

**Follow-ups:** macOS AS measured FULL/HEAVY run · emit F0 prompt pack · wire live app-coupled drivers per STUB register.

---

## 2026-08-11 — Tree compiles (mechanical fix session)

**Branch:** `fix/legacy-callsite-argument-order` · worktree `../lumina-wt/fix-callsites`  
**Claim:** Drive `xcodebuild … build` and `build-for-testing` to zero errors with mechanical fixes only.

**Result:**
- **First commit at which the app tree compiles in recorded history:** `fa22692` (`fix(tree): TreatmentStageView — explicit return on all TreatmentFidelity.label cases`)
- **Errors fixed:** 14 mechanical fixes across 11 files (argument-order, Int(floor) how-many-fit, restored `decided` binding, explicit returns, XCTUnwrap for `Double?` accuracy asserts, `CropSession.flipOrientation`, zip-tuple→arrays)
- **STOP count outstanding:** 0
- **Launch proof:** `artifacts/tree-compiles/launch-proof.png` — Open-a-shoot window reached without crash

**Gates:** `xcodebuild -scheme Lumina -destination 'platform=macOS,arch=arm64' -derivedDataPath ./DD build` → SUCCEEDED · `build-for-testing` → SUCCEEDED.  
`Scripts/quarantine_d40.sh` absent from tree (noted). FAST shell lints (`banned_patterns` / `magic_numbers` / `banned_words`) FAIL on host bash 3.2 (`mapfile` / syntax) — host tooling, not introduced by this session; remaining FAST orchestration OK after PyYAML install.

**Follow-ups (listed, not done):** wire `xcodebuild build` as FULL lane job #1 on macOS runner · warnings triage · install bash≥4 / fix lint shebangs for macOS system bash.

---

## 2026-08-11 — CP0 review: vacuous-green / platform / ledger honesty

**Branch:** `checkpoint/cp0-harness` · **PR:** #32  
**Claim:** Resolve review F1–F4 before merge — no vacuous PASS; FULL/HEAVY macOS-AS-only; stubs owned; ledger UNMEASURED.

**Fixes:**
- **F1** Lane manifests (`lanes/manifests.json`) + inventory guard; summary always prints `N app tests executed / M expected`
- **F2** HARNESS.md platform split (Python orchestration vs Swift-on-macOS app-coupled); every Python app stub marked `STUB` + `owned-by-*`
- **F3** FULL/HEAVY → `PLATFORM-UNAVAILABLE` on non-AS-macOS (exit 2), never PASS
- **F4** `ledgers/orchestration-only.json` records all acceptance numbers as `UNMEASURED`; gates inactive until measured macOS run

**Re-measured lane times (Linux cloud):**
| Lane | Result | Elapsed | App tests |
|------|--------|---------|-----------|
| FAST | PASS | **3149 ms** | **0 app / 0 expected** (16 orchestration) |
| FULL | **PLATFORM-UNAVAILABLE** | **119 ms** | **0 app / 7 expected** |
| HEAVY | **PLATFORM-UNAVAILABLE** | **114 ms** | **0 app / 6 expected** |

Exit codes: FAST `0` · FULL/HEAVY `2` (PLATFORM-UNAVAILABLE). Ledger: `artifacts/harness/ledgers/orchestration-only.json` — all six acceptance numbers `UNMEASURED`, `gates_active: false`.

**Follow-ups unchanged:** live Swift drivers (CP4/CP7/SPIKE A/HEAVY) — stubs refuse PASS until wired.

---

## 2026-08-11 — CP0: harness upgrade

**Branch:** `checkpoint/cp0-harness` (worktree `/lumina-wt/cp0-harness` off `seal-v6.1`).  
**Claim:** Three-lane harness (FAST/FULL/HEAVY), non-blocking watch dashboard, Probe v2 NDJSON, input-script grammar suite, signpost ledger, golden propose→approve keyed by tokens-hash, tokens.yaml codegen, feature drop-in contract — testing never blocks building; red FULL blocks MERGE only.

**Delivered:**
- `Scripts/harness/run.py` + dashboard + worktree snapshot runner
- Probe v2 (`Lumina/Testing/ProbeV2/*`) + Python simulator + 5 seed scripts
- `DesignTokens/HiFiTokens.generated.swift` from `design/tokens.yaml` + freshness lint
- Golden service + chrome metrics golden; acceptance signpost parse + fixture ledger
- `HARNESS.md` with drop-in contract, P/X worked example, GAP LIST ownership (no unowned gaps)

**GAP LIST intake:** codegen / motion-timing guard / grammar scripts / golden service **closed in CP0**; remaining seal follow-ups owned (CP1/CP3/CP5/CP8/HEAVY/D46/1.0) — see `HARNESS.md`.

**Measured lane times (Linux cloud) — superseded by review entry above (vacuous-green / PLATFORM-UNAVAILABLE):**
| Lane | Result | Elapsed | Budget |
|------|--------|---------|--------|
| FAST | PASS | **2959 ms** | 90s |
| FULL | PASS *(vacuous — corrected)* | **409 ms** | 10min |
| HEAVY | PASS *(vacuous — corrected)* | **280 ms** | nightly |

**Platform:** Linux — simulator/fixture FULL; no `xcodebuild`. Live Probe v2 socket + XCUITest remain macOS.

**Follow-ups:** live signpost emitters on product paths (SPIKE A/B+); pixel goldens per body (CP3); A5 CopyContract spacing; P0OpenView alert→facts-chip (CP8).

---


## 2026-08-11 — Constitution: Batch 1 seal verification (agent-rules + Phase 4)

**Branch:** `constitution/batch1-verify-agent-rules` (cherry-picked onto seal tip after #30 squash; #30 head `constitution/amendment-batch-1` also carries the same commits).  
**PR:** [#31 Constitution: Batch 1 seal verify — agent-rules D63 + Phase 4](https://github.com/aniketh-maddipati/vlm_harness/pull/31).  
**Range for Phase 4:** `#29-head (78ea577)..#30-head (21da1d5)` — **not** `origin/main..HEAD`.

**Process CONFLICT (worktree base) — recorded + resolution:**  
GIT PROTOCOL named `origin/main` as worktree base, but `design/contract-v6.md` (and peers) existed only on `cursor/contract-v6-artifacts-3877` (PR #29).  
**Options:** (1) stack amendments on sealed v6 — **chosen**; (2) wait for #29→main.  
Resolution executed: worktree/branch from sealed v6; PR #30 stacked on #29. (Unrecorded resolution would be FAIL — this entry + the Batch 1 entry both carry it.)

**AGENT-RULES CHECK (permanent):**  
- Scanned `.cursorrules`, `AGENTS.md` (no CLAUDE.md).  
- **FAIL found:** `.cursorrules` taught crop latch **A→aspect / X→orientation** re-scoping — contradicts **D63** (R/O; A and X banned from remapping).  
- **Fix:** rewrite crop section to D63; authority line now defers to contract; multi-select re-shelved to match D29/D38; Hold-J named; pointer marks listed.  
- **Gate:** `Scripts/harness/lint/agent_rules_contract.sh` added; wired into `contract_v6_presence.sh` + FAST lane manifest.

**Phase 4 diff-scope (`78ea577..21da1d5`):**  
Only batch artifacts: `BUILD_LOG.md`, `design/checkpoint-sequence-v6.md`, `design/contract-v6.md`, `design/copy-contract.txt`, `design/fixture-manifest.md`, `design/mvp-test-plan.md`, `design/tokens.yaml`. Seal’s own files absent from the batch diff — **PASS**.

**Measured:** `agent_rules_contract.sh` · `contract_v6_presence.sh` · `copy_contract_diff.sh` · `banned_words.sh` · `contract_structure.sh` · `bash -n Scripts/regression.sh`.

**Follow-ups:** regenerate `AUDIT-HIFI.md` (still records old A/X crop PASS); CopyContract.swift wire-up; fixtures; `seal-v6.1` after human review.

---

## 2026-08-11 — Constitution: Amendment Batch 1 (A1–A10)

**Branch:** `constitution/amendment-batch-1` (worktree; based on sealed `cursor/contract-v6-artifacts-3877` — `origin/main` lacked constitution artifacts).  
**PR:** [#30 Constitution: Amendment Batch 1 (A1–A10)](https://github.com/aniketh-maddipati/vlm_harness/pull/30) — stacked on seal branch #29 (squash-merged to seal tip `897b951`; no `seal-v6.1` tag).

**Scope:** Documents only. Integrate MVP-test questionnaire rulings A1–A10 into contract / tokens / copy / fixtures / checkpoint / new `design/mvp-test-plan.md`. No product code. No law weakened beyond the two scoped amendments (A5 D16; A7 R-9.1).

**Laws touched:** D16 (A5), D21/D42 (A4 Hold-J), D23/D63 (A2 crop), D32/D46 (A10), D45/D66 (A7), D47 (A3), D52 (A8), D64 (A6), D65 (A1); Shelved Register updates.

**Scoped weakenings (review):**
1. **A5 → D16:** word "Adapt" verbatim in banner; remainder may compress.
2. **A7 → R-9.1/D45:** TestFlight crash reporting beta-only; **expires at 1.0**.

**Surviving [FLAG] markers:**
1. `[FLAG: body list is Claude's pick; swap freely before fixtures are cut.]`
2. `[FLAG: R/O are Claude's pick — validate with wave-one testers.]`

**Process CONFLICT (flagged, not silent):** GIT PROTOCOL named `origin/main` as base, but `design/contract-v6.md` (and peers) exist only on `cursor/contract-v6-artifacts-3877` (PR #29). Options considered: (1) stack amendments on sealed v6 — **chosen**; (2) wait for #29→main. HARNESS.md absent on sealed tree — noted, not invented.

**Measured:** `contract_v6_presence.sh` OK · `copy_contract_diff.sh` OK · `banned_words.sh` OK. (No xcodebuild on Linux.)

**Follow-ups:** Wire A5/A2/A1 copy through CopyContract.swift; align `.cursorrules` crop A/X remap to D63; six-body fixtures; A7 strip at 1.0; A8 licensing post-test; taste harness after wave-one eval set; human review → merge → `seal-v6.1`.

---

## 2026-08-11 — Constitution re-seal: Contract v6 merge against v5

**Scope:** Second-pass constitution merge. Close the three first-pass CONFLICT blocks; seal D24/D27/D36/D40 amendments against real prior text; freeze D59/D60 verbatim copy; Task 5 checkpoint sanity; drop superseded CopyContract hover string. No tokens.yaml codegen (FOLLOW-UP / CP0).

**Conflicts closed:**
1. Contract v5 source → `design/contract-v5.md` (verbatim PDR D1–D40).
2. Layer-2 + D40 → sealed order in `design/checkpoint-sequence-v6.md` (**reorder: none**).
3. Same-mark / Return-release verbatim → frozen [P] rows from v5 D10/D11; D59/D60 OPEN closed.

**Laws touched:** D21 (R-5.2), D24 (R-X.1), D27 (birth-opacity one-liner), D32/success test (R-A.1), D36 (R-M.1), D37 (hover deleted), D40 history note; D41–D62 carried/sealed.

**Code (session-allowed next step only):** `CopyContract.tableFooterHover` removed → `tableFooterHints` without “(hover)”; call sites updated; D59/D60/R-M strings added to CopyContract.

**Measured:** `contract_v6_presence.sh` · `copy_contract_diff.sh` · `banned_words.sh` · `contract_structure.sh`.

**Follow-ups:** tokens.yaml codegen (CP0); remove remaining hover *handlers* (CP5 / D48); taste-proof gate (D46); fixture bodies.

---

## 2026-08-11 — Constitution: Contract v6 artifacts (documents only)

**Scope:** Prompt Pack v1 constitution session — produce Contract v6, tokens.yaml, frozen copy table, fixture manifest, checkpoint-sequence sanity check. No product code; no D-law weakened.

**Laws touched:** L1–L5 carried; amendments D24 / D27 / D36 (texts from rulings/audit); new D41–D62 integrating R-5.1, R-5.2, R-5.3, R-8.1, R-9.1, R-A.1, R-A.2, R-X.1, R-X.2, R-I.1–I.3, R-M.1–M.5, R-Q.1 + audit items (halo 1.5 pt, Export three-state, post-commit focus advance, Develop banked, birth-opacity).

**Conflicts flagged:**
1. Contract v5 (D1–D40) verbatim source absent — cannot seal D24/D27/D36/D40 diffs against prior text.
2. Prompt Pack Layer-2 sequence body + D40 retirement plan absent — Task 5 reorder = none.
3. Same-mark-clears + Return-release gate verbatim copy lines not pasted — frozen as OPEN, not invented.

**Artifacts:** `design/contract-v6.md`, `design/tokens.yaml`, `design/copy-contract.txt` (v6 tags/change-marks), `design/fixture-manifest.md`, `design/checkpoint-sequence-v6.md`, harness `Scripts/harness/lint/contract_v6_presence.sh`.

**Follow-ups:** Check in v5 + Layer-2; re-seal v6; supply verbatim D59/D60 copy; codegen Swift from tokens.yaml; remove superseded hover string from `CopyContract`; taste-proof gate for D46.

**Measured:** `contract_v6_presence.sh` OK · `copy_contract_diff.sh` OK · `banned_words.sh` OK · `contract_structure.sh` OK. (No xcodebuild on Linux.)

---

## 2026-08-13 — P0 editing merged onto main (post F04/F11)

**Claim:** Merge `cursor/p0-single-photo-editing` (#25) onto current `main` with harness lane dispatch intact, leaf-only probe identifiers preserved, and generated edit harness evidence gitignored.

**Finding:** Four merge conflicts — `.gitignore`, `BUILD_LOG.md`, `ContactSheetInspectImage` body (main had misplaced inspection chrome), `Scripts/regression.sh` (kept F01 harness Phase 1 dispatch; dropped pre-F01 numbered script steps).

**Fix:** Resolved conflicts favoring main harness architecture + P0 editing surface. `ContactSheetInspectImage` restored to image-loading `Group`. Combined ignore rules for harness ephemeral streams and `artifacts/p0-edit*`.

**Build / gates:** Linux FAST orchestration re-run post-merge (macOS xcodebuild not available here). Targeted macOS gates from prior session: `p0_edit_test.swift` 29/29 · `EditingProbeTests` 1/1 · leaf-only id lint. Perf tables in `docs/P0_EDITING.md` remain historical.

---

## 2026-08-07 — P0 editing restacked onto main + minimal editing probe

**Claim:** Land the seven single-photo editing commits on current `main` (post #23 harness, #24 UX hardening) with the harness contracts intact, add the smallest useful structured editing coverage, and stop shipping generated run evidence in the repo — without starting the deeper Metal/grouping roadmap.

**Finding:** The rebase itself was clean after conflict resolution (Debug + Release build green, `p0_edit_test.swift` 29/29), but one conflict-resolution defect survived review and was only caught by running the existing harness: `p0.singlePhoto.image` had been moved onto a plain container `ZStack`. SwiftUI creates no accessibility element for such a container, so the identifier was undiscoverable and `MissingOriginalsTests` failed — it also violated the repo's own leaf-only rule. Two harness traps recurred while writing the new flow: macOS consumes the first mouse-down on a non-frontmost app as a window-activation click, and a slider drag that *begins* at the neutral midpoint can commit an unchanged value (the fingerprint no-op guard then correctly drops it), so the press must start off-neutral.

**Fix:** Moved `singlePhotoImage` onto the two mutually-exclusive presenting leaves (Metal canvas when an image exists, cached preview otherwise). Added one DEBUG-only probe field, `focusedRecipeFingerprint` (the existing `EditRecipe.valueFingerprint` — no paths, pixels, or payload), mirrored in the test-side decoder; one leaf identifier `p0.singlePhoto.exposure` via `P0EditSlider.identifier`; and one flow, `EditingProbeTests`, proving gesture → fingerprint change → cull untouched → undo restores → P/X leaves the recipe alone. Untracked 24 generated evidence files (~180 MB) under `artifacts/p0-edit*` with narrow ignore rules, preserving local copies and correcting the doc links.

**Build / gates:** Debug + Release **SUCCEEDED**; Release binary contains no harness symbols or launch flags (Debug positive control confirms the check). Targeted gates: `p0_edit_test.swift` 29/29 (0.5 s) · logic 5/5 (2.7 s) · `EditingProbeTests` 1/1 (5.0 s, stable over 3 runs) · `MissingOriginalsTests` 1/1 (6.3 s) · `UXHardeningTests` 2/2 (6.3 s) · smoke 6/6 (5.0 s). Not run by design: `P0Fast`, stress, visual, explorer, real-media audit. Perf tables in `docs/P0_EDITING.md` are marked historical — not re-measured since the rebase, which changed preview/scheduler sizing. Scrub and nav latency targets remain missed.

---

## 2026-08-07 — P0 UI automation harness (XCUITest)

**Claim:** A Playwright-like native macOS UI-automation harness that launches Lumina against isolated deterministic fixture state, drives the real P0 interface with keyboard/mouse, and yields replayable evidence (seed + trace + screenshots + structured state) — without touching real user data, changing product behavior, or implementing editing.

**Finding:** No UI-test target, no shared scheme, zero accessibility identifiers, and persistence hard-wired to `~/Library/Application Support/Lumina`. Two macOS-specific traps surfaced: (1) SwiftUI propagates a container's `accessibilityIdentifier` onto every descendant, clobbering leaf identifiers (density/count/toolbar controls became `p0.contactSheet`/`p0.toolbar`); (2) a freshly launched app under XCUITest sometimes stays background, collapsing its accessibility tree, and duplicate cell identifiers (container + inner image) made clicks land on the wrong cell.

**Fix:** DEBUG-only launch mode (`Lumina/Testing/`: `UITestSupport`/`UITestLaunch`/`UITestFixtures`/`UITestStateProbe`/`P0AccessibilityID`) with a `ShootStore.supportDirectory()` override for isolated state, deterministic fixtures (`mixed-60`/`mixed-200`/`missing-originals`, synthesized images — no RAW/binaries), a JSON state probe, and an app activator. `LuminaUITests` (robots + 9 deterministic flows + seeded state-aware explorer + invariants + visual regression) and a minimal `LuminaLogicTests` XCTest target, wired via a shared scheme and `TestPlans/{P0Fast,P0Stress,P0Visual}`. Removed container identifiers (leaf-only rule), made inner cell views non-accessibility, added verify+retry to cell/density clicks and self-healing launch. Runner `Scripts/run_p0_ui_tests.sh` (fast/stress/visual/logic/seed); portable manifest checks wired into `Scripts/regression.sh` (no Linux macOS-test claims); docs `docs/P0_UI_AUTOMATION.md`. No P0 product behavior changed.

**Build:** Debug build green. `P0Fast` 14/14 pass (5 logic + 9 UI incl. short explorer). Explorer seed replay green (`seed 55555`, mixed-200). See delivery report / PR.

---

## 2026-08-06 — P0 trustworthy single-photo RAW editing

**Claim:** Open a photograph from the contact sheet and adjust it with immediate, trustworthy RAW feedback bound only to `EditRecipe`, shared undo, and no cull/selection regression.

**Finding:** Single-photo surface was a JPEG-thumb placeholder; Whites/Blacks/Texture/Clarity/Dehaze remain render-inert; undo coordinator was cull-only; no gesture-coalesced edit command.

**Fix:** `EditMutationCommand` on shared `P0UndoCoordinator`; session scrub/commit/flush/Before; `P0SinglePhotoEditor` + adjustment rail + crop overlay wired to `DevelopRenderScheduler`/`DevelopMetalView`; Whites/Blacks deferred; docs `docs/P0_EDITING.md`; tests `Scripts/p0_edit_test.swift`; harness `--p0-edit-harness`.

**Build / gates:** Debug **SUCCEEDED**. Deterministic P0 edit/cull/state/contact tests green. Live ARW harness **PASSED**. Full `--p0-edit-live` session on 94 Mehendi ARWs **PASSED** (10s scrub, Before, 20-nav, crop, undo, quit/reopen). Fixed preparation saves clobbering live cull/recipe. Perf: scrub p95 ~19 ms during live scrub; nav p95 still misses 35 ms target on cold neighbors.

---

## 2026-08-06 — P0 cull grammar + single-photo placeholder

**Claim:** P/X toggle cull with immediate persistence and undo; exact grid↔photo restore; no AI/recipe side effects.

**Finding:** Contact sheet showed mark slots only — no cull mutations, no shared undo coordinator, inspect overlay lacked grid restore/filmstrip.

**Fix:** `CullMutationCommand` + `P0UndoCoordinator`; session P/X/⌘Z; visual grammar (✓/dim+✕/accent/edit bar); single-photo placeholder + filmstrip; docs `docs/P0_CULLING.md`; tests `Scripts/p0_cull_test.swift`.

**Build:** See delivery report / PR.

---

## 2026-08-06 — P0 contact sheet (open + incremental browse)

**Claim:** Open folder/T7 → usable contact sheet before all previews/metadata finish; identity-keyed caches; no import overlay / AI / tiering on the P0 route.

**Finding:** Legacy import blocked the UI behind `ImportLoadingView`, ran scoring/taste/faces, and the old grid forced uniform cell crops.

**Fix:** `ContactSheetPreparation` + `P0SessionModel` + `NSCollectionView` contact sheet; Open surface with drop/recent/reopen; marks from orthogonal state; docs `docs/P0_CONTACT_SHEET.md`; tests `Scripts/p0_contact_sheet_test.swift`; bench `Scripts/p0_contact_sheet_bench.swift`.

**Build:** See delivery report / PR for measured timings.

---

## 2026-08-06 — P0 canonical state foundation

**Claim:** Stable asset identity, EditRecipe as sole persisted recipe (incl. crop/straighten), actor-backed recoverable shoot store — without redesigning contact-sheet UI or the RAW render engine.

**Finding:** `PhotoRecord` persisted `DevelopRecipe` (no geometry); caches keyed by filename stem; one global `saveDebounced` work item; ephemeral UUIDs at import.

**Fix:** `ShootRecord`/`AssetRecord`/`ShootStore`; `AssetIdentity` rediscovery keys; EditRecipe schema v2 + migration; identity-keyed caches; pruned unwired shells. Docs: `docs/P0_CANONICAL_STATE.md`. Tests: `Scripts/p0_state_test.swift`.

**Build:** Debug **SUCCEEDED** (macOS). Deterministic scripts green. RAW harness not re-run this session (no fixture gate claimed).

---

## 2026-08-04 — Continuous workspace (Workbench / Canvas / Proof)

**Claim:** Replace stack-table + fixed develop sidebar with one continuous photographic workspace — three spatial stages sharing selection and scroll identity.

**Implemented:**
- `WorkspaceStage` (workbench / canvas / proof) on `LuminaShellModel` — no new top-level routes.
- `ContinuousWorkspaceView` + `TreatmentFamilyRow` (≤8 photos, capture order, equal-size expanded grid).
- `ContextualTreatmentStrip` under expanded row (Original / Auto / Current + develop sliders).
- `EmergingSetRail` (kept photos, collapses to tab @ <1100 pt width).
- `StoryCanvasView` / `StoryProofView` — vertical draft sequence, Esc returns to Canvas.
- Keyboard: S/X/M routing, Return expand, Space focus, ⌘1/2/3 stages; destructive swipes removed.
- Presentation buckets capped at **8**; sibling continuation cues for split clusters.

**Build:** `xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug build` → **BUILD SUCCEEDED** (macOS).

**Not verified this session:** Live Mehendi/Death Valley GUI, regression.sh E2E, quit/resume, screenshots.

**Debt:** Undo, persisted story order, per-frame adaptive develop, treatment-compatible grouping — see `docs/WORKSPACE_LAYOUT_REPORT.md`.

---

## 2026-08-04 — Phase 1 shell + spine bridge (cloud follow-up)

**Claim:** Re-land Phase 1 shell on `cursor/ethereal-ui`, connect Attempts active stage to PreviewSpine/Metal, cache presentation adapters, fix Escape, bring `AGENTS.md` from main.

**Repo verification:**
- `AGENTS.md` exists on `origin/main` and is now on this branch.
- Prior Mac-desktop Phase 1 edits were never committed; this Linux cloud checkout rebuilt them.
- Platform: Linux cloud agent — **cannot** `xcodebuild` or run Mehendi live session (see AGENTS.md).

**Bridge requirements implemented in code:**
- `StablePhotoView` → PreviewSpine silhouette + fidelity + PhotoImageCache with AssetID request validation; lower fidelity remains during upgrades.
- `SpineActiveStage` → MetalBrowseCanvas + spine paint for Attempts active image.
- `LuminaShellModel` caches snapshots via `PresentationAdapter.projectFingerprint`; selection overlays without rebuilding groups.
- `PhotoGridView` selection path uses `applySelectionOnly` / `refreshVisibleBadges` — no `reloadData()` for selection.
- Escape closes Focus / inspector / shortcuts only — never workspace → Home.

**Live gate remaining (macOS only):** `bash Scripts/live_bridge_session.sh` with Mehendi ARWs — rapid nav, 20× lens switch, decisions, resize, Focus, quit/resume, screen capture.

---

## 2026-08-02 — Build Loop closure (this session)

**Claim:** Progressive wall complete; Kill-the-Defeater fixes 1–5 code-audited; build + regression green.

**Build:** `xcodebuild -scheme Lumina -destination 'platform=macOS'` → **BUILD SUCCEEDED** (clean + incremental).

**Regression:** `bash Scripts/regression.sh` → **PASSED** — 30 pass · 0 friction · 0 bugs · cache decode p95 **0.14 ms** (headless sample, not browse photon path).

**ProgressivePhotoWall:** Complete. File `Lumina/Views/ProgressivePhotoWall.swift` auto-synced via `PBXFileSystemSynchronizedRootGroup`. Wired in `ImportLoadingView` (import wall), `GroupIntroPhase` (Meet), `ProgressivePickWall` (Pick). Compiles; no pending work.

---

## 2026-08-02 — Kill-the-Defeater (speed browse)

**Claim:** Held-key rip through Mehendi ARWs — p95 in→photon <50 ms; `blit_ms` ≈0; one decode/frame; zero main-thread decode/upload; no RAW on interactive path.

### Findings (pre-fix diagnostic)

| Finding | Impact |
|---------|--------|
| **HUD lying** | `input→photon` measured dict lookup / NSImage bind, not Metal `present`; prefetch “hit” counted warm NSImage, not GPU texture |
| **CPU blit hidden** | Full-frame `CGContext.draw` before IOSurface wrap; cost folded into `wrap_ms` |
| **Double decode** | Parallel NSImage dict + Metal upload on same JPEG |
| **Main-thread upload** | `MetalBrowseCanvas.updateNSView` called sync `upload()` on main |
| **RAW on browse path** | `sourcePathByID` RAW fallback; ImageIO `IfAbsent/Always=true` could demosaic |
| **Filmstrip thrash** | `scrollTo` + chrome animation on every advance during held-key rip |
| **ARW 1616 px synth** | Sony embeds 1616×1080 only; `minLongEdge: 2000` in `ProjectStore.extractBrowsePreview` → 100% ingest-synth for Mehendi ARWs (~456 ms once at ingest, ~50 ms cached JPEG browse thereafter) |

### Fix verification table

| Fix | CLAIM | STATUS | Evidence |
|-----|-------|--------|----------|
| **1 — Honest HUD** | Split upload into decode/blit/wrap; GPU prefetch hit = texture resident; in→photon at Metal present; paint_commit separate | **VERIFIED** | `PreviewSpine.swift` L30–31, L169–177, L196–221, L379–398 · `MetalPreviewPool.swift` L16–21, L161–165 · `MetalBrowseCanvas.swift` L162–165 · `SpeedContractHUD.swift` L20–24 |
| **2 — Kill CPU blit** | No `CGContext.draw` between JPEG decode and IOSurface; vImage copy/convert | **VERIFIED** | `MetalPreviewPool.swift` L12, L84–87, L248–283 · e2e static check: no `ctx.draw` |
| **3 — One decode→GPU** | Drop NSImage preview hot path; browse tier = GPU texture only; silhouette = tiny grid thumb | **PARTIAL** | `PreviewSpine.swift` — no `previews` dict ✓ · dual callers remain (`PreviewSpine.enqueueGPU` + `MetalBrowseCanvas.bind`) · **Hardened:** `MetalPreviewPool.upload` / `scheduleUpload` coalesce per-photo via `inflightUploads` (second caller returns cache-hit / no-op; `.luminaTextureReady` fans out) |
| **4 — Off main upload** | Never sync-decode/upload in `updateNSView`; background pipeline only | **VERIFIED** | `MetalPreviewPool.swift` L62–65, L116–120 · `MetalBrowseCanvas.swift` L183–184 · `PreviewSpine.swift` L336–337 · draw/present stays on main (CAMetalLayer requirement) |
| **5 — Decouple filmstrip/chrome** | Canvas alone updates per keypress; filmstrip/chrome debounced during rips | **PARTIAL** | `SpeedBrowseViewer.swift` L4, L12–14, L100–108, L120–147, L240–285 — debounced filmstrip + rip-skipped controls ✓ · **Gap:** `tierLabel` L112–117 tracks every paint; parent ZStack still observes full `@Observable` spine |
| **RAW guard** | Browse never demosaics RAW; debug assert on RAW path | **VERIFIED** | `PreviewSpine.swift` L79–81, L368–377 · `MetalPreviewPool.swift` L193–198, L219–225 · `PhotoImageCache.swift` L27–33 |
| **SessionCache** | Session-scoped memory LRU + async disk; evict browse GPU on session end | **VERIFIED** | `PhotoImageCache.swift` L42–96, L173–185, L278–295 · `ProjectViewModel.swift` L148, L205, L445, L924 |

**Static audit (e2e):** `[PASS] Defeater-killed browse path` — honest HUD · vImage blit · one GPU decode · no main upload · no RAW fallback.

**Live numbers:** Pending manual ⌥` HUD rip on Mehendi ARWs. Regression cache p95 ~0.14 ms is grid/filmstrip path, not browse photon.

**Docs owed:** ARW 1616 px → synth threshold note in ingest spec; filmstrip decouple note in review-surface charter.

---

## 2026-08-02 — Session cache + Pick hang

**Claim:** Pick grid paints without eternal spinners; cache warm during edit, evict after session.

**Fixed:**
- `SessionCache` + `PhotoImageCache` — memory LRU 320, session disk under `Caches/Lumina/sessions/`, async utility disk writes
- Grid/preview tiers: `allowsRAWFallback: false`, 512 px display cap for filmstrips
- `PhotoImageView` failure placeholder; removed `PreviewSpine.warm` from Pick path
- Prefetch on Meet→Pick transition via `ThumbCache`

**Status:** Build + regression 30 pass. Manual: Meet → Pick from this set.

---

## 2026-08-02 — Progressive photo wall

**Claim:** No horizontal infinite scroll during ingest/Meet/Pick; screen-fit grid; previews fill slowly without jarring bulk load.

**Fixed:**
- `ProgressivePhotoWall` — `FitGridLayout` screen-fit slots, 380–420 ms reveal interval, prefetch window ahead of reveal (`ImportLoadingView`, Meet intro)
- `ProgressivePickWall` — 2-up batch reveal ~280 ms, scrollable grid for selection
- `ProgressiveWallTile` — loads via `PhotoImageCache` at 512 px, `allowRAW: false`

**Status:** Complete. Build + regression 30 pass.

**Manual:** Import a folder — wall should fill slot-by-slot, not dump all thumbs at once.

---

## Manual verification checklist

Run on **Mehendi ARW shoot** (`/Users/aniketh/Pictures/jeevana_mehendi_2026_MATCHED_RAWS`).

### 1. ⌥` HUD held-key rip (Kill-the-Defeater)

1. Open Lumina → import or resume Mehendi project → enter speed browse (F/D cull).
2. Toggle HUD: **⌥`** (Option + backtick).
3. Hold **F** (or **D**) for 3–5 s — rip through 20+ frames.
4. Record HUD lines:
   - `paint_commit` p50/p95 — should stay low (dict lookup, not photon)
   - `in→photon` p50/p95 — **target ≤50 ms**; measured **at present**, not at bind
   - `decode · blit · wrap` p50 — blit should be **≈0 ms** (vImage, not CGContext)
   - `GPU prefetch` % — should climb during rip; misses show silhouette tier briefly
   - `preview: emb · synth · jpg` — Mehendi ARWs expect **synth >> emb** (1616 px embed below 2000 threshold)
5. **Pass criteria:** photon p95 badge green; no main-thread stalls visible; silhouettes acceptable on cold frames, preview tier on warm.

### 2. Pick grid (Session cache)

1. Import → Meet phase → **Pick from this set**.
2. Confirm thumbs appear progressively (not all spinners forever).
3. Re-enter Pick on same set — cached thumbs should paint immediately.

### 3. Import / Meet wall (Progressive wall)

1. Import a large folder — import screen shows screen-fit grid, slots fill one-by-one (~400 ms apart).
2. Meet intro for a cluster — same progressive reveal, no horizontal infinite scroll.

### 4. If photon p95 fails

Diagnostic session only — **no re-architect**. Profile main thread during rip; check for remaining double-upload (Fix 3 gap) or chrome invalidation (Fix 5 gap).

---

## Next session checklist

1. ⌥` HUD held-F rip on Mehendi ARWs — record decode/blit/wrap, GPU prefetch %, in→photon p95
2. Confirm Pick grid after "Pick from this set" — no spinners on cached thumbs
3. If p95 still fails, diagnostic session only — profile main thread during rip
4. Optional hardening: throttle `tierLabel` like filmstrip (inflight dedup in `MetalPreviewPool.upload` landed)

---

## 2026-08-05 — RAW develop engine foundation + Develop Lab

**Claim:** Replace unreliable JPEG-proxy editing with a unified RAW develop graph, immutable recipes, batch treatment, and an isolated `--develop-lab` before Workbench integration.

**Implemented:** `EditRecipe` / `PhotoEditBinding` / `BatchTreatmentSession` / `DevelopRenderGraph` (CIRAWFilter→CI) / `DevelopRenderScheduler` / `--develop-lab` UI / TIFF export hook / docs + deterministic tests.

**Linux verification:** `python3 Scripts/develop_engine_test.py` PASS. `xcodebuild` / live ARW **blocked** on Ubuntu cloud VM.

**Not done:** Workbench Edit integration (gated on live-RAW), measured perf/fidelity on Mac, GUI screenshots from real ARW.

---

## 2026-08-05 — Workbench live RAW editing, WB/denoise/heal, set consolidation

**Claim:** The workbench treatment stage now edits in real time through the RAW pipeline (scheduler + Metal, no CPU bitmap round trip), fixes the stale-preview bug (incomplete `renderKey` dropped temperature/tint/shadows changes), and adds the missing controls.

**Implemented:**
- `LiveDevelopView` — treatment leader routes through `DevelopRenderScheduler.scrub` → `DevelopMetalView` with honest fidelity chip (Interactive → Settling → Full preview / 1:1 RAW); proxy-graded fallback when RAW is offline. RAW session prewarms on stage open.
- `GradedPhotoView.renderKey` now uses the full recipe fingerprint + 30 ms coalescing — every slider re-renders rows too.
- White balance: preset grid (As Shot / Auto gray-world / Daylight / Cloudy / Shade / Tungsten / Fluorescent / Flash), temperature range widened to ±2000 K (was ±50, visually inert).
- Detail: RAW-domain Noise reduction + Sharpening sliders (offsets added to `DevelopAdjustments` with tolerant decoding).
- Erase/heal: clone-based `RetouchSpot` (persisted on `DevelopRecipe`, tolerantly decoded; runtime-carried on `EditRecipe`, in render fingerprints). Applies in RAW, proxy, and export paths — labeled clone heal, not generative fill. Heal-mode overlay with spot size, undo, clear.
- Apply-to-set: ⌘⇧A / button applies the leader's treatment to the whole family row (heal spots stay per-photo); receipt shown.
- Auto/taste calibration: `DevelopRecipe.lrCalibrated()` folds LR whites/blacks/clarity/dehaze into the trusted controls with documented factors and clamps to crs ranges; applied in `TasteRetriever`.
- Rows: singles/pairs merge into "Miscellaneous" rows (≤12), bucket cap 8→12; tiles 274→336 pt (480 pt two-up), compact strip 72→104 pt, decode sizes 480→768 / 1600→2048; neighbor prefetch warms displayed sizes.
- Buttons: `LuminaQuietButtonStyle` gains hover halo + press dip (reduce-motion aware); accessibility labels/hints/values on sliders, WB presets, stage switcher, pager, heal and set actions.

**Verification (this Mac):** `xcodebuild` Debug PASS. `--raw-harness` PASS — 0 failures; 16/16 unit checks (incl. 3 new clone-heal render checks), 6/6 XMP merge; scrub p50 14.5 ms / p95 16.6 ms, settled 191 ms, prepare 204 ms on DSC08242.ARW. `--capture-workbench artifacts/workbench-v3` — 7 captures incl. new treatment stage.
