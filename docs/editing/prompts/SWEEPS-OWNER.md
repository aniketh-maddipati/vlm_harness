# Lightroom sweeps 4–12: the one session

Everything the feature prompts need from Lightroom CC, in one sitting. Same method as sweeps 1–3:
select a group's photos, click a preset, export, next preset. Exports run in the background.
`S` below is `~/LuminaEvidence/parity/sweeps` (on the T7: plug it in).

## 0. Before
- **Your own edits.** A preset overwrites a photo's settings. If a photo below carries edits you
  want back, make a Version of it first (Versions ▸ Create Version).
- **Crop, masks, healing aren't reset by a preset.** The picker already left out the 3 photos that
  have them (DSC06742, DSC06841, DSC06842). The ingest refuses any other export that has them.
- **Sweep 9 needs a shoot first:** `SWEEP9-ISO-LADDER.md` (18 frames, tripod, ~20 min). Skip it
  today if it isn't shot yet; the rest doesn't depend on it.

## 1. Install the presets
File ▸ Import Profiles & Presets ▸ `S/Lumina-sweeps-4-12-presets.zip` (202 presets).
Groups: "Lumina sweeps" (Base), "Lumina sweep 4 Presence" … "Lumina sweep 12 Grain";
sweep 5 has one group per hue ("Lumina sweep 5 HSL Red" …) and "Lumina sweep 5 B&W".

## 2. Make one album per photo list
For each list in `S/photos/`: new album named after it, Add Photos ▸ the folder `S/photos/<list>/`
(links to the RAWs). If Lightroom says they're duplicates, they're already in your library: add the
names in `S/photos/<list>.txt` to the album by search instead.

## 3. Apply and export
For every row: select the album's photos, click **Base**, export; then each preset of the group in
order (numbered), export after each. Export into `S/exports/sweepNN/` (one folder per sweep; NN as
in the table, `sweep04` … `sweep12`; all of sweep 5's albums go into `sweep05`).

| # | Album(s) | Preset group | Presets | Photos | Size |
|---|---|---|---|---|---|
| 4 | sweep04 | sweep 4 Presence | 18 | 40 | 2048 |
| 5 | sweep05-red … sweep05-magenta | sweep 5 HSL *that hue* | 6 each | 4 each | 2048 |
| 5 | sweep05-bw | sweep 5 B&W | 17 | 6 | 2048 |
| 6 | sweep06 | sweep 6 Grade | 55 | 20 | 2048 |
| 7 | sweep07 | sweep 7 Curve | 14 | 20 | 2048 |
| 8 | sweep08 | sweep 8 Sharpen | 13 | 10 | **Full size** |
| 9 | sweep09 (the ISO ladder) | sweep 9 Noise | 7 | 18 | **Full size** |
| 10 | sweep10 | sweep 10 Lens | 6 | 20 | **Full size** |
| 11 | sweep11 | sweep 11 Vignette | 11 | 30 | 2048 |
| 12 | sweep12 | sweep 12 Grain | 12 | 10 | **Full size** |

Base counts as one more click per album. About 230 clicks and 3,200 exports in all; the order above
is the order the feature prompts need them, so stopping part way still helps.

**Export settings** (every export): JPG, quality 100, sRGB, file naming as Lightroom likes
(names don't matter: the ingest reads each file's settings), **Metadata ▸ All metadata** (without it
the files can't be named). Size: long edge 2048 px, or **Full size** where the table says so
(sharpening, noise, lens and grain are scored at 100 %).

## 4. Afterwards, one command
```bash
~/LuminaEvidence/venv-parity/bin/python Tools/parity/lr_cc_sweep.py ingest-sweeps
```
It names every export from its settings into `S/refs/sweepNN/` (+ `refs.json`) and lists, per sweep,
any photo missing a preset and any export that is wrong (wrong folder, not full size, cropped,
masked, a preset clicked twice). Exit 0 means complete. Re-export only what it lists and run it again.

## Still to come
**Sweep 13 (Adaptive Sky / Subject masks)** waits for one masked preset saved from the Lightroom UI
(Presets ▸ Create Preset with a Sky mask and one local slider): send the `.xmp`.

The lists are picked by `Tools/parity/sweep_photos.py` from the Death Valley 156 and the portraits set.
The pools have no buildings, so sweep 10 uses the frames with the most straight lines (window
frames, horizons). Add up to 20 architecture frames (any Sony ARW with lens corrections on in the
camera) to the sweep10 album if you have them.
