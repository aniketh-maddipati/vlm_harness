# v5 plumbing: cloud handoff

Branch `claude/lumina-gallery-redesign-128c5e-262yty`, draft PR #141 ("v5: plumbing, native bridge and
probe scenarios"). Made on Linux (2026-09-29). No page file, `support.js`, `lumina-core-v4.js`,
`lumina-v4-data.js`, `lumina-selftest.js` or vendor file was touched. Nothing is merged.

## Run these on the Mac (about 20 minutes)

```bash
git fetch origin && git checkout claude/lumina-gallery-redesign-128c5e-262yty

# 1. Build + logic tests (includes the new SetsSidecarTests)
xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug -derivedDataPath DD \
  -destination 'platform=macOS,arch=arm64' -only-testing:LuminaLogicTests test

# 2. Plumbing fits the page in WKWebView (ONDIR was measured in Chromium, see below)
bash Scripts/probe.sh contract

# 3. Smoke: page runs, ?selftest passes, app reads / keeps / saves sidecars / reopens
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh smoke

# 4. Screens: record the v5 reference, then compare (prototype and app twins, 0 px)
bash Scripts/probe.sh reference --record
bash Scripts/probe.sh reference

# 5. Storms and fixtures
bash Scripts/probe.sh fuzz
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh app
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh fault
LUMINA_FIXTURE_ROOT=~/LuminaEvidence/fixtures bash Scripts/probe.sh edge

# 6. By hand, once (SAFETY.md asks each item to be tried by hand)
open DD/Build/Products/Debug/Lumina.app
```

What to look for:
- **contract:** ONDIR was measured under JavaScriptCore (WebKitGTK) and matches, so `drift` should pass. If it prints `onDir/readOne changed (fnv N)`, set `ONDIR = N` in `plumbing.js`. Nothing else needs to change.
- **reference:** `--record` replaces the v3 manifest, so look over the new PNGs in `~/LuminaEvidence/probe/<stamp>/screens-1440` before trusting them. The row header's "seen" fade can differ by a few hundred px between runs. If `03-cull-row-seen` or `08-cull-skip` flake, raise their `settleMs`.
- **By hand:**
  - Menu bar: every item works. ⌘W closes the shoot, not the window.
  - Quit with unsaved keepers asks first.
  - Save writes `DSC….xmp` next to each keeper. Save again leaves `.xmp.lumina-bak` next to replaced sidecars.
  - ⌘R opens Finder on the shoot folder.
  - Settings persist across launches.
  - Pull the card mid-cull: the banner shows. Put it back: the banner goes away.

## Work per commit

