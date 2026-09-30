# AGENTS.md

Guidance for AI agents and developers working on **Lumina**, a native macOS photo culling app for
Sony ARW shooters.

## The rule

**The design is the product.** Lumina's UI is the Claude Design page in `design/handoff/lumina-cull/`
(`Lumina Sets v5.dc.html` + `support.js` + `lumina-core-v4.js` + `lumina-v4-data.js` + `lumina-selftest.js`;
the names live in `Scripts/page_files.sh`). The app ships those files **byte for byte** inside a native
window. Nobody edits the UI in this repo.

- Something visible is wrong or missing (layout, copy, keys, empty states)? It goes into
  `design/handoff/DESIGN-ASKS.md` as a ready-to-paste Claude Design prompt. It never gets patched here.
- A new handoff arrives as a zip. Sync it with `bash Scripts/sets_sync_design.sh "<zip>"`. That runs the
  fixtures, audits the wording and demo layer, installs the files, checks the plumbing contract,
  compares every screen pixel for pixel, and runs the robustness suites. It never commits. Add
  `--record` once the new look is approved.
- Authority order: `design/handoff/lumina-cull` (its `PROMPT.md` sets the order inside it: ADDENDUM-1 →
  PARITY → GRAMMAR → the page → CHANGES / SAFETY / MENUS) → `Lumina/Sets` (plumbing) → tests.
  The handoff's own `plumbing.js` is an older reference; the app's is `Lumina/Sets/Web/plumbing.js`.

## What the app is

