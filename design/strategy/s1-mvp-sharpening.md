# S1 — MVP sharpening (strategy session)

**Branch:** `strategy/s1-mvp-sharpening` · **Base:** `origin/main` @ `6652c65`  
**Authority:** `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests  
**Session id:** S1.1  
**Purpose:** Sharpen MVP scope — what exists, what law enforces it, and what risks remain live before the next build wave.

---

## ADDENDUM (pre-PART 1) — Batch 3 / W2 / D67

*Read before PART 1. Sources: `design/amendments/proposal-batch-3.md` (Batch 3 proposal, **NOT RATIFIED**), W2 read-only audit on `main` @ `6652c65`.*

### D67 status rule

**D67 is IMPLEMENTED BUT NOT RATIFIED.** Treat it as follows in every matrix below:

| Matrix | D67 / CP7 intent propagation row |
|--------|----------------------------------|
| **Existence** | **SHIPPED** — propagation machinery is in-tree (see evidence); build-session `IntentPropagation.swift` / `LocalIntentPropagationEngine` on external worktree is **additional** unmerged implementation, not required to mark SHIPPED |
| **Enforcement** | **Citing law not in force** — no `### D67` in `design/contract-v6.md`; no `[● A14]` change-mark; proposal Batch 3 **NOT RATIFIED** |
| **Contract** | **Not settled** — do not treat D67 as constitutional law; do not close gaps by assuming Batch 3 seal |

**Existence evidence (grepped on `strategy/s1-mvp-sharpening`):**

| Artifact | Path | Notes |
|----------|------|-------|
| Wholesale propagation rings | `Lumina/Core/PropagationState.swift` | row → scene → shoot widen/narrow |
| Staging + member sync | `Lumina/Shell/WorkbenchSelection.swift` | `stageTreat`, `syncPropagationMembers` |
| Cross-row hand selection | `Lumina/Core/TablePhotographSelection.swift` | rubber-band, ⇧-extend |
| Shell wiring | `Lumina/Shell/LuminaShellModel.swift` | `stageTreatAtRow`, `widenPropagation` |
| Batch edit command model | `Lumina/Models/P0State.swift` | `BatchEditCommand` |
| Logic tests | `LuminaLogicTests/PropagationTests.swift`, `P0LogicTests.swift` | ring + cross-row |
| **Absent from fetched refs** | `Lumina/Develop/IntentPropagation.swift` | build-session file; external worktree per BUILD_LOG |

**Enforcement evidence:**

```
grep -rn '\bD67\b' --include='*.swift' --include='*.py' .
→ (no Swift/Python hits)

grep '\bD67\b' design/contract-v6.md
→ (no matches)
```

Only `BUILD_LOG.md` audit prose references D67 — **not in-force law**.

### W2 findings — carry as **live risks** (not resolved)

W2 verdicts are **not** closed by this strategy session. They appear in **RISK REGISTER** below as **OPEN / LIVE**.

| W2 Q | Verdict | Live-risk summary |
|------|---------|-------------------|
| Q1 | **SHELF-BROKEN** | Persistent cross-row multi-select / rubber-band exceeds D29/D38 shelved register |
| Q2 | **D36-VIOLATION** | P0 recipe persistence to catalog `shoot.json` vs D36 open-XMP / no-catalog |
| Q3 | probe gap | `probe_growth` vacuous green; `.grouping` route invisible to probe |

### Batch 3 pointer

| Item | Status |
|------|--------|
| **A14 / R-A.3 / D67** proposal | `design/amendments/proposal-batch-3.md` on branch `constitution/batch-3-propagation` — **PROPOSAL ONLY** |
| ITEM 2 (narrow code vs widen proposal) | **Operator choice not made** |

---

## PART 1 — Existence matrix

**Legend:** **SHIPPED** = runnable code on branch · **PARTIAL** = subset live / legacy shell only · **STUB** = harness owner only · **BANKED** = contract gate · **SHELVED** = register row · **NOT BUILT**

