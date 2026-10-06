# PARITY v0.05: what the app needs for an exact match

The page is the source of truth. Ship these files byte for byte, then re-record the screens listed in §5.

## 1. Page files (ship byte for byte)
| File | Bytes | CRC32 |
|---|---|---|
| Lumina Sets v11.dc.html | 333572 | fe1cbd4e |
| Lumina Edit v22.dc.html | 203471 | 4d68cb9b |
| support.js | 69150 | 181800d2 |
| lumina-core-v4.js | 32438 | 3edd5a5c |
| lumina-v4-data.js | 20721 | f25850da |
| lumina-measure.js | 3955 | 560c21ac |
| lumina-selftest.js | 8956 | 1e8e3366 |

- Sets mounts Edit as `<dc-import name="Lumina Edit v22">`, so the file name must be exactly `Lumina Edit v22.dc.html`, next to Sets.
- Edit loads `./lumina-core-v4.js` itself (it's de-duped with Sets).
- Remove the old copies: Sets v8, v9 and v10, and Edit v21.
- Not shipped: `data/lumina-shoot-unsplash.js` (only for `?shoot=unsplash` in the browser).
- CRC32 is the zip CRC (`LuminaCore.crc32`).

## 2. Sample images
- `uploads/`: the 95 JPEGs named in `lumina-v4-data.js` → `SAMPLE_IMGS`. They are byte-identical to the v0.01 handoff and haven't changed since. Keep the app's copy.
- They aren't in this zip: they come to about 1 GB at full size, and shrinking them would change every Pick and large-view pixel.
- If a fresh checkout needs them, copy `uploads/` from the v0.01 handoff.

## 3. Capture rules (so both sides draw the same thing)
- **Page area:** 1440 × 872 and 1920 × 1052 (standard title bar, decision 9a).
- **Before each scenario:**
  - set `lumina-v4-toured = '1'` (or call `tourEnd()`);
  - use `?selftest` when a run must not read or write the session.
- **Snapshot after the page has settled, not after fixed delays:**
  - **Pick:** after the `leadReady` event (`luminaState().leadReady`).
  - **Edit:** after `luminaPresented(seq)` for the newest `luminaState().native.seq`.
  - **Save:** after `workingFiles()` has answered (the meter shows no number until then).
- **The storage meter:** no clock decides what it draws any more, so the `_cpAt = 0` step comes out of `screens-*.json`. `08-cull-skip` should now match without it.
- **Fonts:** system fonts only (SF Pro Text; Iowan Old Style for titles). Capture the prototype in WebKit (Safari or WKWebView), not Chromium, for 0 px.
- **Reduce Motion:** set it the same on both sides. The tile-size animation and the stack unfurl follow it.

## 4. App code to update to match the page
| Area | What to change | Where specified |
|---|---|---|
| `build` override | Build from `this.shifted()`, not `this.real` | CHANGES-v0.04 · Shift |
| Session | Persist `luminaState().shifts`. On reopen, set `this._shifts` before the first build | CHANGES-v0.04 · Shift |
| `onDir` / `readOne` | Keep unreadable files as `{unread:true,nopv:true,…}`. They stay in `_failed`. `0 photos · N unreadable` only when nothing can be read | CHANGES-v0.05 · B1 |
| `lumina-core-v4.js` | Port `buildShoot` (no-time placement, unread singles), `addKw` (`lr:hierarchicalSubject`), `lookString` / `parseLook` | CHANGES-v0.03, v0.05 |
| `writeInto(files,'jpeg')` | `{name:'JPEG/…jpg', look:{src, look, px:2048\|null}}`. Return `{n, errors, decoder}` | CHANGES-v0.05 · C2 |
| Hooks to call | `luminaOpening`, `luminaNotice`, `luminaWorkingFiles`, `luminaStep`; `lumina.cutShort` before load; `lumina.notices()`; `lumina.cardPending` | CHANGES-v0.04 |
| Edit canvas | `canvasRect` / `preview` / `drag` / `roi` / `prefetch`, answered via `luminaPresented` / `luminaHistogram` / `luminaFacts` | BRIDGE-v0.03 §1 |
| Result reasons | Return `reason` as one of: `changed on disk`, `unreadable`, `name too long`, `locked`, `read-only`, `missing`, `disk full`, `failed` | CHANGES-v0.04 · D1/D2 |

**plumbing.js blocks to delete** (the page does these now): `rowKeys`, `readyTile`, `lead`, warm-ahead (c), `readMoved` / stay handling, `pollRect`, the Save `wf` block, and the Prompt 6 `openNote` / `say` stand-ins.

## 5. Screens that change and need re-recording
| Screen | Why |
|---|---|
| Every Save screen | New row: `Also export JPEGs with the look` (unchecked); the button gains `+ JPEGs` when it's checked |
| Pick screens with a no-preview tile (`edge-*`) | Second line `no preview` / `can't be read` on grey tiles; the Open line says `N without a picture` |
| Pick or large view with a long-exposure frame | The `shake` word is gone |
| `08-cull-skip` | The meter now settles. It should match without the workaround |
| Edit screens (app) | Native canvas: the box is transparent and the facts line gains `canvas: native · raw 9: …` |
| **Unchanged** | Open (unless `luminaOpening`, `cardPending` or `cutShort` is set), the keys tutorial, FAQ, tour |

New screens worth adding:
- the shift sheet (`luminaCommand('shiftTime')` on a real two-body shoot);
- Acknowledgements (`luminaCommand('acknowledgements')`);
- Open with `luminaOpening({name})` after 3 s;
- the card in the not-opened-yet state.

## 6. New `data-lumina` markers
`row-gap`, `tile-nopic`, `handoff-jpeg`, `shift-sheet`, `shift-offset`, `shift-preview`, `acks`, `opening-slow`, `cut-short` (Sets) · `decoder-note`, `rendering` (Edit).

The v0.02 markers are all unchanged (contract §2.7).

## 7. Tests that must pass
- `node lumina-core-v4.test.mjs`: no FAIL (21 §9 cases + the originals).
- `?selftest`: every check passes. P on a kept photo moves on, steps are reported, rows have keys.
- `probe.sh contract`: the calls and hooks in BRIDGE-v0.03 and CHANGES-v0.04/05.
