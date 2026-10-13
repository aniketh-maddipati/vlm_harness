# Handoff: Lumina Skim (video step, MVP)

## Overview
Skim is the video step of Lumina, a Mac app that gets a shoot from the card to a final set. The user opens a card or folder of clips, skims them at three levels (Chapters → Takes → Clip), marks each clip **keep / maybe / cut**, then exports an `.fcpxml` for Final Cut Pro. Same family and contract as Pick (`Lumina Sets v11`):

- touch moves, never decides; holding is temporary; a **tap decides**; **esc** puts it back; **⌘Z** undoes any number of steps
- nothing is deleted; clip files are never changed
- the footer always reads `N decided · M undecided · 0 automatic`
- every chip is a **measurement**, never a verdict. Banned words in UI copy: AI, smart, intelligent, detects, understands, suggests, recommended, magic, auto, learns, confidence, score.
- no onboarding, tips, badges or celebrations. No line explains what the app "thinks".

## About the design files
The files here are **design references built in HTML**: working prototypes of the intended look and behaviour, not production code. Rebuild them in the target codebase (the Lumina Mac app; SwiftUI/AppKit is assumed) using its own patterns. `Lumina Skim v3 standalone.html` opens offline in any browser. `Lumina Skim v3.dc.html` is the editable source; it needs `support.js` and `lumina-video-data-mvp.js` next to it.

## Out of scope for the MVP
These were designed and then cut, and aren't in this pack:
- lenses (by rate, with a chip, undecided only, maybes)
- sweep, and the maybes-only pass
- the Frame level at 100 %
- painting marks, ⌘ box marking, and drag-and-drop to wells or chapter boundaries
- dismissing chips, the histogram
- the photos switch for mixed shoots, the card-pulled banner
- the profile question, the `?` keys sheet
- the extra export keywords and the Trash switch

## Fidelity
**High fidelity.** Colors, type, spacing, copy and interactions are final for the MVP. Recreate them exactly.

## Data contract
The page reads:
```
window.LuminaVideo = {
  shoot: { name, days, bytes, free /* bytes or null */, rate /* common fps */, photos? },
  clips: [{ id, name, path, t /* local ISO 'YYYY-MM-DDTHH:MM:SS' */, dur /* s */, fps, w, h, bytes, codec,
            profile: { gamma /* 'S-Log3'|'S-Log2'|'HLG'|'none'|null */, primaries, source: 'sidecar'|'none' },
            frames: [url × 8],
            facts: { state: 'pending'|'ready'|'unreliable', ev, clip /* % */, crush /* % */, sharp /* 0–1, lowest of 8 */,
                     sharpF: [8], motion: 'shake'|'pan'|null, bump: frameIndex|null },
            dismissed: [], mark: 'keep'|'maybe'|'cut'|null }],
  gaps: [{ after: clipId, s }]   // idle seconds between clip end and next clip start
}
```
It calls `lumina.video.mark(ids, mark)`, `lumina.video.preview(on)` and `lumina.video.handoff({keep, maybe, keyword, cut, trash:false, event})`. The browser stub in `lumina-video-data-mvp.js` records these calls in `window.__luminaVideoCalls`.

The only sample is `window.LuminaVideoSamples.fx5`. Its metadata is shaped after Visual Park's free *SONY FX5 Sample Pack*: 7 S-Log3 clips at 24/60/120p and 2 X-OCN RAW clips that read as `profile unknown`. Sizes are as listed; durations and times are estimated; frames are placeholders. Opening the real pack through Open gives true frames and measurements.

Screenshots of each view are in `screenshots/` (01 Open, 02 Chapters, 03 Takes, 04 Takes while holding M, 05 Clip, 06 Working memory panel, 07 Export).

## Screens / views
The window is a column: **Top bar 52px → (Skim only) Skim bar 44px → banners → main (flex:1) → (Skim only) Key bar 30px → Footer 48px.** Base font: system (SF Pro Text) 12px, `font-variant-numeric: tabular-nums`. Serif display: `'Iowan Old Style', Palatino, Georgia`, weight 400.

