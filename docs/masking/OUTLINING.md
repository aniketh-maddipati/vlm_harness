# Outlining: flexible, accurate, by trackpad

Owner's asks (2026-10-23): "can we improve the flexibility and accuracy of outlining", "more trackpad control of
outlining", "to make fine corrections, need a tracer guiding as we are outlining". This is part of the tracking objective (TRACKING-EXPERIMENTS.md): the same fix serves both.

## The yardstick

Owner (2026-10-23): "the idea is that lumina does masking and healing as easy as lr mobile but for videos". Each
step is measured by taps and time to a good result as well as accuracy. Next, in order:

1. One-tap masks: Subject, Sky, People, Background, as Lightroom Mobile's Select buttons (Vision finds them already).
2. Brush to select or remove: one stroke over the thing, handed to the model as a scribble prompt
   (`init(seedScribbleBuffer:)`), then followed and, for Remove, patched.
3. Following starts by itself after the tap.
4. Remove on a moving camera (the parked healing work).

Queued measurements (from the strategy page, 2026-10-23):

- Click-started J&F on the 61 DAVIS val objects for EdgeTAM and SAM 2.1 Base+, seeded with Apple's click mask.
- Volumetric J (`score.py` `vj`) next to per-frame J, which scores an empty mask on a hidden object as 1.0.
- Taps to 90% IoU (NoC90) on DAVIS-585 and COCO-MVal: Apple's prompted segmenter against SAM 2.1 Small.
- Lightroom side by side on 200 stills (50 each of people, objects, sky, removals), by taps and time as well as accuracy.
- Flow-guided fill plus LaMa against ProPainter on DAVIS with synthetic masks. ProPainter, ObjectClear, MatAnyone and
  MiniMax-Remover are reference only (licences); EdgeTAM, SAM 2.1, LaMa and MI-GAN can ship.

## Why outlining is stuck today

A click in the Viewer picks one of Vision's ready-made shapes (`olPick`: click = only this shape, ⇧-click adds a
shape, ⌥-click takes one away). If Vision merged the dog with its owner, no click can split them. On DAVIS val, the
best Vision shape per frame reaches only J&F 0.50 (E1), and of the 15 objects Skim does worst on, 13 never get a
Vision shape of their own.

## The model behind the clicks

macOS 27's Vision has a prompted segmenter, `GenerateIterativeSegmentationRequest` (found in the macOS 27.0 SDK's
Vision swiftinterface):

- seeds: `init(seedPoint:)`, `init(seedBox:)`, `init(seedScribbleBuffer:)`
- refinement: `addIncludedPoint(_:)`, `addExcludedPoint(_:)`
- `qualityLevel` (accurate, balanced, fast), `regionOfInterest`, a compute device per stage
- result: a mask pixel buffer. Its model is downloaded on demand (`DownloadableAssetsRequest`), not bundled.

It ships with the OS, so no outside model is needed for picking and refining. SAM 2.1 and EdgeTAM are measured next
to it (experiment B below) and stay the plan for carrying a mask through the clip where Vision's tracking loses it.
Open questions: whether the download works from the sandboxed app, how it behaves offline, and how fast it is per
added point.

## Controls: click, click again, drag an edge, Esc

