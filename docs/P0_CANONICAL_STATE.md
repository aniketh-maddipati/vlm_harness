# Lumina P0 — Canonical state

Foundation checkpoint: stable asset identity, one recipe authority, and recoverable shoot persistence.

## Canonical state ownership

| Concern | Owner | Notes |
|---|---|---|
| Shoot catalog | `ShootRecord` | Versioned Application Support cache (`shoot.json`) — navigation / previews, not edit authority |
| Per-photo durable state | `AssetRecord` | Identity, source, cull, recipe, caches |
| Cull | `CullDecision` on `AssetRecord` | Independent of edit |
| Edit | `EditRecipe` on `AssetRecord` | Tone + geometry + retouch |
| Final kept order | `FinalSetOrder` | Independent of discovery order |
| Batch apply | `BatchEditCommand` | Exact before/after per recipient; geometry off by default |
| Export history | `ExportRecord` | Does not redefine the kept set |
| Workspace restore | `WorkspaceRestoreState` | Focus, filter, density, scroll, scale, kept-order mode |
| Source / volume | `SourceReference` | Path, bookmark, relative path, availability |

Multi-selection is transient unless deliberately placed in restore state. Missing originals mark `SourceAvailability.missing` and never delete catalog rows.

## Asset identity

`AssetIdentity` derives a rediscovery key from:

1. Volume identity (UUID or volume name)
2. Path relative to the shoot root (handles identical filenames in nested folders)
3. File size
4. Capture timestamp when known

A deterministic UUID is hashed from that key. IDs already stored in existing projects are preserved on migration and win over the hashed value.

Cached preview paths are keyed by `AssetIdentity.cacheStem(assetID)` (UUID string), not the filename stem. Legacy stem-keyed files are copied once into the identity-keyed location on rediscovery.

## Recipe migration

- **Authoritative persisted recipe:** `EditRecipe` (schema v2 includes retouch).
- **Geometry:** `crop` + `straightenDegrees` participate in serialization and `valueFingerprint` (cache invalidation).
- **Tolerant decode:** accepts v1 EditRecipe JSON and legacy `DevelopRecipe`-shaped blobs (no id / schemaVersion / geometry).
- **Render order unchanged:** decode → downsample → WB → exposure → tone → presence → vibrance → NR → sharpen → straighten/crop → display/export.

`DevelopRecipe` remains as a **taste / XMP / older-UI adapter**. Bridging `EditRecipe → DevelopRecipe` still drops geometry; product persistence must not round-trip through that bridge.

## Persistence and recovery

Durable edit receipt lives **beside the media**. Application Support may accelerate
restore and navigation; it is not a second authority for recipes.

| Concern | Owner | Notes |
|---|---|---|
| Canonical in-memory recipe | `AssetRecord.recipe` | Session truth while the shoot is open (D35) |
| Crash window | `ShootDecisionJournal` | Append-only JSONL at `<shoot>/.lumina/decisions.journal.jsonl` |
| Durable edit receipt | Open XMP sidecar | Written on edit commit via `ShootSidecarStore`; survives deleting Lumina |
| Navigation / preview cache | `shoot.json` under Application Support | Catch-up only; must not silently override a newer valid sidecar |
| Sidecar managed hash | Session memory (`sidecarManagedHashes`) | Last observed managed `crs:` hash; cleared on open, re-adopted from disk |
| External XMP modification | `SidecarReconciliation` / `SidecarOpenOutcome` | In-session: detect, do not overwrite session. Relaunch: sidecar wins if not older than the journal crash window |

`ShootStore` (actor) is the narrow persistence owner: `commitEdit` (journal → catalog → sidecar), `recoverShoot` (journal replay then sidecar reconcile), `saveShoot`. Writes are serialized per shoot.

### Relaunch authority

One deterministic winner per asset. Recover never writes XMP.