| ID | Surface / checkpoint | Existence | Primary paths / notes |
|----|----------------------|-----------|------------------------|
| **CP0** | Harness (FAST/FULL/HEAVY) | **SHIPPED** | `Scripts/harness/`, `HARNESS.md` |
| **SPIKE A** | Fidelity ladder evidence | **PARTIAL** | Develop engine + P0 edit; signpost gate STUB |
| **SPIKE B** | Table physics / F07 seal | **PARTIAL** | `spring_physics_f07` manifest id; seal drift FAIL on Linux |
| **CP1** | P0 layout / contact sheet | **SHIPPED** | `Lumina/Views/P0/`, XCUITest P0Fast |
| **CP2** | Sidecar persistence / kill-fuzz | **NOT BUILT** | F06 absent; catalog writes exist (see RISK-002) |
| **CP3** | Device ingest / six-body fixtures | **PARTIAL** | Import pipeline; six-body fixtures registered not complete |
| **CP4** | P0 cull hot loop + pointer marks | **SHIPPED** | `P0SessionModel`, cull grammar machine, A3 marks partial |
| **CP5** | Edit rail (10 controls, arming) | **PARTIAL** | P0 adjustment rail; legacy shell hover STUB debt |
| **CP6** | Focused edit + crop latch | **PARTIAL** | `P0SinglePhotoEditor`, `P0CropControls`; crop latch A2 incomplete |
| **CP7** | Hero intent propagation | **SHIPPED** | `PropagationState`, `WorkbenchSelection`, wholesale staging — **maps to unratified D67** |
| **CP7-D67** | **D67 intent propagation (proposed)** | **SHIPPED** | Same as CP7 row — **existence ≠ ratified law** (ADDENDUM) |
| **CP8** | Export / endgame / rejects-to-Trash | **PARTIAL** | Export service; R-M.1 Trash offer not endgame-complete |
| **P0-edit** | Single-photo RAW editing | **SHIPPED** | Merged #25; `docs/P0_EDITING.md` |
| **F04** | Fast-lane hardening | **SHIPPED** | Merged #40 |
| **F11** | Release integrity | **SHIPPED** | Merged #41; follow-ups open |
| **Batch 2** | Distribution / diagnostics | **SHIPPED** | A11–A13 ratified in contract |
| **Batch 3** | D67 ratification | **NOT BUILT** | Proposal only — **do not mark SHIPPED for law** |
| **D29/D38** | Multi-select + two-up | **SHELVED** | Code **exceeds shelf** (W2 SHELF-BROKEN) — see RISK-001 |
| **D46** | Develop / Tier 1 taste gate | **BANKED** | Tier 2 P0 edit ships; Tier 1 gated |

---

## PART 1 — Enforcement matrix

**Legend:** **IN FORCE** = ratified v6 (or v5 carry) · **PROPOSED** = Batch 3 only · **NOT IN FORCE** = cited but unratified · **SHELVED** = must not ship without ruling · **STUB** = harness placeholder only

| Law / gate | Cited by | In force? | Harness / test gate | Gap |
|------------|----------|-----------|---------------------|-----|
| **D67** (intent propagation) | BUILD_LOG audit; CP7 code comments (implicit) | **NOT IN FORCE** | None named `D67` | Proposal Batch 3 / A14 |
| **D13–D19** (v5 §4 hero) | CP7 implementation; v5 carry | **PARTIAL** (v5 carry + v6 fragments D16/D60/D62) | Oracle unit only for grammar seeds | No D14/D15/D17/D18 harness hub |
| **D29 / D38** (multi-select shelved) | Shelved register | **IN FORCE (shelf)** | None — shelf is negative law | **Code violates shelf** (RISK-001) |
| **D36** (no catalog / open XMP) | v6 carry | **IN FORCE** | `constitution_coverage` (stale) | **P0 catalog write** (RISK-002) |
| **D47 / A3** (pointer cull) | v6 | **IN FORCE** | P0 UI tests partial | FULL live driver STUB CP4 |
| **D63 / A2** (crop latch) | v6 | **IN FORCE** | Partial logic | CP6 incomplete |
| **D66 / A12** (beta channel) | v6 | **IN FORCE** | F11 release lane | Install-page ITEM 4 open |
| **probe_growth** (F03.1) | FAST manifest | **IN FORCE** | `probe_growth` lint | Vacuous pass + route gap (RISK-003) |
| **CP7 live invariants** | HARNESS STUB register | **STUB** | `run_live_invariants.py` owned-by-CP7 | No macOS live run here |

**D67 enforcement row (explicit):**

