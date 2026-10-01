# Workstreams: build to parity fast, in parallel

The build is split into **bounded work packages (WPs)**. Each one can go to its own agent (a Claude Code instance or "factory worker") or engineer, with:
- **owned paths**: only this WP edits these files; everything else is read-only to it;
- **inputs**: the contracts it builds against;
- **done when**: named tests are green, plus `LayoutAndSizingTests` and the screen review checklist.

Shared code changes **only** through WP-0 contracts. This keeps merge conflicts near zero with 8–10 workers running at once.

## Timeline (wall clock, with 9 parallel workers)
```
Wave 0  (1 worker, ~2h)    WP-0 Contracts & skeleton             ← blocks everything
Wave 1  (8 workers, ~1 day) WP-1 … WP-8 in parallel
Wave 2  (3 workers, ~½ day) WP-9 Integration · WP-10 Visual parity · WP-11 Perf & soak
Gate    (CI, ~1h)           Release-candidate gates (TEST_PLAN.md)
```
The backend is ready, so WP-8 wires the stores to it instead of building persistence from scratch.

## WP-0 · Contracts and skeleton (blocking, do first)
**Owns:** `LuminaCore/Contracts/*`, `LuminaUI/Tokens/*`, `LuminaUI/Shell/AppShell.swift` (stub), `LuminaUI/Debug/*`, both test targets, the `Lumina-UITest` scheme.

**Builds:**
1. **Models:** `Photo`, `Scene`, `Burst`, `Shoot`, `Look` (`[String: Double]`), `Decision`, `Step`, `SaveFormat`, `SavedRecord`.
2. **Protocols:**
   - `ShootSource` (card / folder / demo / Unsplash)
   - `DecisionStore`, `EditStore` (each with undo/redo, 200 deep)
   - `PersistenceStore` (backed by the backend)
   - `ImageProvider` (decode at size, preload, fail)
   - `Exporter`
3. **`KeyRouter`:** `Layer`, `Route` and `Action` types, following KEYMAP.md. The table lives here and is the single source of truth.
4. **Tokens:** every colour, radius, spacing and motion value from README.md as Swift constants. `LuminaFont.*(scale)` records every size for `debug.metrics`. `LayoutScale.scale(for:)` and the `@Environment(\.luminaScale)` plumbing.
5. **`AccessibilityID`:** an enum with every identifier in ACCESSIBILITY_CONTRACT.md.
6. **Debug hooks:** `debug.state`, `debug.metrics`, `debug.memoryMB`, `debug.command`, launch env parsing, fault injection, an error funnel counter, os_signpost names. All `#if LUMINA_UITEST`.
7. **Stubs** that compile for every WP's entry view, so other WPs can start immediately.

**Done when:** both test targets build; `CoreRulesTests` compiles (failing is fine); the app launches to a stub shell with `step.*` tabs and `debug.state`.

## Wave 1 (parallel)

### WP-1 · Shell, tabs, global keys, motion
**Owns:** `LuminaUI/Shell/*`, `LuminaUI/Motion/*`.
**Builds:**
- The window with a full-size content view and the tabs in the titlebar area (no toolbar gap).
- The top bar and its breakpoints; the sliding tab thumb; step fades.
- The drop overlay view (the import logic belongs to WP-2).
- Global ⌘1–4, ⌘S and ⌘O through `KeyRouter`.
- Reduced motion.

**Done when:** `test_R01`, `test_R02`, `test_R50` (shell parts), `test_R54`, `test_R57` (title gap), `test_R59` and `test_R61` pass.

### WP-2 · Open and import
**Owns:** `LuminaCore/Import/*`, `LuminaUI/Open/*`.
**Builds:**
- `ImportClassifier`; decode probing with orientation applied; `EXIFReader` (ImageIO).
- `SceneGrouper`; dedupe.
- An import queue that handles drops during an import.
- The summary message wording; folder and file pickers; recursive folder walk.
- A security-scoped bookmark to reopen the last folder.
- The card copy with progress, resuming and only counting up (via the backend copy service).
- Open screen UI; the Start over double-click guard.

