# Lumina harness (CP0)

**Authority:** `design/contract-v6.md` → `design/tokens.yaml` → `design/copy-contract.txt` → code → tests.  
**Checkpoint:** CP0 — harness upgrade (testing never blocks building).  
**Runner:** `python3 Scripts/harness/run.py {fast|full|heavy|watch|all}`

A red FULL lane blocks **MERGE**, never **EDITING**. FULL/HEAVY run against a disposable git worktree snapshot (`Scripts/harness/worktree_runner.py`).

---

## Three lanes

| Lane | Budget | When | Contents |
|------|--------|------|----------|
| **FAST** | <90s | save/commit / `watch` | token lint · copy-table lint · banned-pattern grep · magic-number grep · existing lints (`agent_rules_contract.sh`, …) · unit/property tests · 5 seed scripts |
| **FULL** | <10min | pre-merge, parallel | chrome golden compare (photo regions masked) · input-script grammar suite via probe · signpost trace parse → numbers ledger · one-⌘Z-per-gesture · count invariants (banner=header=receipt, export=kept, chip-absence⟺full-rung) · parallel-instance dry-run |
| **HEAVY** | nightly + release | scheduled | ingest timing · kill-fuzz + replay · eject faults · RAM-tier · LR round-trip · zero-egress audit · grammar-stability re-run of **all** prior scripts unchanged |

Dashboard (optional): `python3 Scripts/harness/dashboard/server.py` → `http://127.0.0.1:8765/`  
Watch mode streams FAST events there (and to `artifacts/harness/dashboard/events.ndjson`).

---

## Feature drop-in contract

A new feature ships as **data**, not runner changes:

1. **Input script** JSON under `Scripts/harness/scripts/seed/` (schema: `Scripts/harness/scripts/schema.json`) — event stream, **never recorded coordinates**.
2. **Probe asserts** — declarative `asserts[]` in the same file (schema: `Scripts/harness/probe/schema.json`).
3. **Optional goldens** — propose via `python3 Scripts/harness/golden/service.py propose <name> --file …` then **human** `approve` (never auto-bless). Store keyed by `tokens-hash`.
4. **Optional signpost names** — add to `Scripts/harness/trace/acceptance_numbers.json`; emit via `AcceptanceSignposts` (DEBUG only).

Zero changes to `Scripts/harness/run.py` required.

### Worked example — P/X advance

File: `Scripts/harness/scripts/seed/px_advance.json`

```json
{
  "schemaVersion": 1,
  "id": "px_advance",
  "title": "P/X advance — keep then reject advances focus",
  "cite": ["D10", "D59", "L1"],
  "fixture": "mixed-60",
  "seed": 1001,
  "events": [
    { "op": "focusIndex", "index": 0 },
    { "op": "key", "key": "P" },
    { "op": "waitProbe", "ms": 0 },
    { "op": "key", "key": "X" },
    { "op": "waitProbe", "ms": 0 }
  ],
  "asserts": [
    { "op": "markEquals", "assetIndex": 0, "mark": "keep" },
    { "op": "markEquals", "assetIndex": 1, "mark": "reject" },
    { "op": "focusIndex", "equals": 2 },
    { "op": "undoEntries", "entries": 2 }
  ]
}
```

On Linux, `Scripts/harness/probe/simulator.py` executes the script against Probe v2 canonical state. On macOS, the same asserts read live NDJSON from `StateProbeV2Server` (loopback).

---

## State Probe v2

- **Schema:** `Scripts/harness/probe/schema.json` (records, marks, staging, focus, generation counters, resident rung per visible frame).
- **Transport:** streaming NDJSON over local TCP (`Lumina/Testing/ProbeV2/StateProbeV2.swift`) — DEBUG / `--probe-v2` only.
- **Fake clock:** `HarnessFakeClock` — `#if DEBUG` only; must not exist in Release.
- **v1 probe** (`UITestStateProbe` accessibility JSON) remains for XCUITest; v2 is the mid-script socket.

---

## Token codegen

```bash
python3 Scripts/harness/codegen/tokens_codegen.py          # write DesignTokens/HiFiTokens.generated.swift
python3 Scripts/harness/codegen/tokens_codegen.py --check  # CI freshness
```

`artifacts/harness/tokens.hash` keys the golden store. Magic-number grep bans raw chrome literals in UI files (allowlisted debt in `artifacts/harness/magic_number_allowlist.txt`).

---

## Seed scripts (5)

| id | Law |
|----|-----|
| `px_advance` | D10 / D59 |
| `same_mark_clears` | D59 |
| `shift_return_return_release` | D60 / D13 |
| `esc_exact_restore` | L5 / D11 |
| `arming_consent` | D24 / D48 |

---

## GAP LIST intake (seal-verification → ownership)

Clauses with no mechanical guard at seal-v6.1, plus seal follow-ups. **No gap may remain unowned.**

| Gap | Status | Owner |
|-----|--------|-------|
| `tokens.yaml` → Swift codegen | **Closed in CP0** | CP0 |
| Motion timing mechanical guard (signpost parse + ledger) | **Closed in CP0** (fixture trace; live Mac emitters DEBUG) | CP0 |
| Grammar scripts (P/X, same-mark, ⇧⏎/⏎ gate, Esc, arming) | **Closed in CP0** (5 seeds + simulator) | CP0 |
| Golden service (propose→approve, tokens-hash keying) | **Closed in CP0** | CP0 |
| Chrome/photo golden *pixel* captures per body | Registered | **CP1** (layout) / body matrix **CP3** |
| Live os_signpost on open/crossfade/settle/grab/halo/slider paths | Registered | **SPIKE A/B** + surface CPs (emitters wired DEBUG in CP0) |
| A5 banner spacing drift (`Adapt → N  ⏎` vs CopyContract one-space) | Registered | CopyContract wire-up (**CP5/CP7**) |
| P0OpenView `.alert` vs Law 3 facts-chip | Registered | **CP8** (allowlisted in banned_patterns) |
| Hover handlers in quarantined Workspace shell | Registered | **CP5** (D48) — legacy hits in `banned_patterns_legacy.txt` |
| ProgressView in legacy Compare/PhotoImageView | Registered | **CP4** retirement |
| Six-body fleet fixtures | Registered | **CP3** |
| Taste-model proof harness | Registered | post–wave-one (**D46 / A10**) — do not begin early |
| A7 TestFlight crash reporting strip | Registered | **1.0 launch** |
| A8 / R-I.3 licensing | Registered | post-test, pre-launch |
| `AUDIT-HIFI.md` regenerate (old A/X crop PASS) | Registered | next audit run |
| LuminaTokens hand literals → yaml secondary enum | Registered | **CP5** rail |
| SwimLane.headerInset pre-yaml chrome | Registered | **CP1** |
| HEAVY ingest/kill-fuzz/eject/RAM/LR live runners | Registered | **HEAVY** (stubs in `heavy_placeholders.py`; need Mac) |
| Grammar-stability suite named by D51 (full prior corpus) | **Partial in CP0** (seed corpus + HEAVY re-run hook) | grow with each CP; **D51** pre-release gate |

---

## Parallel headless instances

`python3 Scripts/harness/parallel_instances.py --n 2 --dry-run` creates isolated temp dirs + journal roots. Live app launch is macOS-only (`--ui-testing --probe-v2 --ui-test-state-directory …`).

---

## Platform note

Linux cloud agents run FAST + FULL (simulator/goldens/trace fixtures) and HEAVY registry checks. `xcodebuild` / live Probe v2 socket / XCUITest remain macOS (see `AGENTS.md`).
