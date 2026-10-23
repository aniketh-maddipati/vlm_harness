# Mask lab

How well do automatic masks hold an object? This measures it, with numbers only. It changes nothing
in the app. The first question: you select an object on one frame of a clip. Which tracker keeps
its mask on that object through the rest of the clip, how steady is the mask, and how fast is the
tracker on this Mac?

```bash
bash Tools/masklab/run-tracker-test.sh                # every tracker on every clip with a prompt → report (Mac)
python3 -m unittest discover -s Tools/masklab/tests   # the scoring tests, synthetic data, Linux too (or: make masklab-test)
swift test --package-path Tools/masklab/track         # masklab-track's Foundation-only half, Linux too
```

Clips, frames, masks and labels stay out of the repo, which is public. Everything a run reads or
writes, apart from the clips, lives in `~/LuminaEvidence/masklab/`:

```
~/LuminaEvidence/masklab/
  prompts.json                         what to track in each clip (below)
  labels/<clip>/<frame>.png            hand labels, sparse
  runs/<date-time>/<tracker>/<clip>/   one PNG mask per frame + timing.json
  runs/<date-time>/report.json, report.txt, log.txt
  runs/latest                          → the newest run
```

## Running

1. Copy `prompts.example.json` to `~/LuminaEvidence/masklab/prompts.json` and give each clip an entry.
2. `bash Tools/masklab/run-tracker-test.sh`. It builds `track/` (`swift build -c release`), runs
   `vision-box` and `vision-instance` on every `.mp4` / `.mov` at the top level of
   `LUMINA_VIDEO_DIR` (default `/Volumes/T7`, where the seven `yvid-a7siii-C00*.mp4` clips are) that
   has a prompt, then scores. A clip without a prompt is listed as skipped. The clips are only read.
3. Read `runs/latest/report.txt`; `report.json` has every number, per labelled frame too.

The run goes through `Scripts/test_guard.py` (name `masklab`, one hour by default,
`MASKLAB_LIMIT=<s>`), so it ends, only one runs at a time, and it is refused while
`~/LuminaEvidence/.tests-off` exists. It does not take the screen. The other settings
(`MASKLAB_TRACKERS`, `MASKLAB_PROXY`, `MASKLAB_FRAMES`, `MASKLAB_SAVE_FRAMES`, `MASKLAB_SAM2_MODEL`,
`MASKLAB_EVIDENCE`) are listed at the top of the script.

### prompts.json

One entry per clip, keyed by the clip's file name without its extension:

```json
{
  "yvid-a7siii-C001": {"start": 0, "box": [0.40, 0.25, 0.20, 0.55]},
  "yvid-a7siii-C002": {"start": 48, "point": [0.52, 0.48], "frames": 600}
}
```

