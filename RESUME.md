# RESUME

**Measured @ `main` `228175c` · 2026-08-13 · Linux pre-commit: exit **1**, FAST **INCOMPLETE** ~5050ms, **26/27** orchestration ids**

Authority order: `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests.  
Strategy source (W4, not on main): `design/strategy/s1-mvp-sharpening.md` on branch `strategy/s1-mvp-sharpening` @ `ce677f6`.

---

## 1. WHERE THINGS STAND

`main` @ `6652c65` (“Merge P0 single-photo RAW editing onto main #25”) is the integration tip; tracked tree is clean except untracked local worktrees under `lumina-wt/`. Merged on main: F04 (#40), F11 (#41), Batch 2 constitution (A11–A13), P0 UI automation (#23 path), P0 UX hardening (#24), P0 single-photo RAW editing (#25), CP7 propagation machinery (`PropagationState`, `WorkbenchSelection`, cross-row selection — W2 **SHELF-BROKEN**), and hi-fi passes h1–h8 (all are ancestors of main). **Not merged:** `constitution/batch-3-propagation` (`design/amendments/proposal-batch-3.md` — Batch 3 / D67 proposal only) and `strategy/s1-mvp-sharpening` (W4 existence/enforcement matrices). Superseded open PRs #36–#39 (F0–F03 reconstruction) remain open on GitHub; operator close failed (integration lacks `closePullRequest`). FAST pre-commit on Linux is **red**: four orchestration failures (`banned_patterns` D48 hover in `P0SinglePhotoEditor.swift:356`, `contract_v6_presence`, missing `Scripts/harness/tests/test_f07_spring_physics.py`, stale `constitution_coverage`). FULL/HEAVY have **never** run app-coupled tests on a measured macOS host in BUILD_LOG — only PLATFORM-UNAVAILABLE on Linux.

---

## 2. OPEN GATES

Each gate: blocker → who clears.

| Gate | Blocker | Who clears |
|------|---------|------------|
| **CONFLICT 2 (H1 absent)** | App-coupled live suite open (`design/build-prompts/INDEX.md` §CONFLICT 2). Measured on this Linux host: FULL → PLATFORM-UNAVAILABLE (exit 2), **0 / 7** app tests; live drivers STUB-owned (CP4 / CP7 / SPIKE A / HEAVY). “H1 absent” = **macOS Apple Silicon host absent** here. *(If read as hi-fi H1: `origin/hifi/h1-copy` is an ancestor of main — merged, not blocking.)* | Operator on macOS AS 14+ runs `bash Scripts/regression.sh pre-merge` and records wall time + app-test counts in BUILD_LOG |
| **F04's macOS FULL run** | F04 merged (#40); BUILD_LOG lists only Linux PLATFORM-UNAVAILABLE readings (106–130 ms, 0/7). macOS pre-merge wall time, cache hit/miss, and F04.1 `build-for-testing` reuse **UNMEASURED** on ship host | Operator on macOS AS runs pre-merge FULL after granting Xcode + Automation |
| **macOS automation mode not enabling** | DEBUG `--ui-testing` / `LUMINA_UI_TEST_MODE` can fail when XCUITest leaves app backgrounded → collapsed accessibility tree (`docs/P0_UI_AUTOMATION_POSTMORTEM.md` §3, §9). Self-heal + auto-open landed; repro under active desktop use documented | macOS operator: pre-grant Accessibility + Automation for test runner; engineering if still reproduces on idle Mac |
| **D67 ratification** | No `### D67` in `design/contract-v6.md`; Batch 3 proposal **NOT RATIFIED** (`design/amendments/proposal-batch-3.md` on `constitution/batch-3-propagation` only). CP7 code ships under law not in force (W4 RISK-004) | Human operator: ratify or reject Batch 3 ITEM 1 (A14 / R-A.3 / D67); ITEM 2 operator choice (narrow code vs widen proposal) still undecided |
| **SPIKE B seal** | F07.4 dead-stop drift: \|value − 1\| = **0.001105** > `spring_dead_stop_epsilon` **0.001** (BUILD_LOG 2026-08-12). `Scripts/harness/tests/test_f07_spring_physics.py` **absent** → FAST `spring_physics_f07` FAIL. HARNESS.md marks F07.4–F07.6 closed; tree contradicts | Engineering: restore F07 test module + fix sampler convergence or obtain ruling to re-seal `design/tokens.yaml` §motion |
| **CP2 → F06 → F12** | **CP2** sidecar / kill-fuzz **NOT BUILT** (W4 existence matrix). P0 writes catalog `shoot.json` — W2 **D36-VIOLATION** (RISK-002). **F06** build prompt **UNMEASURED** (not in `design/build-prompts/`). **F12** / F12.3 bug-report bundle **not shipped** (`docs/release/install-page-content-spec.md`) | CP2 checkpoint session (F06 prompt emission + implementation) before F12; operator sequences after Batch 3 ruling on persistence scope |
| **F11's three Batch-2 follow-ups** | (1) **F11.6** — assert `betaDiagnostics` null on wave builds (semantics updated post-A13; follow-up on F11 branch per BUILD_LOG). (2) **F11.3** — Developer ID + notarize + **staple** `.app` (ad-hoc FAIL in BUILD_LOG). (3) **Install-page spec** — Batch 2 ITEM 4 **NOT RATIFIED** (operator choice a/b/c for copy home); dangling audit citation | Engineering for F11.3/F11.6 on macOS ship host; operator for ITEM 4 copy scope |

