# Amendment Batch 2 — proposal for human ratification

## Ratification decisions (2026-08-12)

| Item | Amendment | Decision |
|------|-----------|----------|
| **ITEM 1** — CONFLICT 4 closure (option 2) | **A11** / **R-I.4** | **RATIFIED** |
| **ITEM 2** — D66 beta channel | **A12** | **RATIFIED** |
| **ITEM 3** — A7 withdrawal | **A13** | **RATIFIED** |
| **ITEM 4** — install-page copy scope | (a / b / c) | **NOT RATIFIED** — no operator choice recorded |

**Status:** **A11–A13 RATIFIED** (2026-08-12) — applied to `design/contract-v6.md` and `design/tokens.yaml` on `constitution/batch-2-distribution`. ITEM 4 deferred.  
**Branch:** `constitution/batch-2-distribution`  
**Session:** B2.1 (proposal) · B2.2 (apply ratified items)

**Authority order reminder:** `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests. An audit doc (`docs/release/MACOS_RELEASE_READINESS_AUDIT.md`) sits below the contract and cannot justify departing from D66 — though it may inform engineering.

---

## Number space (derived from grep)

### A-numbers found in `design/contract-v6.md`

```
grep '\bA[0-9]+\b' design/contract-v6.md
```

| ID | Usage (summary) |
|----|-----------------|
| **A1** | D65 MVP test fleet |
| **A2** | D23 crop latch; D63 crop keys |
| **A3** | D47 pointer cull marks |
| **A4** | D21 Hold-J; D42 clipping hold |
| **A5** | D16 Adapt compression (scoped weakening) |
| **A6** | D64 swim-lane shelved + re-entry door |
| **A7** | D45 / R-9.1 TestFlight crash reporting exception (scoped weakening) |
| **A8** | D52 beta licensing NONE |
| **A9** | MVP success metrics (facilitator notes) |
| **A10** | D32 / D46 taste-model proving schedule |

Batch 1 spans **A1–A10** (contract header: “Amendment Batch 1 (A1–A10)”).

**Next free amendment batch:** **Batch 2**  
**Next free A-number:** **A11** (proposed assignments below: A11, A12, A13).

No A-number above A10 appears in the contract. **STOP** if any proposed ID collides — none do.

### R-numbers found in `design/contract-v6.md`

```
grep 'R-[0-9A-Z.-]+' design/contract-v6.md
```

| Lane | Found | Next free in lane |
|------|-------|-------------------|
| **R-5** | R-5.1, R-5.2, R-5.3 | **R-5.4** |
| **R-8** | R-8.1 | **R-8.2** |
| **R-9** | R-9.1 (scoped by A7) | **R-9.2** |
| **R-A** | R-A.1, R-A.2 | **R-A.3** |
| **R-X** | R-X.1, R-X.2 | **R-X.3** |
| **R-M** | R-M.1 … R-M.5 | **R-M.6** |
| **R-Q** | R-Q.1 | **R-Q.2** |
| **R-I** | R-I.1, R-I.2, R-I.3 | **R-I.4** |

Contract cites “Rulings R-5.1…R-Q.1” as integrated sources; no R-number above the table rows appears as a standalone ruling slot beyond those listed.

**Proposed ruling for ITEM 1 (optional record):** **R-I.4** — beta distribution channel (closes CONFLICT 4). Distribution lane is the natural home; R-9.x is diagnostics posture, not channel choice.

---

## Background

**CONFLICT 4** (prompt factory / BUILD_LOG): open collision between D45 zero-egress posture, frozen copy `nothing leaves this Mac`, and Batch-1 A7’s TestFlight crash-reporting exception. Wave engineering already ships **notarized Developer ID** artifacts with `betaDiagnostics: null` (F11.4 / F11.6); `docs/release/install-page-content-spec.md` documents that channel but **contradicts D66** (TestFlight) and **withholds** `nothing leaves this Mac` until CONFLICT 4 closes.

**`design/build-prompts/INDEX.md`:** not in tree at proposal time — §CONFLICTS text unavailable in-repo; CONFLICT 4 status taken from `BUILD_LOG.md` and standing preamble (option **2** = notarized Developer ID, not TestFlight).

---

## ITEM 1 — CONFLICT 4 closure (option 2)

**Proposed amendment:** **A11**  
**Optional ruling record:** **R-I.4**  
**Entry touched:** CONFLICT 4 register (prompt factory); cross-cites D45, D50, D66, R-9.1, R-I.1.

### Proposed text (for contract / BUILD_LOG on ratification)

> **CONFLICT 4 — CLOSED (A11 / R-I.4).** Beta and wave builds distribute as a **notarized Developer ID artifact** (zip or DMG), not Mac App Store TestFlight. There is **no Apple-side crash reporter** on the beta channel. D45 zero-egress posture and the first-wave distribution window **no longer collide**. TestFlight remains out of scope for MVP waves; MAS distribution stays deferred per D50.

### Strengthens / weakens

- **Strengthens:** D45 / R-9.1 coherence for wave builds; aligns law with F11 shipped posture (`betaDiagnostics: null`); removes need to defer sovereignty copy on the install page (follow-up, not automatic — see ITEM 3 / ITEM 4).
- **Weakens:** Nothing material — removes a hypothetical TestFlight path that engineering did not ship.

### What breaks if ratified

- Any document, prompt, or harness text that **requires** TestFlight for beta (D66 as written, A7, F11.6 “expires at 1.0” narrative tied to TestFlight reporter) must be updated in the **same ratification pass** (ITEM 2, ITEM 3).
- `design/build-prompts/` entries that assume TestFlight beta — rewrite or discard.
- Install-page spec hard ban on `nothing leaves this Mac` lifts **only after** ITEM 3 is ratified (exception withdrawn, not merely deferred).

---

## ITEM 2 — D66 beta channel amendment

**Proposed amendment:** **A12**  
**Entry touched:** **D66** — Beta distribution posture.

### Current text (contract-v6)

> Beta via TestFlight with A7 diagnostics exception (expires at 1.0). Wave builds free (A8). Launch = direct-notarized (D50) + local-only diagnostics (D45 restored) + R-I.3 licensing implemented post-test pre-launch.

### Proposed replacement (decision clause only)

> **Beta and wave builds** distribute via **notarized Developer ID artifact** (Developer ID Application signing, notarized, stapled — same family as D50 / R-I.1 direct distribution). Distribution surface: install page linking the current ship artifact and F11.4 build manifest fields. **No TestFlight.** **No Mac App Store beta.** Wave builds remain **free** (A8 — no license machinery). **Launch at 1.0** = direct-notarized (D50) + local-only diagnostics (D45 / R-9.1 in full) + R-I.3 licensing implemented post-test pre-launch.

### Explicit contradiction with committed spec

`docs/release/install-page-content-spec.md` already documents **G2: notarized zip/DMG**, cites F11.4 manifest fields, and excludes TestFlight / `betaDiagnostics`. That spec is **ahead of D66** and is **invalid as law** until this amendment ratifies — it is engineering + content-spec truth, not constitutional authority.

### Strengthens / weakens

- **Strengthens:** Single beta channel; matches F11 release-integrity harness and Developer ID MVP path; D50 and D66 no longer disagree.
- **Weakens:** Closes the TestFlight + A7 diagnostics branch entirely (see ITEM 3).

### What breaks if ratified

- D66 `[● A7]` change-mark must be removed or superseded; A7 withdrawal (ITEM 3) required in same batch.
- Copy and docs citing “beta via TestFlight” — including `design/mvp-test-plan.md` consent line tail “(diagnostics: see contract D45 / A7)” — need a **follow-up edit** (not in this proposal file).
- F11.6 gate semantics shift from “expire TestFlight reporter at 1.0” to “assert `betaDiagnostics` is null on all wave/beta builds” (ITEM 3 consequence).

---

## ITEM 3 — A7 withdrawal

**Proposed amendment:** **A13** (withdraw **A7**; restore D45 / R-9.1)  
**Entries touched:** **A7** (withdrawn), **D45** (remove A7 scoped exception), cross-cites D66, R-9.1, F11.6.

### Proposed text (D45 decision clause after withdrawal)

> Diagnostics are **local-only or absent**; reveal/send **manual only** — never automatic egress. **No beta-channel exception.** No TestFlight crash reporting. No third-party crash reporter bundled with wave builds. Manual reveal chrome remains OPEN if required — not invented here.

### A7 withdrawal statement

> **A7 — WITHDRAWN (A13).** The scoped amendment permitting TestFlight crash reporting for beta only **has no referent** once A12 ratifies notarized Developer ID beta. R-9.1 / D45 apply **in full** to beta, wave, and launch builds alike (subject only to future explicit amendments, not silent sockets).

### Strengthens / weakens

- **Strengthens:** R-9.1 / D45 — removes Batch-1 scoped weakening; makes `[○][P] nothing leaves this Mac` **truthful of wave builds** (no app-level or Apple-reporter egress on the shipped channel).
- **Weakens:** Removes the only Batch-1 escape hatch for automatic crash telemetry.

### Consequences (follow-ups — not changed in this proposal)

1. **Install page:** After ratification, the install-page content spec **may** carry `nothing leaves this Mac` — operator choice whether to add it to distribution surfaces (ITEM 4).
2. **F11.6 (`f11_a7_expiry.py`):** Mechanism becomes an **assertion that `betaDiagnostics` is null** in every wave/beta manifest, not an expiry gate for a TestFlight reporter at 1.0. At marketing version ≥ 1.0, non-null `betaDiagnostics` remains **FAIL** (unchanged outcome, different rationale).
3. **`BetaDiagnosticsSocket.swift`:** Stays `activeKind == nil`; A7 cite removed from manifest socket on ratification pass.
4. **Batch-1 “two scoped weakenings” header** (A5 + A7): becomes **A5 only** after A7 withdrawal — ratification edit to contract preamble.

### What breaks if ratified

- Any test, doc, or consent string that cites **A7** as live beta diagnostics law.
- Harness prose tying F11.2 zero-network check to “CONFLICT 4 / A7” — reword to CONFLICT 4 **closed** / zero egress **restored**.

---

## ITEM 4 — Install-page `[NEW]` strings: scope question (no decision)

**Context:** `docs/release/install-page-content-spec.md` flags ~20 strings as `[NEW — contract entry owed]`. `design/copy-contract.txt` governs product copy; header says banned words apply “user-visible, everywhere” but lint (`copy_contract_diff.sh`) targets **app** `CopyContract` literals, not a web page.

### Option (a) — Distribution section inside `copy-contract.txt`

| | |
|---|---|
| **Mechanism** | New `## DISTRIBUTION` section; same authority line as app strings. |
| **Cost** | Mixes app table law with web/install copy; extends “everywhere” to distribution; single lint path but CopyContract.swift coupling becomes ambiguous for web-only lines. |
| **Benefit** | One home; one diff gate if lint is extended. |

