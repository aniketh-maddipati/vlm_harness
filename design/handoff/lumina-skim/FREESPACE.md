# Skim free space: move cut clips to the Trash (branch video/skim-freespace) — DRAFT

Draft written by the orchestration thread from the user's brief on 2026-10-08; the first chat here should correct it.
Worktree `~/vlm_harness/worktrees/skim-freespace`, cut from `video/skim-mvp`. Read THREADS.md first.

## Goal
After a sorting pass, the clips marked cut can be moved to the Trash, so the space is his again. Mac app only.

## Must hold
- Only from his desktop dump (a folder on a drive he owns). Never a card: a camera card, a read-only volume, or
  anything under a `PRIVATE/M4ROOT` card layout is refused, in plain words. The browser build never offers it.
- Show the GB that will be freed first, with the number of clips, before anything moves.
- A confirm screen: what moves, from where, how much, and that it can be put back from the Trash.
- Undoable from the Trash: use the system Trash (put back works); never delete, never empty the Trash.
- A bridge op for it, listed in `docs/release/TRUST.md` (writes table), with `Scripts/trust_check.py` passing.
- Sidecars (`M01.XML`) travel with their clip. Marks are kept so an undo restores the state.
- Neutral words on screen: selected / maybe / cut. The action reads "Move cut clips to Trash".

## Owns
The bridge op and its Swift side, the confirm screen in the page, and their tests. Not the grid (skim-canvas),
grouping, Rec.709, ingest, or export. Merge video/skim-mvp before page edits; keep the two page copies byte-equal.

## Tests
- Pure logic (what is eligible, what is refused, the GB sum) in LuminaLogicTests and the Linux runner.
- The card refusal, with a fixture laid out like a card and a read-only volume.
- The page's confirm screen against a fake bridge in `Tests/web`.
- By hand, on a scratch folder of copies only: move, check the GB, Put Back, check marks. Never on /Volumes/Untitled
  or the T7 (both are read only for every thread).

## Open questions for the user
- Is "maybe" ever included, or cut only? (Draft: cut only.)
- Should the export to Final Cut be required first? (Draft: no, but say so on the confirm screen.)
