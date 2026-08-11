# Lumina Product Decision Record — Contract v6

**Status:** Amendment Batch 1 (A1–A10) on sealed re-seal.  
**Authority flow:** contract → tokens → copy → code → tests.  
**Provenance:** `design/contract-v5.md` (D1–D40, unmodified PDR body).  
**Sources integrated:** Rulings R-5.1…R-Q.1; audit-accepted items; Layer-2 sequence (Task 5); MVP-test questionnaire A1–A10.  
**Does not:** invent grammar, chips, copy, chrome, or motion beyond rulings and sealed sources.  
**Change-marks:** `[● A#]` = Amendment Batch 1. Two scoped weakenings only: **A5** (D16) · **A7** (R-9.1 / D45).

---

## Conflicts — closed this re-seal

| # | Conflict (first pass) | Resolution |
|---|----------------------|------------|
| 1 | Contract v5 (D1–D40) absent | `design/contract-v5.md` committed; D24 / D27 / D36 / D40 merge against real prior text |
| 2 | Layer-2 + D40 retirement absent | Sequence supplied; Task 5 result in `design/checkpoint-sequence-v6.md` |
| 3 | Same-mark / Return-release verbatim absent | Frozen [P] rows from v5 D10 / D11 entered in `design/copy-contract.txt`; D59 / D60 OPEN closed |

No open CONFLICT blocks remain from the first pass.

---

## How to read v6

1. **Carry:** All of Contract v5 (D1–D40) remains law except where an amendment below replaces named clauses.  
2. **Amend:** D16 (via A5), D21 (via R-5.2 + A4), D23 (via A2), D24, D27, D32/success-test (via R-A.1 + A10), D36, D37 (via R-X.1), D40 history note; D45 (via A7), D46 (via A10), D47 (via A3), D52 (via A8).  
3. **Add:** D41–D62 (rulings + audit integrations); D63–D66 (Batch 1).  
4. **Shelf:** Shelved Register below supersedes first-pass WG-hand multi-select drift — v5 D29/D38 win unless a ruling un-shelves. **A3 un-shelves** pointer culling (D47). **A6 shelves** swim-lane plates with an evidence re-entry door.

Five Laws mapping (v5 D8 ↔ session L1–L5): touch moves never decides · held is temporary · taps decide / work states latch · ⇧ is more ⌥ is less · Esc puts it back / ⌘Z takes it back. Session L3/L4 failure & persistence language remains the operational reading of D35/D36.

**Scoped weakenings this batch (review must see):** **A5** amends D16 (Adapt word verbatim; remainder may compress). **A7** scopes R-9.1 / D45 (TestFlight crash reporting for beta ONLY; expires at 1.0).

---

## House style

Every numbered entry uses: **decision** · **why** · **rejected** · **history / socket**.  
Citations: `D#`, `R-*`.

---

## Amended v5 entries (merge against real prior text)

### D16 — Adapt, never copy *(amended by A5)* `[● A5]`

**v5 prior:** Product language is "Adapt treatment to N," never "sync/copy settings"; each recipient gets a different numeric adjustment sharing the same visual intention; that phrase appears in the banner verbatim.

- **decision:** Product language remains Adapt — never "sync" / "copy settings" (banned words). **Amendment (A5), verbatim:** the word **"Adapt"** appears in the banner verbatim; the remainder of the sentence may compress. Frozen compressed forms: banner `Adapt → N  ⏎ · Esc` · receipt `Adapted → N · ⌘Z` · provenance chip `← 8288`. Each recipient still gets a different numeric adjustment sharing the same visual intention.
- **why:** Banner/receipt chrome must stay scannable at pro rates; the differentiation word is Adapt, not the full v5 sentence.
- **rejected:** Restoring "sync/copy settings"; dropping the word Adapt from the banner; compressing away the count invariant (D19) or the clickable receipt.
- **history / socket:** **Scoped weakening of D16** — one of two Batch-1 weakenings (with A7). D19 count invariant and clickable receipt are untouched. Copy rows in `design/copy-contract.txt`.

### D21 — Truth-at-a-glance *(amended by R-5.2 + A4)* `[● A4]`

**v5 prior:** clipping overlays appear only WHILE adjusting a tone control (momentary).

