# P0 UI Automation — Context Block, Postmortem & Roadmap

> Handoff document. Assumes the reader is picking up Lumina cold. Pairs with
> `docs/P0_UI_AUTOMATION.md` (the how-to reference). This doc is the *why*, the *state of the world*,
> the *UX gaps*, and the *plan* — written so an agent or engineer can act without re-deriving it.

---

## 0. TL;DR

We built a Playwright-like **native macOS XCUITest harness** that launches Lumina against
**isolated, deterministic fixture state** and drives the **real P0 UI** with keyboard + mouse,
producing **replayable evidence** (seed + action trace + screenshots + a structured JSON state
probe). It ships on branch `cursor/p0-ui-automation-harness` (draft PR #19, stacked on
`cursor/p0-cull-grammar`).

- **Green:** Debug + Release build; `P0Fast` 15/15; `P0Visual` 3/3; explorer seed replays; prior
  Swift tests.
- **Safe:** never touches the maintainer's real catalog; all test hooks compile out of Release.
- **Extensible:** a documented contract (accessibility IDs + state probe + robots + invariants) that
  the next checkpoints (editing, compare, batch, export) plug into.

The rest of this doc is what you need to keep it healthy and to make **every P0 UX flow testable** —
including the ones that are only *partially* covered today.

---

## 1. What was achieved (this checkpoint)

| Area | Delivered |
|---|---|
| **Isolated launch mode** (DEBUG) | `--ui-testing` redirects `ShootStore.supportDirectory()` to a temp dir; real catalog untouched; hooks stripped from Release |
| **Deterministic fixtures** | `mixed-60`, `mixed-200`, `missing-originals` — synthesized images (no RAW/binaries), pure function of index |
| **State probe** | Hidden accessibility element publishing a JSON `ProbeSnapshot` (route, counts, focus, selection, per-asset cull map, availability, scroll, visible/missing IDs) — the authoritative structured state |
| **Accessibility contract** | `P0AccessibilityID` (app) ↔ `P0AXID` (test mirror), keyed by durable asset UUID; asserted by `LuminaLogicTests` |
| **Robots** | `LuminaRobot` façade + `OpenShoot/ContactSheet/SinglePhoto/Diagnostics` |
| **Deterministic flows (9)** | open/nav, cull grammar, undo, selection⊥focus, grid↔photo restore, persistence, missing originals, layout, repeated-nav stress |
| **Seeded explorer** | State-aware legal-action walk, invariant sweep, exact seed replay, failure report |
| **Visual regression** | Pinned 1280×800 capture + semantic layout assertions (incl. focused+selected layering) |
| **Plumbing** | Shared scheme, `P0Fast/Stress/Visual` plans, `run_p0_ui_tests.sh`, portable checks in `regression.sh`, docs |

**Out of scope (deliberately untouched):** editing, comparison, batch apply, export redesign, AI,
Rust, deeper Metal. No P0 product behavior changed (one behavior-preserving refactor:
`openRecent` → `openShoot(named:)`).

---

## 2. Harness architecture (so you can extend it)

```
Lumina/Testing/                     App-side, DEBUG-gated except the ID namespace + probe types
  UITestSupport.swift               arg/env parsing; isActive; stateDirectoryOverride; window; autoOpen
  UITestLaunch.swift    (#if DEBUG) LuminaApp.init entry: set overrides, seed fixture
  UITestFixtures.swift  (#if DEBUG) synthesize mixed-60/200/missing-originals into the temp dir
  UITestStateProbe.swift            ProbeSnapshot + NSView probe + activator + window sizer
  P0AccessibilityID.swift           canonical identifier namespace (ships in all configs)

LuminaUITests/                      black-box XCUITest bundle (cannot import the app)
  Support/  P0AXID (mirror), LaunchConfig, SeededRNG, ProbeSnapshot (decoder), Invariants,
            XCUIApplication+Probe, LuminaUITestCase (base + failure artifacts)
  Robots/   LuminaRobot, OpenShootRobot, ContactSheetRobot, SinglePhotoRobot, DiagnosticsRobot
  Flows/    the 9 deterministic flows
  Explorer/ ExplorerModel (states/actions), ExplorerRunner, ExplorerTests
  Visual/   VisualRegressionTests

LuminaLogicTests/  @testable import Lumina — cull/undo/membership + ID/probe contract
TestPlans/         P0Fast.xctestplan, P0Stress.xctestplan, P0Visual.xctestplan
Scripts/run/run_p0_ui_tests.sh
```

