# Answers to Phase 0 questions (from the design side)

## 1. Reference = WebKit render: confirmed
The screenshots in `screenshots/` are out of date and use online placeholders. They are **not** the reference. Delete them.
Reference = `Lumina Sets v3.dc.html` rendered in WebKit (Safari engine / WKWebView) at fixed sizes (1440×900 and 1920×1080), with fixed local sample photos and a fixed debug clock. Compare app WKWebView against that, WebKit vs WebKit. 0 px allowed outside photo areas.

## 2. Updated HTML: use the one in this folder
`Lumina Sets v3.dc.html` in this handoff is updated. The UI side of the addendum is done here:
- Narrow screen, its keys, refs and counts: removed (`narrow` no longer appears)
- Time-of-day labels: removed from all UI (`light` stays internal only)
- "likely out" → "not suggested", "pick"/"best" → "sharpest", keeps → keepers, finals → selects, out → reject, widen → back out, preview auto → show Auto, "applies to:"
- ? key list rewritten for Open → Cull → Edit → Export

**Left for you (plumbing, Phase 2/3), as the addendum says:** sample shoot (keep only as debug fixture data), key C, fake copy timer, zip downloads, X→E `Proxy` remap, iframe / "own tab" checks, localStorage. Don't edit anything else in the HTML. If you find other UI wording that disagrees with `ADDENDUM-remove.md` §4, report it; the fix goes in the design first.

## 3. JPEG look: confirmed, with one change
Render the RAW with default settings (`CIRAWFilter`, no auto-adjust), then apply the **same** maths as the Edit preview. That maths now lives in `lumina-core.js` as `editFilter(r)` (brightness · contrast · sepia / hue-rotate from Exposure, Contrast, Highlights, Shadows, Temp). Implement it as a Core Image kernel using the CSS Filter Effects spec matrices, so export = what Edit showed. Add a fixture: 5 edit settings × 1 test image; the app's output must match the WebKit CSS output within ΔE < 1.
Lightroom handoff is unchanged: edits go as `crs:` values (`freshXmp`), and Lightroom renders them its own way. That's expected.

## 4. Beta = open in place. No copy step.
- Open reads the card or folder **read-only**, and culling happens straight off it.
- Remove "Copy & start culling" and the copy progress from Open for the beta. The card panel's main button becomes **"Cull this card"**.
- Copying happens only at **Export** (RAW / RAW + JPEG to a folder the user picks, checksum-verified).
- Card pulled mid-cull → pause and keep the state, resume on re-insert (same volume UUID).
- The ROADMAP "v1 ingest" section moves to post-beta. The ROADMAP scope line wins.
- The Open-screen change above is a design change. It will land in the HTML here before you start Phase 3; until then treat the copy UI as out of scope and don't build the copy bridge.

## Phase 6
Approved as proposed, including deleting the Swift `CullCore` port. Rewrite `AGENTS.md` around this handoff: the HTML is the UI and the spec, `lumina-core.js` is the logic, and this folder wins over everything else.

## SequenceNumber
Correct to keep parity for now. Post-beta: read Sony `SequenceNumber` in `parseHead` (design side first), regenerate fixtures, then port.
