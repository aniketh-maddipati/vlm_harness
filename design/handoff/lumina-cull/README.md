# Lumina v5 · handoff for an exact-parity build

Start with **PROMPT.md**, then **ADDENDUM-1.md** (it overrides where they differ).

| File | Role |
|---|---|
| PROMPT.md | the brief, guardrails, definition of done |
| PARITY.md | screen-by-screen spec: every element, string, colour, size and motion value |
| GRAMMAR.md | every key, click, drag and gesture (same text as the ? sheet) |
| CHANGES-v4-beta.md | how each behaviour works, with console checks |
| MENUS.md | native menu bar, Settings, About |
| SAFETY.md | file writes, autosave, card handling, permissions |
| TEST-MATRIX.md | cameras, formats and edge cases to test |
| FAQ.md | in-app FAQ text |
| Lumina Sets v5.dc.html | the reference page. Open it in a browser: it runs on a sample shoot |
| lumina-core-v4.js + .test.mjs + .fixtures.json | parsing, grouping, sidecar logic. `node lumina-core-v4.test.mjs` |
| lumina-selftest.js | grammar and performance tests. Open the page with `?selftest` |
| lumina-v4-data.js | grammar text, FAQ, sample shoot, formatters |
| plumbing.js | bridge between the page and the Mac app |
| support.js | page runtime, ship unchanged |

Reference-page flags: `?selftest` runs 22 grammar tests + 2 timing tests · `?selftest&n=1000` runs timing on 1,000 photos · `?n=1000` loads 1,000 sample photos · `?notes` shows import notes · `?oncard` shows the card warning · `?denied` shows the access banner · `?macos` shows the macOS permission sheet.