- **decision:** Clipping joins the **hold grammar** — **Hold-J** shows clipping overlays anytime (momentary; release returns) — Lightroom’s J transferred from forgettable toggle to D9 hold (A4 completes R-5.2). The adjust-time overlay behavior remains as the **automatic subset**. Loupe / hold-B / hold-⇧ remain glances (D9). Still never a panel.
- **why:** R-5.2 + A4; truth-at-a-glance must not depend on already being mid-tone-drag; named key closes the R-5.2 socket.
- **rejected:** Persistent clipping; hover-to-show clipping; LR-style forgettable J-toggle as the only path; inventing a second clipping key without a ruling.
- **history / socket:** Amends D21 clipping clause. Cross-cites D42, D9, R-X.1, A4.

### D23 — Ten controls + Crop mode *(amended by A2)* `[● A2]`

**v5 prior:** Ten controls, four fixed sections (Light · Color · Detail · Crop/Straighten); schema rich, rail narrow; positions never move across versions.

- **decision:** Rail sections and ten controls unchanged (stability promise). **Crop mode enters MVP** as a **work-state latch** (D9), not a panel tour:
  - Interaction (audited frame C): **fixed frame**, photograph slides beneath, rising grid, matte; **non-destructive**; maps to `DevelopRenderGraph` straighten/crop stage; persists in `EditRecipe` rich schema.
  - Keys: **`R`** frees the aspect ratio; **`O`** flips orientation. `[FLAG: R/O are Claude's pick — validate with wave-one testers.]`
  - **`A` and `X` are BANNED from remapping in crop mode** — decision keys keep their meanings everywhere (stability promise). Crop verbs never steal Develop / Reject.
  - Banner + header (Law 3 / work-state latch): `Crop · ⏎ applies · Esc cancels`. Chips in crop state = **facts only** — no key instructions in chips.
  - `⏎` applies crop geometry to sidecar (one ⌘Z entry). `Esc` dismisses crop — restore entry layout hash, nothing written.
- **why:** Amateurs need crop at MVP; fixed-frame model matches audited frame C; remapping A/X would break the decision-key stability promise.
- **rejected:** Re-scoping A→aspect or X→orientation (hi-fi latch drift); hover-only crop handles as sole path; destructive crop; key instructions inside facts chips; inventing crop chrome beyond the frozen banner.
- **history / socket:** Extends D23 Crop section. CP6 scope. Cross-cites D9, D10, D37, D48. Supersedes hi-fi A/X crop re-scoping for MVP. See also D63.

### D24 — Arming / value-echo *(amended by R-X.1 + audit)*

**v5 prior:** “value echoes at the pointer”; arming ring is consent; hold-keycap aim SHELVED.

- **decision:** Value-echo appears **during adjustment only**. At rest, settled changed values remain dark on the rail (the rail IS the edit summary — D25). No hover path reveals or amplifies a value (D48 / R-X.1). Arming (1–4/Tab, 2 pt charcoal ring) unchanged.
- **why:** R-X.1 — all information at-rest or during-action; hover deleted entirely.
- **rejected:** Hover-to-reveal values; persistent competing live readouts; “because” echoes.
- **history / socket:** Amends D24 value-echo clause against `design/contract-v5.md`. Hold-keycap aim remains SHELVED (D38).

### D27 — Motion/fade *(amended by audit frame-F — one-line)*

**v5 prior:** photographs never fade — chrome does; photographs travel, dim in place, or soften toward sharp; duration never carries meaning.

- **decision:** **One-line amendment:** photograph **opacity exists only at birth**; after birth, photographs do not run opacity transitions (they travel, dim in place, or soften toward sharp; chrome may fade).
- **why:** Post-birth opacity reads as the photograph disappearing — a trust break. Birth landing remains the sole opacity channel.
- **rejected:** Post-birth photograph opacity fades; opacity-pulse after birth under Reduce Motion.
- **history / socket:** Explicit one-line audit edit to D27. Dim-in-place (~45–50%) and soften-toward-sharp remain (not opacity-fade-to-absent). Cross-cites D28, SPIKE B.

### D32 / Success test — Amateur pivot *(amended by R-A.1 + A10)* `[● A10]`

**v5 prior:** Tier 1 + A-ladder SHELVED; success test = faster than Lightroom, day one, having read nothing; edit-then-cull-within-row (D5).

