# CHANGES v0.04 (Sets v10 + Edit v22): release round 1

**Fix first:** the v0.03 Sets v9 had a syntax error in `onCard()` (a `//` comment swallowed the rest of the line), so its logic class failed to load. It's fixed in Sets v10 and in v0.03's copy of v9. Re-sync from this handoff.

Everything below is in **Lumina Sets v10.dc.html**. Edit v22, lumina-core-v4.js and the tests haven't changed since v0.03.

## Also fixed
- Since v0.03, a stray network request went out for the literal `{{ p.src }}` on every launch. The tile `<img>` is `loading="lazy"` in the template again, so the streaming parse never fetches it, and `eagerTiles()` switches mounted tiles to eager, so the no-blink fix from ask 7b stays. The load log is clean again.

## Done this round (REMAINING-v0.03 ids)
| Id | What | How the app uses it |
|---|---|---|
| A1 | Opening state | `window.luminaOpening({name,onCard})` / `luminaOpening(null)`. Open shows `Opening <name>…` after 400 ms in the live line, and `the disk is waking up` under it after 3 s. Esc clears it and emits `openCancel` (drop the late listing); ⌘O still works. A read starting clears it. |
| A2 | Card not opened yet | With `lumina.cardPending` set and no `lumina.card`, the card panel reads `<name> · not opened yet` / `The Mac asks once per card. After that it opens at once.`, with one gold button `Allow & open…` → `impStart()`. The Edit button is hidden. |
| A4 | Folder too big, sidecar over 1 MB, session too big | `window.luminaNotice(kind, info)`. `tooBig` / `tooDeep` set the Open line to `not available · <folder> · over 100000 files · open one shoot` (or `folders over 12 deep`). `sidecarBig` adds `<name> · sidecar over 1 MB, not read` to the ? list. `sessionBig` puts `decisions not saved · session too big` in the footer. plumbing's stand-ins can go. |
| B2 | Shift capture time | See below. |
| B3 F | `shake` word removed | It's gone from the tile words and the large view's sense line. The shutter speed stays in facts. (The suggested-keeps logic still reads `f.shake`; it's off with ⇧A anyway.) |
| D1 A, D2 | Result reasons | `Component.REASON` words: `changed on disk · left as it is · ⌘⏎ saves it again`, `sidecar can't be read · left as it is`, `name too long to save`, `read-only disk`, `disk full`, `locked`, `missing`, `couldn't be written`. Add them to SAFETY.md 6. |
| D3 | Export cut short | When `lumina.cutShort[0]` exists at mount, Open shows one quiet line: `last export stopped after 14 of 40 · <folder> · export again to finish`, plus ` · reconnect <folder> so Lumina can tidy it` when `cleaned` is false. It goes on the next key and never retries by itself. |
| E (P7) | Acknowledgements | `luminaCommand('acknowledgements')` opens a sheet with the title, one quiet line, and `await lumina.notices()` in a monospace pane that scrolls, selectable and with no reflow. In a browser (or when `notices` is missing), it lists React 18.3.1, React DOM 18.3.1 and @babel/standalone 7.29.0 with licence links. If `notices()` fails, it adds the line pointing to THIRD-PARTY-NOTICES.txt. esc or ⏎ closes it. |
| B5 b | Merge decisions on restore | This was already in v8/v9: restore merges, and decisions made during the read win. No change. |

## Shift capture time (Prompt 3 B)
- **Open it:** `luminaCommand('shiftTime')` (MENUS: Photo ▸ Shift Capture Time…). With more than one body, the import note's two-body line also gets a `shift a camera's time…` action that preselects the first body.
- **Sheet** `[data-lumina=shift-sheet]`:
  - Choose what to shift: `whole shoot`, one entry per body (model · …last 4 of the serial · N photos), or `from this photo on`. ↑ ↓ move between them.
  - Offset input `[data-lumina=shift-offset]`: type `+1:00:00` or `−0:01:10`; ↑ ↓ in the input step by an hour; there are also `−1 h` / `+1 h` chips.
  - Live preview `[data-lumina=shift-preview]`: `41 rows → 38 rows`.
  - The quiet line, then `⏎ shift · esc cancel`. ⏎ and the Shift button do nothing at 0:00:00.
- **What a shift does:**
  - Rows, stacks and the time axis are rebuilt from the shifted times.
  - Ids are positional, so every decision follows its photo **by path**: marks, stars, depth, saved state, cuts (and their anchors), seen rows, the cursor, and Edit's looks, tags and keep (stack ids too).
  - The footer reads `Shifted 212 photos by +1:00:00`, as one undo step (⌘Z / Q).
  - A shifted row's header adds `· time shifted`.
- **Storage:** shifts are saved with the session (`shifts` in the session object, and in `luminaState().shifts`), never in a sidecar or a RAW.
- **App:**
  - Your `build` override must build from `this.shifted()` instead of `this.real`.
  - Persist `luminaState().shifts` with the session, and before the first build on reopen set `this._shifts` from it (the page does this itself in the browser).
  - A `shifted` event fires after each shift.
- **Edge:** it does nothing without a real shoot. With one body there are no per-body entries; photos without a serial are grouped by model.

## Still open (unchanged from REMAINING-v0.03)
- Not done this round from round 1: A3 (pre-sandbox sessions: needs the app's call name) and the D1 B/C sidecar refresh (`lumina.sidecars`).
- Round 2: B1 grey tiles for unreadable files, C2 export JPEGs.
- Round 3: B5 c calmer growth.
- Waiting on app data: B3 B/C/G, B4 a.
- B6, B7, C1, C3, D4, D5.
