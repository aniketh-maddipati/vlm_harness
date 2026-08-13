# RESUME

**Measured @ `main` `a565c2e` · 2026-08-13 · Linux FAST **PASS** ~6262ms, **33/33** orchestration ids**

Authority order: `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests.  
Strategy source (W4, on main): `design/strategy/s1-mvp-sharpening.md` (#44). Batch 3 proposal (not ratified): `design/amendments/proposal-batch-3.md` (#43).

---

## 1. WHERE THINGS STAND

`main` @ `a565c2e` is the integration tip; tracked tree is clean except untracked local worktrees under `lumina-wt/`. **Landed this cascade:** SPIKE B motion seal (P7, `tokensHash` `666762f7…`), CP2 persistence + F06 (P5), P8 surface sweep (#43/#44 docs: Batch 3 proposal + S1 MVP sharpening). Prior merges still on main: F04 (#40), F11 (#41), Batch 2 (A11–A13), P0 stack (#23–#25), CP7 propagation (W2 **SHELF-BROKEN**). Superseded PRs #36–#39 **closed**. Linux FAST **green** (33/33 orchestration). FULL/HEAVY app-coupled tests **UNMEASURED** on macOS — only PLATFORM-UNAVAILABLE on Linux in BUILD_LOG.

---

## 2. OPEN GATES

Each gate: blocker → who clears.

| Gate | Blocker | Who clears |
|------|---------|------------|
| **CONFLICT 2 (H1 absent)** | App-coupled live suite open (`design/build-prompts/INDEX.md` §CONFLICT 2). Measured on this Linux host: FULL → PLATFORM-UNAVAILABLE (exit 2), **0 / 7** app tests; live drivers STUB-owned (CP4 / CP7 / SPIKE A / HEAVY). “H1 absent” = **macOS Apple Silicon host absent** here. *(If read as hi-fi H1: `origin/hifi/h1-copy` is an ancestor of main — merged, not blocking.)* | Operator on macOS AS 14+ runs `bash Scripts/regression.sh pre-merge` and records wall time + app-test counts in BUILD_LOG |
| **F04's macOS FULL run** | F04 merged (#40); BUILD_LOG lists only Linux PLATFORM-UNAVAILABLE readings (106–130 ms, 0/7). macOS pre-merge wall time, cache hit/miss, and F04.1 `build-for-testing` reuse **UNMEASURED** on ship host | Operator on macOS AS runs pre-merge FULL after granting Xcode + Automation |
| **macOS automation mode not enabling** | DEBUG `--ui-testing` / `LUMINA_UI_TEST_MODE` can fail when XCUITest leaves app backgrounded → collapsed accessibility tree (`docs/P0_UI_AUTOMATION_POSTMORTEM.md` §3, §9). Self-heal + auto-open landed; repro under active desktop use documented | macOS operator: pre-grant Accessibility + Automation for test runner; engineering if still reproduces on idle Mac |
| **D67 ratification** | No `### D67` in `design/contract-v6.md`; Batch 3 proposal **merged (#43) but NOT RATIFIED** (`design/amendments/proposal-batch-3.md`). CP7 code ships under law not in force (W4 RISK-004) | Human operator: ratify or reject Batch 3 ITEM 1 (A14 / R-A.3 / D67); ITEM 2 operator choice (narrow code vs widen proposal) still undecided |
| **R3 before Wave 0** | P7 moved `tokensHash` to `666762f7…` (`6.2-motion-seal`). Any DMG cut before R3 embeds stale hash/version in `LuminaBuildManifest.json` | Operator: re-run `run_f11_release.py` + manifest embed before Wave 0 ship cut |
| **CP2 → F12** | **CP2 landed (P5)** — journal, sidecars, F06 data-safety on Linux FAST. **F12** / F12.3 bug-report bundle **not shipped** (`docs/release/install-page-content-spec.md`); macOS kill-fuzz / LR round-trip **UNMEASURED** | macOS operator validates CP2 app-coupled paths; F12 session after Wave 0 diagnostic |
| **F11's three Batch-2 follow-ups** | (1) **F11.6** — **landed** (`f11_a7_expiry.py` null assertion on all wave/beta builds, D45/A13). (2) **F11.3** — Developer ID + notarize + **staple** `.app` (ad-hoc FAIL in BUILD_LOG). (3) **Install-page spec** — Batch 2 ITEM 4 **NOT RATIFIED** (operator choice a/b/c for copy home); dangling audit citation | Engineering for F11.3 on macOS ship host; operator for ITEM 4 copy scope |