**The load-bearing idea:** tests assert against the **state probe** (structured JSON), not UI text
or pixels. The probe is the contract between the app and the harness. Everything else (identifiers,
robots) is ergonomics on top of it.

---

## 3. Postmortem — findings & hard-won lessons

These cost real iteration time. Internalize them before touching the harness.

1. **SwiftUI propagates a container's `accessibilityIdentifier` onto every descendant.** Putting an
   ID on the contact-sheet ZStack or the toolbar HStack silently overwrote the density/undo/count
   identifiers with the container's. **Rule: identifiers on leaf views only.** Surfaces are detected
   via the probe's `route`, not container elements.

2. **Keyboard events go to the AppKit first responder, which isn't the SwiftUI focusable on load.**
   Arrows/P/X only work after a click puts the `NSCollectionView` in the responder chain. Tests call
   `focus(assetID:)`/`establishKeyboardFocus()`; **this is also a real UX gap (§6.1).**

3. **Cold-start under XCUITest can leave the app backgrounded** → macOS exposes a collapsed
   accessibility tree (window, no descendants) and the SwiftUI Open-surface recent list can be
   momentarily empty. Fixes: an in-app **activator** (`NSApp.activate` + `makeKeyAndOrderFront`),
   **launch self-heal** (poll for the probe, retry once), and **auto-open the fixture by name** via
   the real `openExisting` path so flows don't depend on the fragile Open-surface a11y. **This
   fragility mirrors a real UX robustness gap (§6.2).**

4. **Duplicate accessibility elements make `firstMatch` ambiguous** and clicks land on the wrong
   cell. Each contact cell exposed both its container *and* its inner `NSImageView` with the same ID.
   Fix: inner views set non-accessibility; the cell container is the single labeled element.

5. **Elements go stale during reflow.** The sheet reflows while previews stream in; an element
   resolved a moment ago can be gone at click time (a hard XCUITest click then *throws*). Fix:
   coordinate-center clicks with **verify-and-retry**, and click the *stable* collection view (not a
   specific cell) to establish keyboard focus.

6. **`mixed-200` probe reads are heavy (~4–7 s/step).** The probe serializes a 200-entry cull map +
   ID lists; reading a large accessibility value repeatedly dominates explorer wall-time. Mitigations:
   carry the snapshot forward between steps; stress default = 80 steps; seed replay runs under the
   `P0Stress` time budget. If this bites, add a "lite" probe mode that omits the full cull map when
   `assetCount` is large and diff only counts + focused cell.

7. **Env vars don't reach the test bundle** the way you'd expect. App config goes via
   `launchArguments` (reliable). Test-side knobs (seed/steps/state-root) reach the test process only
   via `TEST_RUNNER_<NAME>` (xcodebuild forwards it stripped of prefix). The runner uses this.

8. **`xcodebuild` default per-test time allowance is 3 min.** Long explorer/stress runs must use a
   plan with a raised `maximumTestExecutionTimeAllowance` — otherwise a healthy run is killed and
   reported as a crash/timeout.