---

## 3. CRITICAL PATH

*From W4 `design/strategy/s1-mvp-sharpening.md` PART 1 — MVP sharpening implications + `design/checkpoint-sequence-v6.md` Layer-2 order. Status from W4 existence matrix on `main`.*

```
Constitutional gate (Batch 3 / D67 ratification — proposal only, NOT RATIFIED)
    ↓
SPIKE A fidelity ladder          PARTIAL
SPIKE B table physics / F07 seal PARTIAL (seal drift + missing test file)
CP1  layout                       SHIPPED
CP2  journal + sidecars + kill-fuzz NOT BUILT  ← D36-VIOLATION live (catalog writes)
CP3  device ingest / six-body     PARTIAL
CP4  cull hot loop + pointer marks SHIPPED
CP5  edit rail (10 controls)      PARTIAL (hover debt)
CP6  focused edit + crop latch    PARTIAL
CP7  hero intent propagation      SHIPPED (law NOT IN FORCE — no ratified D67)
CP8  export / endgame             PARTIAL (F12 bundle absent)
```

W4 implications (carried verbatim in substance):

1. Do not treat D67 as settled contract when prioritizing work or closing coverage gaps.
2. Existence ≠ enforcement for CP7 until Batch 3 seal or explicit rejection.
3. SHELF-BROKEN (RISK-001) and D36-VIOLATION (RISK-002) remain live — schedule remediation or explicit amendment; S1 did not choose.
4. Next constitutional act: human ratification of `design/amendments/proposal-batch-3.md` (branch `constitution/batch-3-propagation`).

**Next single action:** macOS automation-mode **diagnostic** (see §7 queue item 1) — not a build session; every app-coupled assertion is gated until it passes.

---

## 4. DO NOT TOUCH WITHOUT A RULING

