# Handoff: Lumina — Sony cull → edit → export (macOS)

> **Build path: `BUILD-exact.md`.** The HTML is the UI, shipped inside a native shell. Ignore the "rebuild in SwiftUI" steps below. **Then read `ADDENDUM-remove.md`.** It lists what not to port and the final wording; it overrides this README.

## Overview
Lumina is a fast culling app for Sony α shooters. Open a card or folder of ARWs, cull by time rows and bursts with the keyboard, optionally touch up, then hand off to Lightroom / Capture One (XMP sidecars) or export RAW + JPEG into a shoot folder. It never writes to the card or changes originals.

## About the design files
`Lumina Sets v3.dc.html` is a **working HTML prototype** — the reference for look, copy, keys and behavior. Do not ship the HTML. Rebuild it in the target app (recommended: **SwiftUI + AppKit, Apple silicon, macOS 14+**; if the repo already has a stack, use it).

`lumina-core.js` is different: it is the **real logic** the prototype runs on (ARW parsing, grouping, flags, XMP merge, export layout). Port it function-by-function. `lumina-core.test.mjs` + `lumina-core.fixtures.json` are the acceptance tests — the port must produce identical output.

Open the prototype: serve this folder (`npx serve .`) and open `Lumina Sets v3.dc.html` in Chrome. ⌘O opens a real folder of ARWs.

## Fidelity
**High-fidelity.** Colors, type, spacing, copy and keyboard behavior are final for the beta. Read exact values from inline styles in the prototype.

## How to build it with Claude Code
Work in this order. Each step is one Claude Code session; give it this README, `ROADMAP.md`, and the files named.

1. **Core port** — port `lumina-core.js` to Swift (`LuminaCore` package). Write an XCTest that loads `lumina-core.fixtures.json` and asserts the same outputs. Done when all pass.
2. **Open** — folder picker + security-scoped bookmarks; read ARW headers + embedded previews (4 at a time); card detection (see ROADMAP "v1: card detection"). Reference: Open screen in the prototype.
3. **Cull** — rows / groups grid, focus model, every key in the table below. Reference: `isCull` section of the prototype + `handleKey`.
4. **Large view + 100%** — Space large, G hold 100% (decode ARW via Core Image `CIRAWFilter` for 100%; embedded preview otherwise).
5. **Edit** — loupe + strip, scope = photo → group → row, sliders, Auto, P finals.
6. **Export** — XMP merge/fresh, RAW + JPEG shoot folder, `.lumina-bak`, "last export" line. JPEG renders from RAW (`CIRAWFilter`), not the preview.
7. **Trust checklist** — walk ROADMAP "Reddit beta — trust requirements" 1–17 and add a test or a manual check for each.

Rule for every session: if the prototype and this README disagree, the prototype wins; if the prototype is silent, ask.

## Proving the port is exact
Three layers, cheapest first. Don't start the next build step until all three pass.
1. **Unit fixtures** — `lumina-core.fixtures.json` (burst, bracket, soft/blown/shake, XMP merge keeping Lightroom edits, export layout, CRC). `node lumina-core.test.mjs` checks the JS; the Swift port loads the same JSON in XCTest.
2. **Golden data from a real card** — open a folder in the prototype, click **save test data** (Open footer). `lumina-golden.json` holds, per ARW, the parsed header (capture time, exposure, focal length, EV, ISO, orientation, preview offset/length), measured luminance / focus / clip, and the resulting rows, groups, flags and picks. The port runs on the same folder: header fields and grouping must match **exactly**; luminance / focus / clip within 1% (Chrome and ImageIO decode JPEG slightly differently), and picks must still match.
3. **Round-trip** — export .xmp from the port and the prototype for the same folder, diff byte-for-byte, then import both into Lightroom and compare stars, labels and edits.

If exactness matters more than a pure Swift port: run `lumina-core.js` unchanged inside the app with **JavaScriptCore** (built into macOS) for grouping, flags and XMP. Only `measure` and `zip` need native versions. Nothing can drift.

## What the prototype environment does for you (the app must replace)
| In the prototype | Provided by | In the app |
|---|---|---|
| Rendering, templates, state | `support.js` (React-based runtime) | SwiftUI + an observable store |
| Folder access | Chrome folder input / File System Access API | NSOpenPanel + security-scoped bookmarks |
| Writing files | `showDirectoryPicker` (own tab only) or zip download | FileManager, atomic writes, checksum verify |
| Preview-frame limits | host page blocks folder writes and takes some keys | none |
| Decoding previews | `createImageBitmap` + canvas | ImageIO (embedded JPEG), `CIRAWFilter` for 100% |
| JPEG export | canvas from the 1616 px preview | render from RAW |
| Card inserted | simulated with C | NSWorkspace mount notifications |
| Session memory | tab memory; sample shoot in localStorage | per-shoot database in Application Support (removable) |
| 721 tiles at once | browser copes, no virtualisation | lazy grid + thumbnail cache |
No web-only visual effects: flat colors, borders, simple transitions.

## Screenshots
`screenshots/01-open.png`, `02-cull.png`, `04-edit.png`, `05-export.png`, `06-export-options.png` (sample shoot). Where a screenshot and the prototype differ, the prototype wins.