9. **The 127 s `p0.open.recent.mixed-60` dead-poll (root-caused and fixed).** A `P0Fast` run
   spent 2+ minutes re-checking one Recent-row element and then failed with the misleading
   "Recent shoot mixed-60 not listed". Reproduced and proven
   (`OpenNavigationTests/testOpenPreparedShootShowsContactSheet`, failed at 151.9 s):
   - *Trigger:* on a desktop in **active interactive use**, the freshly launched app can lose
     activation to the human user; a backgrounded app exposes a **collapsed accessibility tree**
     (menu bar only — no window, no probe). Both 25 s launch self-heal attempts saw no probe.
     Evidence: `XCUIApplication.state == 3` (background), a11y tree without a window, and the
     failure-time "main window" screenshot showing the user's own frontmost app.
   - *Amplifier 1 — dead-app continuation:* after both attempts failed, `launchUntilProbeAppears`
     returned the **terminated** app handle instead of failing, so every later query polled a dead
     process.
   - *Amplifier 2 — coupling:* `OpenShootRobot.open()` had a Recent-row **click fallback**, so a
     deterministic flow ended up waiting 40 s for `p0.open.recent.mixed-60` — an element that
     cannot exist once auto-open has left the Open surface (or the app is gone).
   - *Amplifier 3 — false-success waits:* `waitForProbe` returned the *last seen* snapshot on
     timeout, so `!= nil` checks passed while the predicate never held, and nested waits stacked
     (8 s + 40 s + 40 s + retries ≈ the 180 s kill allowance).
   - *Not the cause (proven healthy):* fixture seeding/persistence (`shoot.json`, 60 assets, in the
     isolated state root), state-root plumbing (app and runner agree on the path), and Open-view
     accessibility (the row appears in ~2 s when the app is frontmost on `route == open`).
   - *Fix:* the two contracts below, explicit budgets in `UITestWait`, strict `waitForProbe`
     (returns nil unless the predicate matched), launch failure → immediate diagnostic `XCTFail`,
     and bounded re-activation (`app.activate()` when `state != runningForeground`) inside probe
     polls and before clicks. No wait anywhere may approach the 180 s allowance.

   **Separated contracts.** (a) *Deterministic navigation* — cull/undo/persistence/explorer flows
   open fixtures **only** via `--ui-test-autoopen` → real `openExisting`, with one bounded probe
   wait (`UITestWait.autoOpenNavigation`, 30 s) and a diagnostic failure that reports probe route,
   app activation state, state root, the shoots actually seeded on disk, and a concise
   accessibility excerpt. They never look up a Recent-row element. (b) *Recent-list UX* — one
   dedicated test, `testRecentRowOpensPreparedShoot`, proves `route == open`, `mixed-60` seeded in
   the isolated store, the row accessible within `UITestWait.recentRow` (12 s), and a **single**
   click reaching `route == contactSheet` within `UITestWait.transition` (10 s).

   **Budgets** (`LuminaUITests/Support/UITestWait.swift`): launch ≤ 2 × 25 s, auto-open ≤ 30 s,
   Recent row ≤ 12 s, action transition ≤ 10 s. Measured after the fix on a warm Mac: logic suite
   < 0.1 s; Recent-row test 4.6–12.7 s; auto-open test 2.2–7.9 s; full `P0Fast` 20/20 in ~2 min.

---

## 4. Ground truth — the P0 UX surfaces (from the code)

So UX discussion is precise, here is what actually exists today.

**Open surface** (`P0OpenView`): brand header + "Legacy shell" button; "Open a shoot" hero with a
**Choose a folder** button and a dashed **Drop folder** target; **Recent shoots** list (name +
`N photos · N kept · folder`); drop-anywhere. Route `.open`.

**Contact sheet** (`P0ContactSheetView` + `ContactSheetCollection`): a toolbar
(back-to-Open chevron · shoot title · preparation status line · `N export` chip · `N selected`
chip · **Undo** · density `-` / value / `+`) above a **row-packed `NSCollectionView`** (no uniform
crop; cell width from aspect). Per-cell chrome: **focus** = charcoal outline, **selection** = warm
accent outline (distinct rings), **keep** = ✓ chip, **reject** = ~50% dim + ✕ chip, **edited** =
small light bar, **kept-order** = number chip. Keyboard grammar: arrows (focus), **P** keep / **X**
reject (toggle), **⌘Z** undo, **+/-** density, **Return** open, **Esc** close. Pinch magnify also
changes density. Route `.contactSheet`.

**Single-photo placeholder** (`P0SinglePhotoPlaceholder`): header (**Grid** return · filename ·
cull chip · `P keep · X reject · Esc grid` hint); large fit-preview *or* "Preview unavailable —
cached preview missing" (only when both preview and cache are absent); a **filmstrip** of neighbors.
No editing rail yet. Route `.singlePhoto` (overlay within the same focusable view).

