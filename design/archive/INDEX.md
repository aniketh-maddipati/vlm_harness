# design/archive — the paper trail

`design/` holds only the living constitution set:

| Living document | Role |
|-----------------|------|
| `design/contract-v5.md` | Provenance — D1–D40, unmodified PDR body |
| `design/contract-v6.md` | The contract |
| `design/tokens.yaml` | Token authority (generates `HiFiTokens`) |
| `design/copy-contract.txt` | Frozen copy table |
| `design/fixture-manifest.md` | Fixture corpus spec |
| `design/checkpoint-sequence-v6.md` | Sealed Layer-2 order |
| `design/mvp-test-plan.md` | MVP probes (A9) |
| `design/probe-battery.md` | *not yet landed* |

Everything superseded moves here. **Nothing is ever deleted from this
directory** — it is the record of what the product used to believe.

Archived because a document is superseded, not because it was wrong at the
time. Read anything here as history.

## Index

| Archived | Was | Superseded by | Why |
|----------|-----|---------------|-----|
| `hifi-reference.html` | `design/hifi-reference.html` | `design/contract-v6.md` + `design/tokens.yaml` | Hi-fi visual reference from the H0–H8 pass. Chrome reference only; it never had authority over grammar, keys, or the shelf. Not part of the living constitution set. |
| `AUDIT-HIFI.md` | repo root | `Scripts/lint/*` + the FAST lane | Generated output of `Scripts/audit_hifi.py`, which was deleted when T1 migrated the text audits to shell lints and XCTest. The file still records `PASS — Crop latch re-scopes A (aspect) and X (flip)`, which **contradicts D63** (crop uses `R`/`O`; `A` and `X` are banned from remapping). An orphaned artifact asserting a superseded law is exactly the drift the agent-rules gate exists to stop. Closes the `AUDIT-HIFI.md` follow-up in `design/contract-v6.md`. |
| `WORKSPACE_LAYOUT_REPORT.md` | `docs/` | `docs/P0_CONTACT_SHEET.md`, `docs/P0_CULLING.md` | Layout report for the Workbench · Canvas · Proof shell, which D40 quarantines (now under `Legacy/`). Its key table teaches `S` keep / `X` fold / `M` maybe / `A` auto-treatment as the product grammar; Contract v6 decision keys are `P` `X` `⏎` `⇧⏎` `A` (D10 / D59). |

## Related

The superseded Workbench key table and the pre-P0 quick-test walkthrough were
removed from `README.md` in the same checkpoint; `WORKSPACE_LAYOUT_REPORT.md`
above preserves that grammar verbatim.