---

## 3. CRITICAL PATH

*From W4 `design/strategy/s1-mvp-sharpening.md` PART 1 — MVP sharpening implications + `design/checkpoint-sequence-v6.md` Layer-2 order. Status from W4 existence matrix on `main`.*

```
Constitutional gate (Batch 3 / D67 ratification — proposal merged #43, NOT RATIFIED)
    ↓
SPIKE A fidelity ladder          PARTIAL
SPIKE B table physics / F07 seal SHIPPED (P7 — F07.4–F07.6 green on Linux)
CP1  layout                       SHIPPED
CP2  journal + sidecars + kill-fuzz SHIPPED (P5 — Linux FAST green; macOS UNMEASURED)
CP3  device ingest / six-body     PARTIAL
CP4  cull hot loop + pointer marks SHIPPED
CP5  edit rail (10 controls)      PARTIAL
CP6  focused edit + crop latch    PARTIAL
CP7  hero intent propagation      SHIPPED (law NOT IN FORCE — no ratified D67)
CP8  export / endgame             PARTIAL (F12 bundle absent)
```

W4 implications (carried verbatim in substance):

1. Do not treat D67 as settled contract when prioritizing work or closing coverage gaps.
2. Existence ≠ enforcement for CP7 until Batch 3 seal or explicit rejection.
3. SHELF-BROKEN (RISK-001) and D36-VIOLATION (RISK-002) remain live — schedule remediation or explicit amendment; S1 did not choose.
4. Next constitutional act: human **ratification** of `design/amendments/proposal-batch-3.md` (merged #43 — proposal ≠ ratified law).

**Next single action:** macOS automation-mode **diagnostic** (see §6 queue item 1) — not a build session; every app-coupled assertion is gated until it passes.

---

## 4. DO NOT TOUCH WITHOUT A RULING

- **`design/contract-v6.md`** — ratified law (Batch 1 A1–A10, Batch 2 A11–A13). No self-ratification; no build-session D67 inserts.
- **`design/copy-contract.txt`** — frozen user-visible strings; new committed copy requires an entry here first.
- **`design/tokens.yaml` version and §motion`** — version **`6.2-motion-seal`** on main (`tokensHash` `666762f7…`). Edits require `python3 Scripts/harness/codegen/tokens_codegen.py` + `--check` and invalidate F07/F11/F04 artifact keys until re-measured.
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
| **2** | **R3 — F11 release re-measure** | P7 moved `tokensHash`; F11.4 manifest, F04.1 cache, chrome goldens keyed to old hash are **stale** until R3 runs on ship host | **Release session** — `run_f11_release.py` + manifest embed; required before Wave 0 |
| **3** | **CP2 macOS validation** | P5 landed on Linux FAST; journal kill-fuzz / LR round-trip / app-coupled persistence **UNMEASURED** on macOS | **Diagnostic + measurement** on macOS AS after queue item 1 |
| **4** | **D67 ratification** | CP7 code **SHIPPED**; law **NOT IN FORCE** (no `### D67` in contract). Proposal merged #43 — **NOT RATIFIED**. W4 RISK-001/004 live. | **Constitution session** — ratify/reject Batch 3 ITEM 1 (A14 / R-A.3); ITEM 2 operator choice still open |

**Queue rule:** Item 1 must pass before trusting any macOS measurement. Item 2 (R3) must close before Wave 0 ship cut. Item 4 is human ratification — proposal on main ≠ law in force.

---

## 7. WHAT I WOULD DO NEXT

*(Subordinate to §6 queue.)*

1. **Run macOS automation diagnostic** — confirm `[UITestLaunch] ui-testing active` on stderr, probe visible, `P0Fast` ≥1 flow green on an idle Mac; log pass/fail in BUILD_LOG. Reason: gates every downstream app-coupled claim.
2. **Schedule R3** — re-run F11 release with current `tokensHash` before any Wave 0 DMG cut.
3. **Ratify Batch 3** — `design/amendments/proposal-batch-3.md` is on main (#43); operator ratifies/rejects ITEM 1 before treating D67 as settled.