**Cross-cutting:** focus ⊥ selection (independent); cull is immediate + persisted with undo and
never touches recipe/selection; scroll anchor + focus restore on grid↔photo; missing originals keep
cached previews and never delete the catalog; reduce-motion honored.

---

## 5. UX flows × testability matrix

Legend: ✅ covered & robust · 🟡 partially / indirectly covered · ⬜ not yet testable (needs work).

| UX flow | Today's coverage | Gap / what to add to test it well |
|---|---|---|
| Open via **Recent** row click | ✅ `testRecentRowOpensPreparedShoot` proves row accessibility ≤ 12 s of `route==open` and single-click navigation to the contact sheet (§3.9) | Product-side hit-target hardening (§6.2) still worthwhile |
| Open via **Choose folder** / **Drop folder** | ⬜ | Needs a fixture *folder* on disk + a way to drive `NSOpenPanel` (can't via XCUITest) → add a DEBUG `--ui-test-open-folder <path>` that routes through the real `openFolder`; test drop via a synthesized file-URL drag |
| **Arrow** focus navigation | ✅ | — |
| **Density** +/- (and pinch) | ✅ buttons; ⬜ pinch gesture | Add a magnify-gesture driver or a probe assertion after a synthesized pinch |
| **Cull** P/X toggle + independence | ✅ | — |
| **Undo** (incl. after nav) | ✅ | — |
| **Selection**: ⌘-click, ⇧-range | ✅ | Note: any click (incl ⌘) **also moves focus** — see §6.5; add an explicit test asserting that documented behavior |
| **Grid → photo → grid** restore | ✅ focus/scroll/selection | Scroll restore asserted with tolerance; tighten once scroll semantics are firmed |
| **Filmstrip** navigation (click a neighbor) | 🟡 presence asserted | Add clicks on `p0.filmstrip.<uuid>` items and assert focus follows |
| **Double-click** to open | ⬜ (unreliable under automation) | Either make the open affordance a real element or accept Return-only in tests; document |
| **Persistence** across relaunch | ✅ | — |
| **Missing originals** | ✅ catalog + cached previews + structured unavailability | The *UI* has no per-asset "original offline" affordance — §6.6 |
| **Layout** @1280×800 + larger | ✅ reachability + nonzero frames | Add explicit **hit-target** assertions (density buttons fail this — §6.3) |
| **Repeated-nav** stress | ✅ | — |
| **Home / back to Open** | 🟡 button exists | Add a flow: cull → home → reopen → decisions intact |
| **Legacy shell** toggle | ⬜ | Low priority; add a smoke test that it opens and returns |
| **Reduce-motion** | 🟡 forced in tests | Add an assertion that transitions are instant under `--reduce-motion` |
| **Error alert** ("Could not open") | ⬜ | Drive a failing open (bad path) and assert the alert + recovery |

---

## 6. UX issues discovered (candidate product improvements) — each with a testable acceptance criterion

Building the harness surfaced concrete UX frictions. None were "fixed" (out of scope), but each is a
real improvement **and** each comes with a probe-checkable acceptance criterion so it can be
test-driven.

1. **Grid isn't keyboard-ready on open.** A user who opens a shoot must *click* before arrows/P/X
   work. **Improve:** auto-focus the contact sheet (make the focusable view first responder) on
   open. **Testable AC:** after `open`, without any click, `focusNext` changes `focusedAssetID`.

2. **Open-surface recent list is fragile** (occasionally empty on cold start; row-click doesn't
   always navigate). **Improve:** guarantee the recent list is populated before first paint (await
   the listing) and give rows a full-width, ≥44pt hit target. **Testable AC:** `p0.open.recent.<name>`
   exists within N ms of `route==open` on a cold launch; a single click reaches `route==contactSheet`.

3. **Density `+/-` buttons are ~6pt wide** — below Lumina's own `HitTarget.minimum` (44pt).
   **Improve:** size them to the token. **Testable AC:** each density control's frame ≥ 44×24 pt at
   1280×800.

4. **Density glyphs are inverted-feeling:** `-` adds columns ("more photos"), `+` removes them
   ("fewer"). The labels compensate but the glyph is counterintuitive. **Improve:** swap glyphs or
   use zoom-in/zoom-out iconography. **Testable AC:** the control labeled "more photographs" is the
   one whose value increases columns (assert via probe `densityColumns`).

5. **Any click reassigns focus** (including ⌘-click, which is meant to *extend selection*). Focus and
   selection are "independent," but the only way to move focus without disturbing selection is the
   keyboard. **Decide + document** the intended model (should ⌘-click move focus?). **Testable AC:**
   pin the chosen behavior in `SelectionFocusTests`.

6. **Missing-original photos give no in-place affordance.** Opening one shows a normal cached preview;
   the only hint is a global toolbar status line. **Improve:** a per-asset "Original offline" chip in
   the single-photo header (and optionally a corner badge on the cell). **Testable AC:** with
   `missing-originals`, opening a missing asset shows `p0.singlePhoto.originalOffline`; the probe's
   `focusedAvailability=="missing"`. (The identifier is reserved conceptually; add it when built.)

7. **Focus vs selection outlines are subtle** (charcoal vs warm accent, 2–2.5pt). Distinguishing them
   is the crux of the "focused-plus-selected" layering case. **Improve:** stronger visual language +
   a legend/affordance. **Testable AC:** the visual case is already captured; add a semantic check
   that a cell can report both focus and selection (done) and, once redesigned, a pixel baseline
   locally.

8. **No visible affordance that Return/double-click opens a photo, or that P/X cull.** Discoverability
   gap. **Improve:** a subtle hint on hover/first-run. **Testable AC:** presence of the hint element
   when applicable.

> Prioritization (impact × effort): **#1, #3, #6** are high-impact, low-effort and directly improve
> both UX and testability — do these first. **#2** is medium effort but removes the harness's biggest
> flakiness source. **#4, #5, #8** are polish/decisions. **#7** rides the editing/redesign work.

---

## 7. The playbook — how to make any new UX flow robustly testable

When you add or change a P0 surface, do all five, in order:

1. **Identifiers** — add leaf-only `accessibilityIdentifier`s in `Lumina/Testing/P0AccessibilityID.swift`
   **and** mirror them in `LuminaUITests/Support/P0AXID.swift`. Never on a container with identified
   children. Key per-item elements by durable UUID.
2. **Probe** — if the flow has state a test must assert, add a field to `ProbeSnapshot` in **both**
   `Lumina/Testing/UITestStateProbe.swift` and `LuminaUITests/Support/ProbeSnapshot.swift`, and update
   the two full-init sites (`LuminaRobot` fallback, `P0LogicTests`). The probe — not UI text — is the
   assertion surface.
3. **Robot** — express the interaction as intent on the relevant robot; use bounded probe waits,
   coordinate-center clicks with verify-and-retry, no fixed sleeps.
4. **Invariant** — if the flow implies a rule that must always hold, add it to `Invariants.swift` so
   the explorer checks it after *every* action, not just in one flow.
5. **Plan** — add the test class to the right `TestPlans/*.xctestplan` and, if it's a new interactive
   verb, add an `ExplorerAction` (legal only in the right `ExplorerState`).

**Interaction reliability rules of thumb:** prefer semantic elements; click the stable collection to
gain keyboard focus; verify every state-changing click via the probe and retry; treat "off-screen /
virtualized" as a safe no-op, never a hard click.

---

## 8. Roadmap going forward

Sequenced by dependency. Each checkpoint extends the harness via §7.

**Now → next (harden what exists):**
- Land UX improvements **#1 (auto-focus grid)**, **#3 (density hit targets)**, **#6 (missing-original
  affordance)** — each ships with its AC test. These also delete the harness's remaining flakiness.
