# WP-6 (Edit overlays): contract requests

Nothing here blocks WP-6: each item says what the code does meanwhile.

## 1. `LaunchConfig`: carry `LUMINA_INTRO=show`

`LaunchConfig` has only `skipIntro`. The golden test (`edit-intro`) and `lumina-snap --intro show`
need the intro forced even when it was seen before.

```swift
// Contracts/LaunchConfig.swift
public var forceIntro = false
// in init(arguments:environment:)
forceIntro = e["LUMINA_INTRO"] == "show"
```

Meanwhile `OverlayState.init` reads `ProcessInfo.processInfo.environment["LUMINA_INTRO"] == "show"`
itself (works in the app; `lumina-snap` passes its own dictionary, so there the intro shows because
nothing has marked it seen). When the field exists, replace that line with `config.forceIntro`.

## 2. Where the intro flag lives

`lumina.edit.intro.v1` is kept by `IntroFlag` (`LuminaCore/Overlays/OverlayState.swift`): a marker
file of that name in `config.storeDir` when there is one (so a UI test's wiped store means a fresh
intro and nothing touches the user's defaults), `UserDefaults.standard` otherwise, and memory only
for a UI-test launch with no store directory. If WP-8 wants it in the snapshot instead, add
`introSeen: Bool` to `Snapshot` and I'll swap `IntroFlag`'s two closures; nothing else changes.

## 3. Tokens (`parity/tokens.json` → `Tokens.generated.swift`)

The overlays use four values the prototype has and the tokens don't. They are in
`LuminaUI/Edit/Overlays/OverlayParts.swift` (`OverlayPalette`) until the tokens carry them:

| Proposed token | Value | Used for |
|---|---|---|
| `overlay.dim` | `rgba(0,0,0,0.6)` | behind Help |
| `overlay.dimIntro` | `rgba(0,0,0,0.62)` | behind the intro |
| `bg.overlayPanel` | `#2A2927` | the Help and intro panel |
| `shadow.overlayPanel` | `0 20 60 rgba(0,0,0,0.5)` | the panel's shadow |
| `overlay.capOnGold` | `rgba(30,29,27,0.35)` | the ⏎ key cap's edge on the gold Apply button |

## 4. Identifiers (`AccessibilityID.Edit`, ACCESSIBILITY_CONTRACT.md)

Parts the contract has no name for; today they are string constants in `OverlayID`
(`OverlayParts.swift`): `edit.sceneGrid`, `edit.sceneGrid.{photoID}`, `edit.sceneGrid.cancel`,
`edit.picker`, `edit.variations.apply`, `edit.variations.cancel`, `edit.help.intro`,
`edit.intro.shortcuts`, `edit.intro.start`.

## 5. KeyRouter: nothing wrong, two notes

The sweep (`WP6OverlayTests.test_keyRouterSweep_owningLayersLetNothingThrough`) finds no key that
gets past Help, the intro, Crop, Variations or a text field. Two things the table can't express:

- **The scene grid and the picker are not layers.** `AppModel.layers` adds none for
  `Overlay.sceneGrid` / `.picker`, so with the scene grid open the Edit keys still act on the photo
  underneath (← → move the gold ring, which is fine; X, ⏎, sliders' nudges also work). The prototype
  behaves the same. If the scene grid should own the keyboard, add `case sceneGrid` to `Layer`
  (priority beside Variations, `ownsKeyboard`), bind `escape → .editEscape` and the arrows, and add
  it in `AppModel.layers`.
- **Key-up under an owning layer is swallowed**, so a `\` held when Help or Variations opens never
  sees its release. WP-6 ends the peek itself when those open (`edit.before = false`,
  `edit.beforeHeld = false`); no table change needed.

## 6. For WP-4 and WP-5 (new functions, no signature changed)

- `model.variationsToggle()` for the Variations tool button (`edit.tool.variations`): opens the grid
  to stay, or closes it.
- `model.sceneGridOpen()` to open the scene grid (the prototype has no key for it; a click on the
  filmstrip's scene label is the natural place). Setting `edit.overlay = .sceneGrid` works too.
- `model.pickerCancel()` switches the white picker off with its "Picker off" message.
- The overlays place Variations and the scene grid on `Metrics.shared.canvas` when the canvas has
  reported it (window coordinates, top-left origin, as `.global`), else on the window minus the
  controls column.
- `EditOverlays` draws a "Pick white · click something neutral · esc / click here cancels" chip at
  the canvas's top left while `edit.pickingWhite` (or `Overlay.picker`) is on. If the canvas draws
  its own state chip for the picker, tell the integrator and one of the two goes.

## 7. Decisions made where the design left room (say if any should go the other way)

- **Temperature vs white balance.** The README gives both "cooler / now / warmer for temperature"
  and "a 3 × 3 temperature × tint grid when white balance is the target". WP-6: the pointer on
  Temperature → three cells; the pointer on Tint, or the white picker on with the pointer on no
  setting → the 3 × 3 grid (`debug.state.spec` is `wb` for it).
- **The highlighted cell when the grid opens is always the one that changes nothing** ("now", the
  middle of the 3 × 3, the vignette's current value), so hold-and-release without choosing never
  edits. The prototype's old two-cell picker opened on the other cell.
- **⏎ and a click wait out the same 120 ms window as releasing V** (one path, R-06 everywhere).
- **Pointing at a cell selects it only after the pointer has moved**, so a grid that opens under a
  resting pointer doesn't pick a cell by itself.
- **The grid's button says "Apply ⏎"** (KEYMAP "In Variations"), not the prototype's "Save ⏎":
  Save is a step in this app and Edit never saves (R-35).
- **Three intro cards** (README) from the prototype's five: its 1 (sliders), 2 (Before and
  Variations) and 4 (⏎ moves you on), with "Three things worth knowing. Everything can be undone."
- **Esc (R-25).** One layer per press in KEYMAP's order; "Large" (controls hidden) leaves with
  focus; Straighten outside Crop is the last layer. So that three presses always suffice, a press
  never leaves more than two layers open: with four or more up at once the innermost tools close
  with it.
- **Help's list** is the prototype's five groups with KEYMAP's keys: X reads "out" (not "reject"),
  Esc is listed, Move shows ⌘1 – ⌘4 and ⌘S instead of only ⌘2.
- **A tall canvas** (controls below the photo) stacks two or three cells instead of drawing three
  slivers; ↑ ↓ walk them as ← → do.