**Done when:** every `FirstTimerTests` test named R-10…R-1D, `ImportClassifierTests`, `EXIFAndGroupingTests`, `test_R1A`, `test_R31` and `test_R85` pass.

### WP-3 · Cull
**Owns:** `LuminaUI/Cull/*`, `LuminaCore/Decisions/*`.
**Builds:**
- The justified grid with `CullLayout`, plus ⌘+/⌘− tile size.
- The tile states: kept pop, Out dim, suggested ring, burst bar.
- Keep-suggested per scene; the preview column; the footer.
- R / X / U / arrows; `DecisionStore` with undo/redo.
- Keeping the current tile scrolled into view without jumps.

**Done when:** `test_R04`, `test_R05`, `test_R28` (Cull part), `test_R56`, `test_R58`, `test_R80`, `test_R82`, `DecisionAndEditTests` (decision parts) and `test_mouseOnly` pass.

### WP-4 · Edit canvas
**Owns:** `LuminaUI/Edit/Canvas/*`, `LuminaCore/Imaging/*`.
**Builds:**
- `ImageProvider`: low-res first, then sharp, with a 150ms fade.
- Preloading next, next+1 and previous; size selection by backing scale.
- Zoom (picker, pinch, ⌘±, Z at the pointer, pan, clamped range).
- Focus mode; Before (hold \ and force click).
- Load failure and Retry; the empty state; the filmstrip; the facts line.
- Crop and straighten: ratios, turn, angle, thirds grid, its own undo.
- `EditLayout.photoRect`.

**Done when:** `test_R41` (via `test_R1C`), `test_R43`, `test_R44`, `test_R45`, `test_R46`, `test_R55`, `test_resizeStorm_whileEditing`, `test_R1D` (display), `test_R24_cropOwnsTheKeyboard`, `test_R81` and `LayoutMathTests.test_R41_R55` pass.

### WP-5 · Edit controls
**Owns:** `LuminaUI/Edit/Controls/*`, `LuminaCore/Edits/*`.
**Builds:**
- Sections; every slider from the README table, to the exact slider-row spec (track, fill, default tick, thumb springs, drag modifiers, snap to default, Esc cancel, double-click reset, type a value, two-finger swipe, hint line).
- Nudge , . and [ ]; reset 0 / ⇧0; Auto; same as last; white picker; copy and paste.
- `EditStore`, with burst frames sharing one edit, and its own undo/redo.
- The flush-on-leave rule (R-07).
- The bottom bar.

**Done when:** `test_R07`, `test_R20`, `test_R22`, `test_R27`, `test_R28` (Edit part), `test_R03`, `test_R33`, `test_R35`, `test_R86` and `DecisionAndEditTests.test_burstFramesShareOneEdit` pass.

### WP-6 · Edit overlays
**Owns:** `LuminaUI/Edit/Overlays/*`.
**Builds:**
- Variations: hold V, the target under the pointer, three cells (or the 3×3 white-balance grid, or two cells for vignette); apply on release; tap opens without applying; cancelled if the photo changes; closes when the window loses focus.
- Help with the KEYMAP list.
- First-run intro.
- Esc unwinding one layer at a time.
- The scene grid.

**Done when:** `test_R06`, `test_R21`, `test_R23`, `test_R24_*`, `test_R25`, `test_R26` and `KeyRouterTests` pass.

### WP-7 · Save
**Owns:** `LuminaUI/Save/*`, `LuminaCore/Export/*`.
**Builds:**
- The format segment and its descriptions; the destination picker; Include my edits.
- `SaveSignature`; the Save button states and note; the saved card.
- The ⏎ guard; ⌘S.
- XMP, folder and JPEG writers through the backend export service, with file I/O off the main thread.
- Show in Finder.

**Done when:** `test_R32`, `test_R34`, `test_R36`, `test_R83`, `DecisionAndEditTests.test_R34`, and `test_R57` (Save) pass.

### WP-8 · Persistence, windows, faults (backend wiring)
**Owns:** `LuminaCore/Persistence/*`.
**Builds:**
- `PersistenceStore` on the backend: write-through, Edit drags coalesced, saved at least every 15 copied photos.
- Restore on launch: the step, current photo, decisions, edits and copy progress.
- Storage-full handling, with the warning while still working in memory.
- The other-window notice; offline state.
- Data migration from the previous version.

