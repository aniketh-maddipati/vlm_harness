# Data guide for Gemini Argon (add-on to HANDOFF-GEMINI-ARGON.md)

Checked on disk 2026-10-28, read-only. Full inventory: /Volumes/T7/Lumina/DATA-INVENTORY-2026-10-28.md

## Setup (every run)
- Work disk: /Volumes/T7/Lumina/factory/mac.sparsebundle, mounted at /Volumes/LuminaFactory (F below). If it's missing: hdiutil attach -nobrowse /Volumes/T7/Lumina/factory/mac.sparsebundle
- source /Volumes/LuminaFactory/env.sh  (puts HF_HOME, TORCH_HOME, pip/uv caches, TMPDIR and MASKLAB_EVIDENCE=$F/masklab under $F, plus PYTORCH_ENABLE_MPS_FALLBACK=1)
- Venvs (Python 3.11, torch 2.14.1):
  - $F/venv: SAM 2.1
  - $F/venv-edgetam: EdgeTAM + coremltools 9
  - $F/venv-iopaint: IOPaint 1.6, LaMa / MI-GAN / flow fill
  - Scorers (score.py, heal_score.py) use ~/LuminaEvidence/venv-parity, Python 3.9 + numpy/Pillow/scipy. It's on the Mac's internal disk; rebuild it on the T7 if possible.
