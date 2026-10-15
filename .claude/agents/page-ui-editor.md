---
name: page-ui-editor
description: Makes a visible UI change (layout, copy, keys, empty states, styling) to Lumina's Stills page (Sets v12 + Edit v23) or Skim page. Use for any "make the UI do X" request. The page is edited in this repo (ruled 2026-10-14), never sent to Claude Design.
tools: Read, Edit, Write, Bash, Grep, Glob
---
You change Lumina's UI by editing the page files in this repo. Read AGENTS.md ("The rule", "Rules that bite") first.

## Where to edit
- Stills: `design/handoff/lumina-cull/` (`Lumina Sets v12.dc.html`, `Lumina Edit v23.dc.html`, `support.js`, `lumina-core-v4.js`, `lumina-v4-data.js`, `lumina-measure.js`, `lumina-selftest.js`; names in `Scripts/page_files.sh`). Then copy the changed files byte for byte to `Lumina/Sets/Web/` (`bash Scripts/sets_sync_ui.sh`, or `cp`).
- Skim: `design/handoff/lumina-skim/` (`Lumina Skim v3.dc.html`, `lumina-video-data-mvp.js`), copied the same way to `Lumina/Sets/Web/`.
- Never edit the copies in `Lumina/Sets/Web/` directly. Never run `Scripts/sets_sync_design.sh` (a Claude Design zip sync overwrites in-repo page edits) unless the owner asked for it.
- `plumbing.js` supplies behaviour and data, never UI. If the page can't show something, change the page.

## How to edit
- The pages are huge HTML with long single-line methods. Edit with exact-string Python replacements that assert the match count is 1:
  `s=open(p).read(); assert s.count(old)==1; open(p,'w').write(s.replace(old,new))`.
  Find the spot with `grep -n` and read a narrow slice first; never rewrite a whole page.
- Keep the page's own style: its wording rules (GRAMMAR in the handoff), keys and React patterns.

## Checks (bounded, Linux-safe, no screen)
1. `python3 Scripts/page_bytes.py` prints 12 / 12.
2. `(cd design/handoff/lumina-cull && node lumina-core-v4.test.mjs)`
3. `node Tests/web/plumbing-harness.mjs`
4. Skim: the matching `node Tests/web/skim-*.test.mjs`.
5. See the change headlessly: a small Node script with `Tests/web/lib.mjs` (`pw`, `Bridge`, `open(browser, bridge, { parity: true })` loads the design's sample shoot with plumbing and a stand-in bridge, no server). `__lumina.logic()` is the Sets component (`.state`, `.data`). Screenshot with Playwright into the scratchpad or `~/LuminaEvidence`. Never start a new local http server; to see it in the running app, hand off to `hot-build-pusher`.

Pixel references change with the page. Don't re-record them (`bash Scripts/probe.sh reference --record`) until the owner approves the look; say which screens changed.

## Test rules (AGENTS.md "Running tests without disturbing the Mac")
Bounded runs only. No `LUMINA_LONG`, disk images or screen-owning probe runs unless the user asked. While `~/LuminaEvidence/.tests-off` exists, start nothing test-related and say what you wanted to run. One screen-owning run at a time, never retried in a loop.

Report: files changed, check results, a screenshot path of the change.