- **`design/contract-v6.md`** — ratified law (Batch 1 A1–A10, Batch 2 A11–A13). No self-ratification; no build-session D67 inserts.
- **`design/copy-contract.txt`** — frozen user-visible strings; new committed copy requires an entry here first.
- **`design/tokens.yaml` version and §motion`** — version **`6.2-batch2`** on main; §motion sealed at SPIKE B (`6.2-motion-seal` params in BUILD_LOG). Edits require `python3 Scripts/harness/codegen/tokens_codegen.py` + `--check`.
- **Shelved Register** — `design/contract-v6.md` §Shelved Register (v6): multi-select, two-up, gather-drag, cross-row compatibility, Tier 1/Develop banked on taste proof, etc. Code currently **exceeds** shelf (W2 Q1); narrowing or un-shelving requires explicit register amendment.

---

## 5. PLAYGROUND RULES

Hand experimentation only — not merge gates.

- Scratch branch off **`main`**, never a feature branch with an open PR.
- Run `bash Scripts/regression.sh pre-commit` **before you start** and **before you stop**; green-then-red means the diff is yours, not a mystery baseline.
- `tokens.yaml` edits require codegen and its `--check` lint; a magic number in UI code is a compile failure by design.
- A new user-facing string needs a `copy-contract.txt` entry before it is committed; experimenting freely is fine, committing is not.
- To recover: `git stash` → confirm pre-commit green → unstash → bisect your own change.

---

## 6. ONE-OFF QUEUE

*Operator sequence after wrap-up cascade. Supersedes ad-hoc “do next” lists. Each item: measured fact → why it blocks → session type.*

| # | Item | Blocks | Session type |
|---|------|--------|--------------|
| **1** | **macOS automation mode** | Every app-coupled assertion — F04 FULL, F07 live/motion, F11 Release `.app` checks, all XCUITest flows (`P0Fast` / stress / visual). DEBUG `--ui-testing` / `LUMINA_UI_TEST_MODE` (`Lumina/Testing/UITestLaunch.swift`) must activate; backgrounded-app collapsed tree documented (`docs/P0_UI_AUTOMATION_POSTMORTEM.md` §3, §9). **Failed twice** (operator report — no BUILD_LOG row yet). | **Diagnostic only** — reproduce, capture TCC/activation/probe evidence; **not** a build session |
| **2** | **CP2** — journal, sidecars, crash-only startup | **Long pole.** D36 open-XMP / no-catalog (W2 **D36-VIOLATION**, RISK-002). **F06** prompt **UNMEASURED** (not in `design/build-prompts/`). **F12** bug-report bundle and HEAVY kill-fuzz / LR round-trip (`Scripts/harness/heavy/run_job.py` → HEAVY/CP2) sit behind CP2. P0 today: `ShootStore.saveShoot` → catalog `shoot.json`. | **Checkpoint build session** (single CP2 owner) |
| **3** | **SPIKE B** — S18 → S19 → seal → S20 | **Before artifact hardening** — seal edits `design/tokens.yaml` §motion → **`tokensHash`** changes → F11.4 manifest, F04.1 build cache key, golden trajectories all invalidate until re-measured. Measured on main: F07.4 dead-stop drift **0.001105** > ε **0.001**; `test_f07_spring_physics.py` **absent**; FAST `spring_physics_f07` FAIL. **S19** = Develop Lab playground (`--develop-lab`, `hook_inventory.yaml` `s19_playground`) — on main. **S18**, **S20** = operator session labels — **UNMEASURED** in tree (no BUILD_LOG / prompt rows). `Lumina/Testing/MotionProbe/` **absent** on main (F07 motion-probe hook registered, not shipped). | **SPIKE sessions** S18–S20 then seal ruling on §motion |
| **4** | **D67 ratification** | CP7 code **SHIPPED**; law **NOT IN FORCE** (no `### D67` in contract). W4 RISK-001/004 live. | **Constitution session** — **after W3 proposal is in front of operator:** `design/amendments/proposal-batch-3.md` on `constitution/batch-3-propagation` (Batch 3 / B3.1, **NOT RATIFIED**). Ratify/reject ITEM 1 (A14 / R-A.3); ITEM 2 operator choice still open |

**Queue rule:** Item 1 must pass before trusting any macOS measurement for items 2–3. Item 3 must close (including `tokensHash` re-measure) before F11.3/F11.4 artifact hardening. Item 4 waits on W3 proposal review — not before.

---

## 7. WHAT I WOULD DO NEXT

*(Subordinate to §6 queue.)*

1. **Run macOS automation diagnostic** — confirm `[UITestLaunch] ui-testing active` on stderr, probe visible, `P0Fast` ≥1 flow green on an idle Mac; log pass/fail in BUILD_LOG. Reason: gates every downstream app-coupled claim.
2. **Do not start CP2 or SPIKE B build sessions** until diagnostic item 1 is green or failure mode is named with evidence.
3. **Surface W3 proposal to operator** — merge or PR `constitution/batch-3-propagation` so `proposal-batch-3.md` is reviewable before queue item 4.
