# Lumina Ingest: continuation (written 2026-11-13)

Start a new loop from this file plus `docs/dev/INGEST-AGENT-LOOP.md` (roles and rules) and `AGENTS.md` (wins on conflict).

## Where it stands

Branch `claude/ingest-one-a7bf8b` (worktree `.claude/worktrees/ingest-one-a7bf8b`), six commits on top of main `f72fa6c5`,
**not pushed, no PR**:

| Commit | What |
|---|---|
| `f1d5c801` | first attempt at safety risks A to E (another session) |
| `495f3010` | A to E reconciled; a test that `f1d5c801` left failing fixed |
| `3f430433` | cards that are in and usual folders open from the page (`ingestSources`, `ingestOpen`, C key) |
| `fb35d5bd` | shoots from gaps + split / merge / undo + names; opt-in folder pattern, copy waits for `I` |
| `9a879794` | verified copies hold one 4 MB block, not every byte read (the 76 GB memory growth) |
| `e557c81b` | packages (`.fcpbundle`, `.photoslibrary`, …) copied whole |

Checked (all light, no Xcode): `IngestCopyTests` 17/17 in a two-file SwiftPM copy, `IngestHost` typechecked against stubs,
`trust_check.py`, `page_bytes.py` 12/12, `lumina-ingest-shoots.test.mjs`, `Tests/web/ingest-{sources,shoots,clocks}.mjs`.

**Never done on any of the six commits:** an `xcodebuild`, the hosted logic tests (`SetsFileOpsTests` included), one run in
the app, one real card through the app. The line added to `SetsRootView.runOpenPanelWith` has never been compiled.

## The card copy (outside the app)

`~/LuminaEvidence/ingest-card-t7/tool/cardrun` copies `/Volumes/Untitled` → `/Volumes/T7/Lumina/ingest-card-2026-11-12`,
log `run4.log`, record `library.json`. Rebuilt from `9a879794`; 34 MB resident after 3 minutes (was 76 GB).
- The T7 cannot take the whole card: about 83 GiB was left on the card, 69 GiB free, the tool keeps 10 GB. Expect about
  24 GiB logged `NO ROOM`. **The card is not safe to format.**
- One broken link on the card (`C0002.fcpbundle/…/C4815.mp4`) has no data behind it.
- A 365 MB half-written `.lumina-tmp-…` sits in `2026-09-09/` on the T7 from the run that was killed.
- The tool plans its own folders (file time, not EXIF; no shoots, no pattern, packages file by file). What is on the T7
  is the tool's layout, not the app's.

## What went well

- No copy ever wrote to the card; every copy is SHA-256 checked; a rerun picks up where it stopped.
- The whole-card count for "safe to format" fails safe in every odd case found (same-named folders, links, late files).
- Light checks made progress possible while builds were off limits: a two-file SwiftPM package, a stubs typecheck,
  headless page harnesses with a stand-in for the Mac side.
- The memory bug was found by reading the loop, then proven with a before / after measure (2.43 GB → 12 MB on 768 MB).

## What went wrong

1. **Two sessions fixed the same five risks in the same six files at once.** One writer per file was the rule and was
   not held. Cost: a reconcile pass and a discarded attempt.
2. **A commit said "22 tests passing" with a failing test in it.** Reports were trusted over runs.
3. **A long copy of a real card was started with a tool nobody had run small first.** It held every byte it read,
   ran a 24 GB Mac to 76 GB resident and 80 GB of swap, and was killed twice. No memory watch, no size check of the
   destination (it never had room for the card).
4. **Sessions acted on the same process without a shared note.** One reported "still running" minutes before another
   stopped it on the owner's word.
5. **Four features are stacked on a branch that has never been built or opened in the app.** The card copy blocked
   builds all day; work went on anyway. Each is tested headlessly only, and keys in the app can be taken by the menu.
6. **The first draft of the package copy put a broken link in the wrong place and dropped unknown entries quietly.**
   A test caught it. Paths made standard differ for a link that points nowhere; walk by name.
7. **Shoot thresholds (6 h / 2 h / 36 h) were proposed and built without a measure on real shoots.**

## Next, in order

1. When `cardrun` ends: read the last line of `run4.log` and its `NO ROOM` / `NOT COPIED` lines, tell the owner what is
   still only on the card. Ask before removing the temp file or freeing T7 space. Nothing else touches the card or that folder.
2. Build and run the logic tests (`python3 Scripts/test_guard.py run --name ingest-logic --limit 900 -- xcodebuild …
   -only-testing:LuminaLogicTests/IngestCopyTests -only-testing:LuminaLogicTests/SetsFileOpsTests test`), then the
   classes `Scripts/ci_changes.py` names. Fix what the compiler finds.
3. In the app (the lead, one watcher, owner present): the sources line and `C`, a card going in, shoot headings and their
   name fields, split / merge / undo, the pattern editor, `I`, a package, a library unplugged mid-copy.
4. Measure the shoot thresholds on the owner's real capture times; change the numbers in `lumina-ingest-shoots.js` only.
5. Open items: no retry for "not copied" after a lost library; shoot names and corrections are forgotten on reload;
   a split is only offered at the start of a part; companions of an "other" file can be copied twice; `cardrun`'s own
   planning should be replaced by the page's (or dropped).
6. One push and one PR, on the owner's word.

## Rules to add to the loop

- A report is checked by running it. No "N tests pass" without the command and its output.
- Any run on real media: first the same binary on a small folder with peak memory read (`/usr/bin/time -l`), a check
  that the destination has room, and a watchdog that stops it past a memory limit.
- Anything started outside a session gets a line in the shared notes: what, pid, who may stop it.
- No feature after the second one that has not been built and opened in the app.