### Top bar (all steps)
- 52px tall, padding 0 20px, gap 18px, bg `#262523`, bottom border 1px `rgba(239,236,230,0.08)`.
- "Lumina" wordmark, serif 21px.
- **Steps** segmented control: 3 × 64px, padding 2px, radius 7px, track `rgba(239,236,230,0.06)`. The thumb is `#5B5854`, radius 5px, shadow `0 0.5px 1px rgba(0,0,0,.4)`, and slides with `transform 180ms ease-out`. Labels: **Open · Skim · Export**. Text `#EFECE6` when active, `#9A958D` otherwise, `#5B5854` when disabled (no shoot open). Keys ⌘1 ⌘2 ⌘3.
- Shoot name 13px `#EFECE6`, then the shoot line in `#9A958D`: `9 clips · 1 day · 13.0 GB`. This group is `flex:1 1 0; min-width:110px`; the line truncates with an ellipsis.
- **Memory pill** on the right: 26px tall, radius 6px, bg `rgba(239,236,230,0.06)` (0.14 while open), a 2×2 icon of 4px squares, then the tab's memory size (e.g. `1 MB`). Clicking it opens the Working memory panel.

### Working memory panel (popover)
330px wide, anchored under the pill, right-aligned, top 32px. Padding 14px 16px, radius 12px, bg `#2A2927`, shadow `0 0 0 1px rgba(239,236,230,.12), 0 12px 32px rgba(0,0,0,.5)`.
- Title "Working memory", 13px, weight 600.
- **In this tab** (heading `#FFD27A` 700). Two-column rows, keys 96px `#9A958D`, values `#EFECE6`: `clips open · N · read from the card, not copied`, `frames made · N · X MB`, `measured · N of M`, `videos open · N`, `undo steps · N`.
- **Saved in this browser**: `this shoot · N marks`, `all shoots · N shoots · X KB`.
- The line `No network requests. Frames and measurements are made in this tab, from pixels.`
- Three full-width buttons. Each is 8px 10px padding, radius 9px, bg `rgba(239,236,230,.08)`, with a 600-weight title and a `#9A958D` sub-line:
  1. **Clear frames**: "drops N frames · made again in the background". At 45 % opacity when no frames have been made.
  2. **Forget marks**: "deletes this shoot's saved marks from this browser". The first click turns it into `Forget N marks? Click again` (bg `rgba(255,138,122,.22)`, text `#FF8A7A`). It resets after 3.5 s. The second click deletes the marks, clears undo history and flashes `marks for this shoot forgotten`.
  3. **Clear memory**: "closes the shoot, frees frames and measurements · saved marks stay". Goes back to Open.

### Open
Content is centred, max-width 1000px, padding `clamp(24px,5vh,56px) clamp(16px,4vw,48px) 40px`, gap 24px.
- Title "Open clips", serif 30px, followed by `MP4 · MOV · MXF · Sony sidecars are read when present` in `#9A958D`.
- **Open now** card, shown when a shoot is open: radius 12px, bg `#262523`, inset ring `rgba(239,236,230,.1)`. It holds the name, the line `9 clips · 0 decided · 9 undecided · <source>`, and a `⌘2 Skim` button.
- **Drop zone**: the whole zone is a button, min-height 200px, radius 14px, bg `#232220`, inset ring 1.5px `rgba(239,236,230,.18)`. While a drag is over it: ring `#FFD27A`, bg `rgba(255,210,122,.06)`. Copy: "Drop a card or a folder of clips", a primary button `⌘O Choose Folder…` (bg `#FFD27A`, text `#1E1D1B`, weight 800, radius 10px), and "Clips are read in this tab. Nothing is uploaded or changed."
- Status lines: an error such as `No clips in that folder.` or `N photos and no clips in that folder. Photos are picked in Pick.` in `#FFD27A`; progress `measuring N of M clips` in `#B8B3AB`.
- **Sample card** (FX5 Sample Pack): radius 12px, bg `#262523` (hover `#2E2C29`), serif 19px name, a line of clips · size, a dim line `SONY FX5 · Visual Park, free · 1 day`.

### Skim bar
44px tall, padding 0 20px, bottom border `rgba(239,236,230,.06)`.
- **Levels** segmented control on the left: same style as Steps, 3 × 68px, labels **Chapters · Takes · Clip**.
- **Rec.709 preview** switch on the right. The switch is 28×16, knob 12px; track `#B8B3AB` on, `rgba(239,236,230,.18)` off. Under it, 10.5px `#9A958D`, max-width 220px with ellipsis, one of:
  - `S-Log3 · S-Gamut3.Cine · from the clip's sidecar`
  - `off · showing files as they are`
  - `profile unknown · showing this file as it is`
  - `no clip's profile can be read · showing files as they are` (switch disabled, 45 % opacity)

### Measuring progress
A 2px bar under the top bar, fill `#B8B3AB`, animated `width 400ms linear`.