- Test clone: $F/repo, branch claude/heal-benchmark (draft PR #317, nothing unpushed). Factory scripts: $F/scripts.
- datasets.py: MASKLAB_DATASETS defaults to $F/datasets. MANIFEST.json (also at /Volumes/T7/Lumina/datasets/) records DAVIS only. Add the others with `python3 Tools/masklab/datasets.py verify`.

## Datasets
Converted means mask-lab layout: OUT/clips/*.mov, OUT/labels/<obj>/<frame>.png, OUT/prompts.json.

| Set | Source (sign-in?) | Raw on disk | Converted | Convert command |
|---|---|---|---|---|
| DAVIS 2017 trainval 480p (CC BY 4.0) | data.vision.ee.ethz.ch/csergi/share/davis/DAVIS-2017-trainval-480p.zip (no sign-in) | $F/datasets/davis2017/DAVIS (1.6 GB) | val: $F/masklab-davis (61 objects); train: $F/masklab-davis-train (144 objects) | python3 Tools/masklab/davis.py $F/datasets/davis2017/DAVIS $F/masklab-davis --set val (or --set train) |
| VOST val (CC BY-NC-SA) | tri-ml-public.s3.amazonaws.com/datasets/VOST.zip, 54 GB; vost.py range-reads only the files it needs (no sign-in) | $F/datasets/vost/VOST (61 videos) | $F/masklab-vost (101 objects); smoke set $F/masklab-vost-smoke (3) | python3 Tools/masklab/vost.py $F/masklab-vost --split val --max-objects 100 --data $F/datasets |
| LaSOT test (research use) | huggingface.co/datasets/l-lt/LaSOT (no sign-in); raw frames deleted by design | none | $F/masklab-lasot (82 of a 100 cap; box labels, tag box-only) | python3 Tools/masklab/lasot.py $F/masklab-lasot --max-objects 100 --every 10 |
| MOSE v1 train, used as held-out (CC BY-NC-SA) | huggingface.co/datasets/FudanCVL/MOSE MOSE_release.zip (no sign-in) | $F/datasets/mose/train: 21 videos, no labels | **none, conversion incomplete** | python3 Tools/masklab/mose.py $F/masklab-mose --max-objects 100 --per-video 3 |
| VIPSeg (sky / person / background classes) | VIPSeg page (no sign-in) | $F/datasets/vipseg/extracted/VIPSeg/{imgs,panomasks}: 60 videos, list in pick.txt | **none, no converter yet** | (to write: panomasks → per-class labels) |
| RORD-50, healing truth (Apache-2.0, Xiaomi SVOR on Hugging Face) | Hugging Face (no sign-in) | $F/datasets/rord50/{videos,masks,gts} (50 each) | staged for healing: $F/heal/rord/{videos,masks,gts} | — |
| DAVIS-345, GrabCut, Berkeley, COCO-MVal (taps-to-90% sets) | the interactive-segmentation (RITM/SimpleClick) dataset links | $F/datasets/clicks/*.zip, **not extracted** | none | (unzip, then a NoC90 script still to write) |
| Healing holes on DAVIS val | made here | — | $F/heal/davis/holes-moving, holes-still (30 clips each) | python3 Tools/masklab/make_holes.py FRAMES OUT --area 0.10 [--still] |
| Owner's SD clips, no truth | own footage | /Volumes/T7/Lumina/clips/sd-20261023 (42 MP4) | heal set: $F/heal/sd/{frames,holes,track} (9 clips) | bash $F/scripts/sd-holes.sh (skim-prompted follow, 120 frames at 1280 px, grown 8 px) |
| Owner's a7S III clips | own footage | /Volumes/T7/yvid-a7siii-C00*.mp4 and /Volumes/T7/Lumina/fixtures/video/* | $F/masklab (6 prompts) | — |
| FiveK (research only, never ship) | — | /Volumes/T7/Lumina/fixtures/lumina-harness/fivek (50 × 5 experts) | — | — |

**Not on disk anywhere:**
- **Sign-in needed:** YouTube-VOS 2019 (CodaLab), full RORD and VSPW (owner sign-ins).
- **Fetch by hand from Google Drive:** LVOS ($F/datasets/lvos exists but is empty).
- **Never fetched:** DAVIS-585, SA-V, OVIS, VISOR, Places2 masks, PPR10K, and any dedicated sky or people set. VIPSeg is the stand-in for sky and people.

## Weights (all in $F)
| Model | Path |
|---|---|
| SAM 2.1 large / small (PyTorch, Apache-2.0) | $F/models/sam2.1/sam2.1_hiera_large.pt, sam2.1_hiera_small.pt (from dl.fbaipublicfiles.com/segment_anything_2/092824/) |
| SAM 2.1 small, Core ML (Hugging Face apple/coreml-sam2.1-small) | $F/masklab/models/coreml-sam2.1-small/SAM2_1Small{ImageEncoder,PromptEncoder,MaskDecoder}FLOAT16.mlpackage |
| EdgeTAM (Apache-2.0, github facebookresearch/EdgeTAM) | $F/src/EdgeTAM/checkpoints/edgetam.pt (the scripts use this one; a duplicate is in $F/ref/EdgeTAM); backbone timm repvit_m1 in $F/cache/hf. **No Core ML yet:** the export is blocked on a coremltools `int` op |
| big-lama, MI-GAN (IOPaint downloads them) | $F/cache/torch/hub/checkpoints/big-lama.pt, migan_traced.pt |
| ProPainter + RAFT + flow completion (**reference only, non-commercial**) | $F/src/ProPainter/weights/{ProPainter.pth, raft-things.pth, recurrent_flow_completion.pth} |
| Source trees | $F/src/{sam2, EdgeTAM, ProPainter} |

## Run and score commands
- **App trackers on a converted set:**
  `LUMINA_VIDEO_DIR=$F/masklab-davis/clips MASKLAB_EVIDENCE=$F/masklab-davis MASKLAB_TRACKERS="skim skim-prompted" MASKLAB_PROXY=854 MASKLAB_BIN=$F/build/masklab-track/release/masklab-track MASKLAB_PYTHON=~/LuminaEvidence/venv-parity/bin/python3 bash Tools/masklab/run-tracker-test.sh`
  Run it from $F/repo; $F/scripts/guard-sweep.sh wraps it. Swap the folder for masklab-vost or masklab-lasot: **neither has a run yet**.
- **Score:** `python3 Tools/masklab/score.py RUN… --labels $F/masklab-davis/labels --out report.json`. Strip honesty: `strip_stats.py report.json`. Sure-rule fit: `calibrate.py --fit RUN… --test RUN…`.
- **SAM 2.1:** `$F/venv/bin/python $F/scripts/run-sam2-ref.py davis --davis $F/datasets/davis2017/DAVIS --out $F/masklab-davis/runs/<run> --model large|small [--prompt mask]`
  - Any converted set: `run-sam2-ref.py clips --clips DIR --prompts prompts.json --out RUN --proxy 720`
  - Its pointer to Tools/masklab/ref/setup-refs.sh is dead: that file doesn't exist.
- **EdgeTAM:** the same script under `$F/venv-edgetam/bin/python` with `--model edgetam`. Add `--prompt maskdir:$F/apple-click` for the one-click flow (0.76).
- **SAM 2.1 Core ML per frame:** `MASKLAB_SAM2_MODEL=$F/masklab/models/coreml-sam2.1-small bash Tools/masklab/run-tracker-test.sh`
- **Healing:** `bash $F/scripts/heal-run.sh davis|rord|sd skim-plate|lama|migan|flow-lama [moving|still|real]`
  - Output: $F/heal/<set>/out/<healer>-<mode>/<clip>, scores in $F/heal/<set>/scores
  - LaMa / MI-GAN: `$F/venv-iopaint/bin/iopaint run --model lama|migan --device mps --image F --mask H --output O`
  - skim-plate: `$F/build/heal/masklab-heal FRAMES HOLES OUT`. Build it with `swiftc -O -o $F/build/heal/masklab-heal Lumina/Sets/Look/LookMasks.swift Lumina/Sets/Video/SkimPlate.swift Tools/masklab/heal/Stub.swift Tools/masklab/heal/main.swift`
  - Score: `heal_score.py --out O/<clip> --holes H/<clip> --truth T/<clip> --report …` (use `--src` in place of `--truth` when there's no truth)
  - Table: `python3 Tools/masklab/heal_table.py $F/heal/davis/scores --out $F/heal/davis/out --md`
  - heal-run.sh still calls heal_score.py and flow_fill.py from $F/wt/push-1. They're identical to $F/repo's copies; point the script at $F/repo.
- **ProPainter:** never run (the output folder is empty). Entry point: `$F/src/ProPainter/inference_propainter.py`.

## Where the healing benchmark stopped (nothing running)
- **DAVIS val:** 210 scores. Done: lama, migan and skim-plate (moving and still), plus flow-lama moving. flow-lama still stopped at 7 clips with no scores.
- **Results so far (PSNR in the hole):** LaMa 21.56 moving / 21.49 still, flow-lama 20.17, MI-GAN 19.57, skim-plate 14.64 / 12.65. They're in docs/masking/HEALING.md on PR #317.
- **RORD-50 and the SD clips:** staged, no outputs.
- **Next:** finish flow-lama still, run RORD and SD, run ProPainter as the reference, then land #317 with sam's OK.

## On the Mac's internal disk (move to the T7 when convenient; none of it is masking or healing data)
- ~/datasets (24 GB): realblur 13 GB, kwentar 6.4 GB, sid-sony 5.6 GB (a second copy; the T7 has its own at /Volumes/T7/Lumina/datasets/sid-sony)
- ~/LuminaEvidence/datasets (4.3 GB): simplecube++ 4 GB, dped-samples
- ~/LuminaEvidence/venv-parity (the scorers' venv)
- ~/Library/Caches/executorchcoreml (494 MB, origin unknown)
- ~/vlm_harness-masklab: an old clone, superseded by $F/repo
- ~/LuminaEvidence/masklab is only a symlink to $F/masklab