- Add the ⬜ flows: **open-by-folder** (`--ui-test-open-folder` through real `openFolder`),
  **filmstrip clicks**, **home→reopen persistence**, **error-alert + recovery**, **reduce-motion
  instant-transition** assertion.
- Add a **CI gate on a Mac runner** (Accessibility permission pre-granted) running `P0Fast` on every
  checkpoint; `P0Stress`/`P0Visual` before merge.

**Checkpoint: trustworthy single-photo editing** (the immediate product next step):
- The editor lands on `EditRecipe` and must stay **independent of cull**. Extend the harness:
  identifiers for each control (exposure/contrast/temp/tint/crop/straighten/rotate); a probe field
  `editRecipeHash` for the focused asset.
- Flows: adjust a control → the **edited mark** appears and the recipe hash changes; **cull an edited
  asset → recipe hash unchanged** (guards the hard invariant); undo an edit restores the prior hash;
  edits **persist across relaunch**; crop/straighten geometry round-trips.
- New `editControl` explorer action (legal only in `singlePhoto`) + invariant "cull never mutates the
  recipe hash."
- New visual case: edited preview at 1280×800.

**Later checkpoints (each plugs into §7):**
- **Comparison** (A/B, multi-up): identifiers per pane; probe `comparisonSet`; invariant "compare
  never mutates cull/recipe."
