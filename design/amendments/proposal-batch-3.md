# Amendment Batch 3 — proposal for human ratification

## Ratification decisions

| Item | Amendment | Decision |
|------|-----------|----------|
| **ITEM 1** — D67 intent propagation (CP7 hero) | **A14** / **R-A.3** | **NOT RATIFIED** — proposal only |
| **ITEM 2** — W2 implementation gap (SHELF-BROKEN / D36-VIOLATION) | (narrow code / widen proposal) | **NOT RATIFIED** — operator choice recorded below; this proposal decides neither |

**Status:** **PROPOSAL ONLY** — no edits to `design/contract-v6.md`, `design/tokens.yaml`, or code in B3.1.  
**Branch:** `constitution/batch-3-propagation` (off `origin/main`)  
**Session:** B3.1 (extract D67 from build-session material for human ratification)

**Authority order reminder:** `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests. A build-session ledger (`BUILD_LOG.md`) and W2 audit sit **below** the contract and cannot ratify law.

**Provenance:** D67 entered the tree through a build session on ad-hoc branch `human-led-edit-propagation` (external worktree; never merged). That session authored D67 text and attempted Shelved Register edits **without** a constitution session. This proposal **extracts** the lawful CP7 core and **rejects** self-ratification, cross-row un-shelving, and catalog persistence that W2 flagged.

---

## Number space (derived from grep)

### Amendment batches

```
grep -i 'Batch [0-9]' design/contract-v6.md design/amendments/proposal-batch-2.md
```

| Batch | Status in tree |
|-------|----------------|
| Batch 1 | A1–A10 ratified (contract header) |
| Batch 2 | A11–A13 ratified (`proposal-batch-2.md`) |

**Next free amendment batch:** **Batch 3**

### A-numbers

```
grep -oE '\bA[0-9]+\b' design/contract-v6.md design/amendments/proposal-batch-2.md | sort -u
```

Highest assigned: **A13** (Batch 2 — A7 withdrawal).

**Next free A-number:** **A14** (proposed below for ITEM 1).

No **A14** or above appears in `design/contract-v6.md` or `proposal-batch-2.md`. **STOP** if collision — none at proposal time.

### D-numbers

```
grep '^### D[0-9]' design/contract-v6.md
```

Highest contract entry: **D66** (`### D66 — Beta distribution posture`).

**Next free D-number:** **D67** (proposed below).

No `### D67` or `D67` decision entry appears in `design/contract-v6.md`. **STOP** if collision — none at proposal time.

### R-numbers (propagation / CP7 lane)

```
grep -oE 'R-[0-9A-Z]+(\.[0-9]+)?' design/contract-v6.md design/amendments/proposal-batch-2.md | sort -u
```

| Lane | Found in contract | Next free in lane |
|------|-------------------|-------------------|
| **R-A** | R-A.1, R-A.2 | **R-A.3** |
| **R-5** | R-5.1, R-5.2, R-5.3 | R-5.4 |
| **R-8** | R-8.1 | R-8.2 |
| **R-9** | R-9.1 | R-9.2 |
| **R-I** | R-I.1, R-I.2, R-I.3, R-I.4 | R-I.5 |
| **R-M** | R-M.1 … R-M.5 | R-M.6 |
| **R-Q** | R-Q.1 | R-Q.2 |
| **R-X** | R-X.1, R-X.2 | R-X.3 |

CP7 / “propagation as act two” is anchored in **R-A.1** (D32 story re-weight) and **contract-v5 §4** (D13–D19 carry). The natural ruling record for ITEM 1 is **R-A.3** — hero intent propagation scope for MVP.

**Proposed ruling for ITEM 1 (optional record):** **R-A.3** — row-scoped intent propagation (CP7); not an un-shelf of D29/D38.

---

## Background

### Build-session material (not law)

`BUILD_LOG.md` (2026-08-12 auditor entry) records:

