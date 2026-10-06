# CHANGES v0.05 (Sets v11 + Edit v22): release round 2

Sets v11 and `lumina-core-v4.js` changed; Edit v22 didn't. **Port `buildShoot` again.** The new behaviour in `onDir` (unreadable files kept) must also go into the app's own `onDir`/`readOne`, since the app replaces both.

## B1. Photos Lumina can't show (Prompt 3 A, v0.02 "6b/7a")
- **Kept, never dropped.** When `readOne` throws, `onDir` now keeps the file as a photo instead of dropping it:
  - the record is `{unread:true, nopv:true, name, path, bytes, fileObj, xpath, xmp, date:''}`, plus zero measures;
  - it is still listed in `_failed`, so the ? list doesn't change;
  - a folder where *nothing* can be read keeps the old `0 photos · N unreadable`.
- **Tile** (`[data-lumina=tile-nopic]`): the grey tile shows the file number with a second line under it (10 px, `#7D7971`): `no preview` or `can't be read`. The tile words read the same.
- **Large view:** the info line reads `DSC00203 · can't be read · 0 KB`. A missing preview still reads `· no preview in this file`.
- **Counts:**
  - The Open line reads `500 photos · 41 rows · 12 stacks · 3 without a picture` (no preview + can't be read) and no longer says `N unreadable`.
  - Import notes: `2 without an embedded preview · shown as grey tiles`, `1 can't be read · shown as a grey tile · see ? for the list`.
  - Other failures (e.g. a sidecar over 1 MB) show as `N not read · see ? for the list`.
- **Core:**
  - A photo without a capture time goes right after the photo with the nearest lower file number, in that photo's row. There is never a `00:00` row and never a gap label worked out from a missing time.
  - Rows after it are still split against the last photo that has a time.
  - Unreadable, no-preview and no-time photos are always singles, never joined to a stack or ranked as sharpest.
  - Records gain `unread` and `notime`. `sec` is `''` when there's no time.
- **Keys and Save:** P, R, F, ⌘A, undo and paint work on these photos as on any other. A kept one gets its sidecar. A failed write is listed with its reason (v0.04 wording).
- **Tests:** two new cases (no-time placement, unreadable is a single). There are 21 §9 cases now.

## C2. Export JPEGs with the look (Prompt 1 §7)
- **Save card** (`[data-lumina=handoff-jpeg]`):
  - A checkbox `Also export JPEGs with the look`.
  - When it's on: a segmented control `2048 px · Full size` and `JPEG/ next to the sidecars`. In a browser it reads `JPEG export needs the app`.
- **Button:** `Save 88 picks + JPEGs`, or `Save 51 photos · 3 passes + JPEGs`.
- **Write:** after the xmp write, `writeInto(files, 'jpeg')`. Each file is `{name:'JPEG/DSC03311.jpg', look:{src:<path>, look:<canonical look string>, px:2048|null}}`.
  - The look comes from Edit's store: the photo's own look, else its stack's. It's `''` when the photo is as shot.
  - The xmp payload hasn't changed.
- **Result:** `88 saved · 88 JPEGs · JPEG/ · rendered with RAW 9` (the decoder comes from the write result). JPEG errors join the error list. In a browser: `· JPEG export needs the app`.
- The look is never written into an XMP.

## Checked
- The logic class parses; the page loads with an empty console.
- Save: the checkbox shows the size control, and the button gains `+ JPEGs`.
- `buildShoot` on a 5-file mix with one unreadable file: one 15:10 row of 4, then 18:00; the unreadable photo is a single.
- I couldn't drive grey tiles in the browser (it needs a damaged ARW). Use the forged fixtures from probe `edge-corrupt-preview`.

## Still open
- Before release: A3 (pre-sandbox sessions: needs the app's call name) and D1 B/C (`lumina.sidecars` refresh at Save).
- Fine to ship after: B5 c calmer growth, B3 B/C/G, B4 a, B6, B7, C1, C3, D4, D5.