1. **`v5 milestone 1: plumbing.js fits v5, sidecars saved into the shoot folder`**
   - **`plumbing.js`, native read:** repeats v5's `onDir` + `readOne` step for step, with `LuminaCore.parseHead` / `measure` (moved out of the page in v5).
     - Carries every new photo field (`model`, `fnum`, `w`/`h`, `lens`, `serial`, `program`, `wb`, `flash`, `seq*`, `releaseMode2`, `dhash`, `nopv`).
     - Rows appear as the read prefix grows (48 photos or 400 ms, as the page does).
     - `intake()` is fed the native listing, non-ARW names included. The page's own `openNote` wording is used when a folder has no ARW. Import notes and `realInfo` are the page's.
   - **`plumbing.js`, contract:** `missing()` checks page members, `LuminaCore` / `LuminaV4` globals, and the window hooks the page sets on mount. `drift()` hashes `onDir + readOne`.
   - **`plumbing.js`, sessions:** marks / flags / stars / cuts by path; seen / tsz / regions / lastEx; the cursor.
     - Saved every 2 s and on each view change. Decisions for files not read this time are kept.
     - A summary (`n`, `dec`, `kp`, `last`) feeds the Open screen's recent cards.
   - **`plumbing.js`, `writeInto('xmp')`:** calls native `writeSidecars`, and returns per-file errors `{name, reason}`.
   - **`plumbing.js`, `window.lumina`:** `readingCard`, `willPromptAccess: false`, `reveal`, `setPrefs` (with `lumina-prefs` seeded from `__luminaConfig.prefs` before the page starts), `openSettings`, `checkAccess`, `reopen`.
   - **`plumbing.js`, `__lumina`:** `cardGone` / `cardBack`, `unsaved`, `closeShoot`, `command`, `inspect`.
   - **Swift, `SetsFileOps.writeSidecar`:**
     - Accepts `.xmp` only, inside the folder: no `..`, no absolute path, no link out, not a link itself.
     - Refused on a card. Keeps `.lumina-bak` first (never replaced later).
     - Writes atomically (existing `atomicWrite`: temp, fsync, rename), then reads back after the rename.
     - Reasons: locked / read-only / disk full / missing / failed.
   - **Swift, `SetsIngest.list`:** adds `others` (names only) and `onCard`. New `accessDenied()`.
   - **Swift, `SetsBridge`:**
     - New ops: `writeSidecars`, `reveal`, `setPrefs` (UserDefaults `lumina-prefs`), `openSettings`, `checkAccess`, `reopenDenied`, `reopenCurrent`.
     - `openFolder` returns `{denied}` when the listing is refused.
     - The card JSON gains `path`. `cardGone(stopped, ours)` / `cardBack()`. Recents come in v5's shape.
   - **Swift, `SetsShootStore`:** `seen` / `keepers` / `last` per shoot.
   - **Swift, window:** minimum 1024 × 700 (ADDENDUM-1 §4). The `sample` config flag is removed.
   - **Checks:**
     - `Tests/web/plumbing-harness.mjs` (Chromium, runs in CI).
     - `SetsSidecarTests`.
     - `app-plumbing-contract`, `smoke`, `keys-open-return` rewritten for v5; new `app-smoke`; `probe.sh smoke`.
2. **`v5 milestone 2a: menu bar, Quit prompt, screens and selftest scenarios`**
   - **Menu bar from MENUS.md**, through `window.luminaCommand`.
     - Open Recent, Close Shoot, and Remove Working Files… (asks first).
     - Zoom 100% goes through `luminaGesture('hold')`.
     - About, Help.
   - **Quit** asks about unsaved keepers.
   - **Contact links** from the page open in the browser or mail app on a click.
   - **Save's working-files size** is given when Save opens.
   - **Parity mode** shows the design's sample recents and card state.
   - **Scenarios:**
     - `screens-1440` / `1920` (+ `-app`) rewritten for v5 screens, with `"storageWrites": false`.
     - `selftest.json`, using the new `query` scenario key.
   - **`Tests/web/parity.mjs`.**
3. **`v5 milestone 2b: probe suites for v5, empty states from the design, docs`**
   - **plumbing:** the zero-photo guard is removed, because v5 has its own empty Cull and Save.
   - **Suites reorganised:** `smoke`, `selftest`, and `v3` for the not-yet-rewritten scenarios.
   - **Fuzzer:** v5's key set.
   - **Docs:** DESIGN-ASKS, EDGE-CASES and AGENTS updated.
4. **`Fix: pass prefs to the page as Any`** fixes a type error I spotted by eye (no Swift compiler on Linux).

## Checked on Linux

- `node lumina-core-v4.test.mjs`: no FAIL.
- `node Tests/web/plumbing-harness.mjs`: all ok (54 checks). It runs the real v5 page, `plumbing.js` and a Node stand-in for `SetsBridge`, reading 12 synthetic ARWs (TIFF + EXIF + embedded JPEG, one turned 90°). Checked areas:
  - the contract, and the probe contract scenario's own expressions
  - prefs, and the no-ARW note
  - the read: fields, notes, portrait, previews by URL
  - P keeps, autosave by path, recents summary, the unsaved count
  - ⌘3, ⌘⏎: 2 sidecars written into the folder, 3★, `.lumina-bak`, `where` = the folder
  - ⌘R
  - close + reopen restores the marks
  - card gone / back, `readingCard` → `onCard()`
  - access denied → allowed
  - no page errors