- **Claim:** Photographer-authored Develop change → editable intent group → per-recipient adaptation → Return-release commit.
- **Verdict:** **NEVER MERGE** — D67 + Shelved Register rewrite authored without constitution session; CP7 on ad-hoc branch; cross-row selection and ⇧⏎ ring widen exceed ratified shelf.
- **Routing (lawful carries under CP7 after ratification):** Return-release gate, Esc ring narrow, `BatchEditCommand` atomic undo, IntentBoundaryCorrection (**contract-v5 D33**), LocalIntentPropagationEngine adaptation math, VoiceOver include/exclude, EditRailLayout tolerance, develop double-apply test.
- **CUT:** D67 file edits, contract self-ratification, cross-row selection paths, identical `⌘⇧A` set apply, scene-ring banner string absent from copy-contract, FAST demotion without ruling.

`Lumina/Develop/IntentPropagation.swift` — **not on `origin/main`** at proposal time; build-session implementation lives outside this ratification branch.

### Checkpoint anchor (grepped)

`design/checkpoint-sequence-v6.md`:

> **CP7** | The hero: **row-scoped batch**; halo 1.5pt; warm-in; Return-release gate; Edited protection; post-commit advance | D13–D19, R-Q.1 / D57, D60, D62 | Propagation as act two (R-A.1)

Binding clarification:

> **Multi-select:** D29/D38 keep multi-select shelved. CP7’s “re-scope free-selection max-3 → row” is **D17 row-scope** — not an un-shelf of D29.

### contract-v5 §4 hero interaction (provenance only)

Grepped in `design/contract-v5.md` §4 — D13–D19 define release-never-commits, propose→stage→commit, Edited protection, Adapt-never-copy, **scope = the row (MVP)**, four exposures, count invariant. v6 carries D16 (amended), D60, D62, and shelved register; **does not yet carry a single D67-style CP7 hub entry**.

---

## W2 audit findings (carried verbatim)

**Scope note (W2):** Audit run on `main` @ `6652c65`; `IntentPropagation.swift` absent from fetched refs.

### Q1 — SHELF

**Verdict: `SHELF-BROKEN`**

Shelved register (grepped):

> `| Multi-select + two-up | Shelved (D29 / D38) — first-pass hi-fi un-shelf does **not** override v5 |`

**Does group membership survive the gesture that created it?** **Yes** — rubber-band / ⇧-extend / ⌘-toggle selection paths persist in `TablePhotographSelection.ids` and `P0SessionModel.selectedAssetIDs` after release.

**Can a user act on a group as a unit after releasing?** **Yes** — `WorkbenchSelection.stageTreat` binds `memberIDs` into `table.setMembers` for wholesale staging.

**One origin photograph, or a set of equals?** **One reference origin + many recipients** — `PropagationState.referencePhotoID` with `memberIDs` scope; cross-row hand selection explicitly ignores row scope.

### Q2 — PERSISTENCE

**Verdict: `D36-VIOLATION`**

D36 v5 prior (grepped): *no catalog; files stay put; **edits in open XMP**; deleting Lumina loses nothing*.