### Level 1: Chapters
Scrolling area with padding `18px clamp(16px,2.2vw,40px) 40px`.
- **Gap slider**: `chapters ⟷ takes`, a native range input (accent `#B8B3AB`, flex 0 1 360px). Value = number of longest gaps cut. To its right: `3 chapters · gaps over 25 min`, `no gaps cut` or `every gap cut`. Keys −/=. Dragging regroups the whole shoot live. The default cuts every gap of 20 min or more.
- **Chapter tiles**: grid `repeat(auto-fill, minmax(250px,1fr))`, gap 26px 22px. Each tile has 8px padding with a −8px margin and radius 10px:
  - the first frame at 16:9, radius 3px
  - span in serif 19px (`06:48 – 07:31`, plus ` next day` when it crosses midnight), with the size on the right in `#9A958D`
  - `N clips` in `#B8B3AB`, with the reason on the right in `#9A958D` (`gap of 41 min`, or `first clip on the card` for the first chapter)
  - a row of 6px dots, one per clip, coloured by mark (`rgba(239,236,230,.2)` when undecided). Above 48 clips the dots become a 6px stacked bar.
  - the cursor tile gets an outline `1.5px solid rgba(239,236,230,.6)`; selected tiles get bg `rgba(255,210,122,.07)`.

### Level 2: Takes
- **Furled chapter strip** (40px) along the top. Pills are 26px tall, radius 6px, and show span · count · a 28×3 progress bar. The current chapter's pill is `#5B5854`. Clicking a pill jumps to that chapter.
- Takes are listed in sections, one per chapter. Section header: serif 19px span, then `N clips` `#B8B3AB`, size `#9A958D`, and `N of M decided` on the far right. Between sections there's a boundary row: a 1px `rgba(239,236,230,.12)` line with the reason (`gap of 41 min`) centred.
- **Take tile**: grid `repeat(auto-fill, minmax(272px,1fr))`, gap 20px 18px. Each tile has 7px padding and radius 9px:
  - a 4 × 2 filmstrip of 8 frames, each 16:9 with 2px gaps, radius 4px overall
  - a mark edge `inset 0 0 0 2px <mark colour>` and a mark pill at top-right (`#161514` bg, mark colour, 700)
  - a line: name `#EFECE6` · duration · size `#9A958D` · time `#9A958D`
  - up to 3 chips, worst first, min-height 20px
  - the cursor tile gets an outline `1.5px solid rgba(239,236,230,.7)`; a selected (boxed) tile gets bg `rgba(255,210,122,.08)`.
- **Ghost while K/M/X is held**: the target tile shows its edge in the mark colour at 60 % alpha, and the pill text (`keep`/`maybe`/`cut`) at 70 % opacity on `rgba(22,21,20,.82)`.

### Level 3: Clip
Two columns: `minmax(0,1fr) minmax(240px,300px)`, gap 28px.
- A **take strip** (46px) of 56×32 thumbnails sits under the chapter strip. The current one gets an outline `1.5px solid #EFECE6`.
- The large frame is `width: min(100%, calc((100vh - 330px) * 16/9))` at 16:9, radius 4px, with a 3px mark edge. Moving the pointer across it scrubs through the 8 frames. Below it: a scrub bar (2px track, 8 ticks, 2×14px playhead `#EFECE6`), then `00:12.4 of 00:28.0 · frame 3 of 8`.
- Right column: serif 22px name with `16:20 · 28 s`; all chips; then fact lines in two columns (86px keys `#9A958D`): exposure (`−0.8 stops against middle grey, after the preview`), clipped, crushed, sharpness (`0.84 lowest of 8 frames · sharp`), motion, bump, rate, duration, size, format, profile, recorded, path, mark. When facts are pending: `measuring · exposure, clipping, sharpness and motion are still being measured`. When unreliable: `measures · couldn't be read for this clip`.

### Export
Two-column grid, `repeat(auto-fit, minmax(440px,1fr))`, gap 32px, max-width 1200px.
- Left column:
  - title "Export to Final Cut Pro", serif 30px
  - a 4-row table (bg `#2A2927`, 1px gaps, radius 10px): `keep · N clips · size · into the event`, `maybe · … · into the event · keyword "maybe"` (or `left out`), `cut · … · stay on the card`, `undecided · … · stay on the card`
  - fields **Event** (defaults to the shoot name) and **Maybe keyword** (defaults to `maybe`). Inputs are 30px tall, bg `#161514`, inset ring `.14` (focus 1.5px `#FFD27A`), 13px.
  - switch **Include maybes**, on by default
  - the lines "Clip files are never changed." and `Paths point at the card as the camera wrote it.` (for an imported folder: `Paths assume the card is mounted at /Volumes/<folder>.`)
  - buttons `esc Back to Skim` and the primary `⌘⏎ Download .fcpxml · N clips`, which is at 45 % opacity with "Nothing marked keep yet" when there's nothing to export. On success it shows `Saved <event>.fcpxml · N clips` in `#A9D18E`.
