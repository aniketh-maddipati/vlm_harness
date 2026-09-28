# Lumina Sets — roadmap

**Beta scope: Sony only (ARW, + JPEG/HEIF pairs). Open in place — no copy/ingest.** Card read-only; keeps copied to ~/Pictures/Lumina on finish. Bursts/brackets from Sony maker notes (drive mode, sequence no.). Check embedded preview size per body; decode ARW for 100% + Edit. Photo Mechanic: read XMP ratings/labels; register as "Open with" target. Full ingest deferred until testers ask.

Enact in this order after the current round of feedback.

## Reddit beta — trust requirements (must ship with all)
**Files**
1. Never write to the card — no delete, rename, format, or "clean up card".
2. Never change originals — edits live in Lumina's own records, not the RAWs.
3. Copy, never move. Checksum-verify every copy before calling it done.
4. "Safe to format in camera" only after every file is copied + verified.
5. One visible library folder (~/Pictures/Lumina) + "Show in Finder".
6. No delete in beta — "out" only hides.

**Privacy**
7. Nothing leaves the Mac. No uploads, no cloud AI. Said on first launch.
8. Crash reports opt-in, no image content or file names.
9. No account.
10. Access only to the card/folder the user picks — never Full Disk Access.

**Exit**
11. Export keeps as a folder or XMP ratings (Lightroom / Capture One).
12. Uninstall leaves every photo in place.

**Honesty**
13. Clearly labelled beta + known-issues list.
14. Stated scope: Sony ARW, Apple silicon, macOS version.
15. Tell testers: keep your own backup, don't format until you've checked.
16. Signed + notarized (or TestFlight). Never an unsigned build.
17. One bug-report channel + public changelog.

## Locked for beta (works now — don't redesign before feedback)
- Four steps: Open → Cull → Edit (optional) → Export. Finals = P in Edit. Exposure story = optional beta link inside Export.
- Open: card panel on top ("Copy & start culling"), recent-shoot search below. Copy status in header.
- Cull: time rows → groups (bursts / brackets / singles), recursive ↑↓ ←→ focus, R/X act on focus, picks + likely-out dot, L to flag, Space large, A/V auto preview, W compare, B split / ⇧B merge, box + shift-arrow select.
- Edit: loupe + rows; focus = scope (photo → group → row), esc widens, sliders on , . [ ].
- Objective flags only: soft (relative in group), blown (>2% clipped), shake (shutter > 2/focal).
- Brightness never altered for undecided photos.

## Ask testers
- Are rows and bursts right on your shoots?
- Do soft / blown / shake flags match your eye?
- Any lag, glitch, or moment you weren't sure what an action would hit?
- Would you trust it with a card you haven't backed up? What would change that?

## Speed test baseline (α7 III, 721 ARW / 11.3 GB, built-in SD slot, Chrome)
- Card read ~92 MB/s flat at 1/4/8 parallel → UHS-I ceiling. Full read ≈ 2 min (~8 photos/s).
- Preview-only (header + embedded JPEG): all 721 cull-ready in 10.5 s, first preview 92 ms, 0 errors.
- Embedded preview: 1616×1080, ~712 KB — fine for grid, soft on Retina large view, unusable for 100%.
- Integrity: 822 copies verified, 0 mismatches, planted corruption caught, all ARWs parse. Hash cost <1% of read.
- Browser write path 16–38 MB/s (Chrome .crswap) — not representative; native app required for copy numbers.
- No sub-second capture time in α7 III EXIF → bursts need Sony maker notes / sequence.

## v1 ingest (decided)
**Stream-copy, then cull from disk.** Native macOS app, Sony ARW only.
- Copy card → disk in shooting order, 1–2 files at a time (card is serial), hash while copying, verify.
- A photo appears in Cull only once copied + verified. Nothing visible lives only on the card — no "is it imported?" ambiguity.
- Copy (~8 photos/s) outruns culling (~1–2 photos/s), so the user never waits after the first second.
- Previews: embedded JPEG for grid; native RAW render (Core Image) for large view + 100%, swapped in when ready, neighbours prefetched.
- Lag/overload guards: bounded worker pools (copy 1–2, decode ≈ cores/2), priority queue (on-screen > next > background), LRU bitmap cache with a memory cap, virtualized rows, main thread never waits on disk, held-key debounce.
- Failure: card pull → keep verified, mark rest missing, resume on reinsert; low-disk check before start; never "safe to format" until all verified.

