# Lumina Ingest: agent loop (lead + workers)

Paste this into a fresh Claude Code session in this repo. Read `AGENTS.md` and `docs/dev/WORK-SPLIT.md` first; they win on conflict.

## Goal

Take Lumina Ingest (Debug-only prototype, merged in #357) from "works on fixtures" to "trusted on a real trip":
drop any cards, folders or phone exports → read → verified copy → clocks right → cull in Pick. Test as you go.

## Roles

```
Lead (this session)                    Workers (one per task, own worktree)
  plan → split → brief ──────────────►   build on own branch, test headless
  review diff + reports ◄──────────────   commit, report (no push, no merge)
  merge into integration branch
  run checks + in-app test (hot app)
  one push → PR → owner merges
```

- **Lead** owns the integration branch, the hot app (`bash Scripts/dev-ingest.sh --watch`, one watcher), all merges, all pushes and the single PR. It drives the app (computer use) for end-to-end tests.
- **Workers** each get one task, a worktree cut from the integration branch, and a brief that names the files, what "done" means and how to check it. They commit on their own branch and report. They never push, open PRs, merge into any other branch, run `dev-ingest.sh`/`dev.sh`, or take on work outside their brief (no cleanup, no disk housekeeping, no "while I'm here").
- At most 3–4 workers at once. Workers whose files overlap run one after another, not in parallel.

## Rules that kept biting (from the first round)

- **The page file is shared.** Put new logic in its own file (`design/handoff/lumina-ingest/lumina-ingest-<topic>.js` + a Node test). Keep edits to `Lumina Ingest v1.html` to a few lines; list the new file in `SetsSchemeHandler.pageFiles` (Debug) and `Scripts/dev-ingest.sh` `FILES`.
- **Invent nothing visual.** UI is built only from parts the Stills page (`Lumina Sets v12.dc.html`) already has.
- **Trust.** Never write to a source or card, copy never move, SHA-256 verify every copy, nothing leaves the Mac. Any new bridge op or reach needs a `docs/release/TRUST.md` row; `python3 Scripts/trust_check.py` passes.
- **Release unchanged.** Every native change is `#if DEBUG` and gated on `SetsPage.isIngest`.
- **Page in the app ≠ page headless.** `host` (`window.webkit.messageHandlers.lumina`) exists only in the app; ⌘/keys may be taken by the native menu; focus can sit on hidden elements. Anything with keys or the bridge needs an in-app check by the lead.
- **zsh doesn't split `$X`**: pass test lists as `${=X}`. Scratch dirs under `/private/tmp` get swept; keep fixtures in `~/LuminaEvidence`.

## Testing as you go

| Level | Who | Command |
|---|---|---|
| Logic (JS) | worker | `node design/handoff/lumina-ingest/*.test.mjs` |
| Page headless | worker | Playwright on the page + `~/LuminaEvidence/fixtures` (see `Tests/web/ingest-clocks.mjs`); `window.__ingest.state()` |
| Swift | worker | `python3 Scripts/test_guard.py run --name <n> --limit 900 -- xcodebuild … -only-testing:LuminaLogicTests/<Class> test` |
| Repo gates | worker + lead | `trust_check.py`, `page_bytes.py` (12/12), `node Tests/web/plumbing-harness.mjs` |
| In app | lead | hot app, `~/LuminaEvidence/ingest-test/Trip/{CardA,T7copy}`, library `~/LuminaEvidence/ingest-test/library` |
| CI-equivalent | lead, before the one push | `git diff -z --name-only origin/main... \| xargs -0 python3 Scripts/ci_changes.py`, run its `xctest=` list |

A worker is done only when its checks pass and its report says what was **not** checked.

## Report format (workers → lead)

```
branch · commit
done:      one line per behaviour, with numbers
checked:   commands run + result
not done / not checked: …
files touched: …
```

## Backlog (lead splits these; owner decides product questions)

1. Real card end to end: 1,000+ files, two cards plus a T7 copy. Read speed (files/s), copy MB/s, memory, "safe to format" only for a whole card. **Needs the owner present** (card + full-screen control).
2. Two sources opened in Pick from the library, checked in the app.
3. Clocks: dates for HEIC and clips, EXIF `OffsetTime*`, FeaturePrint matching through a native op (measured ≤ 0.35 ⇒ 95 % precision).
4. Card pulled mid-copy: pause, resume on reinsert, no partial file left under a final name.
5. Speed: native listing + head reads for big cards (the page's File API read vs `SetsIngest`), parallel readers per source.
6. Clips: read in Ingest, hand-off to Skim (Pick is photos only).
7. **Owner calls, not agent calls:** whether Ingest becomes Stills' Open step; the library layout (trips, days); whether anything leaves the Mac (Elorian).

Start by reading #357's description, `git log origin/main -- design/handoff/lumina-ingest Lumina/Sets/Core/Ingest*`, then propose the first split (≤ 4 workers) to the owner before starting any.
