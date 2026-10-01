# WP-3 (Cull): contract requests and notes for the integrator

Nothing here blocks WP-3: each item says what Cull does today instead.

## Requests

1. **A place for per-user preferences (WP-0 / WP-8).** The ⌘+ / ⌘− tile height must be remembered,
   but `Snapshot` is per shoot and has no field for it, and `CullState.tileHeightOverride` is not
   persisted by anyone. Today `CullPrefs` (in `Decisions/AppModel+Cull.swift`) writes
   `cull-prefs.json` into `LaunchConfig.storeDir` when there is one, `UserDefaults`
   (`lumina.cull.tileHeight.v1`) in the real app, and nothing in tests or command-line tools.
   Wanted: `PersistenceStore.loadPrefs()/savePrefs(_:)` (or a `tileHeight` field that `restore()`
   fills), so the store owns it and a full disk is reported in one place.

2. **`AppModel.say` should expire (WP-0).** The prototype clears a message after 3.2 s. `say` has
   no timer, so Cull wraps it (`cullSay`, timer kept in `CullSession`) and clears the toast itself
   when it is still the one it set. If `say` took over the timer, Cull's wrapper and Edit's would
   be one thing.

3. **Tokens (WP-0, `tokens.json`).** Two values Cull needs are not tokens:
   - the dotted strip box, `rgba(239,236,230,0.45)`: drawn as `LuminaColor.textPrimary.opacity(0.45)`;
   - the kept badge's ✓ is 10.5pt in the README, below the 11pt floor R-54 checks through
     `LuminaFont`. It is drawn as a shape (no font), so `minFontPt` stays at 11.

4. **Shoot invariants Cull relies on (WP-2's grouper, WP-0's `Shoot`).** Please keep, or say so:
   - `PhotoScene.index` equals the scene's position in `Shoot.scenes` (`keepSuggested(scene:)`,
     `cull.scene.{index}` and the grid use it as an array index);
   - `Shoot.photos` is in scene order, each scene's `ids` in photo order. ← → walk `photos`, the
     grid draws scenes; if the two orders differ the arrows won't follow the rows. The grid still
     draws correctly (it falls back to a full layout instead of the incremental one).

## Notes

- **`lumina-snap` cannot show Out.** `NSView.cacheDisplay` does not run Core Animation filters, so
  `.saturation(0)` (and `.grayscale`, and a `Canvas` filter: all three tried) come out in colour in
  the PNG. Out tiles and the preview show only the 70 % dimming there. The grey needs the
  integrator's eye in a real window, or the golden run.
- **R-58 and the preview column's padding.** README gives the column padding 16 / 20 / 16 / 4;
  LAYOUT_SIZING says the photo fills the column "with no other padding". Cull keeps the README
  padding around the column's content, and inside it the photo's box (`cull.preview`) takes all
  the space the line and the buttons leave; the photo is shown whole in that box and touches it on
  one axis (gap 0). `cull.preview`'s frame is the box (318pt wide at a 900pt window), which is what
  `test_R57_R58_noDeadBands` measures.
- **Keep / Out buttons do not move on.** The prototype's buttons call `mark()` and advance; the
  WP-0 contract says `cullSet(keep:)` decides without moving, and `test_mouseOnly` clicks a tile
  and then Keep. Cull follows the contract.
- **Kept fill on the Keep button** is `#EFECE6` (README), not the prototype's gold.
- **State label** is "Kept" / "Out" / "Undecided" (README), without the prototype's
  "· suggested keep".
- **`Components.PhotoThumb` is not used by Cull.** Cull has its own loader (`CullThumbs`: byte-capped
  cache, six decodes at most, newest request first, cancelled when the tile scrolls away).
- **New public API in `Decisions/`** (additions only, nothing renamed): `DecisionStore.decide`,
  `undo(from:)`, `redo(from:)`; `CullGrid`; `CullCopy`; `Photo.cullDetails`; `CullSession`;
  `AppModel.cullSession`, `cullTileHeight(gridHeight:)`, `cullRestoreTileSize()`,
  `cullKeyReminder`, `cullMessageSeconds`; `CullLayout.userStep`, `userRange`.
- **`debug.state` at 5,000 photos.** `debugStateJSON` serialises the whole `keep` dictionary on
  every change. Not measured here (the headless load test times the key path only, 5,000 decisions
  in about 0.2 s); worth a look if `test_R82` is slow in the UI run.
