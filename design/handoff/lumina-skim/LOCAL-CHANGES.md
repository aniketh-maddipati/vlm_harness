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
