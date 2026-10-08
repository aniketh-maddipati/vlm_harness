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
