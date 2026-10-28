# Checkpoint sheets

Contact sheets made by `Tools/masklab/sheet.py` at each tracking checkpoint (docs/masking/TRACKING-EXPERIMENTS.md):
one row per object, frames spread over the clip, the truth tinted green and each tracker magenta, with IoU per tile
and skim's sure / shaky / lost state as the strip under its tile. Only public-dataset frames go here, never the
owner's footage.

| sheet | what |
|---|---|
| 01-davis-vision-skim-oracle.jpg | DAVIS 2017 val: vision-instance, skim, vision-oracle on six objects |
| 05-window-crop.jpg | DAVIS 2017 val: skim before and after the window crop (#310) on three objects |
| 06-prompts-on-merged.jpg | DAVIS 2017 val frame 0: Apple's prompted segmenter (one click, click + exclude, box) on objects Vision merges |
| 08-prompted-follow.jpg | DAVIS 2017 val: skim vs skim-prompted (a clicked outline kept with the prompted segmenter) on five objects, with the frame where the outline jumps to a neighbour marked |

Frames: DAVIS 2017, CC BY 4.0 (davischallenge.org).
| 09-healing-davis.jpg | DAVIS 2017 val: hole, skim-plate, LaMa, MI-GAN, flow-lama, truth (3 frames × 4 clips) |
