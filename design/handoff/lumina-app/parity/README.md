# Lumina parity kit

This is an add-on to `design_handoff_lumina_app`, which you're already running. It makes "built to parity" something you can check, not a judgement call. There are four layers; use all four.

| # | Layer | What it catches | Files |
|---|---|---|---|
| 1 | **Tokens** | Drifting colours, sizes and timings | `tokens.json` |
| 2 | **Behaviour traces** | Subtle behaviour differences: where the current photo lands, what undo restores, when Save fires | `traces/traces.json`, `XCTest/TraceReplayTests.swift` |
| 3 | **Golden screenshots** | Visual drift on every screen and state, at 4 sizes | `capture/capture-goldens.mjs` → `goldens/`, `XCTest/GoldenSnapshotTests.swift` |
| 4 | **Human sign-off** | Feel, motion, anything automation misses | The checklist below |

Also included:
- `demo-shoot-117.json`: the exact demo shoot. The native `LUMINA_CARD=demo117` card **must** reproduce these ids, scenes, bursts, aspect ratios, suggested keepers and camera details, so that traces and goldens line up.
- `prototypes-v1.1/`: two small prototype fixes found while recording the traces (see the end of this file). Copy them over `design_handoff_lumina_app/prototypes/`.

---

## 1 · Tokens (`tokens.json`)
Every colour, font size, weight, radius, height, width formula, breakpoint, spacing step, shadow, slider constant and motion curve. All values are in points, and chrome values are multiplied by `luminaScale`.

**Use:** generate `LuminaUI/Tokens/Tokens.generated.swift` from it with a build-phase script, then review the generated file. Never hand-edit token values in Swift; change the JSON and regenerate.

This belongs to WP-0. If it's already done by hand, diff the hand-written values against the JSON once.

## 2 · Behaviour traces
`traces/traces.json` has **6 flows and 97 recorded steps** from the prototype: cull basics, step switching, ⏎ guards, edit basics, edit conflicts and the save flow. Each step records:
- the current step and photo;
- kept and out counts, and the decision on the current photo;
- the current edit settings;
- the open overlay and the zoom;
- the saved record.

`TraceReplayTests.swift` replays the same keys and clicks in the native app and checks state **after every action**.

**Setup:** add `traces.json` to the UI-test bundle resources and add `TraceReplayTests.swift` to `LuminaUITests` (it uses the `Lumina` driver from the main package). The demo card has to match `demo-shoot-117.json`.

**Re-record** after any agreed behaviour change: `cd capture && npm i && node record-traces.mjs`.

Behaviours these traces pin down that the specs only imply:
- **U** moves to the next *undecided* photo (DSC03263 → DSC03264).
- **↓** jumps to the first photo of the next scene (→ DSC03274); **↑** goes to the first photo of the previous scene.
- **⌘Z in Cull** also restores the current photo to where that decision was made.
- **Edit remembers its own position:** entering Edit lands on the first keeper (DSC03260), not on Cull's current photo, and returns to wherever you left Edit.
- **Save leaves Cull's current photo alone.**
- **`]` then `.`** nudges Temperature by +100 K (5200 → 5300). **⇧.** nudges by +5 steps (5300 → 5720, the 2% multiplicative step × 5 for Temperature).
- **X in Edit** moves to the next keeper; **⌘Z** brings back both the photo and its decision.
- **⌘S from Edit** goes to Save without saving. A second ⌘S saves, and the record shows `ne` 0 → 1.

## 3 · Golden screenshots
`capture/capture-goldens.mjs` renders **28 states × 4 sizes = 112 PNGs** from the prototypes in real Chromium:
- Sizes: 1100×760 @2x, 1440×900 @2x, 2560×1440 @1x, 480×800 @2x.
- States: empty, copying and recent Open; armed Start over; import result and failure; the drop overlay; Cull empty, copying, mid-way and all decided; Edit empty, intro, loaded, edited, help, variations, crop, 1:1, focus, colour, effects, load failure and storage warning; Save ready, saved, changed and nothing to save.

```
cd design_handoff_lumina_parity/capture
npm i                     # installs Playwright and Chromium
node capture-goldens.mjs  # about 2–3 min, writes ../goldens/** and goldens/manifest.json
```

**Why it's a script instead of PNGs in the zip:** screenshots from my tools can't render the prototype at exact sizes with every photo loaded. Playwright in a real browser can, and it's repeatable when the design changes.

`manifest.json` marks each shot:
- `"compare": "pixel"`: the native app should match within 2% of pixels. This leaves room for font rendering; the colour tolerance is 16/255.
- `"compare": "layout"`: LAYOUT_SIZING.md overrides the prototype here. That's every Cull state, because rows are now justified and tiles grow, and every 2560×1440 shot, because of the 1.25× scale. No pixel diff runs; the shots are attached for human review, and tests R-54…R-59 guard the rules.

`GoldenSnapshotTests.swift` drives the native app to each state (the `States` table mirrors the script's state names one to one), captures the window, diffs it, and attaches **golden | native | diff** images to the Xcode report every time, pass or fail.

Setup:
- Add `goldens/` to the UI-test bundle as a folder reference.
- The native window must use the full-size content view with no toolbar (LAYOUT_SIZING §5), so the captured window matches the browser viewport.

## 4 · Human sign-off
Each work package's PR must include:
1. Side-by-side screenshots (prototype | native) of its screens at 1100×760, 1440×900, 2560×1440 and 480×800. The golden test's attachments are fine.
2. A 10–20 second screen recording of its interactions, played next to the prototype doing the same.
3. The checklist, ticked:
   - [ ] Nothing reads smaller than the prototype; 2560 wide is 1.25×.
   - [ ] No dead bands (LAYOUT_SIZING §5).
   - [ ] Colours and hover/pressed states match `tokens.json`.
   - [ ] Copy matches word for word, including empty, error and loading states.
   - [ ] Motion matches durations and easing; reduced motion turns it off.
   - [ ] Focus ring visible; Tab order makes sense; VoiceOver reads every control.

One designer-reviewer, the WP-10 owner, signs off. A PR without the side-by-sides doesn't merge.

## Rules that make it stick
- **Definition of done** for each WP: its spec tests, trace replay and golden snapshots are green, and the side-by-sides are attached.
- **Freeze:** tag the current prototypes as `v1-parity`. After that, every design change goes into the README or tokens, then the goldens and traces are re-recorded, *then* the code changes. Never the other way round.
- **Divergence log:** if native has to differ (a platform constraint), record it in `PARITY_EXCEPTIONS.md` with a screenshot, and mark that shot `"compare":"layout"` in the manifest.

## Prototype fixes in `prototypes-v1.1/`
Both were found while recording the traces:
1. **Cull didn't save the current photo when you moved with ←/→, ↑/↓ or U.** A relaunch landed on the last photo you'd *decided*, not the one you were looking at (part of R-70). Fixed: moving saves.
2. **A live state hook for recorders** (`window.luminaFlow()`, and `keep` in `luminaState()`), so traces read in-memory state instead of debounced storage. This matches the native `debug.state` contract.

Copy both files over the main package's `prototypes/`. Neither changes anything visual.
