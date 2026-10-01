# LuminaKit: the native Lumina UI

The native rebuild of `design/handoff/lumina-app` (Open · Cull · Edit · Save). The design folder is
the authority: `README.md` (screens, copy, tokens) → `LAYOUT_SIZING.md` → `KEYMAP.md` →
`BEHAVIOR_SPEC.md` (R-xx rules) → `ACCESSIBILITY_CONTRACT.md`, then `parity/` (tokens.json, the
recorded traces, the demo shoot). When the prototype and the README disagree, the README wins.

Two libraries: **LuminaCore** (models, stores, the key table, layout maths, the window's `AppModel`;
no SwiftUI) and **LuminaUI** (views). The app target links both and shows `AppShell` when the native
switch is on (`Lumina/Native/NativeApp.swift`: `-LuminaUITest YES`, `-LuminaNative YES` or
`LUMINA_NATIVE=1`). Folders are compiled as they are: adding a file never touches the Xcode project.

## Who owns what

One work package owns each folder. Edit only your own; everything else is read-only.

| WP | Owns (under `LuminaKit/`) |
|---|---|
| 0 Contracts | `Sources/LuminaCore/Contracts`, `Sources/LuminaUI/Tokens`, `Sources/LuminaUI/Debug`, `Sources/lumina-snap`, `Package.swift`, `Tests/LuminaCoreTests/{CoreRulesTests,ParityKitTests,Support,Fixtures}.swift` |
| 1 Shell | `Sources/LuminaUI/Shell`, `Sources/LuminaUI/Motion`, `Sources/LuminaCore/Flow` |
| 2 Open + import | `Sources/LuminaCore/Import`, `Sources/LuminaUI/Open` |
| 3 Cull | `Sources/LuminaCore/Decisions`, `Sources/LuminaUI/Cull` |
| 4 Edit canvas | `Sources/LuminaCore/Imaging`, `Sources/LuminaUI/Edit/Canvas` |
| 5 Edit controls | `Sources/LuminaCore/Edits`, `Sources/LuminaUI/Edit/Controls` |
| 6 Edit overlays | `Sources/LuminaCore/Overlays`, `Sources/LuminaUI/Edit/Overlays` |
| 7 Save | `Sources/LuminaCore/Export`, `Sources/LuminaUI/Save` |
| 8 Persistence | `Sources/LuminaCore/Persistence` |

Each WP also owns its own test files, `Tests/LuminaCoreTests/WP<n>*.swift`, and its own
`CONTRACT-REQUESTS/WP<n>.md`.

## The contract (WP-0)

- **`AppModel`** (`Contracts/AppModel.swift`) is one window's state. Stored state is declared there;
  behaviour is in `AppModel+<Area>.swift` inside each WP's folder. The names and signatures of the
  functions that exist today are the contract between WPs: change bodies in your own files, never
  a signature. State only your WP needs lives in your own `@Observable` class, reached with
  `model.feature(MyState.self) { MyState() }`.
- **Keys**: `KeyRouter` is KEYMAP.md as a table. Views never read the keyboard; everything arrives
  through `model.handle(KeyEvent)` → `model.perform(Action)` → your function.
- **Time**: `model.clock.now` and `model.clock.after(_:_:)`, never `Date()` or `asyncAfter`. Tests
  run on a virtual clock.
- **Sizes and colours**: tokens × `@Environment(\.luminaScale)`. Fonts only through `LuminaFont`.
  `Tokens.generated.swift` comes from `parity/tokens.json` (`python3 Scripts/gen_tokens.py`).
  Formulas and breakpoints: `Breakpoints`, `LayoutScale`, `CullLayout`, `EditLayout`.
- **Identifiers**: every interactive view gets its `AccessibilityID` when it is created.
- **Services**: pictures, export and storage are behind `ImageProvider`, `Exporter`,
  `PersistenceStore`. The package's defaults need no app; the app's adapters over
  `Lumina/Sets/Core` and `Lumina/Sets/Look` go in `Lumina/Native`.
- **`debug.state` / `debug.metrics`** (`Contracts/DebugState.swift`) read the model; report layout
  through `Metrics.shared` (`canvas`, `photo`, `tileH`, `rows`).
- **Need a contract change?** Don't edit WP-0's files and don't fork a type. Write what you need and
  why in `CONTRACT-REQUESTS/WP<n>.md`, keep going with the closest thing that compiles, and say so
  in your report. The integrator applies requests between waves.

## Checking your work without a window

Nothing here opens a window or takes the keyboard, so many workers can run at once.

```bash
cd LuminaKit
swift build
swift test                                   # CoreRulesTests + the parity traces + your WP<n> tests
swift test --filter ParityKitTests           # the six recorded flows, state checked after every action
# Look at a screen: renders offscreen to a PNG. Keys run on a virtual clock.
swift run lumina-snap --out /tmp/x.png --size 1100x760 --keys "return,wait:2500,r,r,x,cmd+3,wait:300,." --state
```

`Tests/LuminaCoreTests/Support.swift` has `Harness`: a model on a virtual clock driven by keys and
read through the same `debug.state` JSON the UI tests use. Write the R-rules of your WP as headless
tests with it first; the XCUITests (`LuminaUITests/Native`, the design's 96 + trace replay + goldens)
take over the screen and are run by the integrator only, one at a time.