- **decision:** Story re-weights to **land → tidy → Tier 0 → cull → export**, with **propagation as act two**. Tier 1 + A-ladder under the **Develop** rename is the critical path for tasteful finishing, **GATED on taste-model proof** — until the gate passes it stays **banked** (door, not deletion; D38 shelf preserved). Success test rewrites to: **finished, happy, organized — having read nothing.** **A10 proving schedule:** taste model proves **after wave one** on consented tester shoots; benchmark = each tester’s own final hand edits; Tier 1/Develop ships only when it beats that benchmark; target vehicle wave two or v1.1; **do not begin** taste-model work before the eval set exists. MVP success probes: see `design/mvp-test-plan.md` (A9).
- **why:** R-A.1 amateur pivot; Tier 0 already delivers most value at zero model risk (D32); A10 prevents ungated model work.
- **rejected:** Shipping Tier 1 ungated; banned synonyms for Develop; propagation as act one; success metrics that require reading chrome; beginning taste-model work before the eval set exists.
- **history / socket:** Amends D32 shelf posture (gate, not silent deletion) and replaces the success-test paragraph. D5’s row loop remains lawful inside the re-weighted story once Develop is ungated. Cross-cites D46, A9, A10.

### D36 — Anti-irritant + rejects endgame *(amended by R-M.1)*

**v5 prior:** Opens silently; no catalog; files stay put; edits in open XMP; deleting Lumina loses nothing; **X never touches the file system**; rail/grammar stable across versions.

- **decision:** All v5 anti-irritant clauses remain. **Amendment (R-M.1):** the **ONE** file-touching verb in the product is the post-export offer **`Rejects to Trash · N files · size`**. macOS Trash only; **never automatic**; **never before ✓**; **never asks twice**. Mark key **X** still never touches the file system.
- **why:** Destructive file motion only after keep-path proof (export ✓); Trash keeps L3/L4 honesty.
- **rejected:** Auto-trash on cull; trash-before-export; second confirms; any second file-touching verb; per-network cleanup “presets.”
- **history / socket:** Amends D36 against real prior text. Copy frozen. Cross-cites D61, D34, CP8.

### D37 — Visual language *(amended by R-X.1)*

**v5 prior:** “Nothing under 44 pt; nothing hover-only.”

- **decision:** **Hover is deleted entirely** (not merely “hover-only affordances banned”). All information is at-rest or during-action. No hover handlers for product information. Rings / marks / primary rules unchanged.
- **why:** R-X.1.
- **rejected:** Timed hover hints as required path; hover keycaps on photographs; hover-only footers as sole teacher.
- **history / socket:** Strengthens D37 “nothing hover-only.” Cross-cites D24, D48.

### D40 — Engineering reconciliation *(history note — retirement schedule)*

**v5 prior:** P0 live path; legacy quarantined and retired checkpoint-by-checkpoint; salvage EmbeddingService (grouping) + ExifToolService; Lab develop into P0; canonical state; XCUITest invariants with every surface; BUILD_LOG per session.

- **decision:** D40 decision text **unchanged**. **History / socket:** the sealed Layer-2 sequence in `design/checkpoint-sequence-v6.md` (SPIKE A/B → CP1–CP8) is the retirement schedule that executes D40. CP4 retires the corresponding legacy cull checkpoint. Harness invariants remain a continuous gate on every surface (not a substitute Layer-2 reorder).
- **why:** Task 5 alignment; doors not deletions (D38).
- **rejected:** Re-entering quarantined types under new names; Lab develop into the legacy shell; interactive grading of camera JPEGs.
- **history / socket:** No weakening of salvage limits or P0-only new work.

---

## New contract entries (rulings + audit)

### D41 — Chip copy in consequence language *(R-5.1)*

- **decision:** Fidelity/readiness chips use **consequence language** of the “sharpness not final” class — facts about the rung’s consequence, never diagnosis essays, never “because.”
- **why:** D18 facts-only bright line; R-5.1.
- **rejected:** Scoring chips; “AI thinks…”; reason chips.
- **history / socket:** Touches D18, D20, D22, D43. Exemplar frozen: `sharpness not final`.

### D42 — Clipping hold grammar *(R-5.2 + A4)* `[● A4]`

- **decision:** See D21 amendment. Clipping glance key = **Hold-J** (momentary; release returns). Adjust-time overlays remain the automatic subset. Numbered here as the ruling entry for citation from checkpoints (CP6).
- **why / rejected / history:** As D21 amendment. Touches D9, D21, D48. Completes R-5.2.

