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
