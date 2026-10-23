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

## Order

1. E1 on DAVIS (running).
2. Fetch and convert the sets above, then E1 on each.
3. E2: cues logged, rule fit on the train splits, checked on all held-out sets. This becomes a PR against #308 that
   changes `SkimFollow.sureness`.
4. E3 and E4 once the installs are in. The fallback is a PR of its own.
5. E5, then the round report.
