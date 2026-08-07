# P0 UI Automation Harness

A Playwright-like native macOS UI-automation harness for Lumina's P0 flows, built on
**XCUITest / XCUIAutomation**. It launches Lumina against isolated, deterministic fixture state,
drives the real P0 interface with keyboard and mouse, and produces replayable evidence (seed +
action trace + screenshots + structured state) rather than relying on the maintainer to remember
and manually re-check every flow.

Appium is intentionally **not** used in this checkpoint. It is documented below only as a possible
future external-driver layer.

---

## 1. Architecture

| Layer | Location | Role |
|---|---|---|
| Deterministic logic tests | `Scripts/*.swift` + `LuminaLogicTests/` | State/command logic (Swift scripts, still authoritative) + native XCTest (`@testable import Lumina`) |
| UI tests | `LuminaUITests/` | XCUITest driving the real app |
| Robots / page objects | `LuminaUITests/Robots/` | Readable, intent-level interactions |
| Support | `LuminaUITests/Support/` | Base test case, launch config, seeded RNG, probe decoder, invariants, ID mirror |
| Seeded explorer | `LuminaUITests/Explorer/` | State-aware randomized workflows |
| Visual regression | `LuminaUITests/Visual/` | Pinned-window capture + semantic layout assertions |
| App-side test hooks | `Lumina/Testing/` | DEBUG-only launch mode, fixtures, state probe, accessibility IDs |
| Test plans | `TestPlans/*.xctestplan` | `P0Fast`, `P0Stress`, `P0Visual` |
| Runner | `Scripts/run_p0_ui_tests.sh` | `fast` / `stress` / `visual` / `logic` / `seed` |

The **state probe** is the backbone: an invisible accessibility element
(`p0.stateProbe`) whose value is a JSON `ProbeSnapshot` of the live session (route, counts,
focus, selection, per-asset cull map, availability, scroll anchor, visible/missing asset IDs).
Assertions read structured state from the probe rather than scraping UI text.

---

## 2. Local Mac requirements

- macOS 14+ with **Xcode 15+** (developed on Xcode 26 / Swift 6 toolchain, Swift-5 language mode).
- **Accessibility / Automation permission**: the first XCUITest run may prompt to allow the test
  runner to control the app. Grant it (System Settings → Privacy & Security → Automation /
  Accessibility). Headless CI on a Mac needs this pre-granted.
- `exiftool` is optional for fixtures (they synthesize their own images and have no EXIF dates).

## 3. What runs where (Linux vs macOS)

| Task | Linux cloud agent | macOS |
|---|---|---|
| `bash Scripts/regression.sh` static/manifest checks | ✅ (bash-syntax, test-plan JSON, scheme XML) | ✅ |
| `xcodebuild build` / `build-for-testing` | ❌ | ✅ |
| `LuminaLogicTests` (XCTest) | ❌ | ✅ |
| `P0Fast` / `P0Stress` / `P0Visual` (XCUITest) | ❌ | ✅ |

`regression.sh` runs the portable manifest checks everywhere and **exits cleanly on Linux without
claiming it ran macOS UI tests**.

---

## 4. Test-only launch mode (DEBUG only)

Compiled out of Release entirely (`Lumina/Testing/UITestLaunch.swift` is `#if DEBUG`). Activated by
launch arguments (preferred) or environment variables:

```
--ui-testing
--fixture-shoot mixed-60
--ui-test-state-directory <temp-dir>
--ui-test-seed 84721
--reduce-motion
--ui-test-window 1280x800      # optional, pins content size for visual/layout determinism
--ui-test-reset                # optional, force-rebuild fixtures instead of reusing
```

Environment equivalents: `LUMINA_UI_TEST_MODE=1`, `LUMINA_UI_TEST_FIXTURE`,
`LUMINA_UI_TEST_STATE_DIR`, `LUMINA_UI_TEST_SEED`, `LUMINA_UI_TEST_WINDOW`, `LUMINA_UI_TEST_RESET`.

Guarantees:
- **Never touches real state.** `ShootStore.supportDirectory()` is redirected to the temp state
  directory; the maintainer's `~/Library/Application Support/Lumina` is never read or written.
- Deterministic known state; supports clean launch and relaunch against the same temp directory
  (relaunch preserves decisions; `--ui-test-reset` rebuilds).
- Disables nondeterministic behavior (no AI/taste/scoring is invoked by P0; reduce-motion honored).
- Uses the **real** P0 UI, command, and persistence paths — fixtures only seed prepared state; every
  subsequent action goes through the app.

## 5. Fixture system