### D43 — Settle-as-confirmation *(R-5.3)*

- **decision:** The **final rung crossfade** is the one sanctioned **positive** truth signal. **No chip invented** for settle / “full truth.”
- **why:** D20 — chip disappearing IS the guarantee.
- **rejected:** “1:1 · full RAW” chips; toast celebrations; second positive truth channels.
- **history / socket:** Touches D20, D41, SPIKE A, CP6.

### D44 — ⌥⌘E recipe re-entry *(R-8.1)*

- **decision:** `⌥⌘E` reopens Export with the recipe pre-filled. Frozen copy: `⌥⌘E changes the recipe.`
- **why:** One chord, one surface; no presets safari.
- **rejected:** Per-network presets; copy-settings flows.
- **history / socket:** Touches D34, D55, CP8.

### D45 — Diagnostics local-only or absent *(R-9.1 + A7)* `[● A7]`

- **decision:** Diagnostics are local-only or absent; reveal/send manual only — never automatic egress. **Scoped amendment (A7):** Beta builds distribute via **TestFlight**; **TestFlight crash reporting is accepted for the beta ONLY**. **Expiry (must not silently persist):** this exception **expires at 1.0** — launch builds are **direct-notarized** (R-I.1 / D50) with **local-only diagnostics** (R-9.1 restored in full). Write the expiry into every beta diagnostics socket so it cannot outlive 1.0 by neglect.
- **why:** D4 / D36 sovereignty; zero-egress ideal at launch; beta needs a crash channel without poisoning 1.0.
- **rejected:** Auto crash reporters in launch builds; background telemetry; network calls from failure chips; letting the TestFlight exception silently persist past 1.0.
- **history / socket:** **Scoped weakening of R-9.1** — one of two Batch-1 weakenings (with A5). Manual reveal chrome OPEN if required — not invented here.

### D46 — Amateur pivot + Develop gate *(R-A.1 + A10)* `[● A10]`

- **decision:** See D32 / success-test amendment. Develop is the sanctioned physical word (key `A`); critical path gated on taste-model proof per A10 schedule (`design/mvp-test-plan.md`).
- **why / rejected / history:** As D32 amendment. Touches D32, D38, D47, A9, A10.

### D47 — Pointer path to culling *(R-A.2 → MVP via A3)* `[● A3]`

- **decision:** Pointer path to culling **ships at MVP** (un-shelved from MVP-question rank). Persistent **✓** and **✕** mark targets on the **focused frame**:
  - **Always visible** (never hover — D48 / R-X.1 holds).
  - Hit target **≥44 pt** (`tokens.yaml` `hit.minimum`).
  - Taps **decide** (Law 3); never commit on release or hover.
  - Each wears its key: ✓ shows **P**, ✕ shows **X** — the button teaches the fast path.
  - Full **same-mark-clears** parity with the keys (D59).
  - Advance behavior **identical** to P/X.
  - Marks are **shapes never color alone** (D37).
- **why:** Amateur door without hover grammar; teaches keyboard without replacing it.
- **rejected:** Hover-only marks; persuasive reject chips; color-only mark encoding; timed double-tap marks; release-commit on the targets.
- **history / socket:** Resolves R-A.2 shelf → MVP. CP4 scope. Touches D10, D37, D48, D59. Multi-select remains shelved (D29/D38).

### D48 — Hover deleted entirely *(R-X.1)*

- **decision:** See D37 amendment. No hover handlers for product information.
- **why / rejected / history:** As D37. Touches D24, D42, D47. Supersedes hi-fi “hover ≥500 ms” teaching.

### D49 — Layout quantized everywhere *(R-X.2)*

- **decision:** Layout quantized everywhere; nothing interpolates at rest; min window implied by 800 pt rail (1280×800); pinch density snaps between named steps.
- **why:** D7 / D28 exact-at-rest.
- **rejected:** Continuous rest interpolation; shrinking decision targets.
- **history / socket:** Touches D7, D28, CP1, SPIKE B. Named density steps beyond current P0 — OPEN for token seal.

### D50 — Distribution Developer ID *(R-I.1)*

- **decision:** Developer ID direct; MAS deferred with socket.
- **why:** Matches offline licensing (D52) during grammar stabilization.
- **rejected:** MAS-first.
- **history / socket:** MAS socket only.

