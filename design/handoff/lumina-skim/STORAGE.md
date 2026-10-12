# Skim storage: one line, five things, a dump and a refresh for each (branch video/skim-storage)

From the user's brief of 2026-10-12. Worktree `~/vlm_harness/worktrees/skim-storage`, cut from `video/skim-mvp`.
Absorbs FREESPACE.md: its "move cut to Trash" is item 3 here, built once.

## Goal
As a shoot gets larger, five things fill up. Each shows in one storage line in the footer, can be dumped or
refreshed with one button, and work continues while it happens. Nothing is emptied or deleted without a click;
Skim never empties the Trash. Marks are never part of any dump.

| # | What fills up | Figure | Dump | Refresh | State |
|---|---|---|---|---|---|
| 1 | Frames in memory (`frameSz` sum + `thumbs`) | MB of the limit | Drop frames (covers stay) | Make frames again | step 1, merged (PR 238) |
| 2 | Saved covers and measures (reopen is instant) | MB on disk, shoots held | Clear for shoots not open | Re-measure this shoot | step 2, built for the browser; the app's container next |
| 3 | Cut clips still on the drive | GB, clips | Move cut to Trash: scene / day / shoot | Put back | step 4, Mac app |
| 4 | Trash on each drive | GB waiting | Show in Finder (he empties) | Re-read size | step 3, Mac app |
| 5 | Final Cut's generated media | GB per library | Show size, point at Final Cut's own Delete Generated Library Files | Re-read size | step 5, findings first |
Free space per drive is the read-out all five feed, not a sixth item.

## Steps (each ships by itself)
1. The line, from item 1 only (page, browser too): `Component.storeLine(parts, fmtB)`, `Component.dumpSay(kind,
   bytes, n, fmtB)`, `Component.farFrames(clips, at, cover)` (the plan) and `dropFar()` (carries it out).
2. Item 2: covers and first measures persisted by clip identity (name + capture time + size, INGEST.md item 4):
   IndexedDB in the browser, the container in the app; capped, least-recently-opened shoot evicted first; the clear
   button in the same change. Hooks into `runQueue` / `readClip` agreed with skim-ingest.
3. Free space and item 4 (Mac app): a read-only bridge op per drive a shoot's clips are on: total, free,
   purgeable, Trash size. Fills `d.shoot.free`. Forecast lines on the action they concern.
4. Item 3 (Mac app): FREESPACE.md, with the scope (scene / day / shoot) and "N GB free once you empty the Trash".
5. Item 5 (Mac app, last): find out on a scratch library how Final Cut 12.4 lays out generated media and whether
   sizes can be read without opening it. Report before building.

## Hooks into the reading code (skim-ingest owns runQueue / readClip)
Two lines and no more: `importFiles` waits for `coverLoad(d)` before `runQueue`, and `runPass` calls `coverNote(c)`
after a clip's first-pass read succeeds. A clip restored from saved covers already has its cover frame, so the first
pass passes over it (its `idxOf` answers `[]`); the fill reads its other frames where he looks, as before.

## Must hold
- No dump blocks keys, scrubbing or marking; no main-thread task over 100 ms.
- The clip on screen and its neighbours (the 24 around it) are never dumped by any button.
- Automatic only for item 1 (`enforce()` at the limit). Everything else waits for a click.
- Every button says what it gives back before the click; the line updates after.
- Never on a card (camera card, read-only volume, anything under `PRIVATE/M4ROOT`), refused in plain words.
  Never delete; the system Trash only; never empty it.
- Under 20 % free on any drive: one plain line. A copy that cannot finish is refused before it starts. No pop-ups.
- Plain free space, purgeable mentioned, so the figure agrees with Finder.
- A row in `docs/release/TRUST.md` per bridge op; `Scripts/trust_check.py` passes. No network. Neutral words.

## Answers taken as defaults (the user's drafts)
- Only cut clips move to the Trash, never maybe.
- The Final Cut send comes before cut clips move, and the line says so.
- The storage line shows in the web preview with the items that exist there (1 and 2).
