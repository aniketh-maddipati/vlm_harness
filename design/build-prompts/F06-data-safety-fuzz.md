# F06 — Data safety fuzz (CP2 gate)

**Authority:** `design/contract-v6.md` → CP2 row in `design/checkpoint-sequence-v6.md`.  
**Prerequisite:** append-only journal (D35), open XMP sidecars (D36), crash-only startup.  
**Fault schedules:** `design/fixture-manifest.md` §2 only — no invented schedules.

---

## Scope

1. **Kill-fuzz replay** — SIGKILL mid journal append; committed prefix survives (D35 quit-anywhere).
2. **Journal round-trip** — committed cull/edit records replay on crash-only startup; exact restore.
3. **X never touches FS (D36 / R-M.1)** — before/after filesystem snapshot: mark key X and journal record decisions; photograph bytes unchanged.
4. **Staged-not-persisted (D13)** — staging never appears in journal kinds or replay state.
5. **Hostile schedules (§2 bounded):** `card-disk-full`, `card-two-card`, `card-corrupt-file`.

## Failure shape (D35)

Every fault path: **no modal**, **no NSAlert**, **no spinner**, **no progress bar**. One sentence names it · one action fixes it · the table keeps working.

Banned UI patterns apply verbatim in failure paths.

## TENSION T1 — lane placement

| Corpus | Lane | When |
|--------|------|------|
| **Bounded schedule set** | `pre-merge` (`run.py full`) + FAST orchestration mirror | Every merge |
| **Full schedule corpus** | `nightly` (`run.py heavy`) | Scheduled / release |

**Ceiling:** FULL **600000 ms** (<10 min). If bounded F06 breaks the ceiling, **report it** — demoting data safety out of pre-merge is a **ruling**, not a build decision.

## Entrypoints

- `Scripts/harness/cp2/f06_data_safety.py --bounded` — pre-merge bounded set
- `Scripts/harness/cp2/f06_data_safety.py --full` — nightly full corpus
- Swift logic: `ShootCrashRecoveryTests`, `IngestFaultScheduleTests`

## STOP

Any schedule not listed in `design/fixture-manifest.md` §2 → propose in manifest first; do not invent here.