## Screens
Top bar: step pills `open → cull → edit → export` (active pill: bg #EFECE6, text #1E1D1B; inactive: text #B8B3AB), counts next to each. Bottom context bar lists the keys for the current view (monospace 12px, #9A958D; key chip bg rgba(239,236,230,0.08)).

**1 Open** — card panel on top when a Sony card is mounted ("Copy & start culling"), recent shoots with search below, footer `⌘O open a folder of ARWs` + live line ("reading 312 / 721 · 78 photos/s"; "read-only · your files are never changed, moved or uploaded").

**2 Cull** — one row per time moment (gap > 90 s), label = start time + light (morning / midday / afternoon / evening). Inside a row: groups. Burst = frames < 1 s apart; bracket = 3+ frames with distinct EV spanning − to +; singles collapse into a run. Tiles 3:2, portrait tiles use contain + dashed 2:3 outline. Keep = full brightness + mark; undecided = full brightness (never dimmed); out = dimmed. Pick = sharpest clean frame in a burst. Flags: soft, blown (> 2% clipped), shake (shutter > 2 / focal).

**3 Edit (optional)** — kept photos only. Big loupe (one at a time) + row strip. Focus level sets the scope of a slider change: photo → group → row (esc widens). P = final (★ badge #FFD27A), ⇧P = finals only.

**Export** — one primary button ("Send 42 keeps to Lightroom ⏎", bg #FFD27A, text #1E1D1B, 18px/800, radius 12, padding 18×20). Pills: Keeps / Finals only. "Options…" reveals: target (Lightroom, Capture One, RAW + JPEG, RAW, JPEG), finals label (Green default, Red, Yellow, Blue, Purple, None), "Include Lumina edits", "Mark outs as rejected", JPEG size (Full, 2048 px). Result block in green (#9ED7B0 on rgba(158,215,176,0.08)) with import steps. "Last export HH:MM · what → where" line. Small "beta · Write an Exposure story" link at the bottom.

**Exposure story (beta)** — reachable only from Export (W). Cover, captions, text blocks. Must never block cull/edit/export.

## Keys
| Where | Key | Action |
|---|---|---|
| All | 1 2 3 / ⌘[ ⌘] | switch step (state kept per step) |
| All | ⌘O | open folder |
| All | Q / ⌘Z | undo (one stack across steps) |
| All | H | hide hints · ? all keys |
| Cull | ↑↓ | rows, then into groups; ← → photos | 
| Cull | → / ⏎ | go in a level · esc out a level |
| Cull | R / X | keep / out whatever is focused (photo, group, row) |
| Cull | Space | large view · G hold 100% · A hold auto preview |
| Cull | V | preview auto on focus · ⇧A apply |
| Cull | W | compare |
| Cull | B / ⇧B | split / merge group |
| Cull | L | flag · drag = box select · ⇧arrows extend |
| Cull | Tab | edit these |
| Edit | , . | pick slider · [ ] nudge · A auto |
| Edit | P / ⇧P | final / finals only |
| Export | ⏎ | send · ↑↓ targets · W story |
Confirm every row against `handleKey` in the prototype before building.

## Navigation & state
Steps are views over one state: `marks{id:'keep'|'out'}`, `final{}`, `auto{}`, `rA{}`/`rO{}` (edits), `cuts{}` (manual split/merge), `sel{}`, `undo[]`, `mem{view:{cur,node,lvl,scrollTop}}`. Leaving a step never commits or discards. If the remembered photo is gone, land on the nearest one in shoot order. Only confirmation dialog: unapplied previews when leaving Cull.

## Export contract
- **Lightroom / Capture One:** one sidecar per RAW, same basename, **keep the existing file's case** (.XMP stays .XMP). Existing sidecar → `mergeXmp` (rating + label only). No sidecar → `freshXmp`; include develop settings only if "Include Lumina edits" (default off when the folder had no sidecars). Keep 3★, final 5★ + label, out −1 if "Mark outs as rejected".
- **RAW / JPEG / RAW + JPEG:** `exportPlan()` gives the layout: `<picked>/<shoot>/RAW/…` and `<shoot>/JPEG/…` for both. Copy, never move; verify checksum after write.
- Any file being replaced is first saved as `<name>.lumina-bak`.
- Record every export (time, what, destination path) and show the latest on Export.
- Lumina's own caches live in one app-support folder per shoot, removable from Export. Never touch RAWs or sidecars during cleanup.

## Design tokens
Colors: bg #1E1D1B · surface #2A2927 · surface-2 #262523 · deep #161514 · line rgba(239,236,230,0.06) · text #EFECE6 · text-2 #B8B3AB · text-3 #9A958D · text-4 #6F6C66 · accent (primary action, finals) #FFD27A · soft accent #FFECCD · ok #9ED7B0 · warn/out #FFB4A2.
Type: UI `-apple-system` (SF Pro); headings `'Iowan Old Style', Georgia, serif` (28px Export title, 18px target names); data/keys `ui-monospace, Menlo` 12–12.5px.
Radius: 2–3 (tiles), 5–8 (chips, buttons), 10–12 (panels), 999 (pills). No shadows.
Motion: rise 160ms ease-out (translateY 6px → 0), pop 120ms (scale .985 → 1), fade, slide 14px. Border/opacity transitions 120–140ms ease-out.

## Assets
None. Sample images in the prototype are placeholders; the app shows the user's own previews.

## Files
- `Lumina Sets v3.dc.html` — prototype (open in Chrome; needs `support.js`, `lumina-core.js` beside it)
- `support.js` — prototype runtime only; not part of the app
- `lumina-core.js` — logic to port
- `lumina-core.fixtures.json`, `lumina-core.test.mjs` — acceptance tests (`node lumina-core.test.mjs`)
- `ROADMAP.md` — locked scope, beta trust rules, card detection, export follow-ups, tester questions
