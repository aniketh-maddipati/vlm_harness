# Lumina v0.01: handoff to wire the Mac app and finish testing

Start here, then read **BRIDGE.md** (the contract between the page and native code), then **TEST-PLAN.md**.

## What this is
Lumina is a photo-culling app for Mac. You open a card or folder, pick picks, optionally edit, then save.
- **Inputs:** Sony ARW, plus phone DNG (iPhone ProRAW, Android RAW).
- **Outputs:** .xmp rating sidecars for Lightroom Classic and Capture One. Phone DNG picks are copied into a Picks folder instead.
- **Never:** writes to RAWs or the card, makes network calls, or needs an account.

The two `.dc.html` files are **high-fidelity, working references**: behaviour, copy, layout and motion are final for v0.01. Open them in Chrome. They run in the browser with browser I/O, and on a bundled sample shoot when no folder is open. Your job:
1. Host the page in the native shell (WKWebView). Keep the page as is; only swap its browser I/O for native calls through `window.lumina` (BRIDGE.md).
2. Implement the native side of every bridge call.
3. Run TEST-PLAN.md to green and report.

If you rebuild any part natively instead of hosting the page, match the reference exactly. Read the source whenever a detail isn't written down.

## Order of truth (earlier wins)
1. This README and BRIDGE.md
2. `Lumina Sets v7.dc.html` and `Lumina Edit v21.dc.html` (Edit is embedded inside Sets)
3. ROADMAP.md (beta trust rules 1 to 17 are binding)
4. Older handoff docs in `reference/` (v5 era; the bridge there is partly stale, see BRIDGE.md, "Changed since v5")