### D51 — Silent updates *(R-I.2)*

- **decision:** Background download; apply on quit; footer fact at most; rollback until first clean launch; grammar-stability suite is the pre-release gate.
- **why:** D36 no update dialogs — silence must be honest.
- **rejected:** Mid-session forced relaunch modals; apply while staging without quit; progress-bar update chrome.
- **history / socket:** Update channel vs zero-egress ideal — OPEN. CP8 binds R-I.2 socket.

### D52 — Offline licensing *(R-I.3 + A8)* `[● A8]`

- **decision:** Offline; no account; at most one cached activation; trial fails with one sentence, one action, nothing lost (D35). **Beta licensing: NONE (A8).** Wave / beta builds are **free** — no license machinery, no expiry ceremony. **R-I.3 implementation is post-test, pre-launch** — not during MVP waves.
- **why:** Sovereignty; quit-anywhere; wave testing must not be gated on licensing chrome.
- **rejected:** Account walls; online heartbeat hard-deps; trial discarding table state; beta license / expiry ceremony; implementing R-I.3 during wave builds.
- **history / socket:** Touches D35, D36, D45. Licensing work starts only after wave testing, before 1.0.

### D53 — Device-plug ingestion *(R-M.2)*

- **decision:** Device-plug ingestion in-contract; iPhone ProRAW + HEIC first-class bodies.
- **why:** Phone bodies are real shoots; “import” as noun stays banned.
- **rejected:** Phone-as-JPEG-only; separate phone mode.
- **history / socket:** Touches D31, CP3, fixture manifest.

### D54 — Sample shoot onboarding *(R-M.3)*

- **decision:** Bundled sample shoot; copy `Sample shoot — yours replaces it`; retires silently on first real ingest.
- **why:** D36 no tours — real photographs are the onboarding.
- **rejected:** Multi-step tours; sample overwriting user work.
- **history / socket:** Touches D36, CP8, fixture sample-shoot spec.

### D55 — Share sheet destination *(R-M.4)*

- **decision:** Share sheet is a destination field on the ONE recipe; no per-network presets.
- **why:** D34 one recipe; banned “preset.”
- **rejected:** Per-network preset packs.
- **history / socket:** Field labels OPEN if chrome needs more words. CP8.

### D56 — Videos copied, counted, not shown *(R-M.5)*

- **decision:** Videos copied and counted, not shown on the table; ✓ covers them.
- **why:** Table is for photographs; card completeness still honest.
- **rejected:** Video frames on the table; auto-transcode; silent leave-behind.
- **history / socket:** Count chrome beyond ✓ — OPEN. CP3.

### D57 — 90 px / PERSUADE *(R-Q.1)*

- **decision:** PERSUADE is the target; adapted previews from **proxy-linear** (never embedded JPEG); warm-in **120 ms** crossfade; near row-mates **120–140 px** within elasticity; Fallback A (brighter ring) **designated**; Fallback B (growth) **rejected**; shipped halo **1.5 pt**; hold-Space on staged strip frame → loupe on **ADAPTED** preview regardless of spike resolution.
- **why:** Closes v5 open question 1 with designated fallback; honesty of adaptation.
- **rejected:** Embedded-JPEG adapted lies; Fallback B growth; loupe ignoring staged adaptation.
- **history / socket:** Supersedes “both fallbacks mocked and unpicked.” Touches D14, D20, D43, SPIKE A, CP7.

### D58 — Halo 1.5 pt restored *(audit)*

- **decision:** Proposal halo ships at 1.5 pt warm-white; selection charcoal distinct (D37).
- **why:** Audit restore; D37 ring taxonomy.
- **rejected:** Collapsing selection/halo color; Fallback B as default.
- **history / socket:** Subordinate to D57 on Fallback A designation.

### D59 — Same-mark clears *(D10 + audit; copy sealed)*

- **decision:** Re-pressing the mark on a marked frame clears it to unreviewed, in place. Decision keys never autorepeat. Frozen copy (verbatim):
  - `Re-pressing the mark on a marked frame clears it to unreviewed, in place. Decision keys never autorepeat.`
  - footer: `P keeps · X rejects · same key again clears`
- **why:** D10 adopted-from-code; recoverability without a second verb.
- **rejected:** Same-key no-ops; modal unmark; hover-to-clear.
- **history / socket:** OPEN closed — verbatim from v5 D10 / re-seal resolution 3.

