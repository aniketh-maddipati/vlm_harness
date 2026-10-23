# Outlining: flexible, accurate, by trackpad

Owner's asks (2026-10-23): "can we improve the flexibility and accuracy of outlining", "more trackpad control of
outlining", "to make fine corrections, need a tracer guiding as we are outlining". This is part of the tracking objective (TRACKING-EXPERIMENTS.md): the same fix serves both.

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
  `checkpoints/06-prompts-on-merged.png`.
- **B2. Box from the track, mask from the prompt.** Every frame: Skim's tracked box as the seed box. This is E4's
  "Vision tracks the box, the model makes the mask", with Apple's model as the first candidate.

## Order

1. B and B2, with the SAM 2.1 speed fix (1.6 fps today).
2. One PR on the page and the Mac side: click and click again, Esc, the strip's red marks, and the six controls that go.
3. Drag along the edge: the tracer, then refined by the model.
4. A screenshot sheet of each control on a DAVIS clip, then the owner tries it on a T7 clip.
