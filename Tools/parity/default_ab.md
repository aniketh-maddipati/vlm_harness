# Blind A/B: Lumina's default render vs Adobe Color (Phase E)

Criterion (`criteria.json`): blind preference for Lumina's default render ≥ 45 % against Adobe
Color on ten photographers' photos. This is the only step that needs people; everything is local.

## Make the pairs

Ten photos (one per photographer, ideally not from the golden set), each with:
- `A`: Lightroom's `__base.tif` (Adobe Color, everything reset; the sweep plug-in makes it), and
- `B`: Lumina's base render of the same ARW:
  `Tools/parity/lumina-render/.build/release/lumina-render render <arw> --look "" --px 2048 --space srgb --out <stem>.lumina.png`.

Convert the TIFFs to sRGB PNGs for the browser (`sips -m /System/Library/ColorSync/Profiles/sRGB\ Profile.icc --setProperty format png in.tif --out out.png`) and put the twenty files in one folder as `<stem>.adobe.png` and `<stem>.lumina.png`.

## Run it

```bash
cd <that folder> && python3 -m http.server 8765
open http://localhost:8765/ab.html      # copy Tools/parity/ab.html into the folder first
```

`ab.html` (a plain page, no network) lists the `<stem>` pairs you type or paste, shows each pair
side by side in a random left/right order, asks "Which do you prefer?" and, at the end, offers a
CSV (`stem,left,right,chosen,ms`) to download. The rater never sees which side is which. Collect
one CSV per rater (≥ 5 raters, ≥ 50 judgements) and summarise:

```bash
python3 - *.csv <<'PY'
import csv, sys
n = win = 0
for f in sys.argv[1:]:
    for row in csv.DictReader(open(f)):
        n += 1; win += row['chosen'] == 'lumina'
print(f"{win}/{n} = {win / n:.1%} prefer Lumina (criterion ≥ 45 %)")
PY
```

Put the percentage (numbers only) in the parity report's Phase E section; the images stay out of
the repo.