### D60 — Return-release gate *(D11 + audit; copy sealed)*

- **decision:** After ⇧⏎ stages, ⏎ cannot commit until Return is physically released. One held press can never stage-and-commit. Frozen copy (verbatim):
  - `After ⇧⏎ stages, ⏎ cannot commit until Return is physically released. One held press can never stage-and-commit.`
- **why:** D11 adopted-from-code; D13 release never commits.
- **rejected:** Timed chords; release-commits; compressing ⇧⏎+⏎ into one held press.
- **history / socket:** OPEN closed — verbatim from v5 D11 / re-seal resolution 3. CP7 binds.

### D61 — Export three-state *(audit + D37)*

- **decision:** Export: quiet text (`Export —`, kept = 0) → quiet outline (kept > 0) → dark primary (cull-complete / Open receipts). State-based primary (D37).
- **why:** Progress-of-decisions without progress bars.
- **rejected:** Progress bars; always-dark Export; auto-jump into Export.
- **history / socket:** CP8. Touches D36, D39, D44.

### D62 — Post-commit focus advance *(audit)*

- **decision:** On staged commit (⏎), focus advances to the next row’s first kept frame (skips rejects). Plain arrows still walk every frame.
- **why:** Edit phase reads row → row → row; D39 prediction of the obvious.
- **rejected:** Focus stuck on reference as sole path; arrows that cannot re-mark rejects.
- **history / socket:** CP7. Touches D11, D19.

### D63 — Crop latch keys & ban on decision-key remap *(A2)* `[● A2]`

- **decision:** Numbered citation entry for crop-mode keys and the A/X remap ban. Normative text lives in the D23 amendment. Frozen banner: `Crop · ⏎ applies · Esc cancels`.
- **why:** Checkpoints and tokens need a stable D# for crop latch without overloading D9.
- **rejected:** Inventing additional crop chips or teaching strings beyond the banner.
- **history / socket:** CP6. Cross-cites D23, D9, tokens `grammar.crop_*`.

### D64 — Swim lanes shelved with evidence clause *(A6)* `[● A6]`

- **decision:** **No lane plates** at MVP. The watched tidy is the explanation of grouping; the **time rail + gap language** carry it at rest. **Re-entry door:** if wave-one testers fail the cold probe *what do you think the rows mean?* at a rate that alarms, lanes re-enter **only** as a ruled experiment (new ruling required). Probe lives in `design/mvp-test-plan.md`.
- **why:** Closes the audit’s open swim-lane ruling without inventing chrome; evidence before plates.
- **rejected:** Shipping lane plates without the probe; silent un-shelf; inventing plate copy.
- **history / socket:** Shelf register. Token `color.swimlane_fill_opacity` retained as socket only — not a plate mandate.

### D65 — MVP test fleet & unsupported body *(A1)* `[● A1]`

- **decision:** MVP test floor = Apple Silicon, macOS 14+; Intel never. Bodies at MVP test: Sony A7 IV, Canon R6 II, Nikon Z6 III, Fujifilm X-T5, iPhone ProRAW DNG + HEIC — see `design/fixture-manifest.md` + `design/mvp-test-plan.md`. `[FLAG: body list is Claude's pick; swap freely before fixtures are cut.]` Unsupported body → facts-chip `body not yet supported`; table keeps working (D35 exercise, not a failure modal).
- **why:** Perf contract assumes unified memory + Metal purgeability; phone bodies are first-class (D53).
- **rejected:** Intel support at MVP; modal dead-ends for unsupported bodies; inventing fleet bodies beyond the flagged list without a fixture cut.
- **history / socket:** Fixture critical path ~doubles vs. 3-body plan.

### D66 — Beta distribution posture *(A7 + A8)* `[● A7]` `[● A8]`

- **decision:** Beta via TestFlight with A7 diagnostics exception (expires at 1.0). Wave builds free (A8). Launch = direct-notarized (D50) + local-only diagnostics (D45 restored) + R-I.3 licensing implemented post-test pre-launch.
- **why:** Citation hub for beta vs 1.0 distribution without scattering expiry.
- **rejected:** Shipping 1.0 with TestFlight crash reporting still on; beta license walls.
- **history / socket:** Touches D45, D50, D52.

---

## Shelved Register (v6)