- **Batch application:** leader→recipients; `BatchEditCommand` already exists; probe the recipient
  set + geometry-stripping default; invariant "batch is undoable and geometry excluded unless opted
  in."
- **Export redesign:** kept-set == export count is already a P0 invariant (`exportCount == keptCount`);
  extend probe with export collections; invariant "export snapshot never redefines the live kept set."
- **AI / taste / scoring:** must stay **disabled** under `--ui-testing` (they are, on the P0 route);
  when re-enabled, add a determinism seam so fixtures stay reproducible.
- **Rust / deeper Metal:** rendering perf — add metrics capture to the probe (`p0.first_usable_preview`
  etc. already recorded via `LatencyMetrics`) and a perf-budget assertion in `P0Stress`.

---

## 9. Known limitations / risks

- **First cold launch ~25–30 s** (self-healing retry); warm launches ~4 s. Acceptable but real.
- **`mixed-200` probe reads are heavy** → explorer is slow at scale (see §3.6 for the mitigation).
- **Exact pixel gating is local-Mac-only** by policy (macOS renders vary); semantic layout + capture
  are the portable, gated floor.
- **macOS + Xcode only**; Linux runs only the portable manifest checks. First XCUITest run needs
  Accessibility/Automation permission granted (blocks headless CI until pre-granted).
- **`NSOpenPanel`-based open can't be driven by XCUITest** — needs a DEBUG folder-open arg to be
  testable end-to-end.
- The **auto-open-by-name** path is a test convenience; keep the one manual click-through test
  (`testRecentRowOpensPreparedShoot`) so the real Open UI stays covered.
- **A desktop in active interactive use degrades XCUITest reliability**: the human user can steal
  activation/focus at any moment, collapsing the app's accessibility tree and swallowing injected
  clicks/keys (§3.9). The harness re-activates the app (bounded) and fails fast with diagnostics,
  but a genuinely contended screen can still fail click-driven tests — prefer a quiescent session
  (or a dedicated CI Mac) for gating runs.

---

## 10. Quick reference

```bash
bash Scripts/run/run_p0_ui_tests.sh fast            # deterministic flows + logic + short explorer
bash Scripts/run/run_p0_ui_tests.sh stress          # mixed-200, long explorer, relaunch, resize
bash Scripts/run/run_p0_ui_tests.sh visual          # pinned 1280x800 capture + semantic layout
bash Scripts/run/run_p0_ui_tests.sh logic           # native XCTest only (fast, no UI)
bash Scripts/run/run_p0_ui_tests.sh seed 84721 120  # exact explorer seed replay
```

Artifacts (per run): `artifacts/ui-automation/<mode>-<timestamp>/` — `.xcresult`, log, isolated
`state/` (failure snapshots preserved). Result-bundle path is printed. Full reference:
`docs/P0_UI_AUTOMATION.md`.

**Key files to know:** `Lumina/Testing/UITestStateProbe.swift` (the probe schema — the contract),
`Lumina/Testing/P0AccessibilityID.swift` (+ mirror `LuminaUITests/Support/P0AXID.swift`),
`LuminaUITests/Support/Invariants.swift`, `LuminaUITests/Explorer/ExplorerRunner.swift`.
