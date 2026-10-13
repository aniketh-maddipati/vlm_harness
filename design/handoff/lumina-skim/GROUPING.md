# Skim grouping: how clips are grouped so culling is easy (branch video/skim-grouping)

Owner of the grouping logic only (pure functions + tests). The canvas worktree (video/skim-canvas) draws what this
produces; do not edit the grid drawing here. Merge video/skim-mvp before page edits; keep page copies byte-equal.

## The decision being supported
Stills: pick one frame of a burst. Video: (1) pick the best take of a shot, (2) does this clip hold a usable 2–5 s
stretch. The friend's real clips (T7/friend_test_log: a7S III, XAVC HS, 11–14 s) end in whip pans; his exports are
~7 s, so he trims. Group so these two decisions sit in front of him.

## Axes, in order (each a function from clips → groups or labels, with a score and a plain reason)
1. Moment (exists: regap/break score: time gap, new day, frame rate/size change, look change). Keep; expose levels.
2. Takes: clips of the same shot back to back. Signals: first-look frame similarity (colour histogram + small
   structure fingerprint from the frames already made), same fps/size, within the moment, short gaps. Output: take
   groups inside each moment, with a "best take" suggestion (sharpness, exposure, least shake).
3. Shot type: static / pan / walking / whip / slow-mo (fps ≥ 50) / timelapse — from fps and frame-to-frame change
   across the 8 frames (luma difference + sharpness drop).
4. Accidental: < 2 s, mostly dark (lens cap/pocket), mostly blurred → "probably random", bulk-cuttable.
5. Usable stretch per clip: from the 8 frames, trim ends that are blurred / moving fast; propose in/out; later the
   export writes it as a Final Cut favorite range.

## Interface for the canvas
groupsAt(zoom) → [{level:'moment'|'take', title, why, clips:[ids], best?}] ; labels(clip) → {shot, accidental, stretch:[in,out]}.
Pure, Node-tested (Tests/web), deterministic for the fixtures; fast for 1,000 clips (< 20 ms).

## Check
On T7/friend_test_log and the 401-clip a7 III card: moments match what you'd call stops; takes of the same view group;
whip-pan ends trimmed in the proposed stretch; accidental filter catches only junk. Write results into this file.
