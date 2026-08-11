# Checkpoint sequence — Contract v6 (Task 5 sealed)

**Authority:** Contract v5 D40 + Layer-2 sequence supplied at re-seal.  
**Supersedes:** first-pass `design/checkpoint-sequence-v6.md` (CONFLICT placeholder).

---

## D40 retirement plan (v5 §10 — carried)

- P0 is the live path.
- Legacy shell (Workbench/Canvas/Proof, S/X/M, tiers, taste-index, audit piles, set rail) is quarantined and **retired checkpoint-by-checkpoint**.
- Salvage only: EmbeddingService + burst grouping; ExifToolService.
- Lab-gated develop engine integrates into **P0**, never the legacy shell; interactive grading of camera JPEGs must never return.
- Canonical state discipline + P0Command (one ⌘Z / gesture) govern new work.
- XCUITest harness invariants (leaf-only IDs, deterministic fixtures, state probe) ship with every new surface.
- `BUILD_LOG.md` — one entry per session.

---

## Sealed Layer-2 order

**Reorder decision: none.** The supplied sequence already matches D40’s checkpoint-by-checkpoint retirement and the R-A.1 story re-weight (land → tidy → Tier 0 → cull → export; propagation as act two). Reasons against reorder are stated per step.

| Step | Name | Binds | D40 / story fit |
|------|------|-------|-----------------|
| SPIKE A | Fidelity ladder on real files (ingest tee, three rungs, fused float16, latest-wins, histogram in-shader, R-Q.1 90/120/140 px ledger) | D20, D21, R-5.3, R-Q.1 / D43, D57 | Evidence before hero/fidelity chrome; does not touch legacy shell |
| SPIKE B | Table physics (owned spring, retargeting, transform-only 40-frame @ 120Hz, dead-stop, reduced-motion) | D27, D28, R-X.2 / D49 | Physics evidence before layout CP; aligns D27 birth-opacity amendment |
| CP1 | Layout as pure function; quantized; exact-at-rest; long rows wrap; no rest compression (audit V9 dead) | D7, D26, D28, R-X.2 / D49 | Foundation for all table surfaces; P0-only |
| CP2 | Journal + sidecars + crash-only startup; staged-not-persisted; kill-fuzz; LR round-trip | persistence, D35, D36 | Data-safety non-deferrable (D35); D36 anti-irritant + XMP before file-touch endgame |
| CP3 | Ingest for real: D31 + device-plug + videos-copied-not-shown + ✓/eject | D31, D39, R-M.2 / D53, R-M.5 / D56 | Card-in IS import; before cull hot loop |
| CP4 | Culling hot loop; same-mark-clears; resume-first-undecided; **retire corresponding legacy cull checkpoint** | D10, D11, D39, D59 | Explicit D40 retirement step; story places cull before propagation |
| CP5 | The rail: ten controls from tokens; arming; detents; value-echo during-adjustment-only; pixel-diff golden | D23, D24, D25, R-X.1 / D48 | Hover deletion + rail stability before focused edit |
| CP6 | Focused edit + fidelity chrome; clipping-hold; consequence chips; settle-as-confirmation; loupe on ADAPTED | D9, D20–D22, D26, R-5.1–5.3, R-Q.1 | Lab develop → P0 (D40); after cull baseline |
| CP7 | The hero: row-scoped batch; halo 1.5pt; warm-in; Return-release gate; Edited protection; post-commit advance | D13–D19, R-Q.1 / D57, D60, D62 | Propagation as act two (R-A.1); after SPIKE A evidence |
| CP8 | Open surface, export, endgame: resume sentences; Tier 0; one recipe + share destination; ⌥⌘E; rejects-to-Trash; sample shoot; three-state Export; R-I.2 socket | D32, D34, D35, D36 amendment, R-M.1/M.3/M.4, R-8.1, D61, D51 socket | Endgame after table loop exists; D40 harness continues on each surface |

---

## Binding clarifications (not reorders)

1. **CP2 ↔ D36:** CP2 takes D36’s persistence / no-catalog / XMP / “X never touches FS” clauses. **Rejects-to-Trash** (R-M.1 amendment) ships in **CP8**, after ✓ — not in CP2.
2. **Harness:** D40’s XCUITest invariants are a **continuous gate** on every CP surface, not a separate Layer-2 slot that displaces SPIKE A. CP0/codegen from `tokens.yaml` remains FOLLOW-UP / build work.
3. **Multi-select:** D29/D38 keep multi-select shelved. CP7’s “re-scope free-selection max-3 → row” is D17 row-scope — not an un-shelf of D29.
4. **Develop / Tier 1:** Banked under D46 until taste-model proof; CP6/CP7 ship Tier 2 radiation + rail grammar without ungating Tier 1.

---

## Why not reordered

| Temptation | Why rejected |
|------------|--------------|
| Open/export (CP8) earlier | D39/D31 need table+ingest honesty first; Open greets only when nothing is new |
| Hero (CP7) before cull (CP4) | Conflicts R-A.1 act-two propagation and D40’s explicit legacy-cull retirement at CP4 |
| Rail (CP5) before spikes | SPIKE A/B are measurement doors; moving them after CP5 wastes the rail golden on unproven fidelity/physics |
| Merge SPIKE A into CP6 | D40/R-Q.1 require evidence ledger before shipping PERSUADE claims |

---

## FOLLOW-UPS

- CP0 / build: codegen from `design/tokens.yaml`; grammar-stability suite named by D51.
- Do not start a build session that spans two checkpoints.