| Case | Winner | Proof |
|---|---|---|
| 1. Clean shutdown, XMP and shoot cache agree | Agreed mapped recipe | `SidecarAuthorityTests.testCase1_cleanShutdownXMPAndShootCacheAgree` |
| 2. Journal newer than sidecar | Journal (crash window) | `SidecarAuthorityTests.testCase2_journalNewerThanSidecarWinsCrashWindow` |
| 3. Sidecar newer than shoot cache | Sidecar | `SidecarAuthorityTests.testCase3_sidecarNewerThanShootCacheWins` |
| 4. External XMP changed | Sidecar adopted; XMP bytes unchanged; in-session drift does not mutate session | `SidecarAuthorityTests.testCase4_externalXMPChangeDetectedNotOverwritten` |
| 5. Shoot cache exists, sidecar missing | Journal then catalog; sidecar not created | `SidecarAuthorityTests.testCase5_shootCacheWithoutSidecarKeepsRecipe` |
| 6. Sidecar exists, Application Support deleted | Sidecar reconstructs mapped recipe | `SidecarAuthorityTests.testCase6_deletedApplicationSupportReconstructsFromXMP` |
| 7. Application Support exists, source drive returns later | Offline: catalog only. Drive back: same as 1–6 | `SidecarAuthorityTests.testCase7_sourceDriveReturnReconcilesSidecar` |

Save path for `shoot.json`:

1. Encode sorted JSON to a temp file
2. Promote previous `shoot.json` → `shoot.json.good`
3. Replace with the temp file
4. Refresh the good copy

Corrupt primary recovers from `shoot.json.good`. Current files decode directly as `ShootRecord`. Legacy `project.json` is decoded only at the compatibility boundary and rewritten as `shoot.json` on the next save. Persistence errors are recorded and surfaced; they are not silently discarded.

## Legacy compatibility boundary

| Type | Status | Why it remains |
|---|---|---|
| `LuminaProject` | Compatibility-only + unreachable legacy island | Legacy project decoding and the retired shell implementation still consume it |
| `PhotoRecord` | Compatibility-only + unreachable legacy island | Legacy project decoding and retired services still consume it |
| `ProjectStore` | Unreachable legacy island | Retired import, catalog, and shell code still compile against it |
| `DevelopRecipe` | Superseded for photo persistence | Taste learning, XMP mean, older slider offsets |
| `EditRecipeStore` / `BatchTreatmentSession` | Lab / batch grammar | Not the shoot catalog; keep for develop lab |
| Workbench / Canvas / Proof implementation | Unreachable legacy island | Deleting it requires removing its coupled views and services as a separate task |

The current app root, P0 views, `P0SessionModel`, `ContactSheetPreparation`, and `ShootStore`
do not read or write `LuminaProject`, `PhotoRecord`, or `ProjectStore`. The old shell door was
deleted when the canonical-state boundary became mandatory.

Deletion conditions:

- Delete `ProjectStore` and the project-to-shoot conversions after the retired shell, catalog,
  and import pipeline are removed or migrated to `ShootRecord`.
- Delete legacy project decoding and `PhotoRecord` after the supported-install migration window
  for on-disk `project.json` closes.
- Delete `DevelopRecipe` bridges after taste and XMP consumers use `EditRecipe` directly.

Obsolete architecture notes in `docs/DEVELOP_ENGINE.md` and `BUILD_LOG.md` that claimed EditRecipe was already the stored source of truth are corrected here: in-session canonical state is `EditRecipe` on `AssetRecord`; the durable receipt for edits that survive outside Lumina is open XMP.

## Next checkpoint (contact sheet)

Completed on branch `cursor/p0-contact-sheet` — see `docs/P0_CONTACT_SHEET.md`.

## Next checkpoint (culling)

Start from the contact-sheet branch after merge:

1. Read `docs/P0_CONTACT_SHEET.md` + this doc
2. Mutate `CullDecision` only from the contact sheet (P / X / hold)
3. Keep focus, selection, density, and scroll restore intact
4. Do not open Workbench, AI scoring, or the editing rail yet
