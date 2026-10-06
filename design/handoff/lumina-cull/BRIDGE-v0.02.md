# BRIDGE v0.02: new and changed calls

These are additions to BRIDGE.md. Guard every call with `typeof lumina.x === 'function'`, so the page still runs in a browser without it. Where this file and BRIDGE.md disagree, this file wins.

## 1. Auto: one source of truth (`prompts/PROMPT-auto-backend.md`)
| Call | Native must | Returns |
|---|---|---|
| `lumina.auto(rel)` | Run `AutoDevelop.recipe(for:)` on the RAW's ImageStats (scene-linear), not on the embedded JPEG. | `Promise<{look:{ev,wb,tint,hl,sh,wh?,bl?,con?}, version}>` or `null` |

- **Units** are the Edit sliders' units: `ev` in stops, `wb` in K, `tint` and `hl / sh / wh / bl / con` on the −100…100 scale.
- **Order the page tries:**
  1. `lumina.auto`, with the footer reading "Auto · …";
  2. `window.LuminaAutoFixtures[fileName]`, with the footer reading "Auto · recorded";
  3. the page's own preview-JPEG estimate, with the footer reading "Auto (estimate) · …".

  An estimate must never be shown as the real Auto.
- **Fixture file:** `data/auto-fixtures.js` holds AutoDevelop's real output for every sample-shoot file and every ARW fixture. Regenerate it whenever AutoDevelop changes. Add its `<script>` to the helmet of Edit v21 and Sets v8 only once the file exists.
- **Same values everywhere:** arrival-auto (`autoArrive`), the A key and scene matching (`matchScene`) all use these values. Cache them per file + AutoDevelop `version`.
- **Acceptance:** the Auto loop in LOOPS.md (median |Δexposure| < 0.25 EV against the photographer's own edited XMPs). Tune against the default render (§3), never against the AgX preview.

## 2. Edit ↔ native canvas (section 11 of the design asks; native Edit rendering ships in v0.02)
Edit calls these when present:
| Call | When | Payload |
|---|---|---|
| `lumina.canvasRect(r)` | on open, layout change, resize and when something covers the canvas | `{x,y,w,h,dpr}` (the surround's inner rect, transparent in the app), or `null` when hidden |
| `lumina.drag(phase)` | slider press / release | `'start'` / `'end'` |
| `lumina.roi(r)` | while Z is held | `{x,y,w,h}` in image px, or `null` |
| `lumina.preview(rel, look, px, seq)` | at most once per animation frame | `look` is the canonical look string (§4). Returns `null` → keep the canvas box transparent |
| `lumina.prefetch(list)` | on keep, ⇧P, entering Edit, cursor moves in Edit, entering Save | `[{rel, pri:0\|1\|2, px:'screen'\|'full'}]`. Each call replaces the earlier list. Schedule as in NATIVE-EDIT.md |

Native calls these page hooks:
| Hook | Payload | Page does |
|---|---|---|
| `window.luminaPresented(seq)` | the seq now on screen | drops older pending previews (a stale result never replaces a newer image) |
| `window.luminaHistogram(h)` | `{seq,r,g,b,clipHi,clipLo}` | histogram and clipping warnings |
| `window.luminaFacts(f)` | `{canvas, raw9, decoder, note}` | facts line names the decoder ("RAW 9"). In `note`, "update shoot" links to `lumina.edit.updateDecoder()`. While `raw9` is true, hide Colour NR, Detail and Moiré |
| `window.luminaEditStats(s)` | timing counters | probe only |

- Noise reduction (`nr`) is applied on release, not while dragging.
- `raw9` / "RAW 9" is macOS's RAW decoder (CIRAWFilter decoder version 9). A decoder version change invalidates only the render cache, never the linear cache (NATIVE-EDIT.md).

## 3. Rendering baseline
- **Default render:** the Lightroom-match ruleset `rules-v1.json`, scored on photos it wasn't tuned on at ΔE median 2.32 / worst 5% 7.82. Edit v21 now starts in this mode in the browser too (`state.tm='match'`).
- **AgX tone mapper:** opt-in with ⇧T until it beats that baseline within +0.05 median / +0.10 p95 ΔE ("Handoff - Tone mapper.md").
- **The browser AgX** (log window −10…+1 with a mid-grey power fit) is **browser only; do not port it**. The native window is −12.47393…+4.026069 stops on scene-linear input.

## 4. Look string
- Store one canonical look string per photo, plus `rowLook` per row, in Edit v21's own key set (Edit v21 `static ALLS` / `SL`: `ev, wb, tint, hl, sh, wh, bl, con, sat, vib, sat_<colour>, cMid, cDark, cLight, vig, vRound, …, crop, rot, curve*`).
- The app translates nothing (remove the `plumbing.js` translator).
- Round-trip test: parse → format → parse gives the same look.

## 5. As-shot white balance
- Fill `wbK` (Kelvin) and `wbTint` on each photo record passed to `onDir`.
- Sets passes them to Edit as `wbShot` / `tintShot`. Without them, every photo starts at 5500 K / 0.

## 6. Save
- **One pass:** `.xmp` rated with the Settings rating, as before.
- **Two or more passes:** every photo that made at least pass 1 gets:
  - `xmp:Rating` = the last pass it made (capped at 5);
  - the keyword `Lumina pass N` in `dc:subject`;
  - `Lumina|pass N` in `lr:hierarchicalSubject`.
- Existing sidecars: earlier `Lumina pass` keywords are replaced. Other keywords and all edits are kept.
- `LuminaCore.freshXmp(rating,label,dev,kw)` and `mergeXmp(src,rating,final,kw)` do this. Port both exactly.
- DNG picks are still copied to `Picks/`.
- `readOne` now tries each embedded preview candidate in turn, and the first one that starts with FF D8 wins. probe.sh `contract` will flag the drift: update ONDIR and culleval's READONE.

## 7. Window chrome (decision 9a)
- Standard title bar. The page area is 1440 × 872 under it, and nothing in the page moves.
- See `Window Chrome Options.dc.html` (9a is marked chosen).