## Files
| File | Role |
|---|---|
| Lumina Sets v7.dc.html | The app: Open → Pick → Edit → Save, tour, working files, known issues |
| Lumina Edit v21.dc.html | Edit step (sliders, variations, tone mapper ⇧T), mounted by Sets |
| lumina-core-v4.js | Parsing (ARW/DNG/JPEG Exif), `phoneOf`, grouping, sidecars, zip. Port as is |
| lumina-core-v4.test.mjs + .fixtures.json | `node lumina-core-v4.test.mjs` must print no FAIL |
| lumina-measure.js | Pixel measures for the big view (edge detail, clipping, focus point vs sharpest area) |
| lumina-v4-data.js | Shortcut-sheet text, FAQ, formatters, sample shoot (local images in `uploads/`) |
| lumina-selftest.js | Behaviour and timing tests. Open Sets with `?selftest` |
| support.js | Page runtime. Ship unchanged |
| Phone Handoff Check.dc.html | Go/no-go page for real phone RAW folders |
| Lumina Ingest design.dc.html | Hi-fi reference for Add + Phone photos + error states (1440×900, big targets) |
| screenshots/ | Reference captures of each screen and state for parity |
| uploads/*.jpg | Sample-shoot images, bundled so the sample makes no network calls |
| Handoff - Tone mapper.md | Native port of the Edit tone mapper (AgX-style), with ΔE targets |
| ROADMAP.md | Scope, trust rules, ingest and card-detection plans |
| reference/plumbing.js | v5 bridge shim. Start from it, then update to BRIDGE.md |
| reference/SAFETY.md, TEST-MATRIX.md | v5 safety rules and camera matrix, still valid |

## New in v0.01 (since the v5 handoff)
- **Phone RAW.** DNG is read alongside ARW. A file counts as a phone only from EXIF Make/Model (`LuminaCore.phoneOf`), never from the extension. Phones show as e.g. "iPhone 15 Pro" with a "1× camera" lens. `fl` becomes the 35 mm equivalent, so the shake check and row splits use it. Mixed shoots get a "bodies" note that says to check the camera clock against the phone's.
- **DNG save.** DNG picks are copied to `<dest>/Picks/`, not rated, because Lightroom ignores sidecars for DNG. ARW picks still get .xmp files.
- **Tour.** Five steps on first launch (`lumina-v4-toured`). It can be reopened from the ? sheet.
- **Working files.** Squares in the top bar on every step, also floating in Edit. In the app it is one segment, sized and cleared through `workingFiles` / `removeWorkingFiles`.
- **Beta 0.01 chip.** Shows known issues (`Component.ISSUES`) and a bug-report link.
- **Open screen.** "Go straight to" Card / Pictures / Downloads / Desktop, drag a folder from Finder, and an iPhone export hint.
- **Show in Finder.** In the browser it copies the path and shows the ⌘⇧G steps. **In the app it must call `lumina.reveal(path)`.**
- **Measured column.** Focus point vs sharpest area, and highlight clipping split into one/two channels (likely recoverable) or all channels.
- **Responsive.**
  - Tile size picks itself from the window width until the user sets one.
  - The big view drops its side columns under 980 px and widens them from 1700 px.
  - Open and Save widen to 1360 px.

## Also new since the first handoff draft
- **Shoot names:** always visible in the top bar. A new shoot focuses the name field with a suggestion (folder name, or the date if the folder is generic). Names show on Recent and in Save.
- **Seen-before memory:** decisions are remembered per photo (serial + time + size + name). Re-importing brings them back, with a note naming the earlier shoot.
- **Sources:** a shoot is a set of source references. Add from anywhere with ⌘O in a shoot, the + on the name, holding ⇧, or by dropping. Duplicates are skipped. A second camera with a clock offset gets a merge preview. Sources can be filtered with "show only".
- **Phone photos page (v0.0.1):** manual AirDrop, Photos export or Android+OpenMTP → drop, Choose files or Watch Downloads. Labelled RAW vs HEIC/JPG. Ends in New shoot → Pick, or Add to the open shoot.
- **Picks tray:** drag tiles, or files from Finder, onto the bottom Picks bar to pick them.
- **Back to Save:** clicking a pick on Save opens the big view. The pill or a double-click returns to Save.
- **Copy:** "keepers" is now "picks" everywhere. The DNG copy folder is `Picks/`.
- **Phone Handoff Check.dc.html:** drop real phone folders to see detection, preview, orientation and twins. "Copy report" gives a fixture.

## Latest changes (final pass)
- **Open screen:** "Go straight to" buttons removed. Use ⌘O, drag and drop, or Add from phone. A disclaimer reads: RAW only (ARW, DNG), JPEG and HEIC not supported yet.
- **Phone photos page:**
  - iPhone | Android switch, remembered.
  - Steps show on first use, then collapse to one line. The "All Photos Data" tip sits on top.
  - Clickable drop zone sits beside the steps, with Watch Downloads for iPhone in Chrome/Comet.
  - One main button: "Add N to <shoot>", or "Start shoot with N".
  - 60 px targets.
- **Working files:** "Keep up to" 200 MB / 1 GB / 5 GB / No limit, with a usage bar. When the limit is reached, the oldest previews and earlier cards go first. This card's picks are always kept.
- **Contact:** "Report a bug" emails anikethcov@gmail.com (prefilled subject). LinkedIn and X sit alongside it in the Beta panel and the ? sheet.
- **FAQ:** rewritten for v0.0.1 (lumina-v4-data.js).

## To do (known, not blocking v0.0.1)
1. **Auto on DNG is poor (Edit).** Auto exposure / white balance is computed from the embedded preview, which for phone ProRAW is already tone-mapped and often brightened, so Auto over-corrects (too dark, cool cast).
   - **Fix:** for DNG, compute Auto from linear data. Use the native Core Image RAW decode (`CIRAWFilter`, `baselineExposure` and `neutralChromaticity`) and read DNG `BaselineExposure` (tag 0xC62A) and `AsShotNeutral` (0xC628) in `parseHead`.
   - Until native decode exists, Auto on phone DNG should start from `BaselineExposure` and `AsShotNeutral` instead of the preview histogram, and clamp to ±1 EV.
   - **Test:** 10 ProRAW and 10 Pixel DNGs. Auto result within ±0.3 EV and ±300 K of Lightroom Auto.
2. Cable import (iPhone, ImageCaptureCore), Photos library import (PhotoKit), Android auto-detect: v0.1 (BRIDGE.md).
3. Native RAW decode for Edit and 100% zoom: also fixes soft big view on phone previews.
4. Firefox/Safari: read-only fallbacks (no Watch, Save downloads a zip). Beta states "Chrome/Comet or the Mac app".

## Definition of done
- Core tests: no FAIL. `?selftest` in the app: every check passes, key-to-frame median < 50 ms, big view opens < 100 ms.
- Every TEST-PLAN.md row ticked on real hardware, with notes.
- Trust rules 1 to 12 in ROADMAP.md each checked by hand once.
- Zero network requests during a full session (check with a proxy or Little Snitch).
- Report: files changed, test output, perf numbers, and every decision the spec didn't cover.

## Guardrails. Stop and ask instead of:
- writing to RAW/DNG files or anything on a mounted card
- adding keys, settings, dialogs, colours or copy not in the reference
- any network call
- spending more than 15 minutes on one failing check (report what you saw and tried)
