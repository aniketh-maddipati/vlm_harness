# Constitution coverage matrix

Generated from `design/contract-v5.md`, `design/contract-v6.md`, and `Scripts/harness/coverage/artifact_registry.yaml`. Cells list **named artifacts only** — no adjacency inference. Battery column empty (F10 gated).

## Summary

| Total entries | Covered | Shelved | NOT-COVERED |
|--------------:|--------:|--------:|------------:|
| 82 | 44 | 7 | **31** |

> A low NOT-COVERED count would be suspicious; honest gaps are expected pre-CP1.

## NOT-COVERED (printed)

- `D1`
- `D2`
- `D3`
- `D4`
- `D5`
- `D6`
- `D7`
- `D12`
- `D14`
- `D15`
- `D17`
- `D18`
- `D20`
- `D21`
- `D22`
- `D25`
- `D28`
- `D30`
- `D31`
- `D33`
- `D34`
- `D40`
- `D45`
- `D49`
- `D51`
- `D52`
- `D55`
- `D56`
- `D58`
- `D62`
- `D66`

## Matrix

| Entry | Title | lint | logic | flow | golden | battery | NOT-COVERED |
|-------|-------|------|-------|------|--------|---------|-------------|
| D1 | The interface is a table with photographs on it. |  |  |  |  |  | NOT-COVERED |
| D2 | Agentic-quiet: the AI is embodied in the table's behavior, never address |  |  |  |  |  | NOT-COVERED |
| D3 | Lumina arranges but never judges. |  |  |  |  |  | NOT-COVERED |
| D4 | Positioning: "Edit the set, not every photograph." |  |  |  |  |  | NOT-COVERED |
| D5 | The row is the unit of work; the loop is edit-then-cull-within-row. |  |  |  |  |  | NOT-COVERED |
| D6 | Chronological landing → one watched tidy pass. |  |  |  |  |  | NOT-COVERED |
| D7 | Spacing is quantized language — two values in MVP. |  |  |  |  |  | NOT-COVERED |
| D8 | Five laws replace the rulebook. | `held_is_temporary` | `CullGrammarTests.testHoldKeysTrackMomentaryState` |  |  |  |  |
| D9 | Glances are holds; work states are latches. | `held_is_temporary`<br>`grammar_oracle_unit`<br>`grammar_oracle_parity` | `CullGrammarTests.testHoldKeysTrackMomentaryState` |  |  |  |  |
| D10 | Culling keys: P/X decide AND advance; no Hold/Maybe; no chord on the hot | `same_mark_clears`<br>`grammar_oracle_unit`<br>`grammar_oracle_parity` | `CullGrammarTests.testD10_decisionKeysToggleWithoutAutorepeatSemantics`<br>`P0LogicTests.testCullToggleGrammar` | `CullGrammarTests.testKeepRejectToggleGrammar` |  |  |  |
| D11 | The ⏎ doctrine. | `shift_return_return_release`<br>`esc_exact_restore`<br>`grammar_oracle_unit`<br>`grammar_oracle_parity` | `CullGrammarTests.testD11D13_releaseNeverCommitsHeldReturn`<br>`CullGrammarTests.testD11D13_shiftReturnKeyDownWithoutReleaseDoesNotCommit`<br>`CommandChordTests.testHeldReturnCannotDoubleCommit` |  |  |  |  |
| D12 | Modifier temperaments: ⇧ enlarges/coarsens, ⌥ refines. |  |  |  |  |  | NOT-COVERED |
| D13 | Release never commits — anywhere, in any form. | `shift_return_return_release`<br>`grammar_oracle_unit`<br>`grammar_oracle_parity` | `CullGrammarTests.testD11D13_releaseNeverCommitsHeldReturn`<br>`CommandChordTests.testHeldReturnCannotDoubleCommit` |  |  |  |  |
| D14 | Propose → stage → commit, with the halo as the proposal. |  |  |  |  |  | NOT-COVERED |
| D15 | Exceptions: click-toggle; `Edited` protection with visible override. |  |  |  |  |  | NOT-COVERED |
| D16 | Adapt, never copy *(amended by A5)* `[● A5]` | `copy_contract_diff`<br>`copy_table_lint` | `P0LogicTests.testA1FormatterSamplesInCopyContract` |  |  |  |  |
| D17 | Scope = the row, full stop (MVP). |  |  |  |  |  | NOT-COVERED |
| D18 | The four exposures + facts-only chips. |  |  |  |  |  | NOT-COVERED |
| D19 | Count invariant + clickable receipt. |  | `P0LogicTests.testA1InvariantRowScope`<br>`P0LogicTests.testA1InvariantExcludedCount`<br>`PropagationTests.testA1AtShootRingWithExclusions` |  |  |  |  |
| D20 | The fidelity contract. |  |  |  |  |  | NOT-COVERED |
| D21 | Truth-at-a-glance *(amended by R-5.2 + A4)* `[● A4]` |  |  |  |  |  | NOT-COVERED |
| D22 | Sharpness is judged only in the loupe or at 1:1. |  |  |  |  |  | NOT-COVERED |
| D23 | Ten controls + Crop mode *(amended by A2)* `[● A2]` | `agent_rules_contract` | `P0LogicTests.testCropLayoutHashRestoration`<br>`P0LogicTests.testCropStraightenMagnet`<br>`P0LogicTests.testCropKeyScopeNeverStagesOrRejects`<br>`CropTests.testLayoutHashChangesOnEditAndReverts`<br>`CropTests.testCropHeaderNeverMentionsReject` |  |  |  |  |
| D24 | Arming / value-echo *(amended by R-X.1 + audit)* | `value_echo_adjustment_only`<br>`grammar_oracle_unit`<br>`grammar_oracle_parity` | `CullGrammarTests.testMoveFocusAndArming` |  |  |  |  |
| D25 | Detents in photographic units; slider anatomy fixed. |  |  |  |  |  | NOT-COVERED |
| D26 | Focused edit = hero + elastic strip + rail; no ghost table. | `esc_exact_restore`<br>`grammar_oracle_unit`<br>`grammar_oracle_parity` | `CullGrammarTests.testEscRestoresPreStageMarks` |  |  |  |  |
| D27 | Motion/fade *(amended by audit frame-F — one-line)* |  |  |  | `golden-birth-opacity` |  |  |
| D28 | Elasticity: elastic in motion, exact at rest, anchored at the focus. |  |  |  |  |  | NOT-COVERED |
| D29 | Selection: standard Mac grammar; hold-to-select banned. |  |  |  |  |  | SHELVED |
| D30 | Trackpad: full map, no decisions. |  |  |  |  |  | NOT-COVERED |
| D31 | Card-in IS the import; direct to table. |  |  |  |  |  | NOT-COVERED |
| D32 | ### D32 / Success test — Amateur pivot *(amended by R-A.1 + A10)* `[● A1 |  |  |  |  |  | SHELVED |
| D33 | Learning = within-shoot memory only. |  |  |  |  |  | NOT-COVERED |
| D34 | Export = receipts, not a task. |  |  |  |  |  | NOT-COVERED |
| D35 | The failure-mode law. |  | `P0StateTests.testMissingOriginalShootPersistence`<br>`P0StateTests.testAtomicSaveLeavesFinalAndGoodCopy` | `MissingOriginalsTests.testMissingOriginalsPreserveCatalogAndPreviews` |  |  |  |
| D36 | Anti-irritant + rejects endgame *(amended by R-M.1)* |  |  |  | `golden-rejects-trash-offer` |  |  |
| D37 | Visual language *(amended by R-X.1)* | `token_lint` |  |  |  |  |  |
| D40 | Engineering reconciliation *(history note — retirement schedule)* |  |  |  |  |  | NOT-COVERED |
| D41 | Chip copy in consequence language *(R-5.1)* |  |  |  | `golden-fidelity-rungs` |  |  |
| D42 | Clipping hold grammar *(R-5.2 + A4)* `[● A4]` |  |  |  | `golden-hold-j-clipping` |  |  |
| D43 | Settle-as-confirmation *(R-5.3)* | `unit_trace` |  |  | `golden-fidelity-rungs` |  |  |
| D44 | ⌥⌘E recipe re-entry *(R-8.1)* |  | `P0LogicTests.testExportRecipeHintContract` |  |  |  |  |
| D45 | Diagnostics local-only or absent *(R-9.1 + A7)* `[● A7]` |  |  |  |  |  | NOT-COVERED |
| D46 | Amateur pivot + Develop gate *(R-A.1 + A10)* `[● A10]` |  |  |  |  |  | SHELVED |
| D47 | Pointer path to culling *(R-A.2 → MVP via A3)* `[● A3]` | `probe_growth`<br>`probe_mirror`<br>`leaf_only_ids` | `CullGrammarTests.testD47A3_pointerMarksMatchKeysAndAdvanceIdentically` |  |  |  |  |
| D48 | Hover deleted entirely *(R-X.1)* | `banned_patterns`<br>`value_echo_adjustment_only`<br>`leaf_only_ids`<br>`grammar_oracle_unit`<br>`grammar_oracle_parity` |  |  | `golden-hover-absent` |  |  |
| D49 | Layout quantized everywhere *(R-X.2)* |  |  |  |  |  | NOT-COVERED |
| D50 | Distribution Developer ID *(R-I.1)* |  |  |  |  |  | SHELVED |
| D51 | Silent updates *(R-I.2)* |  |  |  |  |  | NOT-COVERED |
| D52 | Offline licensing *(R-I.3 + A8)* `[● A8]` |  |  |  |  |  | NOT-COVERED |
| D53 | Device-plug ingestion *(R-M.2)* | `contract_v6_presence` |  |  |  |  |  |
| D54 | Sample shoot onboarding *(R-M.3)* |  |  |  | `golden-sample-retire` |  |  |
| D55 | Share sheet destination *(R-M.4)* |  |  |  |  |  | NOT-COVERED |
| D56 | Videos copied, counted, not shown *(R-M.5)* |  |  |  |  |  | NOT-COVERED |
| D57 | 90 px / PERSUADE *(R-Q.1)* |  |  |  | `golden-adapted-proxy-linear` |  |  |
| D58 | Halo 1.5 pt restored *(audit)* |  |  |  |  |  | NOT-COVERED |
| D59 | Same-mark clears *(D10 + audit; copy sealed)* | `copy_contract_diff`<br>`contract_v6_presence`<br>`same_mark_clears`<br>`grammar_oracle_unit`<br>`grammar_oracle_parity` | `CullGrammarTests.testD59_sameMarkClearsInPlace`<br>`P0LogicTests.testCullToggleGrammar` |  | `golden-cull-marks` |  |  |
| D60 | Return-release gate *(D11 + audit; copy sealed)* | `copy_contract_diff`<br>`contract_v6_presence`<br>`shift_return_return_release`<br>`grammar_oracle_unit`<br>`grammar_oracle_parity` | `CullGrammarTests.testD11D13_releaseNeverCommitsHeldReturn`<br>`CommandChordTests.testHeldReturnCannotDoubleCommit` |  |  |  |  |
| D61 | Export three-state *(audit + D37)* |  |  |  | `golden-export-three-state` |  |  |
| D62 | Post-commit focus advance *(audit)* |  |  |  |  |  | NOT-COVERED |
| D63 | Crop latch keys & ban on decision-key remap *(A2)* `[● A2]` | `agent_rules_contract`<br>`contract_v6_presence` | `P0LogicTests.testCropKeyScopeNeverStagesOrRejects`<br>`CropTests.testLayoutHashChangesOnEditAndReverts` |  | `golden-crop-latch` |  |  |
| D64 | Swim lanes shelved with evidence clause *(A6)* `[● A6]` |  |  |  |  |  | SHELVED |
| D65 | MVP test fleet & unsupported body *(A1)* `[● A1]` | `unit_lane_guards` |  |  |  |  |  |
| D66 | Beta distribution posture *(A7 + A8)* `[● A7]` `[● A8]` |  |  |  |  |  | NOT-COVERED |
| R-5.1 | Chip copy in consequence language |  |  |  | `golden-fidelity-rungs` |  |  |
| R-5.2 | Clipping hold grammar (Hold-J) |  |  |  | `golden-hold-j-clipping` |  |  |
| R-5.3 | Settle-as-confirmation | `unit_trace` |  |  | `golden-fidelity-rungs` |  |  |
| R-8.1 | ⌥⌘E recipe re-entry |  | `P0LogicTests.testExportRecipeHintContract` |  |  |  |  |
| R-9.1 | Diagnostics local-only or absent | `zero_egress_audit` |  |  |  |  |  |
| R-A.1 | Amateur pivot / Develop gate |  |  |  |  |  | SHELVED |
| R-A.2 | Pointer path to culling (shelf → MVP) |  | `CullGrammarTests.testD47A3_pointerMarksMatchKeysAndAdvanceIdentically` |  |  |  |  |
| R-I.1 | Distribution Developer ID | `contract_v6_presence` |  |  |  |  |  |
| R-I.2 | Silent updates | `heavy_job_registry` |  |  |  |  |  |
| R-I.3 | Offline licensing |  |  |  |  |  | SHELVED |
| R-M.1 | Rejects endgame / Trash offer |  |  |  | `golden-rejects-trash-offer` |  |  |
| R-M.2 | Device-plug ingestion | `contract_v6_presence` |  |  |  |  |  |
| R-M.3 | Sample shoot onboarding |  |  |  | `golden-sample-retire` |  |  |
| R-M.4 | Share sheet destination | `copy_table_lint` |  |  |  |  |  |
| R-M.5 | Videos copied, counted, not shown |  |  |  | `golden-export-three-state` |  |  |
| R-Q.1 | 90 px / PERSUADE |  |  |  | `golden-adapted-proxy-linear` |  |  |
| R-X.1 | Hover deleted / value-echo at-rest | `banned_patterns`<br>`value_echo_adjustment_only`<br>`leaf_only_ids` |  |  | `golden-hover-absent` |  |  |
| R-X.2 | Layout quantized everywhere | `magic_numbers` |  |  |  |  |  |
