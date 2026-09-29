# Addendum: what to remove (read before building)

> Build path: **`BUILD-exact.md`**. The HTML ships as the UI inside a native WKWebView shell. "Delete" below means remove the browser/demo code path and replace it with a bridge call. Don't rewrite the UI.

This overrides README.md wherever they disagree. The prototype has things that only exist because it runs in a browser preview, and names from earlier rounds. **Do not port anything listed here. If you find it in the app, delete it.** After each build step, search the codebase for the terms in section 4 and fix every hit.

## 1. Remove: prototype-only mechanics
| In the prototype | Why it exists | In the app |
|---|---|---|
| `support.js`, `<x-dc>`, `{{ }}` templates, `renderVals()` | design runtime | **keep**. This is the UI. Bundle it unchanged |
| Sample shoot (placeholder images, "Hudson Valley", "Trailhead, first light" captions, seeded frames) | demo data | delete; start empty on Open |
| `localStorage` persistence of the sample session | demo only | delete; per-shoot database (ROADMAP) |
| Key **C** "insert / pull card" | simulates a card | delete; use mount notifications |
| Simulated copy progress (`setInterval`, `total:550`) | fake ingest | delete; real copy + checksum |
| `webkitdirectory` input, `showDirectoryPicker`, `window.self!==window.top` checks, "open in its own tab" copy | browser file access | delete; NSOpenPanel + bookmarks |
| Zip downloads (`lumina-xmp.zip`, `lumina-jpg.zip`) and `LuminaCore.zip` / `crc32` | browser can't write folders | delete; write files directly, verify with SHA-256 or xxHash |
| `createImageBitmap` / canvas decode, `LuminaCore.measure` | browser decode | keep for grid previews, or serve thumbs from the native cache; same maths |
| JPEG export from the 1616 px embedded preview + the note saying so | browser can't decode RAW | render from RAW (`CIRAWFilter`); delete the note |
| Fake cleanup list (Preview cache / Grid thumbnails / database sizes) | placeholder numbers | show real sizes from Application Support, or hide |
| "save test data" link on Open | golden-data capture | keep only behind a debug build flag |
| `Proxy` remap of X→E in `onKey`, host-key workarounds | preview host steals keys | delete; bind keys directly |
| Toast strings mentioning "this tab", "Chrome", "prototype" | browser context | delete or rewrite for the Mac app |

## 2. Remove: features that were cut
- **Narrow step.** Gone. Selects are made in Edit with **P**; **⇧P** shows selects only. No `narrow` view, route, keys or copy.
- **Write as a step.** Only reachable from Export as "Exposure story (beta)". Not in the step bar, not on number keys.
- **Time-of-day labels** on rows (morning / midday / afternoon / evening). Rows show time + photo count only. `light` may stay internal but is never displayed.
- **"Likely out"** wording and **"pick"** badge. Use **not suggested** and **sharpest**.
- **Dimming undecided photos.** Undecided = full brightness. Only rejects are dimmed.
- **Finals label "Final"** in XMP. Labels are colour names (Green default).
- Anything in older design files in the repo (`Lumina Elastic*`, `Lumina Flow`, `Lumina Stitch`, `Lumina Two-Mode`, `Lumina Speed Test`, etc.). **Only `Lumina Sets v3.dc.html` is the reference.**

## 3. Keep, but port carefully
- `lumina-core.js`: `parseHead`, `buildShoot`, `mergeXmp`, `freshXmp`, `hasDevelop`, `exportPlan` → port exactly; must pass the fixtures and golden data.
- `.lumina-bak` before overwriting any file.
- "Last export HH:MM · what → where" line (use the full path in the app).

## 4. Words: find and replace in all UI copy
| Old (remove) | New |
|---|---|
| keeps / Keeps | keepers / Keepers |
| final, finals, Finals only | select, selects, Selects only |
| out, outs, "X out", "all out" | reject, rejects, "X reject", "reject all" |
| widen | back out |
| into | open |
| accept picks | keep suggested |
| preview auto / previewing auto | show Auto / showing Auto |
| likely out, likely-outs | not suggested |
| pick (badge) | sharpest |
| sub-row, row header | group, row |
| scope, "edits →" | applies to |
| narrow | (delete) |

Internal identifiers (`marks`, `'keep'`, `'out'`, `final{}`) can stay as they are; only user-facing text changes. README.md still uses the old words in places. This table wins.

## 5. Done when
- A search for `narrow`, `likely`, `widen`, `finals`, `keeps`, `localStorage`, `zip`, `Chrome`, `tab` in UI strings returns nothing.
- No sample data ships in the release build.
- Fixtures + golden data pass.
