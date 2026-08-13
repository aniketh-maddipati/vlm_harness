# Lumina build prompts — index

**Authority:** subordinate to `design/contract-v6.md`. Prompt factory conflicts register here.

---

## §CONFLICTS

### CONFLICT 1 (CP0 shell fragmentation) — partially closed

Single entry point (`regression.sh` → `run.py`), lint home via manifest ids only, enforced `budgetMs` ceiling, allowlist ratchet, bash-3.2 shell lints, HARNESS lane-alias table. Remaining shell work rolls to macOS measured FULL/HEAVY (CONFLICT 2).

### CONFLICT 2 (app-coupled live suite) — open

FULL/HEAVY report PLATFORM-UNAVAILABLE on this host; 0 app-coupled tests executed; live Swift drivers remain STUB-owned (CP4 / CP7 / SPIKE A / HEAVY per STUB register).

### CONFLICT 4 (prompt factory / beta distribution) — ruled

**RULING (2026-08-12):** option **2** — beta and wave builds distribute as a **notarized Developer ID artifact** (zip or DMG), not Mac App Store TestFlight. No Apple-side crash reporter on the beta channel. D45 zero-egress and the first-wave distribution window no longer collide.

**Pointer:** Amendment Batch 2 — **A11** / **R-I.4**; **A12** (D66); **A13** (A7 withdrawal). See `design/amendments/proposal-batch-2.md` (ratification decisions) and `design/contract-v6.md`.

---

## Prompts

| Id | Title | Path | Gate |
|----|-------|------|------|
| **F06** | Data safety fuzz | `design/build-prompts/F06-data-safety-fuzz.md` | CP2 crash-only startup + §2 bounded schedules |
