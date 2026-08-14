# Footprint register — lightweight dependency tree

**Authority:** Contract v6 scope + `design/strategy/legacy-disposition.md`.

## Completed in-tree (automation + Release compile gates)

| Item | Status | Evidence |
|------|--------|----------|
| Release `LUMINA_SHIPPING_APP` excludes headless harness | Done | `Lumina.xcodeproj` Release flags; `#if !LUMINA_SHIPPING_APP` on runners |
| Lazy P0 develop scheduler | Done | `P0SessionModel.developSchedulerStorage` |
| Shared Metal device | Done | `LuminaMetalDevice.shared` |
| Adaptive develop presentation cache | Done | `DevelopPresentationCache.defaultBudgetMegabytes()` |
| Release strip + dead-code settings | Done | `DEAD_CODE_STRIPPING`, `STRIP_*` on Lumina Release |
| Harness symbol inventory (F11) | Done | `hook_inventory.yaml` headless_harness hook |
| FAST lint: shipping fence, module boundary, artifact bloat | Done | `Scripts/harness/lint/*.py` |
| macOS footprint baseline script | Done | `Scripts/harness/release/footprint_baseline.sh` |
| Dead `IngestOrchestrator` removed | Done | P0 uses `ContactSheetPreparation` |
| Duplicate artifact dirs pruned | Done | canonical: `workbench-v6`, `raw-harness-v6`, `raw-perf` |

## Contract-blocked until CP7 / CP8 (do not delete early)

See `design/strategy/legacy-disposition.md` for the full inventory. Major buckets:

- Propagation set (`ContinuousWorkspaceView`, `TreatmentFamilyRow`, `PropagationState`, …) — **CP7**
- Legacy shell + import stack (`ProjectViewModel`, `ImportPipeline`, Vision ingest) — **post-CP8**
- Export/finish surfaces — **CP8**
- Dual token bridge (`LuminaTokens` vs `HiFiTokens`) — consolidate after legacy severance

## macOS verification (required after each footprint change)

```bash
bash Scripts/harness/release/footprint_baseline.sh
python3 Scripts/harness/release/f11_hooks_absent.py --app build/Release/Lumina.app
bash Scripts/regression.sh pre-merge
```

Track `artifacts/harness/footprint/latest.json` across releases.

## Target module graph (next structural step)

```text
LuminaApp → LuminaP0UI → LuminaImaging → LuminaCore
LuminaHarness (CLI) → LuminaImaging → LuminaCore
LuminaLegacy (temporary) → LuminaImaging → LuminaCore
```

Splitting synchronized Xcode groups into static modules is the largest remaining compile-time win once CP8 deletes the legacy door.