Owner (2026-10-23): "how to make it simpler and more intuitive with less variation in controls". Today's Viewer has
11 outline controls (O, hover, click, ⇧-click, ⌥-click, scroll for the edge, ⇧-scroll to soften, ⏎, Esc, { }, "Fix
this stretch"). They come down to:

| gesture | does |
|---|---|
| click | outlines the thing under it, and following it through the clip starts by itself |
| click again | outside the outline adds that part, inside takes it away (one click on the neighbour Vision merged in takes it out) |
| drag along the edge | the tracer for fine corrections: the line snaps to the picture's edges and replaces that stretch |
| Esc | undoes the last click or drag; a second Esc lets go of the shape |

No modifier keys and no modes. Pinch and two-finger pan still zoom and move, as everywhere else. What goes:

- ⇧-click and ⌥-click: inside or outside decides.
- ⏎: following starts on the first click and restarts after each fix.
- Scroll and ⇧-scroll for the edge: a soft edge sized to the shape, kept as a setting in Export.
- The O switch: outlines show on hover.
- { } and "Fix this stretch": the strip only marks what needs you, in red where the track is unsure. A click on a mark
  jumps there, and a click on the frame fixes it the same way. Only that stretch is followed again.

Every gesture shows its result while the finger is still down. The target is under 100 ms per click on the M4 Pro,
measured before the UI is built.

### The tracer, for fine corrections

A magnetic trace in the style of intelligent scissors (live wire). A drag that starts on the outline's edge follows
the cursor but snaps to the strongest nearby edge in the frame. The path from the last anchor to the cursor is shown live, before
it's committed:

- The cost of each pixel comes from the frame's own edges: gradient strength, and the edge direction against the path's
  direction, on the 720 proxy and only in a band around the cursor. A shortest path from the last anchor to the cursor
  (Dijkstra) runs on each move, which is fast at that size.
- Anchors drop on their own after the cursor has stayed on the same edge for a while, as Photoshop's magnetic lasso
  does, so the drag never has to stop. Letting go ends the trace, and Esc takes it back.
- The trace replaces just the stretch of the outline between where it started and where it rejoined it.
- The traced stretch is then handed to the model as a scribble along the edge, with an included point inside and an
  excluded point outside, so the mask beyond the stretch stays consistent. The edge snap runs on the result.
- Pinch zoom works mid-trace, so a hair-width edge can be traced at 400%.

The edge snap (`LookMasks.guided`) stays on top of whichever mask comes back.

## Experiments before building

- **B. Prompts on merged objects.** DAVIS val frame 0 of lab-coat, gold-fish, pigs and shooting: Vision's best shape
  against one click, a click plus one excluded click on the merged neighbour, and a box. Run with SAM 2.1 small,
  EdgeTAM and `GenerateIterativeSegmentationRequest`, scored against the labels, with ms per prompt. Sheet:
  `checkpoints/06-prompts-on-merged.jpg`.
- **B2. Box from the track, mask from the prompt.** Every frame: Skim's tracked box as the seed box. This is E4's
  "Vision tracks the box, the model makes the mask", with Apple's model as the first candidate.

### B results (2026-10-23): Apple's prompted segmenter on merged objects

DAVIS 2017 val frame 0, the 16 labelled objects of lab-coat, gold-fish, pigs and shooting. Mean IoU against the label
(`Tools/masklab/prompts_merged.py`, `masklab-iterative`; sheet `checkpoints/06-prompts-on-merged.jpg`). The click is
the label's pixel nearest its centroid; the exclude click sits on the neighbour Vision merged in.

| | 1 click | click + exclude | box |
|---|---|---|---|
| Vision's best instance (vision-oracle) | 0.240 | | |
| GenerateIterativeSegmentationRequest, fast | 0.751 | 0.768 | 0.806 |
| balanced | 0.753 | 0.771 | 0.809 |
| accurate | 0.747 | 0.759 | 0.770 |

Two of the 16 are specks of 18 and 14 px (lab-coat_1 and _2) that nothing finds. Without them, balanced reaches 0.86
with one click and 0.89 with a box, against Vision's 0.27. Per object (balanced, one click): lab-coat_3/4/5
0.96/0.91/0.92, gold-fish_1–5 0.86–0.97, pigs_1–3 0.96–0.98; shooting_1 (a person holding a gun) 0.38, 0.64 with
the exclude click. Accurate is no better than balanced.

Time (M4 Pro, one process per request, so the first request includes a ~150 ms model load): the first request on a
frame ~310 ms (fast, balanced) and ~410 ms (accurate); each added include or exclude point ~20 ms (balanced) and ~40 ms
(accurate). The image encoding is kept between points, so a fix-up click is immediate. In process, warm: 155 ms
balanced for the first request. The model is a one-time download from Apple (`downloadAssets`, ~55 MB, 5.9 s here)
into macOS's own protected storage. SAM 2.1 small and EdgeTAM rows follow.

**Brush (scribble), 2026-10-23.** The same 16 objects, seeded with `init(seedScribbleBuffer:)`: a stroke along the
label's skeleton, 2 % of the long edge wide, kept inside the label (`Tools/masklab/scribble_merged.py`). Balanced:

| | 1 click | click + exclude | box | brush stroke |
|---|---|---|---|---|
| all 16 | 0.753 | 0.771 | 0.809 | **0.835** |
| 14 (without the two specks) | 0.861 | 0.881 | 0.886 | **0.924** |

The stroke wins most on thin or busy shapes: shooting_2 0.67 → 0.89, gold-fish_2 0.82 → 0.96, gold-fish_1 0.86 → 0.93.
First request ~163 ms median, the same as a click. What the buffer is, measured (the SDK documents none of it): a
one-channel `CVPixelBuffer` wrapped as `CVReadOnlyPixelBuffer(unsafeBuffer:)`; `OneComponent8` with the stroke at 255
and `OneComponent32Float` with the stroke at 1.0 give the same mask; its origin is the image's top left (a vertically
flipped stroke scores 0), unlike `NormalizedPoint`'s bottom left; a buffer at half the image's size works the same
(it is scaled to the image). Points added after a scribble seed: up to 13 (the doc comment).

## Order

1. B and B2, with the SAM 2.1 speed fix (1.6 fps today).
2. One PR on the page and the Mac side: click and click again, Esc, the strip's red marks, and the six controls that go.
3. Drag along the edge: the tracer, then refined by the model. The tracer is in (2026-10-23): a drag on the outline
   redraws that stretch along the picture's edges, and a drag with no outline draws a new shape by hand. A hand fix
   holds on its own frame; carrying it through the clip (as a scribble prompt) is next.
4. A screenshot sheet of each control on a DAVIS clip, then the owner tries it on a T7 clip.
