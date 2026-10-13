# Skim ingest: opening and measuring in one shot, feeling instant (branch video/skim-ingest)

Two deliverables: (A) the read/measure pipeline, (B) an assessment of the control grammar for the canvas.
Owner of the reading code (importFiles, runQueue/runPass, readClip, mockRead, paceWait, factsOf/pix, the clock).
Not the grid drawing (video/skim-canvas), not grouping (video/skim-grouping), not the Rec.709 maths
(video/skim-rec709). Merge video/skim-mvp before page edits; keep page copies byte-equal. Native decode is
video/skim-native: keep the page's hooks compatible with it.

## A. One shot, feels instant
Today (measure with the clock, Working memory ▸ More, `lumina-skim:clock`): pass 1 = one frame per clip (covers
first, snap to the nearest full frame, 3 decoders in Safari); retry pass; pass 2 = the other 7 frames + measures,
nearest-to-you first. The friend's real clips: XAVC HS HEVC 10-bit 4K ~97 Mb/s, 11–14 s, metadata in each file's
last ~2 KB (no sidecars). The user's a7 III card: 401 clips, 113 GB, H.264 8-bit 4K, first frame 0.35–0.7 s in
Chromium, outliers 1–7 s off the SD card.

Work out, measure and build:
1. Instant listing: names, sizes, dates, camera, profile, length and timecode from file metadata only (no decode)
   — all clips on screen with their info in < 1 s for 500 clips.
2. First look budget: one decoded frame per clip; target time for 400 clips on Safari off the T7; break the
   per-clip cost into open (metadata) / seek / decode / readback / encode / measure, and attack the largest.
3. Measures in the same pass: compute flags from the first-look frame immediately (exposure, clipped, crushed,
   sharpness), refine as more frames come; "measured" means usable flags, not all 8 frames.
4. Frames between sessions: persist covers and measures (IndexedDB in the browser, keyed by clip identity
   name+capture time+size) so reopening the same card is instant; cap and evict.
5. What is visible first, always: the reading order follows the viewport and the current clip, not card order.
6. Background tabs (browsers pause video): already waits and requeues; measure the cost; say it on screen.
7. Report: a per-stage timing table for the 400-clip card and the friend's 5 clips, Safari and Chrome, before/after.
Targets to aim at (to confirm with the user): listing < 1 s, every cover < 60 s for 400 clips off an SSD, usable
flags with the covers, the rest in the background without the UI ever stuttering.

## B. Grammar and feel for a creator like him (write CANVAS-GRAMMAR.md)
Who: travel/lifestyle shooter, a7S III S-Log3, Final Cut, edits ~7 s pieces to music for TikTok, hundreds of clips
per trip, culls to save storage, trackpad on a MacBook. Lumina's own grammar so far: K/M/C (selected/maybe/cut),
hold a key + tap/box to mark an area, pinch/zoom between levels, ←→ move, ↑↓ zoom out/in, ⌘Z, P progress, Z zoom,
V preview. Assess against how he works and against Final Cut (J/K/L, I/O ranges, F favorite, Delete reject,
skimming with the pointer) and Lightroom mobile (swipe, flags). Deliver: the gestures and keys for the canvas
(contact sheet ↔ moments ↔ takes ↔ clip), skimming (pointer = time), ranges (in/out for the usable stretch), the
dock (drag in/out), discoverability (what's on screen vs learned), what to drop; with a short test script to run
with him on a call and what to watch for. Recommend, don't build the canvas here.
