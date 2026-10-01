# Accessibility and test-hook contract

The XCTests find everything by **accessibility identifier**, never by position or visible text (except where a test checks the copy itself). Add these identifiers while building each view; they are cheap and must not be left for later. Identifiers are stable strings; `{…}` parts are filled in at runtime.

## Identifiers
| Area | Identifier | Element |
|---|---|---|
| Shell | `step.open` `step.cull` `step.edit` `step.save` | Step tabs. Set `isSelected` on the current one. |
| Shell | `shell.copyStatus` | "Copying 42/117" or "All 117 copied and checked" |
| Shell | `shell.dropOverlay` | Exists only while a drag is over the window |
| Open | `open.card` | The card's primary button |
| Open | `open.openFolder` `open.choosePhotos` | Import buttons |
| Open | `open.importProgress` `open.importMessage` | Progress line and result message (value = full text) |
| Open | `open.recent` `open.startOver` `open.reopenFolder` | Recent row, Start over, folder to reopen |
| Cull | `cull.grid` | Scroll view |
| Cull | `cull.scene.{index}` `cull.keepSuggested.{index}` | Scene header and its button |
| Cull | `cull.tile.{photoID}` | Tile. `value` = "kept" / "out" / "undecided" / "suggested". `isSelected` when it's the current photo. |
| Cull | `cull.preview` `cull.previewMeta` `cull.previewState` | Preview image and the line under it |
| Cull | `cull.keep` `cull.out` | Buttons |
| Cull | `cull.decided` | `value` = "12/117" |
| Cull | `cull.toEdit` `cull.toSave` `cull.message` | Footer |
| Edit | `edit.canvas` `edit.photo` `edit.photoLowRes` | Canvas and images. `edit.photo` `value` = "loaded" / "loading" / "failed". |
| Edit | `edit.empty` `edit.empty.goCull` | Empty state |
| Edit | `edit.loadError` `edit.retry` | Failure state |
| Edit | `edit.section.{light,curve,colour,effects}` | Section tabs |
| Edit | `edit.slider.{key}` | Slider (see the README table). `value` = the formatted value. |
| Edit | `edit.value.{key}` `edit.valueField` | The clickable value, and its text field |
| Edit | `edit.tool.{auto,crop,before,variations}` | Tools |
| Edit | `edit.variations` `edit.variation.{index}` | Grid and cells. `isSelected` on the current cell. |
| Edit | `edit.help` `edit.intro` `edit.crop` `edit.cropRatio` | Overlays |
| Edit | `edit.zoom` | Zoom picker. `value` = the zoom factor, e.g. "1.00". |
| Edit | `edit.prev` `edit.next` `edit.save` `edit.out` `edit.undo` `edit.redo` | Buttons |
| Edit | `edit.filmstrip` `edit.facts` `edit.hint` `edit.toast` | Strip, facts line, hint line, toast |
| Edit | `edit.warning` | Storage, other-window and offline warnings (value = text) |
| Save | `save.format.{xmp,folder,jpeg}` | Segments. `isSelected` on the chosen one. |
| Save | `save.includeEdits` | Toggle |
| Save | `save.button` `save.note` `save.summary` | `save.button` `isEnabled` follows the disabled rules |
| Save | `save.savedCard` | Exists after a save |

## Test hooks (UI-test builds only)
Turn these on with the launch argument `-LuminaUITest YES`. **Compile them out of release builds** (`#if DEBUG`, or a separate test target configuration).

| Hook | Kind | Purpose |
|---|---|---|
| `LUMINA_STORE_DIR` | env | A temporary store directory. The test wipes and re-creates it per test. Must fully isolate the user's real data. |
| `LUMINA_FIXTURE` | env | Path to a fixture folder (see `XCTest/Support/Fixtures.swift`). If set, it's imported as if the user had picked that folder. |
| `LUMINA_CARD` | env | `demo117` or `demo:{n}` (scaled demo), or a path to a fixture "card". Feeds the Open card tile. |
| `LUMINA_COPY_RATE` | env | Photos per second for the simulated copy. Default: real speed. Tests use 66 to match the prototype. |
| `LUMINA_WINDOW` | env | `{w}x{h}`: initial content size. Tests also resize by sending a `debug.resize` request (below). |
| `LUMINA_FAULTS` | env | Comma-separated faults to inject: `storageFull`, `imageLoadFail`, `slowDecode:{ms}`, `offline`. |
| `LUMINA_INTRO` | env | `skip` hides the first-run intro. |
| `debug.state` | identifier | A hidden static text (size 1×1, alpha 0.01). Its `value` is compact JSON, updated on every state change. See the shape below. |
| `debug.command` | identifier | A hidden text field. Typing a JSON command and pressing ⏎ runs it. Commands: `{"resize":[w,h]}`, `{"relaunchSoon":true}`, `{"injectFault":"storageFull"}`, `{"clearFault":"storageFull"}`, `{"openSecondWindow":true}`, `{"drop":["/abs/path", …]}` (walk and import exactly as a real drop would), `{"blur":true}` (window resigns key), `{"keyDown":"v"}`, `{"keyUp":"v"}` (holds; XCUITest can't hold keys on macOS), `{"releaseAllKeys":true}`. |
| `debug.memoryMB` | identifier | A hidden static text. Its value is the current phys_footprint in MB, for the soak test. |

`debug.state` JSON shape (keep the keys stable):
```json
{"step":"cull","cur":"DSC03261","copied":117,"total":117,
 "kept":12,"out":3,"undecided":102,
 "keep":{"DSC03260":true,"DSC03261":false},
 "look":{"ev":0.25},"looksCount":4,"lookBytes":1830,
 "zoom":1.0,"overlay":null,"spec":null,
 "saved":{"sig":"…","n":12,"ne":4,"fmt":"xmp","again":false},
 "import":{"busy":false,"n":6,"msg":"Added 6 photos…","local":true},
 "errors":0}
```
- `overlay` ∈ `null`, `help`, `crop`, `variations`, `intro`, `sceneGrid`, `picker`, `focus`.
- `errors` counts caught-but-unexpected errors. The app's error funnel increments it in UI-test builds.

`debug.metrics` (a hidden static text, refreshed after every layout pass): XCUITest can read frames but not font sizes, so the app reports what it actually used:
```json
{"scale":1.0,"minFontPt":11,"bodyFontPt":13,"fonts":{"step.cull":13,"cull.message":12},
 "canvas":[x,y,w,h],"photo":[x,y,w,h],"tileH":100,"rows":[{"scene":0,"width":812,"gridWidth":812,"last":false}]}
```
All fonts must go through the token function (`LuminaFont.body(scale)` and so on), which records them. A font created outside it is a review failure.

Why a state hook: XCUITest can't read the app's memory or storage. Every assertion the HTML suites made through `luminaState()` and storage reads goes through `debug.state` instead.
