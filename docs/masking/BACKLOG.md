# Masking and healing backlog

The running list for AI masking and healing in Skim (video) and Stills. One PR per item, one commit
per step. A round ends with a short report: what shipped, what was measured, what waits on the owner.

**Order: provisional.** It should follow `notes/model-features-priority.md`, but that note and the
other four design notes are not in the repo, on any branch, or on the Mac yet. Re-rank once they are.
Until then the order follows the owner's request of 2026-10-23 and what PR #308 left open.

## Rules for every item

- **Data lives on the T7.** Datasets, model weights, caches, test outputs and renders go under
  `/Volumes/T7/Lumina/` (`datasets/`, `models/`, `masklab/`, `factory/`), never on the Mac's internal
  disk. Every run and download checks first that `/Volumes/T7` is mounted and writable, and stops
  when it isn't. The T7 is exFAT: no builds on it directly (see F1).
- **Builds and tests on the Mac use a separate copy of the repo**, never the owner's checkout.
- **Done means measured.** A feature is done after it has been run on real T7 clips and on the
  public sets. Report the share of frames tracked "sure", fps on the Mac, and IoU / boundary F
  where labels exist.
- **Models run on the Mac to ship.** Tinker and big models are only teachers or labellers.
- **RapidRAW (AGPL) and darktable (GPL) give ideas only**, cited in a comment, never code.
- **Stop and ask the owner only for:** hardware (the T7 plugged in, the Mac awake), Final Cut
  checks, and merges.

## Open PRs

| PR | What | Waiting on |
|---|---|---|
| #258 | Outlines, Follow, Final Cut matte, mask lab | owner review |
| #308 (on #258) | every-frame tracking, sure/shaky/lost strip, choose gestures, clean-plate Remove | Mac run on T7 clips, Final Cut patch check (V7) |
| #298 | dust removal for stills | merged 2026-10-23 |

## Backlog

### Factory (needed before anything else is measured)

- **F1. Mac test copy.** A clone of the repo inside an APFS sparse bundle stored on the T7
  (`factory/mac.sparsebundle`, attached with `-nobrowse` so Finder doesn't show it). DerivedData
  lives there too. Every round fetches the PR's branch into it, then builds and runs the
  `-only-testing` classes `ci_changes.py` picks. The owner's checkout is never touched.
- **F2. Move mask lab data to the T7.** `MASKLAB_EVIDENCE` defaults to `/Volumes/T7/Lumina/masklab`,
  and the runner refuses to start without the T7. Today 2 GB (runs plus `coreml-sam2.1-small`)
  sits in `~/LuminaEvidence/masklab`; copy it over, then delete the old copy once the owner OKs it.
- **F3. Dataset fetcher.** `Tools/masklab/datasets.py`: one entry per public set (URL, licence,
  size, checksum, what it's for), downloads only to `T7/Lumina/datasets/<set>`, and converts each set
  to the mask lab's `prompts.json` + `labels/` layout. The list comes from
  `notes/public-datasets-and-tinker.md`. Likely candidates until then: DAVIS 2017 and YouTube-VOS
  (video segmentation), MOSE and LVOS (occlusion, long clips), SA-V (SAM 2's set) and LaSOT
  (tracking), the DAVIS/YouTube-VOS inpainting splits (video inpainting), and Places2 masks for
  stills inpainting.
- **F4. `skim-sure` in the mask lab.** Run `SkimTracker` / `SkimFollow` headlessly over a clip, the
  way the app runs them, and report the share of frames sure / shaky / lost plus fps, next to IoU.
  This is the "done" number for every tracking item below.

### Skim: masks and tracking

1. **#308 on real clips.** Mac build in F1, then tracking on the T7 clips (`a7m3-day1`, the
   a7siii 4K clips, `skim-test-vp9`) and DAVIS 2017 val. Tune `SkimFollow.refind` (0.6 is a guess).
2. **Clean-plate Remove on a tripod clip (V5)**, then the 10-minute Final Cut check of the
   connected patch (V7, owner). The alpha is written straight, not premultiplied.
3. **EdgeTAM when Vision loses track.** Core ML EdgeTAM, called only on stretches marked lost or
   shaky. Measure the sure share with and without it.
4. **SAM 2.1 tracker comparison** on the T7 clips and the public sets: vision-box, vision-instance,
   sam2-coreml (small) and EdgeTAM. Report IoU, boundary F, drift, flicker and fps per tracker.
5. **Sky masking test** (`Tools/masklab/sky`) on real landscape stills and clips.
6. **Final Cut matte wired as a mask** (still open from #258).
7. **Matching across clips** (⇧⏎ every clip) and the H overlay.

### Skim: healing

8. **LaMa or MI-GAN inpainting for moving shots.** Core ML on the Mac, the patch layer the same as
   clean-plate Remove. Pick the model by quality per ms on the inpainting splits.
9. **Flow fill**: borrow pixels from neighbouring frames along optical flow before inpainting.
10. **Dust removal for video**: `LookDust`'s search across frames (a spot that stays put while the
    scene moves), healed as a patch layer.

### Stills

11. **Dust removal**: shipped in #298. Follow-up: measure on the T7 shoots and a public defect set.
12. **Masks in Edit** (DESIGN-ASKS Prompts 28 and 29 from #258): the page's Masks list and
    mask-local sliders, edited in the page now.
13. **Remove a distraction in a still** (LaMa / MI-GAN, the same model as item 8).

### Fine-tuning (Tinker)

14. Only when an item's numbers call for it: fine-tune the inpainting or refine model on the public
    sets through the Tinker API, convert it to Core ML, and keep it only if the held-out numbers
    improve.

## Rounds

### Round 1 (proposed 2026-10-23)

F1, F2, F4, then item 1 (#308 measured on the T7 clips) and item 2's clean plate. F3 is drafted,
but nothing is downloaded until the dataset list is confirmed. Waiting on the owner: the five
notes, the Mac staying awake with the T7 plugged in, the go-ahead to delete the old mask lab copy
after it's moved, and the Final Cut check once the patch is rendered.