| Path | What it does |
|---|---|
| `Lumina/LuminaApp.swift` | One window and the menu bar from MENUS.md: every item calls `window.luminaCommand(name)`; Quit asks about unsaved keepers |
| `Lumina/Sets/SetsRootView.swift` | The WKWebView, the native folder pickers, downloads |
| `Lumina/Sets/Web/` | The design's files, copied unchanged by `Scripts/sets_sync_ui.sh`, plus `plumbing.js` |
| `Lumina/Sets/Web/plumbing.js` | **The only app-side difference.** It swaps the page's browser I/O (`openFolder` + `onDir`/`readOne`, `writeInto`, `impStart`, `libOpen`) for native calls, provides `window.lumina` (the data contract: `card`, `readingCard`, `reveal`, `setPrefs`, `openSettings`, `checkAccess`, …), persists sessions, makes the grid thumbnails (720 × 480; measures stay on the page's 360 px bitmap) and decodes them ahead of a scroll (design ask 7), keeps the reader's place and decisions when a read they culled during ends (design ask 8), and drives the page's hooks (`luminaCardGone`, `luminaAccess`, `luminaCommand`) |
| `Lumina/Sets/Core/` | The native bridge: `SetsIngest` (reads opened folders: listing, 256 KB heads, byte-range previews, prefetch, stops when the card goes), `SetsFileOps` (`writeSidecar`: v5's Save, one `.xmp` into the shoot folder with `.lumina-bak`, atomic, read back, refused on a card; SHA-256 copies), `SetsExport` (+ crash journal; v3's RAW/JPEG export, unused by v5), `SetsEditLook` (v3's Edit look, unused by v5), `SetsCardWatcher`, `SetsShootStore` (per-shoot sessions), `SetsSchemeHandler` (`lumina://`, no network) |
| `design/handoff/vendor/` | React / Babel pinned to the SRI hashes in `support.js` (see `VENDOR.md`) |

Trust rules, from the ROADMAP; the tests enforce them:
- never write to the card or change originals (v5 writes only `.xmp` sidecars, into the shoot folder);
- copy, never move, and verify every copy;
- keep a `.lumina-bak` before replacing any file;
- nothing leaves the Mac, and the page has no network access.

## Checks

```bash
# Design logic fixtures
(cd design/handoff/lumina-cull && node lumina-core-v4.test.mjs)

# Linux too: the real page in headless Chromium with plumbing.js and a Node stand-in for SetsBridge
node Tests/web/plumbing-harness.mjs          # contract, native read, sessions, sidecars, card, access
node Tests/web/parity.mjs                    # screens-* in prototype vs app parity mode, every snapshot diffed
# WebKit sandbox (WebKitGTK + JavaScriptCore, real script-message handler): contract, selftest, app flow, screens
xvfb-run -a -s "-screen 0 2000x1300x24" /usr/bin/python3.12 Tests/web/webkit.py   # apt: gir1.2-webkit2-4.1 python3-gi python3-gi-cairo xvfb
# Fast scrolling over 400 synthetic ARWs at a Retina pixel ratio (numbers reported, not gated)
GDK_SCALE=2 xvfb-run -a -s "-screen 0 5200x3000x24" /usr/bin/python3.12 Tests/web/webkit.py scroll
# The Foundation-only Swift (SetsFileOps, SetsShootStore, SetsExport, SetsIngest) + its tests, Swift 6.1 in Docker
bash Tests/linux-swift/run.sh

# Build + logic tests (SetsFileOpsTests, SetsSidecarTests, SetsPageBytesTests, …)
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD \
  -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests test

# Probe: drives the real page + bridge in WKWebView (Tools/LuminaProbe). Evidence → ~/LuminaEvidence/probe
bash Scripts/probe.sh reference     # every screen, prototype and app, byte-compared to Tests/probe/reference/manifest.json
bash Scripts/probe.sh contract      # plumbing.js still fits the page
bash Scripts/probe.sh smoke         # page runs, ?selftest passes, app reads / keeps / saves sidecars / reopens
bash Scripts/probe.sh selftest      # the design's own ?selftest (25 checks + timing)
bash Scripts/probe.sh fuzz          # seeded key + mouse storms
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh scroll  # fast Cull scrolling: frames, blank tiles, thumbnail upscale, memory
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh app     # contract + app-smoke (sidecars, .lumina-bak, sessions)
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh fault   # native writes: kill -9 mid-write, disk full mid-copy
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh edge    # camera-data cases (design gaps show as FAIL)
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh ingest  # the same cases through the native reader
LUMINA_CARD_DIR=/Volumes/…/DCIM/101MSDCF bash Scripts/probe.sh card         # golden card + page vs native read
bash Scripts/probe.sh v3            # scenarios still written for the v3 page: expected to fail until rewritten
```

Day-to-day app: `bash Scripts/install_app.sh` builds this checkout (Release) into `/Applications/Lumina.app`,
the copy the Dock and Spotlight open, and removes older builds from Launch Services.

Build fixtures once with `LUMINA_CARD_DIR=… bash Tests/probe/forge_fixtures.sh`. It only reads the card.
`Tests/probe/EDGE-CASES.md` maps the beta checklist to scenarios and their status.

CI (`.github/workflows/lumina.yml`) runs the fixtures, the byte-for-byte page check, the wording
audit, the Chromium plumbing harness, the WebKitGTK sandbox, the Linux Swift tests, the build + logic tests, and a probe build.

## Rules that bite

- **Don't edit `Lumina/Sets/Web/*.html|support.js|lumina-core-v4.js|lumina-v4-data.js|lumina-selftest.js|vendor`.** Change the design, then sync. `SetsPageBytesTests` and CI fail on drift.
- **`plumbing.js` supplies behaviour and data, never UI.** If the page can't show something, that's a design ask.
- **The native read repeats the page's `onDir` and `readOne`.** `probe.sh contract` fails (`__lumina.drift()`) when a sync changes either: review the read in `plumbing.js`, then update `ONDIR` (`node Tests/web/plumbing-harness.mjs --hash` prints it). Parity with the page's own read is checked with `card-clock.json` in both modes.
- **Pixel parity is 0 px.** App-mode screens (`screens-*-app`, plumbing's test-only parity mode: the design's sample shoot and card) must match the prototype reference byte for byte. Both twins run with `"storageWrites": false`, because the page's "saved" label is browser-only. CSS tricks that change anti-aliasing are out; content-visibility was tried and rejected.
- **The probe never touches a real card.** Fault tests use disk images, and the probe's card watcher only accepts its own images.
- **ExFAT volume labels are at most 11 characters.** `hdiutil` reports a longer one as "Operation not permitted".
- **Probe runs need an awake display.** The probe holds the display awake itself. If runs stall for minutes, macOS is throttling the page process.
- **Personal data stays out of the repo:** golden data, fixtures and evidence live in `~/LuminaEvidence`.
- **macOS only** (Xcode 16.4+, Apple silicon, macOS 14+). Linux agents can run the node fixtures, `design_audit.py`, `Tests/web` (Chromium and the WebKitGTK sandbox: plumbing.js against the real page, not Cocoa or WKWebView) and `Tests/linux-swift` (the Foundation-only Swift; on Linux `FileManager.replaceItemAt` is broken, so the sandbox copy uses `rename(2)`).

## History

Everything before the Sets rebuild (the P0/Elastic SwiftUI UI, its harness and lints, the Swift
`CullCore` port, AutoDevelop) was removed in the Phase 6 cleanup and lives in git history before it.
Auto for the beta is `lumina-core`'s own; the Swift AutoDevelop is parked, to be revisited after beta.