- Right column: a "By chapter" list (span · `N keep` in green · `N maybe` in amber), then "The .fcpxml" as a live preview of the first 44 lines (`ui-monospace` 11px/1.5, bg `#161514`, radius 10px, max-height 440px).

### Key bar (Skim)
30px tall, padding 0 20px, `#B8B3AB`. Key caps: min-width 20px, height 20px, padding 0 5px, radius 5px, bg `rgba(239,236,230,.12)`, weight 700, text `#EFECE6`.
- The bar **starts with where you are** in bold `#EFECE6`, then names **what each key does from there**:
  - Chapters: `Chapters · 16:20 – 16:37 | ↓ open 16:20 – 16:37 | ← <prev span> | → <next span> | K M X hold + tap · mark 5 clips | ⌘⏎ export`
  - Takes: `Takes · C0012 | ↑ Chapters · <span> | ↓ open C0012 | ← C0011 | → C0013 | ⇧↓ next chapter · <span> | K M X mark C0012, move on | esc put back`
  - Clip: `Clip · C0012 | ↑ Takes · <span> | ← → scrub | ⇧→ C0013 | K M X mark C0012 | V preview off`
  - while a mark key is held: `tap <mark> | ⏎ <mark> | let go nothing happens`
- Right side: `↶ ⌘Z N`, `↷ ⇧⌘Z N` (`#6E6A64` when zero).

### Footer (Skim)
48px tall, a 3-column grid `1fr auto 1fr`, bg `#262523`, top border `.08`.
- **Left**: `N decided · M undecided · 0 automatic`. It's replaced by a pending sentence in `#FFD27A` 600 with an `esc` cap (e.g. `keep 14 clips · 6.1 GB?`), or by a 2.2 s flash (`undid · keep 1 clip`). When nothing is undecided, an amber `⌘⏎ Export` button appears next to the counts.
- **Middle**: three **wells**, `keep · maybe · cut`. Each is 30px tall, min-width 92px, radius 8px, bg `rgba(239,236,230,.05)`, with an 8px dot in the mark colour and the count. Clicking a well marks the take under the cursor, or the box.
- **Right**: `cut so far: 4.2 GB` and either `card: 178.0 GB free` or `free space: not readable here`.

## Interactions & behaviour
**Levels**
- Unfurl: pinch out (wheel with ctrlKey, accumulated deltaY < −28, 380 ms lock), ↓, ⏎ or double-click. Furl: pinch in, ↑. esc furls all the way to Chapters.
- Two-finger horizontal swipe (|dX| > 1.5·|dY|, 70 px step, 180 ms lock) moves along the level; on Clip it scrubs (deltaX/90 frames). ⇧↑ ⇧↓ or [ ] jump chapters.
- Furling keeps the cursor on the thing it was in. Level changes animate `scale(.965)→1, opacity 0→1, 180ms ease-out`.

**Marks**
- Hold K, M or X: the target ghosts. A tap (click) or ⏎ while held decides. Letting go without a tap does nothing.
- Tapping K/M/X quickly (key up within 230 ms by event timestamps, no tap) on Takes or Clip marks the current take and moves to the next one.
- esc within 8 s puts back the last mark if it included the current take.
- ⌘Z / ⇧⌘Z undo and redo without limit. Steps are a mark (ids, previous marks, new mark).

**Box**
- Drag on empty grid space draws a box (inset ring `rgba(255,210,122,.85)`, fill `.06`). Tiles light up as the box crosses them.
- The box stays until esc or a click outside it. ⇧←/→ on Takes extends the selection from the cursor.
- While a box is up, K/M/X or a well act on everything in it. The footer shows `keep 14 clips · 6.1 GB?` for **600 ms**, esc cancels, then it lands as **one undo step**.