- `node Tests/web/parity.mjs`: every snapshot and state dump in `screens-1440` and `screens-1920` matches between prototype and app parity mode.
- The page's `?selftest` in Chromium: 25 of 25. → frame median 15.6 ms, large view 16.3 ms.

### Sandbox (2026-09-30): WebKit and Swift on Linux

- **`Tests/web/webkit.py` on WebKitGTK 2.52** (the WebKit engine and JavaScriptCore; no Cocoa). `plumbing.js` is injected at document start, and a real `lumina` script-message handler with replies answers, the channel WKWebView uses. `Tests/web/webkit-server.mjs` plays SetsBridge. Under Xvfb:
  - **contract:** every expression in `app-plumbing-contract.json` passes. **ONDIR under JavaScriptCore is 3373286225**, the value in `plumbing.js`.
  - **selftest:** all behaviour checks pass. Timing under Xvfb without a GPU: → median 49 ms, large view 58 ms (reported only; ADDENDUM-1 §6 measures timing in the app).
  - **flow:** 29 checks pass:
    - the no-ARW note, and a read of 12 synthetic ARWs (notes, portrait, measures from the WebKit canvas)
    - P, autosave within 2 s, the unsaved count
    - ⌘3 ⌘⏎ → 2 sidecars in the folder, 3★; working-files size on Save; ⌘R
    - close, reopen with 2 keepers; save again → `.lumina-bak`
    - card gone / back, `readingCard`, access denied → allowed, menu Zoom
    - no page errors
  - **screens:** `screens-1440` and `screens-1920`, prototype vs app parity mode: all 34 snapshots and state dumps are identical. The two "seen" steps needed `settleMs` 1800: both modes are still fading at 1.0 s and settled by 1.6 s.
- **`Tests/linux-swift/run.sh`, Swift 6.1 (Docker `swift:6.1-noble`).**
  - **Setup:** the app's `SetsFileOps`, `SetsShootStore`, `SetsExport` and `SetsIngest` compile unchanged against small stand-ins for CryptoKit (a real SHA-256), CoreGraphics / ImageIO / UTType (decode stubs) and `SetsEditLook`.
  - **Result:** 21 of 21 tests pass: `SetsSidecarTests` (6), `SetsTrustTests` (9), and `SetsFileOpsTests` (6, without its 3 Core Image tests).
  - **Linux only:** swift-corelibs-foundation's `FileManager.replaceItemAt` fails on Linux *and deletes the original file*, so the sandbox copy uses `rename(2)` instead. Darwin's is correct; the app code is unchanged. `testLockedSidecarIsLocked` is skipped: Linux has no user-immutable flag.
- **Every Swift file parses** under Swift 6.1 (`swiftc -parse`): the app, the tests and the probe.
- **CI:** two new jobs, `webkit` (WebKitGTK sandbox) and `swift-linux`.

## Not verified (needs the Mac)