`Lumina/Testing/UITestFixtures.swift` (DEBUG only) generates deterministic, repository-safe
fixtures at launch — no Sony RAW, no committed binaries. Everything is a pure function of the asset
index (no RNG, no wall clock; capture dates derive from a fixed epoch).

| Fixture | Assets | Notes |
|---|---|---|
| `mixed-60` | 60 | Mixed portrait/landscape/square, bright/dark, repeated-looking runs, a mix of unreviewed/kept/rejected/edited, enough to scroll |
| `mixed-200` | 200 | Navigation/scroll/stress |
| `missing-originals` | 48 | Cached previews present; a deterministic 1/3 of originals removed so they read unavailable while the catalog stays intact |

Fixtures seed a `ShootRecord` + identity-keyed preview cache into the temp state dir; the harness
opens them through the real Recent-shoots UI.

## 6. Accessibility contract

Central namespace: `Lumina/Testing/P0AccessibilityID.swift`, mirrored (black-box tests can't import
the app) in `LuminaUITests/Support/P0AXID.swift`. `LuminaLogicTests` asserts the app side of the
contract. Per-asset elements are keyed by durable **asset UUID** (`p0.asset.<uuid>`), never array
index. Adding identifiers changes no visuals.

> **Container rule:** never attach an `accessibilityIdentifier` to a SwiftUI container that has
> identified children — SwiftUI propagates it onto every descendant and clobbers their specific
> identifiers. Surfaces (`open`/`contactSheet`/`singlePhoto`) are detected via the probe's `route`;
> the filmstrip via its items. Learned the hard way (see BUILD_LOG).

## 7. Robots

```
LuminaRobot          // façade: openShoot / contactSheet / singlePhoto, probe(), waitForProbe, resizeWindow
OpenShootRobot       // reopen the prepared shoot through Recent
ContactSheetRobot    // focus, selection (real ⌘/⇧-clicks), cull (P/X keys), density, undo, open
SinglePhotoRobot     // filmstrip, arrow nav, cull + undo at photo scale, return
DiagnosticsRobot     // screenshots, hierarchy, structured context; attachments (.keepAlways)
```

Robots own accessibility queries, **bounded** waits (poll observable state / probe — never fixed
sleeps), keyboard/mouse input, assertions, and failure diagnostics. Coordinate-based interaction is
used only where no accessible semantic element exists (e.g. establishing keyboard first-responder by
clicking the stable collection view) and is documented at the call site.

Keyboard note: macOS routes keys to the first responder, so keyboard grammar (arrows, P/X, ⌘Z)
requires a prior click into the contact sheet. `focus(assetID:)` clicks (and verifies + retries);
`establishKeyboardFocus()` clicks the stable collection view for the explorer.

## 8. Deterministic flows

`LuminaUITests/Flows/` implements every currently-available P0 behavior:

1. Open & navigate (`OpenNavigationTests`) — open, arrow focus, density.
2. Cull toggle + independence (`CullGrammarTests`).
3. Undo, incl. after navigation (`UndoTests`).
4. Selection vs focus independence (`SelectionFocusTests`).
5. Grid → photograph → grid restoration (`GridPhotoRestoreTests`).
6. Persistence across relaunch (`PersistenceTests`).
7. Missing originals (`MissingOriginalsTests`).
8. Layout at 1280×800 and a larger desktop (`LayoutTests`).
9. Repeated navigation over mixed-200 (`RepeatedNavigationStressTests`).

## 9. Seeded explorer

`LuminaUITests/Explorer/` — a **state-aware** model explorer (not blind clicking). It reads the
visible state from the probe, enumerates only *legal* actions for that state
(`ExplorerState` × `ExplorerAction`), and picks one with a deterministic SplitMix64 RNG so any run
is exactly replayable from its seed. After every action it sweeps invariants (Section 10). Every run
records seed, fixture, ordered actions, before/after state, the failed invariant, and the last
successful action, attached as `explorer-report-seed-<seed>` (`.keepAlways`).

- Short run in the fast suite (`ExplorerSmokeTests`, mixed-60).
- Configurable long run in the stress suite (`ExplorerStressTests`, mixed-200).

### Exact seed replay

```bash
bash Scripts/run_p0_ui_tests.sh seed 84721            # default 200 steps
bash Scripts/run_p0_ui_tests.sh seed 84721 120        # explicit step count
# or, matching the plan example:
LUMINA_UI_TEST_SEED=84721 LUMINA_UI_TEST_STEPS=200 bash Scripts/run_p0_ui_tests.sh stress
```

Seed/steps reach the test bundle via `TEST_RUNNER_LUMINA_UI_TEST_*` (xcodebuild forwards
`TEST_RUNNER_<NAME>` into the test process as `<NAME>`).