> **D67** · Cited by: BUILD_LOG (build-session routing) · **Citing law not in force** · No Swift/test `@ D67` citations · Ratification path: `design/amendments/proposal-batch-3.md` ITEM 1 (A14 / R-A.3) — **NOT RATIFIED**

---

## RISK REGISTER (live — not resolved)

| ID | Source | Severity | Status | Description | Mitigation paths (not chosen in S1) |
|----|--------|----------|--------|-------------|-------------------------------------|
| **RISK-001** | W2 Q1 **SHELF-BROKEN** | **HIGH** | **LIVE** | `TablePhotographSelection.rubberBand`, ⇧-extend, and `P0SessionModel.selectClick` ⇧-range keep persistent membership after release while D29/D38 shelved register forbids multi-select / two-up. CP7 wholesale `syncPropagationMembers` rewrites scope persistently during staging. | (a) Narrow code to Batch 3 ITEM 1 row-only ephemeral staging · (b) Batch 3+ explicit un-shelf rulings |
| **RISK-002** | W2 Q2 **D36-VIOLATION** | **HIGH** | **LIVE** | P0 `commitRecipeMutation` → `ShootStore.saveShoot` → `~/Library/Application Support/Lumina/projects/<shoot>/shoot.json`. CP2 sidecar / kill-fuzz (F06) not landed. Deleting Lumina would lose recipes not in open XMP beside files. | (a) CP2 journal + sidecar path · (b) Interim catalog with explicit D36 amendment (Batch 3 ITEM 2 option b — **not proposed here**) |
| **RISK-003** | W2 Q3 probe gap | **MEDIUM** | **LIVE** | `probe_growth` OK on clean tree without diff; P0 merge added `focusedRecipeFingerprint` but `.grouping` route reports as `"contactSheet"`. Green lint can mask ungrown probe. | Regenerate probe contract for CP6/CP7 surfaces; add route case for grouping |
| **RISK-004** | Batch 3 / D67 | **HIGH** | **LIVE** | CP7 hero code **SHIPPED** under **no ratified D67**. Implementation may exceed proposed row-only scope (ring widen scene/shoot; cross-row selection). **Not settled contract.** | Ratify Batch 3 ITEM 1 before citing D67 in code; or strip/gate CP7 paths until seal |
| **RISK-005** | Checkpoint discipline | **MEDIUM** | **LIVE** | BUILD_LOG: CP7 work landed via build session + legacy shell without owning CP7 checkpoint session. | Re-implement carries inside CP7 session post-Batch 3 seal |
| **RISK-006** | Harness health | **MEDIUM** | **LIVE** | FAST incomplete on Linux: `spring_physics_f07`, `constitution_coverage`, `contract_v6_presence`, `banned_patterns` (D48 hover in P0). | macOS FULL; fix seal drift; resolve hover handler |
| **RISK-007** | F11 follow-ups | **LOW** | **LIVE** | F11.6 betaDiagnostics-null assert, F11.3 staple .app, install-page spec revision (Batch 2 ITEM 4 deferred). | Post-S1 engineering pass |

**W2 verdicts are recorded here as LIVE risks — not marked RESOLVED or WONTFIX in S1.**

---

## PART 1 — MVP sharpening implications

1. **Do not treat D67 as settled contract** when prioritizing work, writing BUILD_LOG claims, or closing constitution-coverage gaps.
2. **Existence ≠ enforcement** for CP7: hero propagation is **SHIPPED** but cites **law not in force** until Batch 3 ratification (or explicit operator rejection of Batch 3).
3. **SHELF-BROKEN and D36-VIOLATION remain live** — MVP sharpening must either schedule remediation (narrow code / CP2) or schedule explicit constitutional amendments; S1 does not decide which.
4. **Next constitutional act:** human ratification of `design/amendments/proposal-batch-3.md` (branch `constitution/batch-3-propagation`) — outside S1 scope.

---

## Session checklist (S1.1)

- [x] ADDENDUM applied before PART 1
- [x] D67 in existence matrix as **SHIPPED**
- [x] D67 in enforcement matrix as **citing law not in force**
- [x] W2 SHELF-BROKEN → RISK-001 **LIVE**
- [x] W2 D36-VIOLATION → RISK-002 **LIVE**
- [x] W2 probe gap → RISK-003 **LIVE**
- [ ] Operator review — PART 2+ (if any) not in this commit

---

*End S1.1 — MVP sharpening PART 1.*
