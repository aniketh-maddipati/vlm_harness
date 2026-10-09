# Skim v3: changes made here, to carry back into Claude Design

The page in this folder is the v3 handoff plus the edits below, found by opening real clips (50 ILCE-7M3
clips with their Sony sidecars, two S-Log3 clips with none) in the page's own import path. Paste this
section into the next Claude Design prompt so the next handoff has them and doesn't undo them.

1. **Frames never showed for real clips.** `support.js` turns a style string into an object with
   `css.split(";")`, and a frame made with `toDataURL('image/jpeg')` starts `data:image/jpeg;base64,…`, so
   `background:url(data:image/jpeg;base64,…)` was cut at the semicolon and dropped. The FX5 sample hid it
   (its frames are colour placeholders). Frames are now `blob:` URLs from `canvas.toBlob`, with their byte
   sizes kept in `c.frameSz` for the Working memory panel, and released (`URL.revokeObjectURL`) by
   `dropFrames` on Clear frames, Clear memory and opening another folder.
2. **The profile was never read from a real Sony sidecar.** The page looked for
   `captureGammaEquation="…"` as an attribute; a camera writes
   `<Item name="CaptureGammaEquation" value="rec709-xvycc"/>` (and the same for `CaptureColorPrimaries`).
   It now reads either form, so an A7 III clip reads `none · from the clip's sidecar` and an S-Log3 clip
   `S-Log3`.

Seen and left for the design (not changed here):
- The Clip level's large picture is the 320 × 180 filmstrip frame stretched to the window, so it is soft.
  The best skimmers show the clip itself there: a `<video>` seeked to the pointer's time.

## Iterations (2026-10-08, from the first run in the app)

3. **Grain on the Clip level.** The picture was the 320 × 180 filmstrip frame stretched to the window. The
   current clip now has a `<video>` of the file itself, seeked to the skim (latest wins); the filmstrip frame
   stands in until the first seek lands. One video open at a time, released when the clip or level changes.
4. **Black first frame in WebKit.** `seeked` can fire before the frame is decoded, so frame 1 of an HEVC clip
   came out black, which read as "13% crushed · sharpness 0.00 · bump frame 1". The import waits for
   `loadeddata` and a painted frame (`requestVideoFrameCallback`, 250 ms at most), looks again up to twice when a
   frame is blank, and leaves a blank frame out of the measures.
5. **The skim was pulled when moving across the picture.** Hover skims only the clip under the pointer and shows
   a 1 px line where it is; leaving puts back the pinned frame; a click pins it. ←→ and a horizontal swipe move the
   pinned frame, and a swipe only scrubs when it is over the current clip.
6. **The Clip level is elastic.** The current clip and as many of its chapter as fit share the canvas, each
   neighbour at 0.62 of the current one and at least 220 px wide, the current one keeping 60% of its size alone
   (2 at 1440 px, 1–2 narrower). A bracket under them names the chapter: `19:50 – 20:08 · same chapter · 10 clips ·
   8 more ›`. A lone clip in a busy window says `1 of 5 clips in … · ⇧← ⇧→ to move`. The scrub bar sits under the
   current clip, with its time and frame.
7. **Recent shoots on Open.** Every opened folder is saved with its marks, name, count, size and days. A card says
   `in memory · N frames ready`, `in memory · measuring N of M`, or `not in memory · its N marks are saved` with
   `Choose the folder again to bring its clips back`; choosing it brings the marks back. Clear memory says so.
   The FX5 sample no longer opens itself on Open; a design preview that starts on Skim still gets it.
8. **Loading.** A frame not made yet is a plain panel that breathes (opacity 0.4–0.9, 1.8 s, staggered 110 ms
   across the 8 frames), and a made frame fades in over 220 ms. A clip whose length isn't read yet shows `—`.
9. **Clips with no profile could not be previewed.** Re-exports and clips copied without their sidecar carry no
   profile, so the switch was disabled for good. The preview line now asks, on one line:
   `no profile in these clips · shot in  S-Log3  S-Log2  HLG  none`. The answer goes to every clip of the shoot
   that has no profile, reads `S-Log3 · S-Gamut3.Cine · as you set it`, and is saved with the shoot's marks.
