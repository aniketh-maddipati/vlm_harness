# WP-8 contract requests

Nothing here blocks WP-8: each item has a workaround in `Sources/LuminaCore/Persistence` that
works today. They are listed so the integrator can fold them into the contract and delete the
workaround.

## 1. `Snapshot.editCur` (Edit's own position)

**Need.** `AppModel` keeps two current photos (`cullCur`, `editCur`); `Snapshot` has one (`cur`,
Cull's). R-70 on Edit means coming back on the photo Edit was showing.

**Workaround.** `SnapshotExtras { editCur }`, saved in the same file as the snapshot through
`SnapshotExtrasStore` (`save(_:extras:)`, `loadWithExtras(shootKey:)`), which `FilePersistence`
and `MemoryPersistence` both implement. A `PersistenceStore` that doesn't implement it (an app
adapter) still works; Edit then lands on the first keeper after a relaunch.

**Request.** Add `public var editCur: String?` to `Snapshot` (optional, so version-1 files still
decode). Then `SnapshotExtras` and `SnapshotExtrasStore` can go, with a one-line migration that
lifts `extras.editCur` into the snapshot.

## 2. `ErrorFunnel`-free "not saved" state in `debug.state` (optional)

**Need.** A write that fails for a reason other than a full disk (permissions, I/O error) is
shown with the same warning as R-71 and reported once through `ErrorFunnel`. Tests can only see
it through `edit.warning`, which exists on Edit only.

**Request.** None required. If Open / Cull / Save should show the storage warning too, that is a
design ask (the warning line is specified for Edit only), not a contract change.

## 3. `Bootstrap.launch` and the reopened folder (R-19)

**Need.** At launch the model has no shoot when the last session was an imported folder; the
snapshot for it is under the folder's shoot key, not the launch shoot's. `restore()` therefore
only *offers* it (`open.reopenName`, `open.reopenCount`, `model.folderToReopen`); the reopen
itself needs WP-2's import.

**Workaround / what WP-2 calls.**
- on import: `model.rememberFolder(url)` (makes and stores the bookmark and the path);
- at launch, after `restore()`: `if let url = model.resolveFolderToReopen() { importURLs([url]) }`,
  and when the import has built its `Shoot`: `model.setShootRestoring(shoot, restoreStep: true)`
  instead of `setShoot(shoot)` (decisions, edits, both current photos, save options, the step);
- on any other import of a folder seen before: `model.setShootRestoring(shoot)` (same, stays on
  its step, R-17).

**Request.** In `AppModel.launch`, after `m.restore()` and when there is no fixture:
`if m.shoot.isEmpty, let url = m.resolveFolderToReopen() { m.importURLs([url]) }` — or leave it
to WP-2's shell code; either way it must happen once, not in both places.

## 4. `LaunchConfig.memoryStore` (optional)

**Need.** "Memory only when asked" has no field in `LaunchConfig`.

**Workaround.** `makePersistence(config:)` returns a memory store for `LUMINA_STORE=memory`, for
a UI-test launch without `LUMINA_STORE_DIR`, and for any process running XCTest (so no test can
reach `~/Library/Application Support/Lumina/native/`).

**Request.** `public var memoryStore = false` on `LaunchConfig`, read from `LUMINA_STORE=memory`.

## 5. Things that change without `changed()`

Persistence only hears about a change through `changed()`. Anything meant to be remembered that
is set without it is saved late (with the next change, or at quit through `flushPersistence()`):
today that is `cull.tileHeightOverride` ("remembered" in the contract, set by `cullTileSize`, not
part of `Snapshot`). If it should survive a relaunch, add it to `Snapshot` and call `changed()`.