## 10. Invariants

Checked after every exploratory action (and asserted in flows) via `Support/Invariants.swift`:
visible main window; identifiable surface; focus refers to a visible asset when expected; selection
count non-negative/non-contradictory and consistent with the ID set; focus/selection independent;
edit markers unaffected by culling; rejected assets remain present; kept count equals kept assets;
undo restores the prior observable cull map; single-photo return restores a contact-sheet state; no
unexpected alert; no blank primary surface; relaunch returns to a valid state; missing originals do
not delete assets. Structured probe values — not UI text — are the source of truth.

## 11. Test plans

- **P0Fast** — logic tests + open/nav, cull, undo, selection/focus, grid/photo restore, persistence,
  missing-originals, layout, short explorer. Target: a few minutes.
- **P0Stress** — mixed-200 repeated navigation, long seeded explorer, relaunch, resize,
  missing-originals, layout; longer per-test allowance.
- **P0Visual** — pinned 1280×800 capture + semantic layout, incl. the focused-plus-selected outline
  case.

## 12. Artifacts, diagnostics & replay

`Scripts/run_p0_ui_tests.sh` writes everything under
`artifacts/ui-automation/<mode>-<timestamp>/`: the `.xcresult` bundle, `xcodebuild.log`, and an
isolated `state/` root (failure snapshots preserved there). The exact result-bundle path is printed.

On failure, `LuminaUITestCase` preserves (via `.keepAlways` attachments): main-window + full-screen
screenshots, the accessibility hierarchy, seed, full explorer/action trace, fixture, launch
args/env, window size, the persisted `shoot.json` snapshot, and the state-probe JSON. Named
`XCTActivity` sections make reports read as human workflows. Artifacts contain only synthetic
fixtures — no real user paths or photographs.

## 13. Visual-baseline policy

macOS rendering varies across machines, so exact pixel comparison is **local-Mac-only** and is
intentionally *not* gated in CI. What is mandatory and portable: **screenshot capture** (kept
always, with pinned fixture / 1280×800 window / reduce-motion / recorded platform metadata) plus
**semantic layout assertions** (element presence, nonzero cell frames, per-cell focus/selection/cull
values from accessibility). The focused-plus-selected outline-layering case is captured *and*
asserted (the cell must truthfully report both focus and selection) — never silently approved. To
add local pixel gating, compare against a per-machine baseline with a documented tolerance; do not
hide real layout changes behind a large tolerance.

## 14. Extending the harness

**Add a new P0 flow test**
1. Add stable identifiers in `Lumina/Testing/P0AccessibilityID.swift` **and** mirror them in
   `LuminaUITests/Support/P0AXID.swift` (leaf elements only — never containers).
2. If a new structured fact is needed, extend `ProbeSnapshot` in **both**
   `Lumina/Testing/UITestStateProbe.swift` and `LuminaUITests/Support/ProbeSnapshot.swift`
   (and the two full-init call sites: `LuminaRobot` fallback + `P0LogicTests`).
3. Add robot methods expressing user intent (bounded waits, verify+retry on clicks).
4. Write the flow as a `LuminaUITestCase` subclass; assert via the probe + `Invariants`.
5. Add the class name to the relevant `TestPlans/*.xctestplan` `selectedTests`.

**Extend the explorer** — add an `ExplorerAction` case, make it legal only in the right
`ExplorerState`, implement it in `apply` (tolerant; let the invariant sweep judge the result), and
add any new invariant to `Invariants.swift`.

### For the trustworthy single-photo editing checkpoint

Single-photo editing lands on `EditRecipe` and must stay independent of cull. To cover it here:
- Add identifiers for edit controls (exposure/contrast/crop/etc.) and an `editRecipe`-summary field
  on the probe (e.g. a stable hash of the focused asset's recipe).
- New flows: open a photo → adjust a control → assert the edit mark appears and the recipe hash
  changes; **cull the edited asset and assert its recipe hash is unchanged** (the existing
  edit-markers-unaffected invariant already guards the mark; add a recipe-value guard); undo an edit
  restores the prior recipe hash; edits persist across relaunch.
- Add an `editControl` explorer action (legal only in `singlePhoto`) and an invariant that culling
  never mutates the recipe hash.
- Add a visual case for an edited preview at 1280×800.

## Future: external drivers (not in this checkpoint)

Appium (via the Mac2 driver, which wraps XCUITest) could later provide a language-agnostic external
driver or cross-tool reporting. It would sit *on top of* the same accessibility identifiers and
launch mode documented here — those remain the contract. It is deliberately excluded now to keep the
harness native, fast, and dependency-free.