- **Swift that only builds on the Mac:** everything that imports AppKit / WebKit / Core Image has been parsed but not type-checked: `LuminaApp.swift` (the `Commands`, the Quit delegate), `SetsRootView`, `SetsBridge` (incl. `writeSidecars`' `Task.detached`), `SetsSchemeHandler`, `SetsCardWatcher`, the probe. `SetsIngestTests` and `SetsPageBytesTests` need ImageIO and the app bundle.
- **WKWebView specifics:** Cocoa key events (the sandbox dispatches DOM key events), the `lumina://` scheme handler, and 0 px parity at the probe's 2× scale with macOS fonts (the sandbox compares at 1× with Linux fonts).
- **Scenarios:** the fuzzer with the new modifiers, and `app-smoke` on the real `two-bodies` fixture. It assumes Save writes exactly 2 `.xmp`; if the fixture already holds sidecars, adjust the counts.
- **Real-disk behaviour:** a TCC denial, a real card eject and remount, disk full or a read-only volume during Save.
- **Real macOS menu behaviour:** ⌘W closing the shoot rather than the window, and the plain-key menu items.

## Decisions the spec didn't cover

- **Recent cards, no card:** the plumbing sends v5's shape (`d` = first capture day as `YYYY-MM-DD`, else the folder name; `n`, `dec`, `kp`, `last`, `where`). `lumina.card` has no `model` / `range` yet: the card panel shows the second line empty until the Mac reads one ARW head on mount. That's a follow-up.
- **Autosave rules:**
  - Autosave doesn't run while a read is in progress.
  - Decisions for files that weren't read this time (card pulled mid-read, file moved) are kept in the session rather than dropped.
  - The cursor is saved by path.
- **Quit rule:** "unsaved keepers" = the kept list differs from the one at the last Save with no errors. It's remembered in the session (`saved`), so a reopened shoot that was saved doesn't ask. DESIGN-ASKS #3 asks the page to own this.
- **Card pull and remount:** `luminaCardGone(true)` fires when the pulled volume holds the open shoot or a read in progress. On remount, `luminaCardGone(false)`, and the folder is read again only if the pull cut the read short (`reopenCurrent`); otherwise the previews come back without a re-read.
- **Access:**
  - `willPromptAccess` is `false`: the Mac's folder picker grants access, so the page's pre-prompt sheet never shows in the app.
  - The access banner's name is the volume name, or the folder name on the startup disk.
- **Sidecar writes:** the temp file is Lumina's existing hidden `.<name>.lumina-tmp-XXXX` in the same folder, not `name.xmp.tmp` as SAFETY.md words it. Same guarantees (same folder, fsync, rename, verify), and the existing tests and the kill -9 recovery already know the name.
- **Menu bar:**
  - Plain-key items show the key in the title ("Keep  P") and have no key equivalent. A menu equivalent would take the key from the page and break hold-to-show and key repeat (DESIGN-ASKS #5).
  - About shows "© 2026 Aniketh Maddipati" and points to Help ▸ Lumina FAQ, because a live link would need a registered URL scheme.
  - Edit ▸ Cut/Copy/Paste are gone: ⌘A is Keep Row, and the page has no text fields.
- **Save screen:** "Remove Lumina's working files (N MB)" gets its size when Save opens (the page asks only after a save in app mode; DESIGN-ASKS #1).
- **Links:** the page's contact links open outside the app, on a click only. The page's own network block is unchanged.
- **Parity twins:** both run with `"storageWrites": false` (the page's localStorage writes throw, as in the app). The browser-only "saved" label would otherwise make every app screen differ. The Save state dump was dropped from the twins: the app sets `ex.wf` there on purpose, and its snapshot still matches.
- **Probe suites:** scenarios still written for v3 are in `probe.sh v3` instead of the default suites. Their list is in `Scripts/probe.sh` and `Tests/probe/EDGE-CASES.md`. They need rewriting for v5 (Save into the folder, ⌘ steps, no Edit / RAW / JPEG export). `look-parity` no longer applies.
- **Debug read:** the page's debug-only JPEG read (`?debug`, a folder with no ARW) isn't mirrored by the native read.

## Next

1. The Mac run above. Fix whatever the compiler and `contract` say first.
2. Rewrite the v3 scenarios for v5: `fault-card-pull-read`, `fault-disk-full` (Save into a full image), `fault-readonly-card` (Save refused), `app-xmp-lightroom` / `app-xmp-both` (merge into the folder), `app-session`, `fuzz-app-card`.
3. `lumina.card.model` / `range` from one ARW head when a card mounts.
4. Send DESIGN-ASKS.md to Claude Design.
