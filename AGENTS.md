# AGENTS.md

Guidance for AI agents and developers working on **Lumina**, a native macOS photo culling app for
Sony ARW shooters.

## The rule

**The design is the product.** Lumina's UI is the Claude Design page in `design/handoff/lumina-cull/`
(`Lumina Sets v3.dc.html` + `support.js` + `lumina-core.js`). The app ships those files
**byte for byte** inside a native window. Nobody edits the UI in this repo.

- Something visible is wrong or missing (layout, copy, keys, empty states)? It goes into
  `design/handoff/DESIGN-ASKS.md` as a ready-to-paste Claude Design prompt. It never gets patched here.
- A new handoff arrives as a zip. Sync it with `bash Scripts/sets_sync_design.sh "<zip>"`. That runs the
  fixtures, audits the wording and demo layer, installs the files, checks the plumbing contract,
  compares every screen pixel for pixel, and runs the robustness suites. It never commits. Add
  `--record` once the new look is approved.
- Authority order: `design/handoff/lumina-cull` (the prototype wins; `ADDENDUM-remove.md` and
  `ANSWERS-*.md` refine it) → `Lumina/Sets` (plumbing) → tests.

## What the app is

| Path | What it does |
|---|---|
| `Lumina/LuminaApp.swift` | One window, File ▸ Open (⌘O), Edit ▸ Undo (⌘Z) |
| `Lumina/Sets/SetsRootView.swift` | The WKWebView, the native folder pickers, downloads |
| `Lumina/Sets/Web/` | The design's files, copied unchanged by `Scripts/sets_sync_ui.sh`, plus `plumbing.js` |
| `Lumina/Sets/Web/plumbing.js` | **The only app-side difference.** It swaps the page's browser I/O (`openFolder`, `writeInto`, `renderJpg`, `impStart`, …) for native calls and provides `window.lumina` (the data contract) |
| `Lumina/Sets/Core/` | The native bridge: `SetsFileOps` (`.lumina-bak`, atomic writes, SHA-256 copies, destination refusal), `SetsExport` (+ crash journal), `SetsEditLook` (the Edit look's CSS matrices in Core Image, RAW → JPEG), `SetsCardWatcher`, `SetsShootStore` (per-shoot sessions), `SetsSchemeHandler` (`lumina://`, no network) |
| `design/handoff/vendor/` | React / Babel pinned to the SRI hashes in `support.js` (see `VENDOR.md`) |

Trust rules, from the ROADMAP; the tests enforce them:
- never write to the card or change originals;
- copy, never move, and verify every copy;
- keep a `.lumina-bak` before replacing any file;
- nothing leaves the Mac, and the page has no network access.

## Checks

```bash
# Design logic fixtures
(cd design/handoff/lumina-cull && node lumina-core.test.mjs)

# Build + logic tests (SetsFileOpsTests, SetsPageBytesTests)
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD \
  -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests test

# Probe: drives the real page + bridge in WKWebView (Tools/LuminaProbe). Evidence → ~/LuminaEvidence/probe
bash Scripts/probe.sh reference     # every screen, byte-compared to Tests/probe/reference/manifest.json
bash Scripts/probe.sh contract      # plumbing.js still fits the page
bash Scripts/probe.sh fuzz          # seeded key + mouse storms
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh app     # export, sessions, ΔE look parity
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh fault   # disk images: card pulled, disk full, locked
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh edge    # camera-data cases (design gaps show as FAIL)
LUMINA_CARD_DIR=/Volumes/…/DCIM/101MSDCF bash Scripts/probe.sh card         # 721-photo stress + scroll pacing
```

Build fixtures once with `LUMINA_CARD_DIR=… bash Tests/probe/forge_fixtures.sh`. It only reads the card.
`Tests/probe/EDGE-CASES.md` maps the beta checklist to scenarios and their status.

CI (`.github/workflows/lumina.yml`) runs the fixtures, the byte-for-byte page check, the wording
audit, the build + logic tests, and a probe build.

## Rules that bite

- **Don't edit `Lumina/Sets/Web/*.html|support.js|lumina-core.js|vendor`.** Change the design, then sync. `SetsPageBytesTests` and CI fail on drift.
- **`plumbing.js` supplies behaviour and data, never UI.** If the page can't show something, that's a design ask.
- **Pixel parity is 0 px.** App-mode screens (`screens-*-app`) must match the prototype reference byte for byte. CSS tricks that change anti-aliasing are out; content-visibility was tried and rejected.
- **The probe never touches a real card.** Fault tests use disk images, and the probe's card watcher only accepts its own images.
- **ExFAT volume labels are at most 11 characters.** `hdiutil` reports a longer one as "Operation not permitted".
- **Probe runs need an awake display.** The probe holds the display awake itself. If runs stall for minutes, macOS is throttling the page process.
- **Personal data stays out of the repo:** golden data, fixtures and evidence live in `~/LuminaEvidence`.
- **macOS only** (Xcode 16.4+, Apple silicon, macOS 14+). Linux agents can run the node fixtures and `design_audit.py`, nothing else.

## History

Everything before the Sets rebuild (the P0/Elastic SwiftUI UI, its harness and lints, the Swift
`CullCore` port, AutoDevelop) was removed in the Phase 6 cleanup and lives in git history before it.
Auto for the beta is `lumina-core`'s own; the Swift AutoDevelop is parked, to be revisited after beta.