**Chips**
At most 3 per tile, worst first:
- `N% clipped` (≥1 %)
- `±N.N stops` (|ev| ≥ 0.7)
- `soft` (sharp < 0.35)
- `shake` / `pan`
- `bump`
- `N% crushed` (≥5 %)
- `60p` / `120p` (when it differs from the shoot's rate)
- `sidecar missing`
- `profile unknown`

Ready chips: bg `rgba(239,236,230,.1)`, text `#EFECE6`, 20px tall, radius 5px, padding 0 7px. Pending: hollow ring `.2` showing `—`. Chips fill in while the user looks; nothing waits on them.

**Rec.709 preview**
Never changes a file, mark or fact. In the browser it's approximated with the filter `contrast(1.35) saturate(1.45) brightness(.96)`. The real app should apply the proper LUT for the profile.

**Import (browser path)**
- A folder picker (`webkitdirectory`) or a dropped folder, walked recursively.
- Clips are `.mp4 .mov .mxf .m4v`; photos are counted. For each clip, a Sony sidecar `<name>M01.XML` is read for `captureGammaEquation`, `captureColorPrimaries`, `CreationDate` and `captureFps`.
- Each clip goes through a `<video>` element via an object URL: 8 seeks to `(i+.5)/8·dur`, each drawn to a 320×180 canvas and saved as a JPEG frame.
- Measures come from the pixels: mean luma gives ev (`log2(mean/.46)·2.2`); clipped is the % of pixels with luma > .98, crushed the % < .02; sharpness is the mean |Laplacian| / .05, clamped to 0–1; bump is a frame whose mean is more than .2 from both neighbours.
- If a clip won't decode, its facts are `unreliable`. The object URL is revoked after each clip. In the Mac app, use AVFoundation for all of this.

**Persistence**
Marks are saved per shoot under the key `lumina-skim:<shoot>-<count>`. The key is removed when everything is empty.

**FCPXML**
Version 1.10. Contents:
- one `<format>` per rate/size (24p `1001/24000s`, 60p `1001/60000s`, 120p `1001/120000s`, 25 `100/2500s`)
- an `<asset>` with `<media-rep kind="original-media" src="file:///…"/>` for each keeper, and for each maybe when included
- `<event name>` containing `<asset-clip>` elements; maybes carry `<keyword value="maybe">`

The file is downloaded as `<event>.fcpxml`.

## State
`step` (import | skim | export), `lv` (0–2), `gi` (chapter cursor), `cur` (clip cursor), `fx` (scrub 0–7), `nCut` (gap slider), `marks{id:mark}`, `pv` (preview), `sel[]` and `box` (area), `held` (mark key down), `prop` (pending area sentence), `undo[]`/`redo[]`, `memOn`/`memConfirm`, `ex{event, kw, maybes}`, `imp{n, done}` (measuring progress).

## Design tokens
- Background `#1E1D1B` · panel `#262523` · raised `#2A2927` · hover `#2E2C29` · drop zone `#232220` · well/inset `#161514` · tile placeholder `#3C3836` · thumb `#5B5854`
- Text `#EFECE6` · secondary `#B8B3AB` · dim `#9A958D` · disabled `#6E6A64`
- Accent / focus `#FFD27A` · keep `#A9D18E` · maybe `#FFD27A` · cut `#FF8A7A`
- Hairlines `rgba(239,236,230, .06 / .08 / .1 / .12 / .14 / .18)`
- Radii 3, 4, 5, 6, 7, 8, 9, 10, 12, 14px
- Focus ring `2px solid #FFD27A, offset 2px`
- Popover shadow `0 0 0 1px rgba(239,236,230,.12), 0 12px 32px rgba(0,0,0,.5)` · sheet shadow `0 20px 60px rgba(0,0,0,.5)`
- Type: system 10.5 / 11 / 12 / 13 / 14 / 16px; serif 19 / 21 / 22 / 26 / 30px
- Motion: 100 ms fade, 120 ms colour, 160 ms rise (translateY 6px), 180 ms segmented thumb and level unfurl

## Assets
No image assets. Frames come from the clips themselves (placeholder two-tone blocks in the samples). The FX5 sample metadata follows Visual Park's free SONY FX5 Sample Pack, which is licensed for personal use only, not commercial use.

## Files
- `Lumina Skim v3.dc.html`: the design source (template + logic). It needs `support.js` and `lumina-video-data-mvp.js` beside it.
- `lumina-video-data-mvp.js`: the FX5 sample shoot and the `lumina.video` stub.
- `screenshots/`: one PNG per view.
- `Lumina Skim v3 standalone.html`: a single offline file, open it directly.
- Related, not included: `Lumina Sets v11.dc.html` (Pick), the visual and wording parent.
