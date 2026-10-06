# Lumina v0.02: handoff

Start here. Then read **CHANGES-v0.02.md** (everything that changed since v0.01, with exact behaviour), **BRIDGE-v0.02.md** (new native calls) and **NATIVE-EDIT.md** (render and cache plan). BRIDGE.md, TEST-PLAN.md and ROADMAP.md from v0.01 still apply where these don't override them.

## About these files
The `.dc.html` files are **high-fidelity, working references** written in HTML. They are the spec: behaviour, copy, layout, motion and the JS logic are final for v0.02.

The plan is the same as v0.01: host the page in the Mac app's WKWebView unchanged, and replace its browser I/O with `window.lumina` calls. If you rebuild any part natively instead, match the reference exactly, and read the source for any detail that isn't written down.

The JS is meant to be ported **exactly**:
- `lumina-core-v4.js` (parsing, grouping, soft/blown, sidecars);
- the logic classes inside the two `.dc.html` files.

Open `Lumina Sets v8.dc.html` in Chrome to run everything, sample shoot included, with no network calls.

## Order of truth (earlier wins)
1. This README, CHANGES-v0.02.md, BRIDGE-v0.02.md, NATIVE-EDIT.md
2. `Lumina Sets v8.dc.html` + `Lumina Edit v21.dc.html` (Edit is mounted inside Sets)
3. BRIDGE.md, TEST-PLAN.md, ROADMAP.md (v0.01)
4. `reference/` (v5 era)

## Files
| File | Role |
|---|---|
| Lumina Sets v8.dc.html | The app: Open → Pick → Edit → Save, passes, aim, tour, keys tutorial, FAQ |
| Lumina Edit v21.dc.html | Edit step. Default render is Lightroom-match; ⇧T switches to the AgX preview. Auto comes from `lumina.auto` first |
| lumina-core-v4.js | ARW/DNG/JPEG parsing (incl. phone preview pieces and RGB thumbnails), Sony MakerNote, grouping, soft/blown, sidecars with pass keywords, zip. **Port as is** |
| lumina-core-v4.test.mjs + .fixtures.json | `node lumina-core-v4.test.mjs`, must print no FAIL. Add the cases in CHANGES §9 |
| lumina-measure.js | Pixel measures for the large view |
| lumina-v4-data.js | ? sheet grammar (shown word for word), FAQ, formatters, sample shoot |
| GRAMMAR.md | The grammar, generated from lumina-v4-data.js |
| lumina-selftest.js | Behaviour and timing checks. Open Sets with `?selftest` |
| support.js | Page runtime. Ship unchanged |
| BRIDGE-v0.02.md | New calls: auto, canvas/preview/prefetch, histogram/facts hooks, render baseline, look string, Save with passes |
| NATIVE-EDIT.md | Native RAW rendering + caching that gets deeper the further the user is in the flow |
| Handoff - Tone mapper.md | AgX port with ΔE acceptance against the `rules-v1.json` baseline |
| prompts/PROMPT-auto-backend.md | Make the app's AutoDevelop the only Auto; fixture file for the browser |
| prompts/PROMPT-8g-culleval.md | Validate the new soft/blown rules on scored shoots; turn ⇧A on only if it passes |
| Window Chrome Options.dc.html | Decision 9a: standard title bar, page 1440 × 872 |
| Phone Handoff Check.dc.html, Lumina Ingest design.dc.html | Unchanged from v0.01 |
| uploads/*.jpg | **Not included, to keep the zip small.** Copy `uploads/` from the v0.01 handoff (same files) next to Sets v8, or the sample shoot shows grey tiles |
| screenshots/ | Not included. The v0.01 captures are in the v0.01 handoff; key bar copy and the Save step differ (see CHANGES) |
| reference/ | v5 docs (GRAMMAR, SAFETY, TEST-MATRIX, plumbing.js) |

## Definition of done
- `node lumina-core-v4.test.mjs`: no FAIL, including the new §9 cases.
- `?selftest` in the app: every check passes. Key-to-frame median < 50 ms; large view opens < 100 ms.
- `probe.sh contract` sees every call in BRIDGE-v0.02.md.
- In the app, the Edit footer says "Auto ·" and never "Auto (estimate)".
- Edit opens a cached pick in < 50 ms. 100 slider events in one frame make 1 preview request.
- Save with 3 passes writes ratings 1/2/3 and `Lumina pass N` keywords. Lightroom Classic shows the keywords after Read Metadata.
- Zero network requests in a full session.
- Report: files changed, test output, perf numbers, and every decision the spec didn't cover.

## Guardrails. Stop and ask instead of:
- writing to RAW/DNG files or anything on a mounted card
- adding keys, settings, dialogs, colours or copy not in the reference
- tuning Auto or soft/blown against anything except the scored loops (LOOPS.md, culleval)
- porting the browser AgX constants
- any network call
- spending more than 15 minutes on one failing check (report what you saw and tried)
