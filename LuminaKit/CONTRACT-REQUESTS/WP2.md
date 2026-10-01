# WP-2 (Open and import): contract requests

Nothing here blocks WP-2; each item says what WP-2 does in the meantime.

## 1. Launch should call `model.reopenLastFolder()` (WP-0 `Bootstrap.launch` or WP-8 `restore()`)

R-19: the imported folder reopens by itself after a relaunch. `reopenLastFolder()` (public,
`Import/AppModel+Open.swift`, safe to call more than once) does it, but nothing in WP-2's
folders runs at launch, so today it is called from `OpenScreen.onAppear`. If a launch restores
the card straight to Cull, the folder is not reopened until Open is seen.

Ask: one line at the end of `AppModel.launch`, after `restore()` and the fixture import:
`m.reopenLastFolder()`.

## 2. The folder memory lives in the store under the key `open.folder` (WP-8)

WP-2 remembers the folder through `PersistenceStore` as one `Snapshot` with
`shootKey == "open.folder"`, using the contract's `folderName`, `folderBookmark`, `folderPath`,
`photoCount`, plus `tags["shoot"]` (the local shoot's key) and `tags["roots"]` (JSON: every
folder / loose file with its bookmark). It is written just before the shoot's own `changed()`, so
`loadLast()` still returns the shoot.

Ask of the file-backed store: keep every `Snapshot` field for any key (including `tags` and the
bookmark `Data`), don't treat `open.folder` as a shoot (the other-window notice should ignore
it), and `loadLast()` should skip it if it ever is the newest.

`AppModel.snapshot` does not need to fill `folderBookmark` / `folderPath`: nothing reads them
from a shoot's snapshot.

## 3. Local shoots are stored under `folder-<hash of the folder's path>` (WP-8)

The first import replaces the card's shoot (`setShoot`) and takes its decisions from
`persistence.load(shootKey:)` for that key; the card button on Open switches back to the card the
same way. WP-2 applies `keep`, `looks`, `tags`, `done`, `cur`, `fmt`, `withEdits`, `saved` and
(for the card) `copied` itself in `adopt(_:from:)`, a copy of what `restore()` does minus the
step. If `restore()` grows (new fields), `adopt` needs the same.

Ask: a public `AppModel.apply(_ snapshot: Snapshot?, step: Bool)` in WP-8 that both use.
WP-2 also keeps the outgoing shoot's `snapshot` in memory when it switches (in case writes are
debounced), so a switch back in the same session never reads a stale store.

## 4. Drops on every step (WP-1)

`View.luminaFileDrop()` (public, `LuminaUI/Open/OpenPickers.swift`) accepts file URLs only, sets
`model.imports.dropTargeted` and calls `model.importURLs`. Open uses it. Ask: put it on the
shell's root so a drop works on Cull, Edit and Save (R-17); the model side is done and tested.

`hooks.pickFolder` / `pickPhotos` are installed by `OpenScreen.onAppear` (as specified). ⌘O on
another step before Open has ever been shown does nothing. Ask: the shell calls
`OpenPickers.install(model)` when it comes up (needs the enum made public; say the word).

The pickers do nothing when `config.uiTest` is on: the tests mash ⌘O and can't drive a system
panel. They import through `debug.command` drops.

## 5. `LayoutAndSizingTests.test_R57_R58_noDeadBands` cannot pass on Open as written (WP-0 / design)

- It measures the dead band from the tabs to `open.card`. README §1 puts the title and subtitle
  (60 to 80 pt) and a 28 pt gap above the card, so that distance is 95 pt or more before any top
  padding; the test allows 72 + 40. R-57 itself ("empty space above the content ≤ 72 pt") holds:
  the space above the title is `clamp(24, 0.07 × height, 72)`, never more than the space below.
- It requires `open.card` to be as wide as the column. ACCESSIBILITY_CONTRACT says `open.card` is
  "the card's primary button", and R-54 measures its height as a button, so it is the button.

Ask: measure to the first content element (the title) and the column's width on a column-wide
element, or give the tile its own identifier (`open.cardTile`).

## 6. No real card (WP-0 / backend)

`Shoot.card(.path)` returns nil and the contract has no copy service, so the card copy stays the
simulated one (`config.copyRate`, 66 a second by default), now timed by the clock. With no card
at all (`Shoot.empty`) Open hides the card tile; the design has no "no card" state (a design ask).

## 7. `lumina-snap` can't drop files (WP-0)

To look at import states offscreen, Open reads `LUMINA_SNAP_OPEN` (`import:/folder`, `checking`,
`reopen`, `armed`), debug builds only and only under `lumina-snap` (activation policy
`.prohibited`). Ask: `lumina-snap --drop <path>` and `--call` hooks, then this goes.

## 8. `ImportItem.rel` starts with the imported folder's own name

"Trip/Day 1/a.jpg", as the prototype's `webkitRelativePath`, not "Day 1/a.jpg": files at the top
of a folder get that folder as their scene title, and two imported folders can't collide. A loose
file is just its name. `Photo.rel` carries the same string. The comment in `ImportTypes.swift`
says so; CoreRulesTests is unaffected.
