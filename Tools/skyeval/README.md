# skyeval — the blue-skies + exposure scorers (research tools, never shipped)

Report: `docs/masking/eval/2026-10-28-sky-exposure.md`. Everything renders through
`Tools/parity/lumina-render` (`swift build -c release` there first), so the numbers are the app's
own pipeline. Needs an arm64 venv with rawpy, numpy, scipy, Pillow, tifffile, scikit-image
(`/Volumes/LuminaFactory/venv-sky`) and `exiftool`. Evidence goes to `~/LuminaEvidence/skyeval/`.

| script | what |
|---|---|
| `f1.py` | F1 / F6: `lumina-render diagnose` per RAW (sky mask, white, clipped-at-sensor via Apple's decoder) vs the RAW's own clipping (`rawclip.py`, white level from the file's tag) |
| `sheet_f1.py` | the 30-frame contact sheet for the owner's labels |
| `f2.py` | F2: the meter's one constant fitted on a development set, scored on the held-out edits' Lightroom Exposure |
| `f2sky.py` | F2: sky white share before / after the meter's move, clamp and sigmoid |
| `f34.py`, `sheet_f34.py` | F3 / F4: collateral, halo, sky hue / chroma / cyan share, 10-bit banding; the sheet |
| `f5.py` | F5: midtone spread per capture-time set before / after, hue collateral |
| `identity.py` | all features off → bit-identical renders against a `lumina-render` built from main |
| `clips.py` | video: one mid-clip 16-bit TIFF frame per clip (`ffmpeg -ss <mid> -frames:v 1 -pix_fmt rgb48le`), S-Log3 / S-Gamut3.Cine decoded to linear Rec.709 here (`--transfer slog3`, Sony's published curve and matrix) or the frame as is (`--transfer 709`); the sky gate + mask, the codec clip inside the sky, the meter, and the global `dehaze` stage (`dhz:+30`, `dhz:+60`, the owner's `hl:-68 dhz:+14 vib:+14`) measured on the sky and on the rest; a contact sheet per set. Evidence `~/LuminaEvidence/skyeval/video/{log,colour,card}` (2026-10-29: the friend's 5 S-Log3 clips, his 6 graded exports, every 12th clip of the a7 III card) |

`LUMINA_SKY=1` turns the flag on for `lumina-render` (`blu` inside a `mask:` token). The sky mask
is attached with `--sky` (render) or `"sky": true` (batch jobs).
