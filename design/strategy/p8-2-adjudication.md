# P8.2 — Adjudication (strategy session)

**Session id:** P8.2-ADJ (PART 0 of the wiring cascade)  
**Branch:** `cursor/p8-2-adjudication-b243` · **Base measured:** `origin/main` @ `f2e9ee3` (`Lightweight footprint: exclude harness from Release and defer P0 develop init (#55)`)  
**Authority:** `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests  
**Contract status read before citing:** `design/contract-v6.md` L3 — *Amendment Batch 1 (A1–A10) + **Batch 2 (A11–A13)** on sealed re-seal.* Batch 3 / `D67`: `rg -c '\bD67\b' design/contract-v6.md` → **0 hits** — **NOT RATIFIED**; nothing below is built against it.  
**Provenance only, not run, not cited as authority:** `design/contract-v5.md`, `design/hifi-reference.html`.  
**Deliverable:** this document + one `BUILD_LOG.md` entry. **No product, test, or harness code in this session.**  

---

## METHOD AND COVERAGE

### The finding that reorders this document

**PART 0 was written to run before any merge. The merges already happened.** Six of the eight cascade branches landed on `origin/main` on 2026-08-13, in the exact order P8.2 recommended, before this adjudication was commissioned:

| Merge commit | Date | PR | Lands |
|---|---|---|---|
| `a366d38` | 2026-08-13 | #47 | **W1** gate truth |
| `90c075f` | 2026-08-13 | #48 | **W3** cull grammar |
| `137deaa` | 2026-08-13 | #49 | **W4** motion wiring |
| `30aa6a5` | 2026-08-13 | #50 | **W5** key routing |
| `25dcbef` | 2026-08-13 | #51 | **W6** memory budget |
| `e0d4473` | 2026-08-13 | #53 | **W8** legacy severance |
| `c7c999b` | 2026-08-13 | — | post-merge allowlist re-baseline (unowned by any PART) |
| `3f41c93` · `f2e9ee3` | 2026-08-14 | #54 · #55 | harness inventory cleanup · Release footprint |

Command: `git log --oneline -12 origin/main`; parents confirmed per commit with `git log -1 --format='%P'`.
**W2 never existed as a branch.** **W7** exists as one doc-only commit and is unmerged: `git log --oneline origin/main..origin/cursor/w7-failure-grammar-39dd` → `314ef1e docs(W7): PLANNED — CP8 gate blocks failure-grammar build`.

**Does the cascade need re-cutting rather than merging?** No — and it cannot be. It is merged. The honest statement is narrower and worse: **the cascade was merged without the adjudication that was supposed to gate it, so three of the five items below (0.2, 0.3, 0.5) now describe debt sitting on `main` rather than conditions on a branch, and the one item that could have changed a merge decision — 0.4, stacked branches — is now only reportable, not actionable.** Nothing in this document proposes reverting a merge. What re-cutting *would* be needed for is the two parts that never ran: **PART 2 / row 3** (0.1) and **PART 7 / CP8** (gated, correctly).

### What this session could and could not measure

| Command | Result on `f2e9ee3` (Linux) |
|---|---|
| `git rev-parse --short HEAD` | `f2e9ee3` |
| `python3 Scripts/harness/run.py fast` | **PASS** 7401 ms · **37/37** orchestration · **0 app tests executed / 0 expected** |
| `python3 Scripts/harness/run.py full` | **PLATFORM-UNAVAILABLE** 111 ms · **0 app tests executed / 7 expected** |
| `python3 Scripts/harness/heavy/run_job.py ram_tier_runs` | **PLATFORM-UNAVAILABLE** — `ram_tier_runs requires macOS Apple Silicon` |
| `python3 Scripts/harness/lint/orphan_symbols.py` | **OK** — `22 orphans registered, 0 dead reported` |
| `bash Scripts/harness/lint/magic_numbers.sh` | **OK** — `95 token literals derived` |
| `bash Scripts/harness/lint/banned_patterns.sh` | **OK** (via FAST) |
| `python3 Scripts/harness/codegen/tokens_codegen.py --check` | **OK** — `hash=1b1db60f4b92…` |
| `rg -c '\bD67\b' design/contract-v6.md` | **0 hits** |
| `xcodebuild … build` · `xcodebuild … -only-testing:LuminaLogicTests test` | **PLATFORM-UNAVAILABLE** — Linux cloud VM, no Xcode / macOS SDK (`AGENTS.md`) |

**PLATFORM-UNAVAILABLE means not verified.** No claim below about compilation, runtime behaviour, resident bytes, or latency is asserted from this host. Three throwaway measurement instruments were used and live in `/tmp`, not in the repo: `/tmp/classify_orphans.py` (0.2 reference sites), `/tmp/orphan_scope.py` (0.2 scan-scope and post-W8 live rule), `/tmp/lane_coverage.py` (0.5 lane holes). Each is a read-only re-implementation of a shipped gate's own rule; every number they produce is cross-checked against the shipped gate's own output where one exists.

### The nine-row instrument re-read on `main` — the headline

P8.2 (`design/strategy/surface-sweep.md` §6) judged `main` @ `83ba118` as **Before on all nine rows**. On `f2e9ee3`:

| # | Row | Reading on `f2e9ee3` | Verdict |
|---|---|---|---|
| 1 | Orphan register | **22** registered, **0** dead (gate rule) · **43** under a post-W8 live rule (§0.2) | **FAIL** — gate exists, count ≠ 0 |
| 2 | Grammar implementations (app) | **1** — `P0SessionModel` routes marks through `CullGrammarMachine` only | **PASS** (caveat §0.2 note 3) |
| 3 | Decision-persistence roots | **2** — journal L1146/L1152 **and** `ShootStore.saveShoot` L1095/L1125 | **FAIL** — Before, everywhere |
| 4 | Key-routing owners (live path) | **1** — `P0KeyRoutingModifier`; legacy header claim now true | **PASS** |
| 5 | Esc owners | **1** — `P0EscLadder`; zero view-level `.onKeyPress(.escape)` | **PASS** |
| 6 | Memory gate | Structure present; ledger **absent**; bytes **UNMEASURED** | **UNMEASURED** |
| 7 | Legacy reachable from launch | Behind `P0LegacyShellContainer`; no legacy `@State` at launch | **PASS** |
| 8 | Magic-number literals gated | **95** derived literals; **277** allowlisted rows | **PASS** with declared debt |
| 9 | Banned-pattern strict scope | **7** strict roots · **72 of 160** product files strict · **54** in **no lane** | **PARTIAL** |

**Four rows read After (2, 4, 5, 7), one reads After with declared debt (8), two read Before (1, 3), one is unmeasurable on this host (6), one is partial (9).** That is the correct current reading, and it is materially better than P8.2's. It is also not wave-worthy: §0.5 adds six blocking readings that had no row at all.

---

## 0.1 — W2 IS GONE AND WAVE 1 RIDES ON IT

### Verification — every tip, with line numbers

`git show <ref>:<path>` on each tip. `ShootStore.swift` L36 is `shoot.json`; `supportDirectory()` resolves through `.applicationSupportDirectory` (L22) and `projects/<name>` (L30), i.e. a central store away from the shoot.

| Tip | `shoot.json` | journal in `P0SessionModel` | sidecar in `P0SessionModel` | `ShootStore.shared.save*` |
|---|---|---|---|---|
| `origin/main` `f2e9ee3` | L36 | **1146, 1152** | **1158, 1168, 1170** | **1095, 1125** |
| W1 `8ef67e6` | L36 | 1059, 1065 | 1071, 1081, 1083 | 1008, 1038 |
| W3 `d35eae1` | L36 | 1133, 1139 | 1145, 1155, 1157 | 1082, 1112 |
| W4 `018ecaa` | L36 | 1059, 1065 | 1071, 1081, 1083 | 1008, 1038 |
| W5 `f7bc9fe` | L36 | 1059, 1065 | 1071, 1081, 1083 | 1008, 1038 |
| W6 `1a67da5` | L36 | 1059, 1065 | 1071, 1081, 1083 | 1008, 1038 |
| W7 `314ef1e` | L36 | 1059, 1065 | 1071, 1081, 1083 | 1008, 1038 |
| W8 `8628307` | L36 | 1059, 1065 | 1071, 1081, 1083 | 1008, 1038 |

**Both write paths are wired simultaneously on every tip and on `main`. No branch consolidates them.** Confirmed also:

- Replay on open is `ShootCrashRecovery.replayJournal` at `Lumina/Services/ContactSheetPreparation.swift:149` and `:296` — the prompt's `~149, ~296` is correct; the symbol is `ShootCrashRecovery`, not `ShootDecisionJournal` directly.
- `ShootDecisionJournal.swift` says what it is in its own header (L3): *"CP2 persistence (journal + open XMP sidecars)"*, L5: *"Staging is intentionally absent (D13)"*.
- `persistShootImmediately` (`P0SessionModel` L1110) writes the **whole** `ShootRecord` on every cull mutation.

### What shoot.json actually carries — the divergence is wider than "2 roots"

`ShootRecord` (`Lumina/Models/P0State.swift:384–413`) persists, inside the central store: `assets: [AssetRecord]` (per-asset `cull` **and** `recipe`), `finalSetOrder`, `decisionLedger: [DecisionEvent]`, `batchHistory`, `exportHistory`, `wholesaleExcludedPhotoIDs`, `workspace`. So the catalog carries **decisions, edits, order, and exclusions** — not a pointer.

Contract, grep-verified this session:

- **D36** (`design/contract-v6.md` L107–114) — v5 prior clause carried verbatim: *"Opens silently; **no catalog**; files stay put; edits in open XMP; deleting Lumina loses nothing"*. All v5 anti-irritant clauses remain in force; R-M.1 amends only the Trash verb.
- **D35** — failure-mode law, carried into v6 by L26 (*"All of Contract v5 (D1–D40) remains law except where an amendment below replaces named clauses"*) and cross-cited at v6 L31 (*"Session L3/L4 failure & persistence language remains the operational reading of D35/D36"*), L218, L312. Quit-anywhere restores the exact table.
- **D13** — release never commits; staged is never persisted. Carried by L26, cited at v6 L278 (*"D13 release never commits"*). The journal honours this by construction (`ShootJournalRecordKind` has exactly `cull.commit` and `edit.commit`).
- `design/fixture-manifest.md` L5, independent of the contract: *"Marks/edits/staging are not cached as a second store of decisions."* `shoot.json` is exactly that second store.

`decisionLedger` is appended only by `Lumina/ViewModels/ProjectViewModel.swift:1099,1114` — the legacy shell — so on the live path it is carried-but-empty. The live divergence is **journal (authoritative on read) vs `shoot.json` (authoritative on write, unreconciled)**, with XMP sidecars beside originals as the ruled open format. Three stores, two of them decision-bearing, no reconciliation contract.

### The gates that look like proof are mirror gates

FAST is green on `cp2_journal_kill_fuzz`, `cp2_lr_round_trip`, `f06_data_safety_bounded`. They do not touch the divergence:

- `rg -n 'shoot\.json|ShootStore' Scripts/harness/cp2/` → **no matches**. The CP2 gates never open the catalog.
- `Scripts/harness/cp2/journal_kill_fuzz.py` L28 docstring: *"Mirror `ShootDecisionJournal.readCommittedRecords` trailing-line recovery."* It SIGKILLs a **Python** worker writing JSONL and verifies a **Python** reader recovers it.

This is the cascade's own thesis appearing a third time: law sealed in `artifacts/`, mirrored in Python, never executed by the app. **Row 3 is not "untested" — it is tested by a mirror that cannot see the bug.** That is worse than a red row, because it reads green.

### Cost basis

The prompt asks for weeks-of-exposure. **I decline to invent week counts** — this session has no schedule input and a fabricated duration would be the same class of error as a fabricated measurement. Exposure is costed in the units the tree actually provides: distribution artifacts shipped while the divergence is live, and write paths that can diverge.

| | (a) Restore PART 2, narrowed to severing the decision-WRITE path | (b) Schedule P5 / CP2 with an owner and a position |
|---|---|---|
| **Files touched** | `Lumina/Services/ShootStore.swift`, `Lumina/ViewModels/P0SessionModel.swift` (2 call sites: L1095, L1125), `Lumina/Models/P0State.swift` (`ShootRecord` shape), `Lumina/Models/ShootMigration.swift` (L60, L153 carry `decisionLedger`), `Lumina/Services/ContactSheetPreparation.swift` (L149, L296 replay must survive a thinner record) | Same set, plus journal/sidecar/kill-fuzz/XMP round-trip/crash-only-startup, as one checkpoint |
| **Collides with PART 3?** | **No — the collision is gone.** PART 3 landed at `90c075f`; `P0SessionModel` is unowned by any open PART. This is the one respect in which (a) is *cheaper* than when the cascade was written. | n/a |
| **Blast radius** | Resume (D32 / D39) reads `workspace` **and** `assets` from `shoot.json`; thinning the record moves resume onto folder-scan + journal replay. Recent-shoot list (`P0SessionModel:220`) reads the same store. A partial or corrupt legacy `shoot.json` must reconcile once, never drop — and there is no ruled format for "newer than its journal". | Same radius, but taken with the migration contract, the fault schedules, and the round-trip in one session |
| **Verifiable on the available host?** | **No.** PART 2's VERIFY list is 4 commands; 3 are macOS-gated (`xcodebuild build`, `xcodebuild -only-testing:LuminaLogicTests test`, and `f06_data_safety.py --bounded` is Linux-runnable but exercises the Python mirror, not the app). Data-safety surgery would merge **UNVERIFIED**. | Same platform constraint, but a checkpoint session is scoped to include the macOS run rather than to work around its absence |
| **Exposure while open** | Ends sooner, but ends with an unverified write-path change on the highest-risk surface | Every wave artifact cut before P5 ships the divergence. §5 already gates **Wave 1 on P5 alone** — so the exposure is bounded by a gate that already exists and is already published |
| **Fault-schedule proof** | Cannot be delivered: PART 2 item 4 requires *every bounded fault schedule in fixture-manifest §2*, and §2 schedules (`card-disk-full`, `card-two-card`, `card-corrupt-file`) are **specifications** — no fixture assets exist in the tree (see §0.3) | The schedule cut is CP2/CP3 work by definition |

### RULING OWED — row 3 ownership

```
RULING-OWED — P8.2-ADJ / 0.1 — decision-persistence root
PRECEDENT: P8 distribution ruling (BUILD_LOG 2026-08-13, "P8 operator ruling:
  wave sequencing (P7 / R3 / P5)"), which fixed Wave 1's gate as P5 alone.

FACT (not in dispute): on origin/main @ f2e9ee3 and on all eight W tips, decisions
  are written twice — ShootDecisionJournal beside the shoot (P0SessionModel
  L1146/L1152) and the full ShootRecord into ~/Library/Application Support/
  Lumina/projects/<name>/shoot.json (L1095/L1125, ShootStore.swift L36).
  D36 carries v5's "no catalog" clause verbatim (contract-v6.md L109).
  The three green CP2 gates never read shoot.json.

OPTION (a) Restore a narrowed PART 2 — sever the decision-WRITE path only.
  Reduce shoot.json to resume pointer + recent list; migrate an existing
  shoot.json into the journal once, on open; leave replay, kill-fuzz, XMP
  round-trip and crash-only startup to P5.
  COST: no PART collision remains (PART 3 landed). Cannot be verified on a Linux
  host — 3 of 4 VERIFY commands are macOS-gated. Cannot satisfy its own item 4
  (fixture-manifest §2 schedules are specs, not assets). Merges the riskiest
  data change in the tree with a PLATFORM-UNAVAILABLE instrument reading.

OPTION (b) Schedule P5 / CP2 with a named owner and a position in the sequence,
  accepting row 3 red until CP2 lands.
  COST: row 3 stays Before through Wave 0. D36's "nothing you did is ever lost"
  stays a claim. Exposure is bounded by the already-published Wave 1 gate.

RECOMMENDATION: (b), with two conditions that must be recorded in the ledger,
  not in a commit message:
  1. P5 is scheduled with an owner and a position NOW — the defect P8.2 named
     ("the highest-risk row moved from a session with a prompt to a session with
     a name") is fixed by giving P5 a prompt, not by re-opening W2.
  2. If a macOS host becomes available before P5 is scheduled, option (a)
     narrowed is defensible — but as CP2's FIRST COMMIT under the one-checkpoint
     rule (checkpoint-sequence-v6.md FOLLOW-UPS), never as a separate W2 that
     would span two checkpoints.
ALSO OWED: rule on whether the three CP2 mirror gates may keep reporting green
  while the app has two write roots. My reading: they may run, but they must not
  be cited as CP2 coverage. They are Python-vs-Python.
```

---

## 0.2 — 28 ORPHANS AGAINST 4 PREDICTED

### First: the register is 28 on W1, 25 on `main`, and the gate counts 22

| Ref | Register rows | Gate reports |
|---|---:|---:|
| `83ba118` (pre-cascade) | file absent | no gate |
| W1 `8ef67e6` | **28** | 28 orphans, **2 dead** (`DecisionDock`, `DecisionDockButton`) |
| W4 `018ecaa` | **25** | 25 (W4 wired `LuminaSpring`, `LuminaSpringCurve`, `LuminaSpringParams`) |
| `origin/main` `f2e9ee3` | **25** | **22 orphans, 0 dead** |

`grep -vc '^#' artifacts/harness/orphan_register.txt` = 25; `orphan_symbols.py` = 22. **Three register rows are stale** — `CullGrammarEvent`, `CullGrammarMachine`, `CullGrammarState` now have live references in `P0SessionModel` (W3), so the gate no longer detects them, and **the gate does not fail on a stale row** (`main()` only fails on detected-orphans-not-registered). PART 3's exit condition — *"orphan_symbols must no longer report CullGrammarMachine"* — is satisfied in the gate output and violated in the register file. The ledger over-reports its own debt by 3, silently.

### Classification of all 28 (W1-tip register), with evidence

Reference sites measured tree-wide by identifier, the same rule the gate uses. `LIVE` = a file under `Lumina/Views/`, `ViewModels/`, `Services/`, `Persistence/`, `Models/`, `Shell/`, or `LuminaApp.swift` / `ContentView.swift` / the two Design bridges, excluding scan dirs. `SCAN-PEER` = another file inside `Lumina/Core`, `Lumina/Design`, `Lumina/Views/Components`.

| # | Symbol · file | Every reference site | Class | Owner |
|---|---|---|---|---|
| 1 | `BetaDiagnosticsSocket` · `Core/BetaDiagnosticsSocket.swift` | TEST `BuildManifestTests.swift`(1) | **TRUE ORPHAN** — sealed null socket, deliberately unwired (D45/A13) | CP8 / R3 |
| 2 | `CullGrammarEvent` · `Core/CullGrammarMachine.swift` | LIVE `P0SessionModel.swift`(1) | **STALE ROW** — wired by W3 | — |
| 3 | `CullGrammarMachine` · same | LIVE `P0SessionModel.swift`(4); TEST `CullGrammarTests.swift`(11) | **STALE ROW** — wired by W3 | — |
| 4 | `CullGrammarState` · same | LIVE `P0SessionModel.swift`(1) | **STALE ROW** — wired by W3 | — |
| 5 | `CullGrammarSnapshot` · same | self-file L62, L108, L300–301 | **DETECTION MISS** — same-file support type of a live-wired type; the gate never follows into the declaring file | CP4 |
| 6 | `CullGrammarStaging` · same | self-file L43, L49, L59, L275 | **DETECTION MISS** — same as above | CP4 |
| 7 | `CullHoldKey` · same | self-file L21–22, L61 | **DETECTION MISS** — enum reached only as an associated value / `Set` element | CP4 |
| 8 | `LuminaBuildManifest` · `Core/LuminaBuildManifest.swift` | TEST `BuildManifestTests.swift`(3); consumed as JSON by `Scripts/harness/release/*` | **TRUE ORPHAN** — harness-consumed by file, not by symbol | R3 |
| 9 | `ProbePolling` · `Core/ProbePolling.swift` | TEST `ProbePollingTests.swift`(2), `LuminaUITests/Support/XCUIApplication+Probe.swift`(1) | **TRUE ORPHAN** — test-support only | CP4 / M1 |
| 10 | `LuminaSpring` · `Design/LuminaSpring.swift` | at W1: `LuminaSpringTests` only | **TRUE ORPHAN then — WIRED NOW** by W4 (bridge `LuminaSpringAnimation.swift`) | P7 → closed |
| 11 | `LuminaSpringCurve` · same | at W1: self + tests | **WIRED NOW** (W4) | P7 → closed |
| 12 | `LuminaSpringParams` · same | at W1: self + tests | **WIRED NOW** (W4) | P7 → closed |
| 13 | `LuminaSpringRetarget` · same | self-file L74, L109 (params of the live API); TEST `LuminaSpringTests.swift`(1) | **DETECTION MISS** — parameter type of a wired API | P7 |
| 14 | `LuminaWorkspaceAppearance` · `Design/LuminaTokens.swift` | self-file L231, inside `extension View { luminaWorkspaceAppearance() }`; that helper is called from **`Lumina/LuminaApp.swift:38`**, `WorkbenchCapture.swift:141`, `P0EditLiveRunner.swift:393`, `DevelopLabLauncher.swift:45` | **DETECTION MISS — ON THE LAUNCH PATH.** Deleting it breaks `LuminaApp`. This is the false positive the cascade warned about, and it is registered as debt today. | CP1 |
| 15 | `A1Invariant` · `Design/StagingCopyContext.swift` | TEST `DevelopStagingTests`(1), `P0LogicTests`(5), `PropagationTests`(1) | **TRUE ORPHAN** — A1 count invariant proven in tests, unwired in UI | CP7 |
| 16 | `PropagationRing` · same | SCAN-PEER `Core/PropagationState.swift`(2), `Core/CullGrammarMachine.swift`(1) ← now live, `Design/CopyContract.swift`(1) | **DETECTION MISS** — transitively reachable through the live-wired machine; the gate computes one hop, not a closure | CP7 |
| 17 | `FloatingDecisionShelf` · `Views/Components/FloatingDecisionShelf.swift` | **none** | **DEAD BY COUNT** — dispositioned `DELETE-AT post-CP4` | CP4 |
| 18 | `FloatingShelfButtonStyle` · same | self-file L85, from #17 only | **DEAD BY COUNT (chain)** — dies with #17 | CP4 |
| 19 | `RecoveryFactsChip` · `Views/Components/RecoveryFactsChip.swift` | **none** (self-refs 6: declaration + previews) | **WIRE-OWED** — zero references, but a live owning checkpoint and a scheduled session (W7/CP8). Not DEAD. | CP8 / W7 |
| 20 | `StableThumbView` · `Views/Components/StablePhotoView.swift` | SCAN-PEER `WorkspaceChrome.swift:129`, inside `AttemptFilmstrip` (#22, zero refs) | **DEAD BY COUNT (chain)** — reachable only from a zero-reference type | CP7 |
| 21 | `DockedChipLaneDropModifier` · `Views/Components/SwimLaneContainer.swift` | self-file L44, from `SwimLaneContainer`, which is referenced by `ContinuousWorkspaceView`, `TableLayout`, `P0LogicTests`, `HiFiTokens.generated` | **DETECTION MISS + SHELF-PROTECTED** — private modifier of a used container; the container is the D64 swim-lane / docked-chip surface | CP7 (see CONFLICT 1) |
| 22 | `AttemptFilmstrip` · `Views/Components/WorkspaceChrome.swift` | **none** | **DEAD BY COUNT** — file dispositioned `PORT-TO-P0 CP7`, this type is not part of the propagation set | CP7 |
| 23 | `GroupRelationshipCaption` · same | **none** | **DEAD BY COUNT** | CP7 |
| 24 | `LensSwitcher` · same | **none** | **DEAD BY COUNT** | CP7 |
| 25 | `LuminaCard` · same | **none** | **DEAD BY COUNT** | CP7 |
| 26 | `WorkspaceCommandBar` · `Views/Components/WorkspaceCommandBar.swift` | **none** | **DEAD BY COUNT** — file has **no disposition row** | unassigned |
| 27 | `LuminaCommandButton` · same | self-file only, from #26 | **DEAD BY COUNT (chain)** | unassigned |
| 28 | `LuminaCommandPressStyle` · same | self-file only, from #26 | **DEAD BY COUNT (chain)** | unassigned |

### Counts per class

| Class | On the W1 register (28) | On `main`'s register (25) |
|---|---|---|
| **TRUE ORPHAN** — tests/self only, owned | **10** (#1, 2, 3, 4, 8, 9, 10, 11, 12, 15) | **4** (#1, 8, 9, 15) |
| **DETECTION MISS** — reachable, route the scanner cannot see | **6** (#5, 6, 7, 13, 16, 21) | **6** (same) |
| **DETECTION MISS — on the launch path** | **1** (#14) | **1** (#14) |
| **WIRE-OWED** — zero refs, owning checkpoint, scheduled session | **1** (#19) | **1** (#19) |
| **DEAD BY COUNT** | **10** (#17, 18, 20, 22–28) | **10** (same) |
| **STALE ROW** — now live, still registered | **0** | **3** (#2, 3, 4 — wired by W3) |
| **WIRED SINCE** | — | #10, 11, 12 (wired by W4; rows removed) |
| **DEAD** — separate gate report | **2** — `DecisionDock`, `DecisionDockButton` | **0** (deleted by W8) |
| **UNCLASSIFIED** | **0** | **0** |
| **Total register rows** | **28** | **25** (gate detects **22**) |

### The expectation is not met, and I will not soften it

The cascade predicted *"most of the extra 24 are DETECTION MISS."* **They are not.** Seven of 28 are detection misses. **Ten are dead by measurement:** nine have no reference from any other file in the tree, including tests, and their only in-file callers are themselves in that set; the tenth (`StableThumbView`) is reachable only from `AttemptFilmstrip`, which is in it. That is legacy workspace chrome which compiles, ships in the binary, and is called by nothing. Three more rows are stale. The unwired surface is real, and the register understates it in three independent directions:

**1. The gate scans 53 of 390 product type declarations — 13.6%.**

```
type declarations inside orphan scan scope:  53
type declarations OUTSIDE orphan scan scope: 337
    Lumina/Models/ 59 · Services/ 51 · Views/ 50 · Develop/ 37 · Views/Workspace/ 35
    Views/P0/ 23 · Presentation/ 18 · Persistence/ 14 · Develop/Lab/ 11 · Shell/ 9
    Testing/ 9 · ViewModels/ 6 · Lumina/ 5 · Testing/ProbeV2/ 5 · Rendering/ 4
```

`SCAN_DIRS` is `Lumina/Core`, `Lumina/Design`, `Lumina/Views/Components` (`orphan_symbols.py` L13–17). "Orphan register 0" is therefore a claim about one seventh of the tree.

**2. The gate counts the severed legacy shell as "live", so 21 symbols read as wired to a door.**

`LIVE_PREFIXES` (L27–34) includes `Lumina/Views/` and `Lumina/Shell/` wholesale. After W8, `Lumina/Views/Workspace/**`, `Lumina/Shell/**`, `Lumina/ContentView.swift` and `ProjectViewModel.swift` are reachable only through `P0LegacyShellDoor` — a door, not the launch path. Re-running the gate's own analysis with those paths removed from LIVE:

```
gate rule           — orphans in scan dirs: 22
post-W8 live rule   — orphans in scan dirs: 43
HIDDEN by counting the severed legacy shell as live: 21
```

The 21 include `PropagationState`, `PropagationScope`, `TablePhotographSelection`, `StagingCopySnapshot`, `TableLayout`, `CopyContractBuilder`, `LuminaHaptics`, `LiveDevelopView`, `WorkbenchDevelop`, `CropOverlayView`, `DevelopHistogramView`, `EditProvenanceChip`, `GradedPhotoView`, `StablePhotoView`, `SpineActiveStage`, `SwimLaneContainer`, `ShortcutsGlanceOverlay`, `DecisionReceiptBanner`, `WorkspaceToolbar`, `SectionHeader`, `PhotoStripPreview`. Several are the CP7 propagation set, which **must not be deleted** (D38, and `legacy-disposition.md` §"CP7 propagation set"). The point is not that they should be deleted — it is that **the gate cannot tell "wired to the live path" from "wired to a door", so it cannot be the instrument that decides a deletion.**

**3. `DEAD` is a hardcoded one-file allowlist, not a measurement.** `DEAD_FILES = {"Lumina/Views/Components/DecisionDock.swift"}` (L45–49). Eleven symbols now satisfy the prompt's own DEAD definition and none of them can be reported as DEAD, because the file is not on the list. The gate reports `0 dead` on a tree containing eleven zero-reference types.

**Note 3 (row 2 caveat).** After W3's ADOPT the app runs one grammar, but the *gate* still runs none of it: `Scripts/harness/probe/grammar_machine.py` L2 — *"Python mirror of `Lumina/Core/CullGrammarMachine.swift` for FAST parity (F02.5) … Must stay aligned with Swift."* `grammar_oracle_parity` compares a Python oracle to a Python mirror. Three implementations of the grammar exist (Swift machine, `simulator.py`, `grammar_machine.py`); the app uses one and the gate compares the other two. Row 2's After is honest about the app and still says nothing about what ships.

### Rule change for PART 1 to implement later — self-classifying gate

Specified, not built. Six changes, in dependency order:

1. **Compute live reachability as a transitive closure from `LuminaApp`, not a one-hop directory test.** `Scripts/harness/lint/swift_reachability.py` already does a symbol BFS seeded at `Lumina/LuminaApp.swift` and W8's BUILD_LOG already used it. Reuse it; do not maintain a second notion of "live". This alone reclassifies #5–7, #13, #16, #21 automatically and stops #14 being registrable at all.
2. **Model the door.** A symbol reachable from `LuminaApp` *only* through `P0LegacyShellDoor` is class `BEHIND-DOOR`, with the owning checkpoint read from `design/strategy/legacy-disposition.md`. Not orphan, not live. This is the 21.
3. **Emit the class, not just the count.** Register rows become `path symbol CLASS owned-by-CP<N> reason`, where CLASS ∈ `TRUE-ORPHAN | DETECTION-MISS | BEHIND-DOOR | WIRE-OWED | DEAD | UNCLASSIFIED`, and the gate **recomputes and diffs the class** rather than trusting the file.
4. **Fail on a stale row.** A registered symbol that is no longer detected is a FAIL with the message "wired — remove the register row", so the ledger cannot over-report. This is the fix for #2–4.
5. **Derive DEAD; delete `DEAD_FILES`.** DEAD = zero references tree-wide including tests **and** no owning checkpoint in the disposition register or the register row. A zero-reference symbol *with* an owner is `WIRE-OWED` — the discriminator the prompt's three classes lack, and the reason #19 (`RecoveryFactsChip`) must not be deleted by a PART 8 acting on a count.
6. **Widen `SCAN_DIRS` to the same set the banned-pattern strict lane uses**, and register the resulting hits in one mechanical commit. Until then, HARNESS.md must say the orphan gate covers three directories.

**No PART may act on `UNCLASSIFIED`.** There are none today, and rules 1–5 must land before the count changes, or the reclassification will read as new debt.

---

## 0.3 — CEILINGS NAMED AND UNVALIDATED

### What exists

`Scripts/harness/heavy/ram_tiers.sh` exists (W6, 944 bytes) and refuses to produce a vacuous PASS: on a non-Darwin host it prints `PLATFORM-UNAVAILABLE: ram_tier_runs requires macOS Apple Silicon` and exits 2. HARNESS.md L70 already carries the row (`RAM tier gate … HEAVY / W6 — active on macOS`), so PART 1's item E is closed by W6 landing.

Ceilings, hand-named in `Lumina/Services/PhotoImageCacheBudget.swift` L7–18, each with a comment:

| Constant | Bytes | Comment |
|---|---:|---|
| `gridTierCeilingBytes` | 48 MiB | grid decode cap (512 px) |
| `previewTierCeilingBytes` | 96 MiB | preview / filmstrip (1600 px) |
| `proxyTierCeilingBytes` | 128 MiB | proxy / unbounded |
| `totalCeilingBytes` | 256 MiB | combined LRU table |
| `prefetchConcurrencyWidth` | 8 | *"tied to `PreparedRawSession` capacity (4) doubled"* |

`artifacts/harness/ledgers/` contains **only** `orchestration-only.json`. **`ram-tiers.json` does not exist. No ceiling has ever been measured.**

### Four findings that make the gate weaker than its label

1. **The named ceiling is not the gate; twice the ceiling is.** `RamTierHarnessRunner.swift:161` — `let pass = peakDuring <= baselineRSS + UInt64(spec.ceilingBytes) * 2 && cacheBytes <= …totalCeilingBytes`. A 2× slack multiplier on a ceiling means the published number cannot fail a run that doubles it.
2. **The fixtures are synthesized flat rectangles.** `synthesizeJPEG` (L181–200) writes `640+…×480+…` single-colour sRGB JPEGs; the tier ids `mixed-200` and `card-clean-500` are labels on generated placeholders, not the fixture-manifest sets. The CRAFT BAR names this exact failure — *"card-clean-500 and mixed-200, not a dozen placeholder rectangles."*
3. **The RAW rung is never exercised.** All three `tierSpecs` (L22–44) set `allowRAW: false`, and none sets `maxPixelSize: nil`, so `proxyTierCeilingBytes` (128 MiB) — the only ceiling that a full-RAW `NSImage` can breach — has **no tier that reaches it**. The fidelity rung ladder is the memory architecture; the gate measures the two cheapest rungs.
4. **The ledger will announce itself as validated.** L74–81 writes `"mode": "measured"` and `"gates_active": true` unconditionally, with a single free-text `"proposal"` string. HARNESS.md L117–123 defines exactly the opposite convention for the numbers ledger: `mode: orchestration-only`, `gates_active: false`, entries `status: UNMEASURED` until a macOS run populates samples. The RAM ledger does not follow the convention the harness already has for this problem.

On Linux the ceilings are guarded only by a **source-text presence** test: `Scripts/harness/tests/test_w6_memory_budget.py` asserts the constant names appear and that the string `"proposal awaiting contract ruling"` is present (it runs inside FAST `unit_invariants`, which discovers `Scripts/harness/tests/test_*.py`). That is a spelling check, not a budget check.

### Adjudication

**Every ceiling is PROVISIONAL until one macOS run against real fixtures confirms it, and a PROVISIONAL ceiling may NOT block a merge.** Recorded here, in the ledger, and not in a commit message — as instructed.

Failure mode of each alternative, stated plainly:

| Posture | Failure mode |
|---|---|
| **Loose ceiling, promoted now** | Gates nothing and reads green forever. Already half-present: the 2× multiplier plus grid-only tiers means the current gate would pass a build that retains four times the grid budget. |
| **Tight ceiling, promoted now** | Fires on fixture noise — and on a synthetic-JPEG corpus every number *is* noise, because peak RSS depends on placeholder dimensions nobody chose deliberately. It gets disabled by the third person it annoys, and the disabling is invisible because the ledger is gitignored-adjacent run output. |
| **PROVISIONAL, non-blocking (adjudicated)** | The gate can be wrong for a while without lying: it publishes bytes and a proposed ceiling, and a breach is a **reading**, not a merge stop. Cost: a real regression can land. Mitigation is honesty, not slack — remove the 2× multiplier and let a breach be reported loudly while non-blocking, rather than hidden by a doubled threshold. |

**A PROVISIONAL ceiling may not block a merge.** It may fail a nightly HEAVY lane and it must appear in the BUILD_LOG of any session that moves it. Promotion from PROVISIONAL to enforced requires a contract ruling, because a byte budget is a product promise about which shoots open — it is not a harness detail. The ceilings must **not** be moved into `design/tokens.yaml` before that ruling; W6 was right to keep them in Swift with a `proposal` marker rather than enshrine them as tokens.

### What a validating run requires

| Requirement | Specification |
|---|---|
| **Host** | Apple Silicon, macOS 14+ (D65 / A1; `design/mvp-test-plan.md` §1). Intel never. Idle machine — peak RSS is contaminated by concurrent Xcode indexing. |
| **Fixtures** | **Citation correction:** the cascade cites *fixture-manifest §1*; §1 is the six-body camera fleet, not a tier list. The tiers named in `RamTierHarnessRunner` come from **§2** (`card-clean-500`) and **§5** (`mixed-200`). A validating run needs **both**: §2/§5 sets for the grid and preview tiers, and §1 bodies (`sony-a7iv`, `canon-r6ii`, `nikon-z6iii`, `fujifilm-xt5`, `iphone-proraw`, `iphone-heic`) for the proxy/RAW tier, because decode size is a per-body fact. **None of these fixtures exist as assets in the tree** — they are specifications. Cutting them is CP3 work and is already on HARNESS.md's GAP LIST as *"Six-body fixtures · Registered · CP3"*. |
| **Command** | `python3 Scripts/harness/heavy/run_job.py ram_tier_runs`, or `LUMINA_RAM_HARNESS_APP=<Debug Lumina.app> bash Scripts/harness/heavy/ram_tiers.sh <ledger>`; writes `artifacts/harness/ledgers/ram-tiers.json`. |
| **Reading that promotes a ceiling** | Three consecutive runs on one idle host, per tier, with: `peakRssBytes − rssBeforeBytes` and `cacheTrackedBytes` both below the proposed ceiling **without** the 2× multiplier; spread across the three runs under 10% of the ceiling (a tighter spread than that is the only evidence that the gate can tell a regression from noise); and at least one tier that actually reaches `proxyTierCeilingBytes` via `allowRAW: true`. Latency re-measured in the same session — BUILD_LOG records scrub p50 14.5 ms / p95 16.6 ms, settle 191 ms, in→photon ≤50 ms p95; a memory win paid for in latency is a trade and must be stated. |
| **Blocked on** | CP3 fixtures + a macOS host. Until both exist, every ceiling stays PROVISIONAL and the honest ledger value is `UNMEASURED`, not `measured`. |

---

## 0.4 — BRANCH TOPOLOGY

### The fact, established not reasoned

`git merge-base --all 83ba118 <branch>` and `git rev-list/log 83ba118..<branch>` for every W branch. `83ba118` is the pre-cascade `origin/main`.

| Branch | Tip | Merge-base with pre-cascade main | Commits | Contains another branch's commits? |
|---|---|---|---:|---|
| `cursor/w1-gate-truth-39dd` | `8ef67e6` | `83ba118` | 2 | no — clean cut; mechanical re-baseline separated as instructed |
| `cursor/w3-cp4-p0-cull-39dd` | `cdd4f35` | `83ba118` | 4 | no |
| `cursor/w3-cull-grammar-39dd` | `d35eae1` | `83ba118` | 5 | **yes — all 4 of `w3-cp4-p0-cull`** |
| `cursor/w4-motion-wiring-39dd` | `018ecaa` | `83ba118` | 3 | **yes — both W1 commits** (`8ef67e6`, `c1a6f4c`) |
| `cursor/w5-key-routing-39dd` | `f7bc9fe` | `83ba118` | 2 | **yes — `dcc6015` from the F11.6 branch** |
| `cursor/w6-memory-budget-39dd` | `1a67da5` | `83ba118` | 3 | **yes — W5's `f7bc9fe` and F11.6's `dcc6015`** |
| `cursor/w7-failure-grammar-39dd` | `314ef1e` | `83ba118` | 1 | no |
| `cursor/w8-legacy-severance-39dd` | `8628307` | `83ba118` | 4 | **yes — and by merge, not rebase**: `8628307` is a merge commit joining `78309ec` (main) and `6dd6997` (the P8.2 doc) into the branch |

**Answer to the question as posed:** it is the first horn, not the second. **Four of eight branches were cut off a predecessor** — forbidden by the git protocol — and P8.2's table reported genuine branch state, not inherited state mislabelled. W4 reads PASS on the gate rows because W4 *contains* W1. W6 reads PASS on the routing rows because W6 *contains* W5. P8.2's own §6 topology line is self-contradictory: it says *"W1–W8 branches fork from `origin/main` @ `83ba118` in **parallel, not stacked**"* and then, one clause later, *"W6 includes W5 commits."* The second clause is true; the first is false for W3-cull-grammar, W4, W5, W6 and W8. W8 additionally merged main into itself rather than rebasing.

### Which debt deltas are wrong, and the corrected numbers

Debt lines are non-blank, non-`#` rows, per `HARNESS.md` L36.

| Ref | `magic_number_allowlist` | `banned_patterns_allowlist` | `orphan_register` |
|---|---:|---:|---:|
| `83ba118` pre-cascade | 3 | 1 | absent |
| W1 `8ef67e6` | 243 | 1 | 28 |
| W3 `d35eae1` | 3 | 1 | absent |
| W4 `018ecaa` | 275 | 1 | 25 |
| W5 `f7bc9fe` | 3 | 1 | absent |
| W6 `1a67da5` | 3 | 1 | absent |
| W8 `8628307` | 3 | 1 | absent |
| `origin/main` `f2e9ee3` | **277** | 1 | **25** |

- **W1's stated delta is right.** BUILD_LOG: *"orphans found 28 · new magic-number hits 240 · new banned-pattern hits 0"*; measured 3 → 243 is +240, and 0 → 28 orphans. `allowlist_ratchet` FAIL at the branch tip was correct and expected pre-merge.
- **W4's delta is the one that would have been wrong if computed against `main`.** Against `origin/main` @ `83ba118` it reads **+272 magic / +25 orphan**; against its true base (W1) it is **+32 magic / −3 orphan**. W4's BUILD_LOG states `Base: cursor/w1-gate-truth-39dd @ 8ef67e6` and reports the +32, so **W4 disclosed the stack and its own numbers are correct**. The document that hid the stack was P8.2's topology line, not W4's PR.
- **W3, W5, W6, W8 could not report a gate-derived delta at all** — they were cut before W1, so those branches carry no orphan register and a 3-row magic allowlist. Any statement of the form "W5 held the ratchet" is vacuous: there was no ratchet on that branch.
- **`main` carried a red gate for the length of the cascade.** The allowlist stood at 243 from `a366d38` through `90c075f`, at 275 from `137deaa` through `e0d4473`, and the literals introduced by W3 and W8 were registered only at **`c7c999b`**, after every merge: `+Lumina/Views/P0/ContactSheetCollection.swift 0.12`, `+… 0.28` (W3's pointer-cull work), `+Lumina/Views/P0/P0LegacyShellDoor.swift 16` (W8's door). Merge-gate step 5 — *"rebased onto current `origin/main`, and (1) and (2) re-run AFTER the rebase"* — was not honoured for W3, W5, W6 or W8; the reconciliation happened afterwards in a commit owned by no PART. `#54` then removed one row (277).

### Published rebase order

The order is now history, and it was the right one: **W1 → W3 → W4 → W5 → W6 → W8**, with W8 last. What remains to be ordered is stated in the republished merge sequence below. **The predictive part of this item is replaced by measurement:** rebasing the pre-gate branches onto post-W1 `main` surfaced exactly **3** new magic-number hits and **0** new banned-pattern hits, plus two `test_gate_truth.py` expectations that had to move for W6's now-present `ram_tiers.sh` and W8's deleted `DecisionDock`. The prediction implied in the cascade — that this would be large — was wrong in the direction of harmless, because W1's re-baseline had already absorbed the pre-existing debt; only literals *written after* W1 was cut appeared as new.

### For whoever sees the first red rebase — this is not a regression

**`git branch -r` shows 57 remote branches; 30 are unmerged and were cut before the gate landed at `a366d38`** (measured: `git merge-base --is-ancestor a366d38 <branch>` false, with commits ahead of `main`). Every one of them was written against a tree with **3** hand-checked magic-number literals (`252`, `1280`, `800`) and **3** banned-pattern strict roots. Post-merge `main` has **95** derived literals and **7** strict roots. When any of those 30 branches rebases, the red it produces is **the gate working for the first time on code that predates it**. It is not W1 breaking something, it is not a bug in the derived check, and it must not be narrowed to make the red go away. The correct response is to register each hit with `# owned-by-CP<N>` and a reason, in a separable mechanical commit — the procedure W1 itself used.

---

## 0.5 — THE INSTRUMENT IS MISSING A BLOCKING ROW

### The M5 hover: fixed at the cited line, alive one file away, and now in no lane

`design/strategy/surface-sweep.md` M5 and the D48/D37 rows record a live-path hover at `Lumina/Views/P0/P0SinglePhotoEditor.swift:356` failing FAST `banned_patterns`.

| Tip | `.onHover` in `P0SinglePhotoEditor.swift` |
|---|---|
| `origin/main` `f2e9ee3` | **absent** — the surrounding block is now `.onTapGesture` at L353; W5 removed it |
| every W tip after W5 | absent |

`rg -n 'onHover' Lumina/` on `main` returns exactly three hits:

| Site | Lane | Live? |
|---|---|---|
| `Lumina/Views/Workspace/ContinuousWorkspaceView.swift:722` | recorded-legacy | behind the W8 door |
| `Lumina/Views/Workspace/ContinuousWorkspaceView.swift:839` | recorded-legacy | behind the W8 door |
| **`Lumina/Views/LuminaButtons.swift:147`** | **NO LANE** | **live P0 path** |

The third is inside `LuminaQuietButtonStyle` (`LuminaButtons.swift` L127, hover at L147: `.onHover { hovering = $0 }`). That style is applied on the live path at:

`P0ContactSheetView.swift` 48, 92, 122, 146, 158 · `P0SinglePhotoEditor.swift` 52, 102, 128, 271 · `P0OpenView.swift` 57, 131 · `P0CropControls.swift` 60, 70, 81 · `P0GroupingView.swift` 35, 96 · `P0AdjustmentRail.swift` 36 · `P0LegacyShellDoor.swift` 28 — **18 call sites across 7 live P0 files.**

**How it left the lane.** At the W1 tip this style lived in `Lumina/Views/Components/DecisionDock.swift` L86–112, hover at L107, inside the **recorded-legacy** scan set. W8 deleted `DecisionDock` (2 dead symbols, 0 references) and, per its own BUILD_LOG, *"Button styles moved to `Lumina/Views/LuminaButtons.swift`"* — a file in neither the strict nor the legacy set. The hover was not removed; it was relocated out of every lane, mechanically, while deleting a genuinely dead file. Nobody laundered anything on purpose, and the effect is exactly what PART 1 named as its own failure mode: *"moving a file between lanes to change its verdict."*

**And the move is invisible in review.** `artifacts/harness/banned_patterns_legacy.txt` — the record that makes legacy hits "not silent" (`banned_patterns.sh` L17, L106–107) — is **gitignored** (`.gitignore:35`). It is regenerated per run and never diffed, so a hit leaving the recorded lane leaves no trace in version control and no row in HARNESS.md's GAP LIST, which still lists only *"Hover handlers (legacy shell) · Registered · CP5."*

### Lane coverage of the live path — measured

`banned_patterns.sh` L19–35: strict = `Views/P0`, `Design`, `ViewModels`, `Core`, `Services`, `Persistence`, `Testing/ProbeV2`; legacy = `Views/Workspace`, `Views/Components`, `Shell`, plus `CompareAndSoftViews.swift`, `PhotoImageView.swift`, `ContentView.swift`.

```
product swift files (excl. test bundles): 160
  STRICT:  72
  LEGACY:  34
  NO-LANE: 54
```

`NO-LANE` includes `Lumina/LuminaApp.swift` (the app entry), all of `Lumina/Models/` (8 files — `P0State.swift`, `P0Command.swift`: the state and command types the P0 path is built on), all of `Lumina/Develop/` (19 files — the render graph on the P0 edit path), `Lumina/Presentation/`, `Lumina/Rendering/`, `Lumina/Testing/` outside ProbeV2, and 12 top-level `Lumina/Views/*.swift` including `LuminaButtons.swift`. Banned-pattern hits inside the un-laned set: **2** — the hover above, and `Lumina/Develop/Lab/DevelopLabView.swift:184 ProgressView()` (S19 playground; `#if DEBUG`-fenced at `DevelopLabView.swift:1`, reached only via `DevelopLabLauncher.swift:1` / `LuminaApp.swift:27` — a debug-only spinner, recorded not blocking).

PART 1's scope A said *"extend the strict lane to every live path"* and then enumerated seven roots. **The enumeration is not the live path**: 54 of 160 product files, including the app entry point and the model layer, are in no lane at all.

### Every Wave 0 / Wave 1 blocker with no row

Walked from `surface-sweep.md` §4 M1–M7 and §5 wave gates.

| Item | Status on `f2e9ee3` | Evidence | Had a row? |
|---|---|---|---|
| **M1 macOS automation** | **UNMEASURED** | `run.py full` → PLATFORM-UNAVAILABLE, `0 app tests executed / 7 expected`; FAST `0/0` | **No** — and it is the reason rows 2, 4, 5, 6, 7 are unverified as *behaviour* rather than as *shape* |
| **M2 SPIKE B** | **CLOSED** | `LuminaSpring.swift` present; `spring_physics_f07` OK; `tokens.yaml` version `6.3-motion-wiring`; `tokens_codegen --check` OK | n/a |
| **M3 CP2 persistence** | **OPEN** | §0.1 | Yes — row 3 |
| **M4 P0 vs contract surface** | **OPEN** | CP7 propagation exists only on the severed shell (`legacy-disposition.md` §"CP7 propagation set") | **No** |
| **M5 D48 hover** | **OPEN, RELOCATED** | `LuminaButtons.swift:147`, 18 live call sites, no lane | **No** — the row P8.2 was missing, and the fix moved the target |
| **M6 D67 / Batch 3** | **NOT RATIFIED** | `rg -c '\bD67\b' design/contract-v6.md` → 0 | **No** |
| **M7 harness honesty** | **CLOSED** | FAST PASS 37/37 | n/a |
| **§5 Wave 0: R3 re-run after the hash move** | **NOT DONE** | W4 moved `tokensHash` to `1b1db60f…` / `6.3-motion-wiring`; `find artifacts -name 'LuminaBuildManifest.json'` → **no artifact**; F11 is macOS-only | **No** — and it is a fixed wave gate |
| **§5 Wave 1: P5** | **OPEN** | §0.1 | Yes — row 3 |
| **P0OpenView `.alert`** | **OPEN, allowlisted** | `P0OpenView.swift:38`; `banned_patterns_allowlist.txt` row `owned-by-CP8` | Partly — W7 is PLANNED, correctly gated |
| **Six-body fixtures / RAM ceilings** | **UNMEASURED** | §0.3 | Row 6 covers the gate, not the fixtures |
| **Disposition completeness** | **9 of 12** `Views/Components` files have no disposition row; of those, `SwimLaneContainer.swift`, `WorkspaceCommandBar.swift`, `RecoveryFactsChip.swift` are not referenced from `Views/P0`, `ViewModels` or `LuminaApp` | grep per file against `legacy-disposition.md` | **No** — PART 8 declared "a file with no disposition is FAIL" |

### Amended row set — Before / target After / current reading

Rows 1–9 are P8.2's, re-read. Rows 10–15 are new and blocking.

| # | Reading | Before (`83ba118`) | Target After | Current on `f2e9ee3` | Status |
|---|---|---|---|---|---|
| 1 | Orphan register | 4 unwired + 1 dead, no gate | 0 orphans, 0 dead | 22 registered / 0 dead (gate rule) · 43 under post-W8 rule · 3 stale rows · 11 DEAD-by-count unreportable | **FAIL** |
| 2 | Grammar implementations (app) | 2 | 1 | **1** | **PASS** |
| 3 | Decision-persistence roots | 2 | 1 | **2** — journal L1146/1152 + `shoot.json` L1095/1125 | **FAIL** |
| 4 | Key-routing owners (live) | 3 | 1 | **1** `P0KeyRoutingModifier`; legacy header true | **PASS** |
| 5 | Esc owners | 2+ | 1 ladder | **1** `P0EscLadder` | **PASS** |
| 6 | Memory gate | STUB, script absent | measured ledger + named ceilings | script present; **no ledger**; ceilings PROVISIONAL; 2× slack; RAW tier unexercised | **UNMEASURED** |
| 7 | Legacy reachable from launch | unconditional `@State` | behind a door | behind `P0LegacyShellContainer` | **PASS** |
| 8 | Numeric tokens gated | 3 hand checks | every token derived | **95** derived; 277 allowlisted | **PASS** (debt declared) |
| 9 | Banned-pattern strict scope | 3 roots | every live-path directory | **7** roots; **72/160** strict; **54 no lane** | **PARTIAL** |
| **10** | **Live-path hover (D48/D37)** | 1 hit, in strict scope, failing | **0** hits anywhere on the live path | **1** hit — `LuminaButtons.swift:147`, 18 live call sites, **no lane**, no GAP row | **FAIL** |
| **11** | **Orphan-gate scope** | no gate | every product declaration classifiable | **53 of 390** declarations scanned (13.6%) | **FAIL** |
| **12** | **App-coupled verification (M1)** | 0 app tests | ≥1 live flow green on macOS | **0 / 7 expected** — PLATFORM-UNAVAILABLE | **UNMEASURED** |
| **13** | **R3 after the P7 hash move (§5 Wave 0 gate)** | pre-P7 manifest stale | manifest re-embedded post-`1b1db60f…` and promoted | hash moved by W4; **no manifest artifact in tree**; F11 macOS-only | **NOT DONE** |
| **14** | **D67 / Batch 3 (M6)** | not ratified | ratified or rejected, code narrowed accordingly | **0 hits** in contract; CP7 code lives on the severed shell | **NOT RATIFIED** |
| **15** | **Disposition completeness (PART 8's own FAIL condition)** | no register | every surviving legacy file dispositioned | 3 non-live `Views/Components` files with no row | **FAIL** |

**Wave-worthy: no.** Not because a lane is red — FAST is green, 37/37 — but because rows 1, 3, 10, 11, 15 read FAIL and rows 6, 12, 13 cannot be read on any host available to this session.

---

## REPUBLISHED MERGE SEQUENCE

The W cascade is merged. What follows is the remaining sequence, per step: what merges, what must be re-run after it, what would make it unsafe to proceed.

| # | Step | Merges | Re-run after | Unsafe to proceed if |
|---|---|---|---|---|
| **0** | **This document** | `design/strategy/p8-2-adjudication.md` + BUILD_LOG. No code. | `python3 Scripts/harness/run.py fast` | Nothing — a doc-only change cannot move a gate. If FAST is not green on `f2e9ee3` before this merges, stop and read the inventory line, because the base moved. |
| **1** | **Operator ruling on 0.1** | Nothing — a ruling, recorded in BUILD_LOG and §5 of `surface-sweep.md` | n/a | A build session touching `ShootStore` or `P0SessionModel` persistence starts before the ruling exists. That is how W2 was lost the first time. |
| **2** | **M1 macOS automation diagnostic** | Whatever it takes to get one `P0Fast` flow green on an idle Mac; probably no product change | `run.py fast`, `run.py full`, `xcodebuild -only-testing:LuminaLogicTests test` | Anything merges after this that claims a behavioural After while FULL still reads `0 / 7`. **This step should come before every remaining one**: rows 2, 4, 5, 7 are currently verified as shape, not as behaviour, and PARTs 2–8's own VERIFY lists are majority-macOS. |
| **3** | **Row 10 hygiene — the relocated hover** | Remove `.onHover` from `LuminaQuietButtonStyle`; widen the banned-pattern lane to cover `Lumina/Views/*.swift`, `Lumina/Models`, `Lumina/Develop`, `Lumina/LuminaApp.swift`, `Lumina/Presentation`, `Lumina/Rendering`, `Lumina/Testing`; register resulting hits mechanically; stop `banned_patterns_legacy.txt` being gitignored | `banned_patterns.sh`, `allowlist_ratchet.py`, `run.py fast`, then `xcodebuild -only-testing:LuminaLogicTests test` on macOS | Removing the hover changes a pressed/hover visual that a golden holds — check `artifacts/harness/goldens/<hash>/` first. Widening the lane before the ratchet is re-baselined in a **separable** commit; that is what makes the debt reviewable. |
| **4** | **Row 11 / 0.2 — self-classifying orphan gate** | The six rule changes in §0.2, no product code, one mechanical re-baseline commit last | `orphan_symbols.py`, `allowlist_ratchet.py`, `run.py fast` | Any PART acts on the register **before** rule 1 (transitive reachability) and rule 2 (door modelling) land. Today the register would authorise deleting `LuminaWorkspaceAppearance`, which `LuminaApp.swift:38` calls. **This step blocks every wire-or-delete instruction in the cascade.** |
| **5** | **W7 / CP8 — facts-chip failure grammar** | Only when CP8 is scheduled; W7 is correctly PLANNED until then | `f06_data_safety.py --bounded`, `copy_contract_diff.sh`, `banned_patterns.sh`, `run.py fast` | The `P0OpenView` `.alert` allowlist row is removed without the pattern, or vice versa. Row 19 of §0.2 (`RecoveryFactsChip`) is deleted by anything acting on a zero-reference count. |
| **6** | **P5 / CP2 — one decision root** | Per the 0.1 ruling. One checkpoint, not two. | `xcodebuild build`, `xcodebuild -only-testing:LuminaLogicTests test`, `f06_data_safety.py --bounded`, `cp2_journal_kill_fuzz`, `cp2_lr_round_trip`, `run.py fast`, `run.py heavy` on macOS | No macOS host is available; or a migration path can lose a decision under a §2 schedule; or the §2 fixtures are still specifications, in which case the fault-schedule proof is unrunnable and must be scheduled with CP3, not asserted. |
| **7** | **CP3 fixtures, then RAM ceiling validation** | Six-body fleet + `card-*` sets; then promote ceilings per §0.3 | `run_job.py ram_tier_runs` on macOS; re-measure latency in the same session | A ceiling is promoted from a run on synthetic flat JPEGs, or with the 2× multiplier still in place, or without a tier that reaches `proxyTierCeilingBytes`. |
| **8** | **R3 — release integrity re-run (row 13)** | `run_f11_release.py` + `write_build_manifest.py` + promote, on macOS, against the current hash `1b1db60f…` / `6.3-motion-wiring` | `f11_read_manifest.py --check`; then Wave 0 may cut | **No wave artifact is cut before this.** Any DMG packaged now embeds a `tokensHash`/`contractVersion` that W4 already moved. This is §5's fixed gate and it is currently open. |
| **9** | **Constitution session — Batch 3 / D67 (row 14)** | Ratify or reject `proposal-batch-3.md`; narrow CP7 code if rejected | `contract_v6_presence.sh`, `constitution_coverage --check`, `run.py fast` | CP7 is ported to the live path before the law that governs intent propagation is in force. |

**Unchanged and re-affirmed:** no wave artifact is cut anywhere inside this stack until step 8. `design/tokens.yaml` is not edited by steps 3, 4, 5 or 7 — a ceiling is not a token until it is ruled. The one-checkpoint rule holds: step 6 is CP2 and nothing else.

---

## RULINGS OWED

1. **Row 3 — decision-persistence root.** Full block in §0.1. Options (a) narrowed W2 vs (b) scheduled P5; recommendation (b) with two recorded conditions. **Also owed:** whether the three green CP2 gates may be cited as CP2 coverage while they are Python-vs-Python.
2. **RAM ceilings (§0.3).** Adjudicated here as PROVISIONAL and non-blocking; **promotion to enforced needs a contract ruling**, because a byte budget decides which shoots open. Owed with it: whether the 2× slack multiplier at `RamTierHarnessRunner.swift:161` may exist at all — my reading is that it may not, because it makes the published number unfalsifiable.
3. **Density steps (D49, OPEN question 7).** The ±0.25 pinch accumulator in `ContactSheetCollection` is now visible to the derived magic-number gate — two of the three literals registered at `c7c999b` (`0.12`, `0.28`) come from that surface. The contract already flags *"named pinch density steps for token seal"* as OPEN. Naming them is a constitution session, not a build session; the gate has done its job by making them visible.
4. **`DockedChipLaneDropModifier` / `SwimLaneContainer` (CONFLICT 1 below).** D64 shelves swim-lane plates with an evidence door; the orphan register carries the modifier as debt owned by CP4. One of the two is wrong about who owns it.
5. **Un-laned live path.** Whether `Lumina/Models`, `Lumina/Develop`, `Lumina/LuminaApp.swift`, `Lumina/Presentation`, `Lumina/Rendering` and top-level `Lumina/Views/*.swift` join the strict lane, or are declared out of scope with a reason. Today they are neither — which is the condition PART 1 was commissioned to end.

---

## CONFLICTS

```
CONFLICT 1 — a DEAD-by-count symbol inside a shelved surface
SIDE A · PART 0.2 / PART 8 as written: "DEAD (zero references anywhere including
  tests; PART 8 deletes)". Measured: DockedChipLaneDropModifier
  (Lumina/Views/Components/SwimLaneContainer.swift:52) has zero references outside
  its own file; its only caller is SwimLaneContainer at L44 of the same file.
SIDE B · D64 [● A6] (design/contract-v6.md L303–308): "No lane plates at MVP …
  Re-entry door: … lanes re-enter only as a ruled experiment (new ruling
  required)." D38 (L328): "Doors, not deletions." The docked-chip lane drop is the
  D16/A5 provenance-chip drop surface, whose only in-tree implementation is the
  legacy shell (legacy-disposition.md §"CP7 propagation set").
  SwimLaneContainer.swift additionally has NO disposition row.
NOT RESOLVED HERE. A measurement said delete; the shelf says door. The register
  row says owned-by-CP4; the surface is CP7's. Nothing is deleted on this branch.
NEEDED: a disposition row for SwimLaneContainer.swift naming CP7, and correction
  of the register row's owner from CP4 to CP7 — or a ruling that un-shelves.
```

```
CONFLICT 2 — the orphan gate's "live" contradicts W8's severance
SIDE A · orphan_symbols.py L27–34 counts all of Lumina/Views/ and Lumina/Shell/
  as the live path, so 21 symbols reachable only from the legacy shell read as
  wired (measured, §0.2).
SIDE B · W8 (merged, e0d4473) and legacy-disposition.md establish that
  Lumina/Views/Workspace/**, Lumina/Shell/** and ProjectViewModel are reachable
  only through P0LegacyShellDoor — a door, not the launch path. D40's retirement
  schedule treats them as quarantined.
NOT RESOLVED HERE. Consequence in both directions: the gate under-reports orphans
  by 21, and simultaneously over-reports by registering LuminaWorkspaceAppearance,
  which LuminaApp.swift:38 calls. A gate that is wrong in both directions cannot
  authorise a deletion.
NEEDED: §0.2 rule changes 1 and 2, landed before any PART acts on the register.
```

```
CONFLICT 3 — a banned pattern left every lane during a dead-code deletion
SIDE A · PART 1: "moving a file between lanes to change its verdict is
  laundering and is this session's failure mode." D48/D37 (contract-v6.md
  L116–123): "Hover is deleted entirely … No hover handlers for product
  information."
SIDE B · W8 (merged) deleted DecisionDock.swift — correctly, 0 references — and
  moved LuminaQuietButtonStyle, hover included, from Lumina/Views/Components
  (recorded-legacy lane) to Lumina/Views/LuminaButtons.swift (no lane). The style
  is applied at 19 live P0 call sites. The record that would have shown this,
  artifacts/harness/banned_patterns_legacy.txt, is gitignored (.gitignore:35).
NOT RESOLVED HERE — PART 0 owns no product or harness code. No intent is imputed:
  the move was mechanical and the deletion was right.
NEEDED: step 3 of the republished sequence — remove the hover, widen the lane,
  and stop the legacy record being untracked.
```

---

## FOLLOW-UPS

Recorded, not acted on.

- `surface-sweep.md` §6 still carries the "parallel, not stacked" sentence contradicted by §0.4, and the nine-row table still reads `main` @ `83ba118`. A future strategy session should supersede §6 with the amended fifteen-row set rather than editing history in place; this document is the citation.
- `artifacts/harness/ledgers/orchestration-only.json` is tracked but rewrites `generated_at` on every FAST run, so every session dirties the tree with a timestamp-only diff (observed this session; restored, not staged). Either untrack it or stop writing the timestamp.
- `artifacts/harness/banned_patterns_legacy.txt` is gitignored, so the "recorded, not silent" lane leaves no reviewable trace. Related: the RAM ledger writes `mode: "measured"` / `gates_active: true` unconditionally, against HARNESS.md L117–123's own convention.
- The orphan register carries 3 stale rows (`CullGrammarEvent`, `CullGrammarMachine`, `CullGrammarState`) and the gate does not fail on them.
- `grammar_oracle_parity` compares two Python artifacts; nothing in any lane executes `CullGrammarMachine.swift`. Same shape as the CP2 mirror gates. A "mirror-gate" audit across the harness would probably find more.
- `RamTierHarnessRunner.tierSpecs` has no tier with `allowRAW: true` or `maxPixelSize: nil`, so `proxyTierCeilingBytes` is unexercised by construction.
- `Lumina/Develop/Lab/DevelopLabView.swift:184` `ProgressView()` — `#if DEBUG`-fenced, un-laned; record it rather than leaving it undiscoverable.
- 30 unmerged remote branches predate the gate (§0.4). Someone should decide which are alive; `surface-sweep.md` already carries "close superseded PRs #36–#39" as an operator action.
- The cascade cites `fixture-manifest §1` for RAM tiers; §1 is the body fleet. The tier sets are §2 and §5. Worth correcting wherever the citation is repeated.
