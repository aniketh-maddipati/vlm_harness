# Claude Design prompt: Lumina Skim v4 (parity with the local build)

**How to use:** start a new Claude Design chat in the Lumina Skim project. Attach the five files in
`attach/`: `Lumina Skim v3.dc.html`, `support.js`, `lumina-video-data-mvp.js`, `LOCAL-CHANGES.md` and
`README.md`. Then paste everything below the line. When the handoff zip comes back, drop it in the thread
and Claude will install it and check it against the tests.

---

The attached `Lumina Skim v3.dc.html` is the page as it runs today in the Lumina Mac app and at
lumina-skim.pages.dev. It has moved well past the v3 you handed off: 149 changes, made by opening real
a7 III and a7S III clips and importing the result into Final Cut Pro 12.4. Every change is listed, with
its reason, in the attached `LOCAL-CHANGES.md`.

**Make v4 from the attached file, not from your v3.** Treat it as the source of truth for behaviour, copy
and structure. Don't rebuild it from your earlier version, and don't bring back anything it removed.
Where a design pass of yours makes it better (spacing, type, motion, the look of a control), go ahead,
but keep every behaviour below. Then update `README.md` so it describes v4 as it is.

## What the product is now

One pass over a card of video before Final Cut: browse every clip in Rec.709, mark it, then download an
.fcpxml that points Final Cut at the clips where they are. The steps are **Open → Skim → Export**. Skim
is one grid. Export is a sheet over that grid.

## Keep these behaviours (the details are in LOCAL-CHANGES.md)

**The one grid (148, 149)**
- Clips are the tiles, and scenes are headers above their clips (title, line, the count per mark, why the
  scene starts there). Clicking a header selects that scene's clips; with K, M or C held, it marks them.
- There are six sizes: scenes as tiles, then small, medium, large, larger, largest (default: large).
  Change them with − / =, the strip's buttons, or a pinch.
- The pinch scales the grid live around the fingers and settles on a size at 60% of a step. The tiles
  glide into place (FLIP), and the grid crossfades between scenes and clips. Past either end it
  rubber-bands and springs back. Pinching past the largest size opens the Viewer.
- Skimming: moving the pointer across a tile shows its 8 frames, or a scene tile's clips. Two fingers
  sideways step one frame or clip every 16 px.
- ↑ ↓ cross the scene headers, and ← → move one tile. [ and ] set the scene count. ⏎ or a double-click
  opens the Viewer.
- There are no Clips / Viewer tabs in the one grid. The scene slider shows only in debug mode.
- Tiles say only what is there: no "nothing to note" and no "undecided" line.
- `?canvas=0` or `#levels` still gives the old three levels. Keep that switch.

**Marking (37, 71–74, 105–107)**
- K, M and C toggle **selected / maybe / cut** on the clip you're on, and the clip doesn't move. The
  words on screen are selected / maybe / cut. The stored keys stay keep / maybe / cut.
- ⌘Z and ⇧⌘Z land on the clip that step marked.
- In the Viewer, ⏎ is next and ⇧⏎ is back, in capture order across scenes, with no wrap.
- The Viewer's three mark buttons are on/off areas in the mark colours.
- Neutral words only: never keep, kept, reject or flag on screen.

**Marks are never stored (146)**
- `Component.KEEP_MARKS = false`. Nothing is saved, and old saved marks are cleared on start.
- Closing the tab with marks not yet downloaded asks first.
- The copy says so: "Marks stay in this tab and are gone when it closes." There is no Forget marks
  button and no Recent shoots on Open.
- This replaces entries 7, 13, 26 and 34. Don't bring saved shoots back.

**Rec.709 preview (9–12, 17, 38, 60, 61, 69, 139, 141)**
- The S-Log3 transform is fitted to Final Cut's own Sony LUT, and the Viewer's video follows the switch.
- The switch changes log clips only. It is greyed when nothing needs converting.
- The profiles chip and card cover clips with no profile ("shot in S-Log3 / S-Log2 / HLG / none").

**Reading a card (40, 41, 46, 110–113, 25, 30, 31, 90–93)**
- Clips are listed first. Each clip gets one frame (scene covers first), then the rest.
- Sony metadata is read from the sidecar or from the clip's last 2 KB.
- The reading line has Pause / Go on. "N clips ready" shows when it's done.
- The Working memory pill and panel, per-load timings and test loads are **debug mode only**
  (`?debug=1` / `#debug`).

**Export (80–84, 97–99, 120–122, 142–145, 147, 149)**
- One button, "Download for Final Cut · N selected" (⌘⏎). It's off when the file would hold nothing.
- The file is checked before it's let go (`checkX`).
- Defaults: selected plus maybes, with maybes tagged "maybe". This replaces entry 36. Keep it: it's what
  we've told people publicly.
- The export summary block (`data-lumina="export-summary"`) holds:
  - what you download: file, size, check;
  - the clips it points at: count, length, footage size, up to 12 previews, "linked where they are,
    nothing copied";
  - what this pass did, per mark;
  - the numbered Final Cut steps;
  - what to check after the import.
- The cut list (count, size you can free, Copy / Save list), then "Clip files are never changed."
- Under a closed Details line: Event, Folder (where the clips are, so Final Cut can relink), and the
  Everything and Include maybes switches. The per-mark table, By scene and the raw .fcpxml show in
  debug mode only.
- In the one grid, Export is a sheet on the right over the grid. A click beside it, or esc, goes back,
  and the grid stays where it was.
- The .fcpxml carries each clip's true rate and `customLUTOverride` for S-Log3 / S-Gamut3.Cine.

## Don't change (the app and its tests read these by name)

- Every `data-lumina="…"` attribute, `data-gi`, `data-fold`, `data-first` and `data-scene`.
- `Component` static names: `ZL`, `ZL_LINES`, `ZL_WORD`, `ZL_DEF`, `zlGeo`, `laySecs`, `laySecAt`,
  `laySecNav`, `zlStep`, `skimAt`, `rubber`, `exSummary`, `exGate`, `checkX`, `cutList`, `cutLine`,
  `foldMark`, `foldSum`, `isCanvas`, `isDebug`, `nextPace`, `KEEP_MARKS`, `MK`, `SL3T`, `MEMDEF`.
- Method heads the tests extract: `buildX`, `extraVals`, `fmtB`, `download`, `markStep`, `stepCur`,
  `clipAt`, `zoomSettle`, `seekVerdict`, `skimSay`.
- The template syntax support.js reads (`sc-if`, `sc-for`, `{{ }}`).
- `support.js`: return it byte for byte.
- Frames are `blob:` URLs, never `data:` URLs inside a style string (entry 1: support.js splits styles on
  `;`).
- Comments use ’ rather than a straight apostrophe inside the page's script, because the tests' quote
  scanner reads straight ones as string quotes.
- No network calls. The page reads files the user picks and nothing else.
- The data contract in `lumina-video-data-mvp.js`: same shape.

## Deliver

A zip with `Lumina Skim v4.dc.html` (the page; a new file name, so the app can tell versions apart),
`Lumina Skim v4 standalone.html`, `support.js` (unchanged), `lumina-video-data-mvp.js`, an updated
`README.md`, and a short `CHANGES-v4.md` listing anything you changed beyond the attached file.
