# Tracking experiments

The one objective for now (owner, 2026-10-23): **video tracking in Skim you can trust.** The strip under the scrub
bar has to be right about which frames are fine, and the track has to hold where Vision alone loses it.
Healing and stills are parked until this is done.

## Done when

On the held-out sets below, measured with `Tools/masklab/score.py` on the owner's M4 Pro:

| | today (DAVIS 2017 val) | target |
|---|---|---|
| frames called **sure**: mean IoU | 0.49 | ≥ 0.85 |
| frames with IoU < 0.5 that are called sure | not measured | ≤ 5 % |
| J&F with the fallback (EdgeTAM on shaky / lost stretches) | 0.44 (Vision only) | ≥ 0.75 |
| speed of a full track | 16 fps | ≥ 15 fps |

The T7 clips also have to run end to end, scored against SAM 2.1 large pseudo-labels with 20 frames checked by eye.

## Data: as varied as the public sets allow

Each set tests a different way tracking fails. Nothing is trained on the held-out (val) splits. The calibration in E2
is fit on the train splits only. Where a set's val split has no public ground truth, its train split is used as a
held-out set, since nothing here trains on it.

| set | why it's here | split used | GT |
|---|---|---|---|
| DAVIS 2017 | the standard; general motion | train (fit), val (test) | masks, every frame |
| YouTube-VOS 2019 | many categories, short clips | train subset | masks, every 5th frame |
| MOSE v1 | crowds, look-alikes, heavy occlusion | train subset | masks |
| LVOS v2 | long clips (1+ min): drift, leaving and coming back | val | masks |
| VOST | the object changes shape (cutting, folding, pouring) | val | masks |
| OVIS | occlusion first: people and animals behind each other | train subset | masks |
| VISOR (EPIC-KITCHENS) | first-person video, hands, small objects | val subset | masks, sparse |
| LaSOT | long single-object tracking, fast motion, small targets | test subset | boxes (box IoU only) |
| T7 clips | the owner's own footage | all with prompts | SAM 2.1 large pseudo-labels |

Subsets cap each set at about 100 objects, spread over its categories, so a full sweep stays under a few hours on
the Mac. Each set goes through `datasets.py` (URL, licence, size, sha256 in `MANIFEST.json`) into
`/Volumes/LuminaFactory/datasets/<set>`, and a converter like `davis.py` turns it into mask lab clips, labels and
prompts. A set that can't be fetched by script (a sign-in or form) is listed in the manifest as `manual`, with the
page to get it from.

Every object also gets attribute tags where the set has them, or from simple measures where it doesn't: small (under
1 % of the frame), occluded, fast, look-alikes in frame, long (over 1,000 frames), shape change. The report then breaks
the numbers down by tag, not just by set.

## Experiments

- **E1. Vision's ceiling** (`vision-oracle`). The best Vision instance per labelled frame. It splits "the masks are
  wrong" from "the tracker picked the wrong one" and sets how much a better tracker on Vision's masks can gain. If the
  ceiling is low on a tag (small, crowds), the fallback has to supply its own mask there, not just a box.
- **E2. Make "sure" mean right.** `masklab-skim` logs each frame's cues: the tracker's figure, how much the tracked box
  and the shape agree, the area change, the feature-print distance to the chosen shape, refound, and Vision's own
  score. A small rule (thresholds, or a tiny logistic model if thresholds can't reach the target) is fit on the train
  splits to predict IoU ≥ 0.7, then checked on every held-out set. Reported: sure share, IoU when sure, share of bad
  frames called sure, and a reliability curve.
- **E3. Trackers side by side.** vision-box, vision-instance, skim, sam2-coreml (per frame), SAM 2.1 small and large
  (PyTorch, MPS; the reference), and EdgeTAM. Reported: J, F, J&F, fps, and by set and tag.
- **E4. The fallback.** skim, with EdgeTAM taking over on the stretches E2 marks shaky or lost and handing back once
  the frames are sure again. Reported: J&F, fps, and the share of frames the model ran on. The question is the J&F gain
  per second spent.
- **E5. The owner's footage.** E3's best and E4 on the T7 clips, against SAM 2.1 large pseudo-labels, with 20 frames
  per clip checked by eye on a contact sheet.

E1 and E2 need nothing installed. E3's SAM 2.1 / EdgeTAM rows and E4 need the PyTorch installs (the owner runs the
commands; Claude Code's safety check won't install outside code).