### Option (b) — Sibling `design/copy-contract-distribution.txt`

| | |
|---|---|
| **Mechanism** | Parallel file with its own authority line: `design/contract-v6.md` → sibling → install page / host. |
| **Cost** | Second file to read; needs its own lint or section in `copy_contract_diff.sh`; banned-word list must be duplicated or imported by reference. |
| **Benefit** | Clean separation — app UI vs first-touch distribution; install page stays out of `CopyContract.swift`; still governed copy. |

### Option (c) — Explicitly outside copy contract

| | |
|---|---|
| **Mechanism** | Install page copy is operator/marketing prose; no contract row. |
| **Cost** | **Cheapest and riskiest** — no mandatory review for the words a stranger reads first; banned-word and sovereignty drift undetected; contradicts agent contract habit of tracing every user-facing string. |
| **Benefit** | Zero schema work; ship page immediately. |

### Recommendation (operator may override): **(b)**

Distribution is not app UI; strangers encounter it before the table. It still needs banned-word and sovereignty discipline — especially if ITEM 3 ratifies and `nothing leaves this Mac` may appear on the page. A sibling file preserves separation without orphaning distribution copy from the constitution stack. Extend lint in the ratification **implementation** pass, not in this proposal.

**This proposal does not ratify (b).** Operator chooses at Batch 2 seal.

