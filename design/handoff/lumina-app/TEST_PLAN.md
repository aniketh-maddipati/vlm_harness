# Test plan

## Layout
```
XCTest/
  LuminaCoreTests/CoreRulesTests.swift        unit: classifier, EXIF, grouping, undo, signature, key router, layout maths
  LuminaUITests/Support/Lumina.swift          app driver (launch hooks, debug.state, keys, waits)
  LuminaUITests/Support/Fixtures.swift        real on-disk fixture folders (messy, nested, names, shapes, EXIF, rotated, big)
  LuminaUITests/KeysAndStateTests.swift       stress suite: keys & state
  LuminaUITests/LayoutAndSizingTests.swift    window shapes, sizing, fill, labels, copy
  LuminaUITests/FlowAndFailureTests.swift     buttons, animation, load failure, storage, resume, save, two windows, relaunch, destructive guards
  LuminaUITests/ControlsConflictTests.swift   controls suite: one meaning per key, layers own the keyboard, esc, undo scope, ⏎/⌘S guards
  LuminaUITests/FirstTimerTests.swift         wrong files, odd names and shapes, EXIF, rotation, drops, reopen, monkey, mash, undo flood
  LuminaUITests/LoadTests.swift               XCTMetric perf: Cull keys, photo switch, decide all, edits size, save, relaunch, import
  LuminaUITests/SoakTests.swift               N rounds of chaos; pile-up, memory, big import at the end
```

## How each HTML suite maps to XCTest
| HTML suite (prototypes/) | Tests | XCTest file |
|---|---|---|
| Stress: keys & state | 9 | KeysAndStateTests (8), ControlsConflictTests (R-24 blur) |
| Stress: layout, labels, tokens | 4 | LayoutAndSizingTests |
| Stress: buttons, animation, loading, storage, import, export, connectors | 7 | FlowAndFailureTests |
| Stress: load | 3 | LoadTests |
| Controls: controls | 13 | ControlsConflictTests |
| Controls: load (demo×13, Unsplash 1,000 or 5,000) | 8 | LoadTests |
| First-timer: wrong files | 16 | FirstTimerTests + CoreRulesTests |
| First-timer: clumsy | 9 | FirstTimerTests + FlowAndFailureTests |
| First-timer: screens and flow | 4 | LayoutAndSizingTests + FlowAndFailureTests |
| First-timer: soak | 5 | SoakTests |
| **New for native:** sizing and fill R-54…R-59 | 6 | LayoutAndSizingTests |
| **New for native:** core unit rules | 15 | CoreRulesTests |

Every test name starts with the rule it enforces (for example `test_R33_…`), so a red test points straight at BEHAVIOR_SPEC.md.

## Setup in Xcode
1. Add a **LuminaCoreTests** unit-test target, linked to the `LuminaCore` framework (the model and logic layer, kept separate from the UI).
2. Add a **LuminaUITests** UI-test target for the app. Add both `Support/` files to it, and add `Fixtures.swift` to the unit-test target as well.
3. Create a scheme `Lumina-UITest`:
   - Debug build with the `LUMINA_UITEST` compilation flag, which compiles the hooks in.
   - Turn off "Automatically terminate apps" and "Allow location simulation".
4. For performance tests, record baselines on the CI machine (an M1 or better): run once, then accept the baselines in Xcode's baseline editor.
   - Set the photo-switch baseline to 50ms, or 60ms at 5,000 photos.
   - Set the Cull key baseline to 100ms and Save to 500ms.
   - Allow 10% deviation.
5. The Unsplash 5,000 card (`LUMINA_CARD=unsplash:5000`) needs network access. For offline CI, point it at a local mirror of the same 5,000 URLs. The manifest is `prototypes/data/lumina-shoot-unsplash.js`; convert it to JSON.

## Running
```
# every commit (~5s)
xcodebuild test -scheme Lumina -only-testing:LuminaCoreTests

# every PR (~12 min on an M1)
xcodebuild test -scheme Lumina-UITest -only-testing:LuminaUITests \
  -skip-testing:LuminaUITests/SoakTests -skip-testing:LuminaUITests/LoadTests

# nightly and before a release
xcodebuild test -scheme Lumina-UITest -only-testing:LuminaUITests/LoadTests
SOAK_ROUNDS=25 xcodebuild test -scheme Lumina-UITest -only-testing:LuminaUITests/SoakTests
```
Run UI tests on a machine where nothing else takes focus. Like the HTML harness, they depend on the app being frontmost.

## Release gates
| Gate | Must pass |
|---|---|
| Merge a PR | CoreRulesTests, plus every UI test that touches the WP's area (see WORKSTREAMS.md), plus `LayoutAndSizingTests` |
| Release candidate | All UI tests, LoadTests within baselines, SoakTests with 25 rounds |
| Ship | Release-candidate gates, plus the manual checks below |

## Manual checks (no automation covers these)
1. A real SD card from three camera brands: RAW decodes and the copy is verified.
2. Running out of disk space during a copy and during a save.
3. Rotated photos from an iPhone (HEIC) and an Android phone (JPEG).
4. A 27-inch display at full screen, and a 13-inch laptop: walk through every step and confirm nothing feels small or empty (LAYOUT_SIZING.md).
5. The app update path: data saved by the previous version opens.
6. VoiceOver walkthrough: Open → Cull → Save.

## Where the HTML harness results stand (the baseline to match)
- **Stress:** 24 of 24.
- **Controls:** 13 of 13.
- **Load, Unsplash 5,000:** copy in 104s; all 5,000 decided in 38s; photo switch 39ms at the 95th; Save in 36ms; reopened in 0.6s.
- **First-timer regression:** 27 of 27, including camera data, nothing-kept Edit and the rotated phone photo.
- **Soak, 50 rounds:** pass. Memory levelled off, with late rounds lower than early ones.