10. **The S-Log3 preview is the real transform.** The CSS stand-in (`contrast saturate brightness`) was 13.5
    levels off on average against Sony's S-Log3 / S-Gamut3.Cine → Rec.709 (36 at p95). An SVG filter
    (`#lumina-slog3`: a 33-point curve per channel, then a 3 × 3 gamut matrix with offsets, fitted in display space
    on frames of two S-Log3 clips) is 0.8 off on average and 3.4 at p95 (of 255). S-Log2 and HLG keep the stand-in.
11. **The profile answer is a toggle.** `shot in  S-Log3  S-Log2  HLG  none` stays on the preview line for clips
    whose profile was set by hand; the chosen one is filled, another click switches, a click on the chosen one takes
    it back (the clips have no profile again and the switch turns off).
12. **Measures follow the preview.** S-Log3 frames are converted with the same curve and matrix before exposure,
    clipping, crushing and sharpness are measured, at import and again (from the frames already made) when the
    profile is answered or taken back.
13. **Saved shoots outlast a quit, in the app.** When the host provides `lumina.video.storeAll()` and
    `storeSet(key, text)`, every saved shoot is also sent there, and on load the page makes its own store match.
    The memory panel's heading says `Saved on this Mac` then, `Saved in this browser` without a host.
14. **The memory panel says what each button does.** `Make frames again · N frames, X MB` / `Forget N marks`
    (asks twice) / `Close “<shoot>” · back to Open` (asks twice: `Close “<shoot>”? Click again to close`; ⌘W does the
    same), each with one plain line of what happens. A recent shoot not in memory reads
    `needs opening again · N marks saved`.
15. **No Maybe keyword field.** Export drops the field; maybes go into the event tagged `maybe`
    (`into the event, tagged “maybe”`, and `Include maybes · tagged “maybe” in Final Cut`).
16. **Clips, not only folders.** The drop zone reads `Drop a card, a folder or clips` and the button `Choose…`; the
    file input is made `multiple` on the element (the template's `multiple=""` doesn't survive the render), so
    several clips picked at once all come through. Loose clips open as `Imported clips`.
17. **The preview corrects for the engine's own video decode.** Every engine converts BT.709-tagged video before a
    filter or a canvas sees it, and Sony tags every clip BT.709. On load the page decodes a 256-step grey ramp
    (lossless H.264, or VP9 where H.264 isn't available; tagged like the camera's clips, 1.7 KB and 0.8 KB, embedded)
    and folds the inverse of what it reads back into the S-Log3 table (now 256 points) of the preview filter and the
    measures. The memory panel's `video decode` row says `matches the files` or `corrected · up to N levels`.
18. **Scenes · Clips · Viewer**, an editor's words, for Chapters · Takes · Clip. The slider reads
    `fewer scenes ⟷ more scenes` and `N scenes`. Fine print is gone: no gap reason under a scene, no "against middle
    grey", "lowest of 8 frames", "far from its neighbours", "shoot is mostly", "free space: not readable here";
    Open says `MP4 · MOV · MXF · M4V` and `Read only.`
19. **As many scenes as fit, by default.** The gap cut is the largest that shows every scene without scrolling
    (every gap cut when all the clips fit), set on open, again when loading finishes, and on resize, unless the
    slider was moved by hand. Loading no longer folds the shoot back to the fewest scenes.
20. **Scenes shot back to back are joined.** A short line joins two neighbouring scenes in a row when less than
    60 s passed between them (by capture time, so it holds across folders opened together later).