## v1: card detection (native)
- Watch mounts via NSWorkspace didMount / didUnmount (or DiskArbitration). No polling.
- On mount: check for /DCIM/1xxMSDCF (Sony) → show the card panel on Open, and bring the app forward only if it's already frontmost (no focus stealing).
- Identify the card by volume UUID + camera body serial (EXIF) → "new since last time" is exact, even with the same "Untitled" name.
- App Store sandbox: use ImageCaptureCore for cards/cameras, or a one-time "Allow Lumina to read this card?" bookmark per volume UUID. Never Full Disk Access.
- Unmount mid-copy → pause, keep verified files, show "Card removed · N safe", resume automatically on remount of the same UUID.
- Non-Sony card → quiet line "Only Sony cards are supported in this beta". Don't hide the card.
- Settings: "Open Lumina when a Sony card is inserted" — off by default.

## v1: export (proposed)
Flow becomes **Open → Cull → Edit → Export**. Narrow folds into Edit (F = final, "finals only" filter). Write moves inside Export as "Exposure story (beta)".
- **Lightroom / Capture One:** write XMP sidecars next to the copied RAWs — never into the RAW. Keep = 3★, final = 5★ (settable). Edits as crs: develop settings. Lowercase .xmp. Merge into an existing XMP from another app, never overwrite it. Then "Show in Finder" + one line: Lightroom → Import → Add (or Metadata → Read Metadata from Files).
- **Folder:** copy keeps or finals as-is to a folder you pick.
- **Exposure story (beta):** full-size sRGB JPEGs of finals, numbered in story order, captions embedded + captions.txt. Upload to Exposure by hand — no known public API.
- **Clean up:** after export, list what Lumina made for itself (preview cache, thumbnails, database for this shoot) with sizes → one "Remove" action. Never touches RAWs or handoff XMPs.

### Export — native app follow-ups
- Write .xmp straight next to each RAW; keep the old file as .lumina-bak.
- Export log per shoot + "Restore previous .xmp".
- Re-send updates only what changed ("12 updated").
- Remember the last destination per target; any folder, any drive.

## Navigation rules
- Steps are views over one shared state. Leaving a step never commits or discards anything.
- Each step remembers its own cursor, focus level, scroll and selection.
- Keep / final / edit changes anywhere show everywhere immediately.
- One undo stack across steps, each entry labelled ("kept 5 · Cull").
- If the remembered photo is gone (unkept), land on its nearest neighbour.
- Back is as cheap as forward: 1–4, ⌘[ / ⌘], or click a step. No confirmation except unapplied previews.

## Roadmap after v1
- Preview-only open from card (10 s cull-ready) + keeps-first background copy — only if testers find the stream-copy start slow.
- Keeps-only copy mode.
- Photo Mechanic: read XMP ratings/labels; "Open with Lumina".
- Other camera brands.

## 1. Scale (do first)
- Virtualize Cull/Edit rows — render only on-screen rows; grid uses small thumbnails, large previews on demand.
- Preview memory cap — keep ~50 large previews around the cursor; release the rest.
- Real local store — IndexedDB, per-photo writes (replace single localStorage blob, ~5 MB cap).
- Freeze touched rows while an import is still streaming; late files form new rows only.

## 2. Import from SD card (deferred — see beta scope)
- "Import" button → pick card's DCIM folder (read locally, nothing uploaded).
- Extract embedded full-size JPEG from each RAW; fall back to small preview + "can't judge sharpness".
- Read EXIF/maker notes: capture time + subseconds, body serial, drive mode, sequence no., exposure comp, focus distance, shutter, focal length.
- Group with the rules: time gaps → rows; drive mode/sequence → bursts; exposure/focus stepping → brackets; RAW+JPEG → one photo.
- 4–8 parallel reads; stream rows in as they arrive.
- Needs from user: camera model(s), typical card size.

## 3. Races
- Bind each keypress to the photo focused at keydown.
- Esc/Q during a drag cancels the drag first.
- Suppress scroll-follow for ~500 ms after any key navigation.
- Two tabs → lock or warn.

## 4. Edge cases
- Bad clocks (unset, time-zone jumps, multiple bodies): sort by body, then time; fall back to file counter.
- Duplicate filenames across cards: key by body serial + counter + time.
- 100+ frame bursts: condensed strip with per-segment pick.
- Buffer stalls splitting a burst; tiny shoots (1 photo / all singles) — structure steps aside.

## 5. Stress
- Held D/F: debounce large-preview decode ~80 ms after last repeat.
- Card pulled mid-import: keep what's read, flag missing.
- Storage quota errors: surface, never silent.
- Narrow windows (~800 px): shrink tiles before wrapping.

## Also open
- Edit sliders: relative drag anywhere on the row, 3 px threshold, no jump-on-click (verify current).
- Write: block reorder via grab handle, 8 px threshold.
- Progress count in top bar ("32 left"); ↓ skips finished rows.
- Export to Exposure (currently placeholder).