Per D38 + rulings. **Doors, not deletions.**

| Item | Status |
|------|--------|
| Tier 1 + A-ladder / Develop critical path | **Banked / gated** on taste-model proof (D46 / D32 / A10) — prove after wave one |
| ⇧P / ⇧X | Shelved (D10 / D38) |
| Multi-select + two-up | Shelved (D29 / D38) — first-pass hi-fi un-shelf does **not** override v5 |
| Gather-drag | Shelved |
| Cross-row compatibility | Shelved (socket on D17) |
| Seam | Shelved |
| Ordering UI | Shelved |
| Haptics | Socket only |
| Hold-keycap aim | Shelved |
| Folder watching | Shelved |
| Speculative pre-render | Shelved |
| Pointer path to culling | **Un-shelved for MVP** (D47 / A3) — mark targets on focused frame |
| Swim-lane plates | **Shelved with evidence clause** (D64 / A6) — re-enter only via ruled experiment after rows-probe alarm |
| MAS distribution | Deferred socket (D50) |
| Suggested-treatment browsing UI | Shelved |
| R-I.3 licensing machinery | **Post-test, pre-launch** (A8) — absent from wave builds |

---

## Banned patterns & words (carried)

Spinners; skeletons; progress bars; modals/NSAlert in failure paths; hover handlers (D48); timed double-taps; release-commits; localStorage-of-decisions analogs; network calls (zero egress ideal); magic numbers in UI (tokens only); hand-typed copy (frozen table only).

**Banned words:** sync, preset, copy settings, catalog, import (noun), AI, smart, auto, analyze, generate, magic.  
**Develop** sanctioned; key `A`. **Auto** still banned in UI.

---

## OPEN QUESTIONS (remaining)

1. ~~**Taste-model proof protocol** for D46 gate~~ → **scheduled by A10** (after wave one; consented shoots; hand-edit benchmark); artifact details of the harness remain OPEN for build.  
2. **R-5.1** additional consequence-class chips beyond `sharpness not final`.  
3. **D55** share destination field labels.  
4. **D56** whether video count needs chrome beyond ✓.  
5. **D51** update channel vs zero-egress ideal.  
6. **D45** manual diagnostics chrome — absent vs minimal local reveal (beta TestFlight path is A7; launch local-only).  
7. **Named pinch density steps** (D49) for token seal.  
8. v5 open question 2 — keycap tap-to-arm feel (still open).  
9. v5 open question 3 — NSCollectionView virtualization of rows/gaps (still open).  
10. `[FLAG]` A1 body list — Claude’s pick; swap freely before fixtures are cut.  
11. `[FLAG]` A2 crop keys R/O — Claude’s pick; validate with wave-one testers.  
12. A6 rows-probe **alarm threshold** (rate that re-opens lane plates) — not named by the ruling.  
13. Hi-fi / `.cursorrules` crop latch still documents A/X re-scoping — must be aligned to D23/D63 (A/X remap banned) in a code/.cursorrules session (FOLLOW-UP; not silent dual grammar).

*Closed by re-seal:* v5 source; Layer-2/D40; D59/D60 verbatim; v5 open question 1 (90 px) → D57.  
*Closed by Batch 1:* R-5.2 key name → Hold-J (A4); R-A.2 shelf → MVP pointer marks (A3); swim-lane plates → shelved with evidence (A6); beta diagnostics/licensing posture (A7/A8); D16 compression (A5).

---

## FOLLOW-UPS (not this session)

- Codegen Swift constants from `design/tokens.yaml` (CP0 / build).  
- Wire new copy constants through UI surfaces beyond CopyContract string drop (incl. A5 compression, crop banner, `body not yet supported`).  
- Remove remaining hover *handlers* in product chrome (D48) — CP5 / build; this re-seal only drops the superseded CopyContract hover string.  
- Implement fixture manifest bodies (six-body fleet — critical path).  
- Grammar-stability suite (D51).  
- Taste-model proof harness after wave-one eval set exists (D46 / A10) — do not begin earlier.  
- Align `.cursorrules` / hi-fi crop latch A/X remapping docs to D23/D63 (R/O; A/X ban).  
- R-I.3 licensing implementation post-test, pre-launch (A8).  
- Strip TestFlight crash reporting at 1.0 (A7 expiry).  
- `seal-v6.1` tag after human review + seal verification (not this session).