P0 single-photo editing (merged #25) persists recipes via `ShootStore.saveShoot` → `~/Library/Application Support/Lumina/projects/<shoot>/shoot.json` (JSON catalog), not beside RAW files. **F06 kill-fuzz / CP2 sidecar path does not exist yet**; a catalog write path exists today that future F06 would need to cover.

### Q3 — PROBE GROWTH

**Finding:** `probe_growth` reports OK on a **clean tree** (vacuous — `git diff origin/main` empty). At P0 merge time, probe gained `focusedRecipeFingerprint` only; new route `.grouping` collapses to `"contactSheet"` in `uiTestSnapshot()` — **green lint over partial / invisible probe growth**.

---

## ITEM 1 — D67 intent propagation (CP7 hero)

**Proposed amendment:** **A14**  
**Optional ruling record:** **R-A.3**  
**New entry:** **D67**  
**Checkpoint socket:** CP7 (after CP4 cull, CP5 rail, CP6 focused edit; **before** CP8 export endgame persistence for committed edits per CP2/D36)

### Proposed text — D67 decision clause (for contract on ratification)

> **D67 — Intent propagation (CP7 hero, row-scoped).** The hero move is **Adapt treatment to N** on the **reference photograph’s row only** (contract-v5 D17 MVP scope; **not** cross-row compatibility — shelved D29/D38/D17 socket unchanged).
>
> **Staging grammar (carry D13–D15, D16, D19, D60, D62):**
> - **Propose → stage → commit:** editing the reference lifts the halo; adapted previews warm per frame; **⇧⏎ stages**; **⏎ commits**; **Esc dissolves** — staging is **ephemeral** and loudly bannered.
> - **Release never commits** (D13) — including pointer release; only ⏎ / ⇧⏎ / the one visible primary commit.
> - **Return-release gate** (D60) — commit arm only after Return key-up, not on key-down.
> - **Adapt, never copy** (D16) — banner language verbatim; per-recipient numeric adaptation, not sync/copy settings.
> - **Edited protection** (D15) — individually edited frames start excluded; deliberate inclusion always wins; one ⌘Z for the batch.
> - **Count invariant** (D19) — banner = receipt = header count.
> - **Post-commit focus advance** (D62) after commit.
>
> **Intent group (terminology):** an **ephemeral staging scope** derived from the reference row — **not** persistent multi-select, **not** rubber-band membership, **not** a set of equals. One **reference photograph**; recipients are row members after exclusions. Membership **does not survive Esc**; it **does not survive** navigation that clears staging.
>
> **Ring / widen:** MVP scope is **row ring only**. ⇧⏎ **scene** or **shoot** ring widen is **not authorized** by this entry — would require a **separate explicit ruling** and shelved-register amendment (not assumed here).
>
> **Persistence (CP2 / D36 socket):** staged intent is **not persisted**. Committed recipe changes follow **CP2** — open XMP beside files, no catalog; **P0 catalog `shoot.json` recipe blobs are not lawful committed-edit storage** once CP2 lands. Until CP2, any catalog write is **engineering debt**, not constitutional permission.
>
> **Within-shoot learning (D33 socket):** corrected boundaries and exclusions may persist **within the shoot** only; no cross-shoot silent model changes.

### Strengthens / weakens

| | |
|---|---|
| **Strengthens** | Closes constitution-coverage gap for CP7 / v5 §4 hero block (D13–D19 hub); gives `LocalIntentPropagationEngine` / `IntentPropagation.swift` a **law target** after ratification; aligns story re-weight “propagation as act two” (R-A.1 / D32) with a citable v6 entry; makes row-scope explicit against shelved multi-select. |
| **Weakens** | Does **not** un-shelf multi-select, two-up, gather-drag, or cross-row compatibility; does **not** authorize wholesale row→scene→shoot ring widen; does **not** bless catalog persistence or build-session Shelved Register rewrites. |

### Interactions (explicit)

| Entry | Interaction |
|-------|-------------|
| **D29 / D38 shelf** | Multi-select + two-up **remain shelved**. D67 defines ephemeral row staging only. Any code path that keeps rubber-band / ⇧-extend / cross-row `TablePhotographSelection` membership after release **exceeds** this proposal unless ITEM 2 option (b) is ratified separately. |
| **D36 / CP2** | D67 **defers committed persistence to CP2** sidecars. Catalog `shoot.json` recipe storage (W2 D36-VIOLATION) is **not** ratified here. |
| **D16 / A5** | Banner must retain **Adapt** verbatim (A5 scoped weakening unchanged). |
| **D60 / D62** | Return-release and post-commit advance are **required** CP7 gates, not optional polish. |
| **contract-v5 §4 D13–D19** | D67 is the v6 citation hub for the hero block; v5 text is provenance, not automatic override of v6 shelf register. |
| **D32 / R-A.1** | Propagation stays **act two** — D67 does not reorder checkpoints. |
| **D33 (v5)** | IntentBoundaryCorrection / within-shoot exclusions socket — not a cross-shoot learning license. |

### What breaks if ratified

1. **Code citing D67 as live law** before contract edit — currently **none in Swift/tests** (see § Citations below); BUILD_LOG audit prose is not a citation of in-force law.
2. **Implementation exceeding proposal (W2):** see ITEM 2 — ratifying D67 alone does **not** legalize SHELF-BROKEN selection, ring widen, or D36 catalog writes.
3. **Copy-contract:** Adapt banner strings, scene-ring banners, and consequence chips for staging must exist in `design/copy-contract.txt` before CP7 ships — **not invented in this proposal**.
4. **Harness:** CP7 surfaces require probe growth (F03.1) and constitution coverage matrix update — W2 probe gap remains a **follow-up**, not auto-closed by D67 text.
5. **Checkpoint discipline:** Hero work must land in a **CP7 checkpoint session** after Batch 3 seal — not on ad-hoc branches.

---

## ITEM 2 — W2 implementation gap (operator choice — not ratified)

W2 returned **`SHELF-BROKEN`** and **`D36-VIOLATION`**. On-tree implementation **currently exceeds** what ITEM 1 proposes.

### Option (a) — Narrow code to the proposal

| | |
|---|---|
| **Mechanism** | Remove or gate persistent cross-row selection (`TablePhotographSelection`, `P0SessionModel.selectClick` ⇧-range, rubber-band overlays); restrict propagation to **row ring only**; route committed edits toward CP2 sidecar path; strip catalog recipe persistence when CP2 lands. |
| **Cost** | Substantial rework of workbench + P0 selection paths already on `main`; may delay CP7 hero demo. |
| **Benefit** | Tree matches ratified law without further shelf amendments. |

### Option (b) — Widen the proposal (explicit un-shelving rulings)

| | |
|---|---|
| **Mechanism** | Separate Batch 3+ items (or Batch 4) with **explicit** shelf amendments — e.g. un-shelf multi-select, authorize scene/shoot ring widen, and/or amend D36/CP2 sequencing to permit interim catalog storage. Each requires its own A-number, human ratification, and shelved-register row edits. |
| **Cost** | Constitution surface expands; contradicts checkpoint-sequence “D29 stays shelved” unless explicitly overturned. |
| **Benefit** | Preserves existing selection/propagation code paths. |

### Recommendation (operator may override): **neither decided here**

This proposal **extracts D67** and **records the gap**. Operator chooses (a) or (b) at Batch 3 seal or a follow-on batch. **ITEM 2 is not ratified in B3.1.**

---

## Citations of D67 citing law not in force

```
grep -rn '\bD67\b' --include='*.swift' --include='*.py' --include='*.md' . 
  (excluding this proposal file)
```

| Location | Kind | Cites D67 as in-force law? |
|----------|------|----------------------------|
| `BUILD_LOG.md:13,17,19` | Audit / routing prose | **No** — describes build-session **attempt** and **NEVER MERGE** verdict |
| `*.swift` | — | **None** |
| `*Tests*.swift` / `Scripts/harness/**` | — | **None** |
| `design/contract-v6.md` | — | **None** — no `D67` entry, no `[● A#]` mark, no Status line |

**Conclusion:** No production code or test cites D67 as ratified law. Only BUILD_LOG audit text references D67 as **proposed-then-rejected** build-session material.

---

## Ratification checklist (human — not executed in B3.1)

- [ ] Operator approves **A14**, **R-A.3**, and D67 decision text (ITEM 1)
- [ ] Operator chooses ITEM 2 option (a) narrow code or (b) widen proposal — or defers
- [ ] Edit `design/contract-v6.md` — add `### D67` with `[● A14]`; update Status header for Batch 3; **do not** edit shelved register except via explicit ITEM 2(b) rulings
- [ ] Bump `design/tokens.yaml` version on implementation pass; regenerate codegen if CP7 tokens added
- [ ] Add/copy rows to `design/copy-contract.txt` for staging banners (Adapt, scope count, provenance)
- [ ] Update constitution coverage matrix / probe contract for CP7 surfaces
- [ ] CP7 checkpoint session owns `IntentPropagation.swift` implementation — not build-session branch
- [ ] BUILD_LOG entry for Batch 3 seal

---

## CONFLICT blocks

**None against ratified v6 D/R entries for ITEM 1 as drafted.** D67 is scoped to row-only CP7 hero staging, preserves D29/D38 shelf, defer CP2/D36 persistence, and does not contradict Batch 2 (A11–A13).

**Latent conflicts if operator chooses ITEM 2 option (b) without new amendments:**

| Conflict | Why |
|----------|-----|
| D29 / D38 shelved register | Un-shelving multi-select requires explicit register amendment — not in ITEM 1 |
| D17 row scope (v5 §4) | Scene/shoot ring widen exceeds MVP row stop |
| D36 v5 prior / CP2 binding | Catalog recipe persistence contradicts “edits in open XMP; no catalog” |
| `checkpoint-sequence-v6.md` clarification #3 | “D29/D38 keep multi-select shelved” |

Those conflicts are **avoided** if operator ratifies ITEM 1 only and later chooses ITEM 2 option (a) or pursues option (b) via **separate** explicit rulings.