- `start`: the frame the object is selected on. Frame numbers count from the clip's first frame,
  starting at 0, in presentation order (the same as ffmpeg's `n`).
- `box`: `[x, y, w, h]`, or `point`: `[x, y]`. Normalized 0…1 with the origin at the frame's top
  left, so they don't depend on the proxy size. A box measured in pixels on a frame of width W and
  height H is `[x/W, y/H, w/W, h/H]`.
- `frames` (optional): stop after this many frames.
- Keys that start with `_` are ignored.

## Labelling

A label is the true mask of the object on one frame: an 8-bit PNG, white (≥ 128) on the object,
black elsewhere, saved as `labels/<clip>/<frame>.png` (`120.png` and `000120.png` are the same
frame). Labels are sparse: label some frames, spread over the clip (every 30th frame and the last
one is a good start, plus frames where the object is hard: occluded, turning, near another object).
Only labelled frames are scored for IoU and boundary.

Draw the labels on the proxy frames, so they line up with the masks pixel for pixel:
`MASKLAB_SAVE_FRAMES=30 bash Tools/masklab/run-tracker-test.sh` also writes every 30th tracked frame
as `runs/<…>/vision-box/<clip>/frames/<frame>.png`. Paint over a copy in any editor (a white layer,
then export the layer alone on black). A label of another size still works: the run's mask is
resampled to the label's size (nearest neighbour), and the boundary tolerance is in label pixels.
A hand label is a judgement; where the object's edge is unclear (hair, motion blur), keep it tight
and use the boundary tolerance for the rest.

## What is measured (`score.py`)

Per tracker and clip:

| column | what |
|---|---|
| `lab` | labelled frames scored (inside the run's frames) |
| `IoU` | mean IoU of the run's mask with the label. A labelled frame the run wrote no mask for counts as empty. Both empty counts as 1 |
| `Δ/100f` | drift: least-squares slope of IoU over frame number, per 100 frames. Negative = the mask slides off with time |
| `last10` | mean IoU of the labelled frames in the last 10 % of the run's frames (— when none is labelled there) |
| `BF` | boundary F-score: a boundary pixel of one mask counts when the other's boundary is within `--tolerance` pixels (3). The measure DAVIS calls F (Perazzi et al. 2016), written from its definition |
| `flick` | flicker: mean changed area between consecutive masks, relative to the mask's mean area (0 = still, 2 = jumped to another place), on frames between two labelled frames at most `--still-gap` (30) apart whose labels have IoU ≥ `--still-iou` (0.95), i.e. where the object itself holds still. — when no such stretch is labelled |
| `flickAll` | the same over every consecutive pair, labels or not (real motion counts too, so compare trackers on the same clip only) |
| `fps` | frames / wall-clock seconds from `timing.json` (decode, tracker and PNG writes); `report.json` also has the tracker's own work per frame, median and p95 |
| `empty` | frames written empty: the tracker had nothing to pick (lost) |

`python3 Tools/masklab/score.py RUN [RUN…] --labels DIR [--out report.json]` scores any runs
(each a folder with one subfolder per clip, or one clip folder). Without labels it still reports
fps, `flickAll` and empty frames.

## The trackers (`track/`, `masklab-track`)

A SwiftPM command line tool (macOS 14+, no dependencies). It decodes the clip with AVAssetReader at
the proxy size (long edge `--proxy`, 720 by default, never upscaled; the decoder scales, so no 4K
frame is kept), decodes and drops the frames before `--start`, and from there writes one mask per
frame (`<out>/000123.png`, 8-bit, 255 = in) and `timing.json`:

```
tracker, clip, start_frame, frames, total_ms (wall clock from the start frame's decode to the last write),
per_frame_ms (the tracker's own work), decode_ms, lost (frames written empty), confidence (vision-box),
proxy [w, h], source [w, h], prompt, model, device {model, os, cores, memory_gb}
```

```bash
swift build -c release --package-path Tools/masklab/track
Tools/masklab/track/.build/release/masklab-track /Volumes/T7/yvid-a7siii-C001.mp4 --start 0 \
  --box 0.40,0.25,0.20,0.55 --tracker vision-box --out /tmp/C001-box
```

- **`vision-box`**: `VNTrackObjectRequest` (accurate) follows the box from frame to frame; on each
  frame `VNGenerateForegroundInstanceMaskRequest` finds the foreground instances and the one with
  the highest IoU with the tracked box is the mask (`generateScaledMaskForImage`, thresholded at
  0.5). Below an IoU of 0.05 nothing is picked and the frame is written empty. A point prompt
  starts the box from the instance under the point.
- **`vision-instance`**: no tracker. Each frame takes the foreground instance with the highest IoU
  with the last non-empty mask; the start frame takes the instance the prompt picks (the one under
  the point, or the one with the highest IoU with the box).
- **`sam2-coreml`** (experimental): only with `--model <dir>`, a folder holding Apple's Core ML
  conversion of SAM 2.1 (Hugging Face `apple/coreml-sam2.1-*`; nothing is downloaded by this tool
  or its script; put the files there yourself). Without `--model` it stops and says so. The code
  was written against this **assumed** interface, not checked against the real files:
  - three models in the folder whose names contain `ImageEncoder`, `PromptEncoder` and
    `MaskDecoder` (`.mlpackage`, compiled on load, or `.mlmodelc`);
  - image encoder: one square image input (e.g. 1024 × 1024; the frame is stretched to it), its
    outputs (e.g. `image_embedding`, `feats_s0`, `feats_s1`) passed on by name;
  - prompt encoder: `points` [1, N, 2] in the encoder's input pixels and `labels` [1, N]
    (1 = on the object, 2 / 3 = a box's corners);
  - mask decoder: each input named like an encoder or prompt-encoder output (exactly, or with or
    without a trailing `s`); outputs `low_res_masks` [1, K, h, w] (logits, > 0 is in) and
    `scores` [1, K] (the highest is kept).
  The tool checks this before the first frame and, when a name is wrong, prints the names the
  models really have. These conversions take one image and one prompt: SAM 2's video memory is not
  in them, so this is SAM per frame with the prompt carried forward as the last mask's box (grown
  by 10 % per side), not SAM 2's own video tracking.

The track's `preferredTransform` is not applied (the clips this was written for are landscape).
`MaskLabCore` (arguments, boxes, masks, instance picking, the timing file) is Foundation only and
tested on Linux; the AVFoundation / Vision / Core ML half builds on a Mac only (on Linux the tool
checks its arguments and says it needs macOS).

**Status:** the AVFoundation / Vision / Core ML code has not been compiled or run yet; it was
written on Linux. The first Mac run is also its first build.

## The app's own track (`skim/`, `masklab-skim`)

`MASKLAB_TRACKERS="vision-box vision-instance skim"` adds the track Skim's Viewer runs (**Follow through the clip**,
`SkimTracker`), built with `swiftc` from the app's own files (`LookMasks`, `SetsMasks`, `SkimFollow`, `SkimFollower`,
`SkimTracker`; `skim/Stub.swift` stands in for the reader and the matte's file name). It takes masklab-track's
arguments and writes the same masks and `timing.json`. The start frame's shape is chosen the way the page chooses it:
Vision's shape that the box overlaps most, or the smallest one under the point, with its kind. Masks are the followed
outlines rastered at `SkimFollow.proxyEdge` (720). `timing.json` also has `sure` (frames per state), `sure_frames` (each
frame's state, from the start frame) and `refind`.

`score.py` reports each clip's share of frames the app calls sure (`sure` column), the IoU of the labelled frames in
each state (`iou_by_sure` in `report.json`, and the run's line under the table), and a line per run with J, F, J&F,
fps and the sure share. The strip can be trusted when "sure" frames score high and "shaky" and "lost" ones low.

## Sky (`sky/`, `masklab-sky`)

The app's sky mask on stills, for checking it on real photos: `bash Tools/masklab/sky/run-sky-test.sh [folder]` (default
`/Volumes/Untitled`) builds `masklab-sky` with `swiftc` from the app's own `LookMasks.swift` and `SetsMasks.swift` (a stub
stands in for the app's reader), takes `SKY_N` photos (240) spread evenly through the folder, reads each one's embedded
preview at 1024 px as the app does, and writes to `~/LuminaEvidence/skymask/<date-time>/` (`latest` points at it): an
overlay per photo (the sky the app would offer tinted blue, every other shape outlined, and a caption with the gate's
score, the sky offered and the finder's area with the gate open), contact sheets of twelve, and `report.json` with each
photo's top scene labels. Nothing is written next to the photos. Same guard as the tracker test.

## Rules

- Numbers only: no clip, frame, mask or label is committed. Clip names appear in the reports.
- Structure only from RapidRAW (AGPL) and other copyleft projects: ideas, cited in a comment, never
  code. Nothing here comes from one.
- A tracker that looks better here is not yet in the app; that is a separate change.