## Results so far

**E1 on DAVIS 2017 val (61 objects):** the ceiling for anything that picks one of Vision's instances is **J&F 0.497**
(vision-oracle). vision-instance is at it (0.498), and skim is 0.06 below it (0.436). Of the 15 objects skim scores worst
on, 13 have an oracle under 0.3: Vision never makes a mask for that object. It merges the people in lab-coat and
shooting, the fish in gold-fish, the pigs, and a rider with their bike. Of skim's "sure" frames, half (1,698) are frames
where no Vision instance fits (skim 0.25, oracle 0.24). On the other half (1,682), skim scores 0.73 against an oracle of
0.82.

What it changes:
- The 0.75 target can't be reached with Vision's masks on any frame selection. The mask has to come from a SAM-class
  model (EdgeTAM / SAM 2.1) wherever Vision's mask doesn't fit the object, not only where the track is lost. E4
  becomes "Vision tracks the box; the model makes the mask when Vision's doesn't fit", with the model run on every
  frame as the upper line.
- For E2, "sure" also needs the mask to fit: an area and shape consistent with the start frame, and one shape on the
  tracker's box (`rivals`), not just a stable pick from frame to frame.

## Order

1. E1 on DAVIS (running).
2. Fetch and convert the sets above, then E1 on each.
3. E2: cues logged, rule fit on the train splits, checked on all held-out sets. This becomes a PR against #308 that
   changes `SkimFollow.sureness`.
4. E3 and E4 once the installs are in. The fallback is a PR of its own.
5. E5, then the round report.

### Speed: window crop (#310), 2026-10-23

`masklab-skim` before (b1e370e) and after (main c7efbcd, with #310), back to back on the M4 Pro with the SAM 2.1 queue paused (a few seconds of other Vision requests overlapped the "after" DAVIS run, so its fps is if anything low).

| set | build | fps | J | F | J&F | sure | IoU sure / shaky / lost |
|---|---|---|---|---|---|---|---|
| DAVIS 2017 val (61 objects) | before | 15.4 | 0.442 | 0.431 | 0.436 | 84 % | 0.488 / 0.234 / 0.198 |
| | after | 17.1 | 0.438 | 0.432 | 0.435 | 82 % | 0.489 / 0.231 / 0.203 |
| T7 C0054 (4K24, 636 frames) | before | 24.7 | | | | 100 % | |
| | after | 24.7 | | | | 100 % | |
| T7 C0095 (4K30, small subject, 1,845 frames) | before | 17.1 | | | | 21 % (lost 1,127) | |
| | after | 20.9 | | | | 23 % (lost 1,094) | |

+11 % fps on DAVIS and +22 % on the small subject, with accuracy unchanged (J&F −0.001). C0054 doesn't move: decoding 4K is the limit there. Per object the crop helps and hurts in about equal measure (mbike-trick_1 +0.05, india_1 −0.09: in a crowd the window's instances merge neighbours; sheet 05). The share of frames on the window vs the full path isn't logged by masklab-skim yet. Runs: `masklab-davis/runs/20261023-131116` (before), `…-132132` (after); `masklab/runs/20261023-131742`, `…-132726`.

## Known issues

- **SetsIngestTests is load-sensitive on the Mac (2026-10-23).** At 071b22b, LuminaLogicTests run while the mask lab
  sweep and the SAM 2.1 reference were busy on the same T7 failed 6 asserts, all in SetsIngestTests: bytes read off the
  "card" (662,144 vs 530,000 expected in `testAPreviewThatStartsInsideTheHeadIsNotReadFromTheCardTwice`, 2,259 vs 1,506
  in `testPreviewIsReadByByteRangeAndTurnedUpright`, 57,718 vs 28,859 "no second read off the card" in
  `testThumbCoversTheLargestRetinaTileUprightAndIsNeverUpscaled`). The same class run alone right after: 12/12 pass.
  Nothing in SetsIngest changed since the last green run (582/0 at 4e2f09a). The tests stay as they are (not skipped,
  not loosened); the cause, a second read when the reader is slow under load, is open.
