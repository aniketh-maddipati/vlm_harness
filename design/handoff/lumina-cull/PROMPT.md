# Brief: build Lumina v5 to exact parity

You are building the Mac app's culling UI so that it matches `Lumina Sets v5.dc.html` exactly: same behaviour, same strings, same layout and motion. The page in this folder is the reference. Open it in a browser and use it side by side while you work.

## Order of truth
1. ADDENDUM-1.md
2. PARITY.md
3. GRAMMAR.md
4. `Lumina Sets v5.dc.html` (read its source when a detail is not written down)
5. CHANGES-v4-beta.md, SAFETY.md, MENUS.md

If two disagree, the earlier one wins. Nothing outside this folder is a reference.

## How to build
- Rebuild cleanly from the spec. Do not copy the reference page's logic class wholesale: it was built with many small patches. Keep its behaviour, not its structure.
- Split into modules: layout (rows, stacks, open-stack lines, virtual scroll) · keys · large view · save · import · settings · overlays (? sheet, FAQ, permission sheet, tooltips).
- Keep the `window.lumina` contract and `plumbing.js`. Keep the `data-lumina` attributes and `window.luminaState()` so `lumina-selftest.js` runs unchanged against your build.
- Port `lumina-core-v4.js` as is. Change it only to fix a failing fixture, and say which.

## Guardrails. Stop and ask instead of doing any of these
- Adding a key, setting, dialog, animation, colour or string that is not in PARITY.md or GRAMMAR.md.
- Bringing back anything removed: reject / X, U, stars, colour labels, multi-select, marquee, resolve-on-leave, tile facts, dimming, the large-view info line, the Lightroom / Capture One picker, the proof chips ("0 deleted" etc.).
- Wording that implies Lumina controls Lightroom or Capture One. It writes sidecar files and nothing else.
- Writing to RAW files, or writing anything to a mounted card.
- Network calls of any kind. The FAQ promises none.
- Copy with em dashes, exclamation marks, or words like "safe", "easy", "smart", "just", "simply", "magic", "effortless".
- Spending more than 15 minutes on one failing check. Stop and report the check, what you saw and what you tried.

## Definition of done
- `node lumina-core-v4.test.mjs` prints no FAIL.
- `?selftest` against your build: every behaviour check passes, key-to-frame median under 50 ms, large view opens in under 100 ms.
- On a 1,000-photo folder: first rows under 2 s, ↓ and → medians under 50 ms.
- Every checkbox in PARITY.md ticked, checked against the reference page side by side at 1440×900.
- SAFETY.md items 1 to 6 implemented and each tested once by hand.
- Report: files changed, test output, perf numbers, and every decision you made that the spec did not cover.