21. Keys K M C mark keep, maybe, cut (X still cuts). Z zooms the Viewer picture; P opens the clips-added pane.
22. Clips added pane (P, the pill in the key bar, or the load bar): every clip with ready / reading / waiting / can't read / open again, its 8 frames as dots, the reading pace when the Mac is warm. Click a row to go to that clip.
23. Pinch: Clips tiles grow and shrink with the fingers (past the ends it opens the clip or closes to Scenes); the Viewer picture zooms where the pointer is, up to 6×, pointer or two-finger scroll pans, pinch back past fit closes to Clips.
24. Double-click in the Viewer: Export when something is kept, otherwise "Nothing marked Keep yet" with Back to Clips (⏎) and Stay (esc).
25. Reading is paced by heat, Low Power Mode, memory pressure and decode speed (app: skimHealth; browser: decode speed only). Working memory shows Mac heat, memory, reading pace.
26. Shoots with one name are numbered ("Card", "Card 2"); saved marks are keyed by the clips themselves, not the folder name and count.
27. Working memory ▸ Controls: frames kept (64 / 128 / 256 / 512 MB / no limit), frames per clip (2 / 4 / 8), frame size (small / medium / large), reading (by heat / eased / slow / paused). Over the limit, clips farthest from where you are let go of their frames (one kept first); they come back when you get near.
28. Working memory ▸ Test load: Vlog day 150, Wedding 600, Event 1,500, Stress 4,000 made-up clips, drawn and measured in memory, nothing on disk, not saved; heat: real / warm / hot / very hot.
29. Clips builds only the rows near the screen and around the current clip (fixed tile heights), so a 1,500-clip shoot moves at ~35 ms a key.
30. Loading: every clip once with one frame first (scene covers first), then the rest and the measures; two decoders on 16 GB+ Macs; decode speed no longer slows a card read (only heat, Low Power and memory do). Status beside the levels: "Reading 160 of 401 · about 2 min left", the clip it is on when one takes long.
31. Stalls: a slow frame is skipped; timed-out clips get one more go with longer waits; three failures in a row stop with "Is the card still in?" and Go on; "cut short" when a clip is shorter than its sidecar says. Make frames again waits until reading is done.
32. Scenes split on time, a new day, a frame-rate or size change and a change of look; the default fills a screen, up to two when the card has more clear breaks.
33. Memory panel: clips, read, frames, Mac, Lumina by default; the rest, frames per clip, size and test loads (150 / 600 / 1,500 / 4,000, not while a card reads, back to the card after) under More. Each load is timed (lumina-skim:clock).
34. Marks are kept per clip (file name + capture time), so opening some, all or more of a shoot's clips brings its marks back; Recent shoots is gone from Open.
35. The open panel takes the XML sidecars with the clips.
36. Nothing has to be selected: Export defaults to Everything (selected clips as Final Cut favorites, cuts rejected, maybes tagged, the rest unrated), Only selected clips is a switch; double-click in the Viewer goes to Export.
37. Neutral words on screen: the K mark reads "selected" (select / selected), M "maybe", C "cut"; stored keys stay keep / maybe / cut so saved marks carry over. No "keep", "kept" or "keepers" in the UI.
38. Profiles: the Rec.709 switch is off and greyed when nothing needs converting ("already Rec.709 · nothing to convert"); a "profiles" card lists each profile and camera in the shoot with what the preview does (S-Log3 exact, S-Log2 / HLG approximate, Rec.709 nothing, unknown: say which, right there). Camera model read from the sidecar.
39. Formats a browser can't play are said as such ("this browser can't play its format", a count beside the levels, "open in Safari" in Chromium) instead of "damaged or cut short"; not retried, never stops the read. The web preview recommends Safari and warns in Chromium (no 10-bit H.264: XAVC S-I, XAVC S 10-bit).
40. Faster reading: filmstrip and measure frames snap to the nearest full frame in the file (fastSeek in Safari and the app; the Viewer stays exact; ?exact=1 turns the snap off to compare); three clips at once in Safari and the app (two in Chromium); the rest of the frames fill in nearest the clip you are on first. The clock records snap and decoders.
41. Sony metadata from inside the clip: XAVC files carry the same NonRealTimeMeta XML in their last ~2 KB, so clips copied without M01.XML (Drive, AirDrop) still give camera, S-Log3 / S-Gamut3.Cine, length, capture time and camera timecode (c.ltc). Reads 16 KB per clip at most. Checked on the friend's a7S III clips (XAVC HS, HEVC Main 10 4:2:0, 4K 23.976).
42. Resizing keeps the scenes as they are (debounced; no regrouping), and a scene's cover is its first clip that already has a frame, so covers don't go blank while the rest is read.
43. Drag-select: tile positions measured once per drag and one update per frame (was every tile, every mouse move); the box disappears on release and what it caught stays highlighted; a click outside the grid (header, tabs) lets go of the selection, the mark buttons keep it.
44. Smoother while reading: repaints coalesced to one per ~120 ms; the scene slider moves its thumb and count live and regroups 140 ms after the hand stops; scenes off screen are not painted (content-visibility). A hidden tab (the browser pauses its video) holds the reading until it is back; reads that failed while hidden go back in the queue instead of counting as bad clips or stopping the read.
45. (canvas) Decoded thumbnails made once: ThumbCache (grid 160×90 / full 320×180), every clip's cover decoded when its first frame lands and pinned, the rest LRU under 128 MB; regrouping decodes nothing new.
46. (ingest) Listed before anything is decoded, and the first look follows the screen. Listing: the metadata of every clip (name, size, date; Sony: length, capture time, camera, profile, timecode from the sidecar or the file's last 16 KB) is read 16 files at a time instead of one after another, the clip's length is filled in from it at once (it was 0 until the clip was opened, so gaps between clips were overstated until then), and only then does reading start; the scenes slider works from that moment. The clock has `meta` (the reads), `metaFrom` (file / sidecar / none) and `listed` (folder handed over → clips drawn), written when the listing is done (a `partial` entry) and replaced by the full entry when the load is done. First look (pass 1) is no longer a fixed order made at the start: each next clip is asked for from what is on screen now — clips on screen (Clips), the clip you are on and three each side (Viewer), a cover for each scene on screen, a cover for every scene, the clips that become covers when the scenes are split further (largest gap first), then the rest by place in the scene — so moving the slider, scrolling or going to a clip changes what is read next (within 250 ms). New: sonyMeta, tailMeta, inBatches, seenNow, firstOrder, pickFirst, clockSave; runQueue, readClip, dropFrames, factsOf and coverOrder are unchanged. What is on screen is read from the tiles (data-gi / data-clip); a layout that draws without them can set `this._seen = {clips, groups}`. Tests: Tests/web/skim-ingest.test.mjs.
50. (canvas) No black or grey tiles. A clip with no frame yet shows a still, neutral tile with its name and time · length (Scenes covers and Clips tiles; the breathing grey blocks are gone). When a tile's picture changes (regrouping, a frame read again) the new one is laid over the old, which stays until the new one is decoded; pictures no longer fade in from empty.
51. (canvas) Layout as maths (canvas plan 1.2): Component.layGeo / laySceneGeo / layClips / layScenes / layout / layHit, static, no DOM; sizes in, tile rectangles out. tileGeo, sceneGrid and the Clips row windowing now call them (same numbers as before, held to the old code in Tests/web/skim-layout.test.mjs). 500 clips lay out in under 0.01 ms median in Node (budget 2 ms; a Node number, not a browser one). Nothing on screen changes.
60. (rec709) The Viewer's large picture follows the Rec.709 switch. WebKit (Safari and the app) does not apply an SVG filter (`url(#lumina-slog3)`) to a `<video>`, so with S-Log3 clips the large picture stayed as shot while the small frames above it changed. When the preview is such a filter, the frame the video is on is drawn into a canvas over it (`pvVia`, `pvCvRef`, `paintVid`; redrawn on each seek, on zoom and on the switch) and the canvas takes the same filter as the stills. Switch off, S-Log2 / HLG and Rec.709 clips still show the video itself. No change to the curve, matrix or tone map.
61. (rec709) The switch changes log clips only. `pvOn` now uses the same rule as the disabled switch (`needsPv`: S-Log3, S-Log2, HLG), so a clip that is already Rec.709, has another profile name, or has none looks the same with the switch on and off, in the grid, the small frames and the Viewer; before, a profile name the page did not know got the approximate filter even while the switch read "nothing to convert". Tests: `Tests/web/skim-rec709.test.mjs`.
65. (marking) One touch in the Viewer and in Clips: a tap of K, M or C marks the clip you are on and moves on to the next undecided clip (it was the next clip, decided or not); past the last undecided clip it goes back to the first one still undecided, and when every clip is decided it is simply the next clip. `Component.nextUp(flat, marks, cur)`, static, no DOM; `quick` calls it and `goClip` does the move. The Rec.709 preview switch is not touched by marking or moving on.
66. (marking) The three choices in the Viewer, under the clip's name: selected / maybe / cut as buttons with their key (K M C) on them, the clip's mark lit in its colour, a line under them with the mark in words (or "undecided") and "cut so far: … GB" (the same figure as the footer, now beside the picture). A click does what the key does: mark, move on. The footer's three wells do the same when one clip is the target (they marked and stayed); with a selection, or in Scenes, they still mark the area.
67. (marking) Undo steps back: ⌘Z after a mark that moved on returns to the clip that was marked and gives it back the mark it had (none, or the earlier one); ⇧⌘Z marks it again and moves on again. The step records where it came from and went to (`step.at`); `Component.markStep` and `Component.stepCur` are the plain functions behind `apply`. Esc within 8 s of a mark that moved on now puts that mark back as well (it closed to Scenes, because the mark was no longer on the clip you were on).
68. (marking) Tests/web/skim-marking.test.mjs: nextUp, markStep and stepCur read out of the page; a full pass, skipping decided clips, the wrap, undo and redo (12 tests).
69. (rec709) The Viewer's video and its preview canvas take the clip's own filter (`it.vflt`), not the still's: a clip opened in the Viewer before any of its frames were made shows its picture converted too, like the frames that follow.
55. (faults) The Viewer picture stopped following the pointer after a slight pinch. Any zoom over 1.01× turned the pointer off for the clip in the Viewer and made a two-finger swipe pan instead of scrub, and a trackpad gives a 1.05× pinch by accident, where nothing looks zoomed. Now the pointer scrubs the clip at any zoom (`picMove` no longer looks at the zoom), and a pinch that stops under 1.25× goes back to fit (`Component.zoomSettle`, on the end of the gesture and 260 ms after the last pinch step). A real zoom is as before: two-finger scroll pans, Z or a pinch back fits.
56. (faults) No seek in the Viewer waits forever. The video is checked 2.6 s after it was asked for a time (`vidArm`, `vidCheck`, `Component.seekVerdict`): still seeking, in error, or not where it was asked after 4 s (10 s while the file is still opening) and the file is opened again, twice at most; the sampled frames underneath follow the pointer meanwhile. After that the video is left off for that clip and the line under it says `the clip isn’t answering · showing its 8 sampled frames`; going to another clip and back tries afresh. A pointer that keeps moving does not push the check back. Coming back to a hidden tab asks the video again.
57. (faults) A neighbour in the Viewer row that has one frame only says `one frame read · click to scrub` beside its time (`Component.skimSay`), instead of a picture that does not move under the pointer.
58. (faults) Tests/web/skim-scrub.test.mjs: zoomSettle, seekVerdict and skimSay read out of the page (9 tests). Checked in WebKit (a WKWebView with clips from the a7 III card): two minutes of pointer scrubbing across four clips stays in step; a 1.05× pinch froze the pointer before and does not now; a video made to swallow its seeks is opened again twice, then left off with the line above, and works again after going to another clip and back.
71. (marking) A mark is a toggle and stays on the clip (replaces the move-on of 65 and 67). K, M, C, the three Viewer buttons and the footer wells mark the clip you are on, in the Viewer and in Clips, and you stay on it; the mark the clip already has turns off (back to undecided), a different one switches to it. `Component.markToggle(has, m)`, static; `quick` and the hold-then-⏎ path call it. `Component.nextUp` and the advance are gone; moving between clips is the arrow keys and clicks only. Marking an area (a selection, or a scene in Scenes) is unchanged: it sets the mark, it does not toggle.
72. (marking) The Viewer's three buttons are on/off areas in the mark colours (`Component.MK`: selected green, maybe amber, cut red). Off: a quiet outline and the word in that colour. On: filled with it, dark word and key. The key bar reads "mark … on / off" in Clips and the Viewer.
73. (marking) Undo and redo land on the clip the step marked (`Component.stepCur(step)`: the one clip of a one-clip step), so ⌘Z after moving away returns to it; Esc within 8 s of a mark puts it back while you are still on that clip, as before 65.
74. (marking) Tests/web/skim-marking.test.mjs rewritten: toggle on, toggle off, switch, undo and redo restoring, a mark never moving the clip (10 tests).
80. (export) The Export screen offers two things and nothing else up front. First, one button, `Download for Final Cut · N selected` (⌘⏎, the same .fcpxml download as before), with one line under it: the maybes come along tagged “maybe”, nothing is copied or changed. Second, a well reading `N cut clips · X GB you can free` with Copy list and Download list, and the sentence "The page cannot delete files; delete these in Finder."; with no cut clips it reads `no cut clips yet`, dimmed, with no actions. `N still undecided` shows only when there are some. "Clip files are never changed." and the mounted-at path line stay. The title reads "Export". Nothing on the screen says the file opens in Final Cut: a real import has not been checked.
81. (export) The cut list (`Component.cutList(clips, marks, fmtB, real)`, static; `cutText`, `cutCopy`, `cutSave`): plain text, a first line with the count and total size (`3 cut clips · 3.5 GB`), then one clip per line in capture order. Each line is the clip's path when the page has a real one (the path inside the folder that was opened, e.g. `Untitled/PRIVATE/M4ROOT/CLIP/C0001.MP4`, or an absolute path), otherwise the file name (sample and test loads). Download saves `<event> cut clips.txt` the way the .fcpxml is saved. Copy uses `navigator.clipboard.writeText`; when that is missing or refused the well says "Copying was refused here. Use Download list instead." No new bridge op, nothing sent anywhere.
82. (export) Everything else is under a closed `Details` line at the bottom (`state.exMore`, kept while the page is open): the four-row table, the event name, the Everything and Include maybes switches, By scene and the .fcpxml preview. They work as before.
83. (export) Export now starts on selected plus maybes (`ex.all` false, `ex.maybes` true); it started on Everything (entry 36). Chosen by the user for the simplified screen. Everything and "without maybes" are still there under Details and produce what they did: `buildX` is untouched, so the .fcpxml for given marks and options is the same. With Everything on, the button reads `Download for Final Cut · N clips` and the line under it says every clip comes along.
84. (export) Words: the cut row and the Everything switch said "rejected"; they read "marked as not wanted in Final Cut" and "cut ones marked as not wanted". With nothing to export the button reads "Nothing selected yet" and the line under it "Select clips in Skim with K."
85. (export) Tests/web/skim-cutlist.test.mjs: cutList read out of the page (order, count line, size sum, names versus paths, nothing cut), the default options, and the Export screen's words (9 tests). Checked in a browser on localhost with eight stand-in clips (2 selected, 1 maybe, 3 cut, 2 undecided): the two actions and their numbers, the text handed to the clipboard and to the .txt download, the refused-copy line, ⌘⏎ producing the .fcpxml (3 clips, one tagged maybe), Details opening and its switches changing the table, the button and the preview.
100. (faults) Zoomed in means hold the frame and look around; at fit means skim. Zoomed is a zoom that would not settle back to fit (1.25× and over, or Z): `Component.zoomHeld`, `Component.pointerScrubs`. Zoomed, the pointer over the clip in the Viewer does not change the time (`picMove`), a click leaves the frame where it is (`picClick`), a two-finger drag pans as before and a click-drag pans too, the picture going with the hand (`picDown`, `mm`, `mu`, `Component.panTo`; cursor grab / grabbing). ← → still step frames and keep the zoom and the pan. The frame under the pointer when the zoom starts is the frame held (`pinHv`), so zooming in does not jump to another one. This replaces the "pointer scrubs at any zoom" half of 55; neighbours in the row still skim under the pointer.
101. (faults) The label on the picture reads `zoomed · Z to fit` and shows only when zoomed (`zoomHeld`), never in the moment of a slight pinch. Under 1.25× the pointer and a swipe skim throughout; the pinch still settles to fit on the end of the gesture or 260 ms after its last step (a dropped `gestureend`).
102. (faults) A slow pinch zooms. `zoomBy` snapped any zoom under 1.01× back to 1 at every step, so a pinch of under about 0.6% a step (a slow one) never left fit. The zoom is kept as it is and the settle takes a slight one back.
103. (faults) A video that stops answering gets a fresh `<video>` element, not only a fresh file (`vidNew`): seen once in WebKit, a seek that never ended (`seeking` true, no `seeked`) on the a7 III clips with nothing wrong on the page. The check runs 1.5 s after the ask and a seek gets 2.5 s (was 2.6 s and 4 s); opening a file still gets 10 s.
104. (faults) Tests/web/skim-scrub.test.mjs is now 14 tests (zoomHeld, pointerScrubs, panTo added). Checked in WebKit with gesturestart / gesturechange / gestureend, ⌃-wheel, mouse and key events on card clips and one S-Log3 clip: skim at fit, hold when zoomed, swipe and drag pan, arrows step, Z and pinch back resume skimming, a slight pinch with or without `gestureend` settles, the Rec.709 canvas keeps the video's frame, zoom and pan.
