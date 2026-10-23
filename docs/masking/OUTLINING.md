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

## Trackpad controls (recommended set)

The modifiers keep their current meaning, with points instead of whole shapes:

| gesture | does |
|---|---|
| click | starts an object at that point (seed point) |
| ⇧-click | adds a point that is part of it (included) |
| ⌥-click | adds a point that isn't (excluded): splits the owner off the dog |
| drag | a box around the object (seed box) |
| ⌘-drag | paints a scribble over it (seed scribble). Press harder (Force Touch) for a wider brush; with ⌥ it erases |
| pinch / two-finger drag | zoom and pan while refining (pinch zoom exists today; pan is added in outline mode) |
| ⌘Z | takes back the last point, box or stroke |
| ⏎ | follows it through the clip, as today |
| Esc | drops the draft |

| T, then move along an edge | the tracer (below) |

### The tracer, for fine corrections

A magnetic trace in the style of intelligent scissors (live wire). With T held or toggled, the line follows the cursor
but snaps to the strongest nearby edge in the frame. The path from the last anchor to the cursor is shown live, before
it's committed:

- The cost of each pixel comes from the frame's own edges: gradient strength, and the edge direction against the path's
  direction, on the 720 proxy and only in a band around the cursor. A shortest path from the last anchor to the cursor
  (Dijkstra) runs on each move, which is fast at that size.
- A click drops an anchor. The path also drops one on its own after the cursor has stayed on the same edge for a
  while, as Photoshop's magnetic lasso does. ⌘Z takes back the last anchor, and Esc drops the trace.
- Started on the current outline and ended back on it, the trace replaces just that stretch of the outline: the fine
  correction. A closed trace on its own becomes a new shape.
- The traced stretch is then handed to the model as a scribble along the edge, with an included point inside and an
  excluded point outside, so the mask beyond the stretch stays consistent. The edge snap runs on the result.
- Pinch zoom works mid-trace, so a hair-width edge can be traced at 400%.

Not recommended: a two-finger swipe to step through candidate masks or frames, since two-finger horizontal moves
already pan and scrub, and would fight. Candidates, if a model offers several, go on Tab.

Each added point re-runs only the prompt (the picture's encoding is kept), so the outline should update while the
finger is still on the trackpad. The target is under 100 ms per point on the M4 Pro, measured before building the UI.

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
2. The page and the Mac side for click, ⇧ / ⌥ points and box, behind the current outline mode.
3. The tracer: live wire on the page, the stretch replaced in the outline, then refined by the model.
4. Scribble with pressure, pan, ⌘Z.
5. A screenshot sheet of each control on a DAVIS clip, then the owner tries it on a T7 clip.