**B2.2 apply (2026-08-12):** ITEM 4 **not ratified** — no `(a)`, `(b)`, or `(c)` line recorded. No distribution copy home created. Install-page `[NEW]` strings remain uncontracted.

---

## Report only (do not fix in B2.1)

### 1. `design/tokens.yaml` version vs embedded manifest

| Fact | Value |
|------|-------|
| `design/tokens.yaml` `version` on `origin/main` | **`6.1-batch1`** |
| F11.4 embed field | `contractVersion` ← tokens.yaml `version` at build time |
| Example ship manifest (F11 branch) | cited `6.2-motion-seal` from unmerged motion work — **not** on main tokens |

**Sequencing consequence:** Ratifying Batch 2 requires bumping `design/tokens.yaml` version (e.g. `6.2-batch2`) and regenerating codegen. **Every artifact built before that bump** carries a stale `contractVersion` in `LuminaBuildManifest.json`. Bug reports and install-page `bugReportLine` from pre-ratification builds will not match sealed law until testers reinstall a post-ratification build. Rollback artifacts (F11.5) retain old manifest JSON — expected; document in operator checklist.

### 2. Dangling reference in install-page spec

`docs/release/install-page-content-spec.md` (committed on main via F11 PR) cites **`docs/release/MACOS_RELEASE_READINESS_AUDIT.md`** as evidence for G2 channel choice. That audit file is **untracked / not on main** — a committed doc pointing at absent law-adjacent prose.

**Better anchor after ITEM 1:** ratified **A11 / R-I.4** and amended **D66** — not the audit doc. Audit may remain engineering input; it cannot justify departing from D66 per authority order.

**Follow-up on ratification:** Either commit the audit as non-authoritative reference or remove the citation from the install-page spec in favor of contract cites.

---

## Ratification checklist (human — not executed here)

- [ ] Operator approves A11, A12, A13 and ITEM 4 choice
- [ ] Edit `design/contract-v6.md` (D45, D66; withdraw A7; close CONFLICT 4)
- [ ] Bump `design/tokens.yaml` version; run codegen
- [ ] Update `design/copy-contract.txt` or add distribution sibling per ITEM 4
- [ ] Update `docs/release/install-page-content-spec.md` (authority cites, optional `nothing leaves this Mac`)
- [ ] Update F11.6 rationale strings; mvp-test-plan consent footnote
- [ ] Rebuild and ship manifest with new `contractVersion`
- [ ] BUILD_LOG entry for Batch 2 seal

---

## CONFLICT blocks

**None.** All four items amend or question entries explicitly in scope (CONFLICT 4, D66, A7/D45, distribution copy scope). No draft text contradicts an untouched decision key, shelf law, or Batch-1 item outside the named set.