**Done when:** `test_R70`, `test_R71`, `test_R72`, `test_R84`, `test_R19` and `test_R1A` (with WP-2) pass.

## Wave 2

### WP-9 · Integration
Merges Wave 1. **Owns nothing new**; it fixes seams through PRs against each WP's paths, with that WP's reviewer. Runs the full PR suite until green.

**Done when:** every UI test except Load and Soak is green.

### WP-10 · Visual parity
**Owns:** visual-only edits across `LuminaUI/*`, coordinated with the WP owners.
**Does:** side-by-side review of every screen at 1100×760, 1440×900, 2560×1440 and 480×800 against `prototypes/`, plus LAYOUT_SIZING.md (which wins where they differ). Checks every token, piece of copy and animation timing.

**Done when:** the screen review checklist below is signed off, and `test_R50`–`test_R59` and `test_R52`–`test_R53` are green.

### WP-11 · Performance and soak
**Owns:** perf fixes, coordinated with the WP owners.
**Does:**
- Records the baselines.
- Profiles with Instruments (Time Profiler, Allocations, Leaks), for photo switching at 5,000 and the soak at 25 and 50 rounds.
- Known traps from the prototype:
  - Recomputing the photo order per render (it was 228ms at 5,000; cache it, keyed by decisions).
  - Global hooks that keep the previous Edit alive (a leak).
  - Thumbnails starving the main photo's download.

**Done when:** LoadTests are within their baselines and SoakTests pass with 25 rounds.

## Screen review checklist (WP-10)
For each screen, at each of the 4 sizes:
- [ ] Nothing reads smaller than the prototype at 1100×760 or 1440×900. Big screens are 1.25× (LAYOUT_SIZING §3).
- [ ] No dead bands: content fills per LAYOUT_SIZING §5.
- [ ] Colours match the tokens, including hover and pressed states.
- [ ] Copy matches word for word, including empty, error and loading states.
- [ ] Motion matches durations and easing; reduced motion turns it off.
- [ ] Keyboard focus is visible and Tab order makes sense.
- [ ] VoiceOver reads every control.

## Rules for every worker
1. Read README.md, LAYOUT_SIZING.md, KEYMAP.md, BEHAVIOR_SPEC.md and ACCESSIBILITY_CONTRACT.md before writing code.
2. Edit only your owned paths. If you need a contract change, open a PR against WP-0's paths and tag the WP-0 owner. Never fork a type locally.
3. Every interactive view gets its `AccessibilityID` when you create it, not later.
4. No hard-coded sizes or colours: tokens × `luminaScale` only.
5. Before you mark done, run `LuminaCoreTests`, your WP's tests and `LayoutAndSizingTests`. Paste the results in the PR.
6. If a test seems wrong, don't edit it to pass. Raise it with the rule ID; the rule and the test change together.

## Kickoff prompt (paste into each worker, then fill in the WP)
```
You are building WP-<n> "<name>" of the Lumina macOS app.
Read, in order: design_handoff_lumina_app/README.md, LAYOUT_SIZING.md, KEYMAP.md,
BEHAVIOR_SPEC.md, ACCESSIBILITY_CONTRACT.md, WORKSTREAMS.md (your WP section).
Open the matching prototype in prototypes/ in a browser to see the behaviour.
You own only these paths: <owned paths>. Everything else is read-only; contract changes go through WP-0.
Build against the WP-0 contracts. Use tokens × luminaScale for every size and colour.
Add the AccessibilityIDs and debug.state fields your views need.
You're done when these pass: <tests> + LuminaCoreTests + LayoutAndSizingTests.
Work in small commits. At the end, post the test results and a screenshot of each screen at 1100×760 and 2560×1440.
```

## If you only have 3 workers
- **Worker A:** WP-0, then WP-1, then WP-8.
- **Worker B:** WP-2, then WP-3, then WP-7.
- **Worker C:** WP-4, then WP-5, then WP-6.

Then all three do WP-9…WP-11 together. Expect about 3 days instead of about 1.5.
