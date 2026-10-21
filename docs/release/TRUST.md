# Lumina: trust model

This is the list of what Lumina promises the people who use it, how each promise is held, and
everything the app can reach. `python3 Scripts/trust_check.py` compares the inventory below with
the code on every pull request (the `design handoff` job). A change that adds anything the
inventory lists (a bridge op, an entitlement, a permission prompt, a place the app sends the user,
a URL in the code, a dependency) fails until a row is added here. That row is the review.

The README's "Trust, and how to check it" section and [PRIVACY.md](PRIVACY.md) are the versions for users. `THREAT-MODEL.md` keeps
the findings and how they were fixed.

## Who this is for

- **Professional photographers.** Client shoots under NDA, people who must not be identified,
  locations that must not be published, copyright that has to travel with the file. They need to
  know that nothing reaches the network, what stays on the Mac, and what an exported file says.
- **Everyone else.** Their photos are personal. They need the same promises in plainer words, and
  no surprises from a card someone handed them.

## Promises

Status: **holds** (enforced and tested on every pull request), **holds, Mac check in CI** (the
check runs on the macOS runner, not on Linux), or **open** (not yet true; the task is named).

| # | Promise | How it is held | Checked by | Status |
|---|---|---|---|---|
| I1 | Originals are never changed, moved or deleted. | The bridge has no op that writes a RAW. Sidecars only, `.xmp` inside the opened folder beside a RAW, never on a card or removable volume (`SetsFileOps.writeSidecar`). | `SetsSidecarTests`, `SetsTrustTests`, `probe.sh fault` | holds |
| I2 | A sidecar is never lost or written from stale text. | `.lumina-bak` before any replace; atomic write, fsync, read back; the write carries the hash of the text it merged and is refused if the file changed (Lightroom wrote it). | `SetsSidecarTests`, `app-xmp-changed-since-open` | holds |
| I3 | An export never loses a file. | Exports go to a folder the user picks, never the card or the source folder; each file is written atomically and read back, a file already there is kept as `.lumina-bak` first, and a journal lets an interrupted export be cleaned up on the next launch. | `SetsFileOpsTests`, `fault-kill-mid-handoff` | holds |
| I4 | The app reaches only what the user picked. | App Sandbox; `files.user-selected.read-write` and security-scoped bookmarks; nothing else. | `probe.sh sandbox smoke`, preflight | holds, Mac check in CI |
| I5 | Nothing leaves the Mac. | No networking code in the app (checked below). The page: content rules block every load but `lumina:` `blob:` `data:` `about:`; a Content-Security-Policy on every page file; WebRTC removed in every frame (`SetsOffline`); navigation only to `lumina://`; a clicked link goes to the user's browser or mail app only if `SetsExternalLinks` names it. | `Tests/web/webkit.py offline` (32 ways out against a local listener), `app-offline` (WKWebView), `SetsOfflineTests`, `SetsExternalLinksTests`, `trust_check.py` | holds; the system does not enforce it while `network.client` is on (D2) |
| I6 | What Lumina keeps is listed and removable. | Files below; File ▸ Remove Working Files. Sessions are capped in size; a shoot id from the page can't name a folder outside the store. | `SetsShootStoreTests`, `SetsWorkingFilesTests` | holds |
| I7 | An exported file says only what the photographer would expect. | Rendered exports carry an allowlist from the RAW (capture time, camera, lens, exposure, artist, copyright, IPTC credit and caption); never location, serial numbers, maker notes or orientation (`SetsExportMetadata`). Looks are never written to XMP. | `SetsExportMetadataTests`, `SetsLookExportTests.testExportMetadataIsTheAllowlist` | holds, Mac check in CI |
| I8 | Logs carry no file names, folder names or paths in clear. | One log (`LuminaLog`, `os.Logger`); names, paths and error texts are private. `NSLog` and `print` are refused in app code. | `trust_check.py` | holds |
| I9 | What ships is what was reviewed. | Page files byte for byte; React and Babel vendored and pinned by hash; no Swift packages; Actions pinned by commit; a design sync prints every new network or bridge call; releases signed from one Mac. | CI page check, `SetsPageBytesTests`, `trust_check.py`, preflight | holds |
| I10 | A bad file can't crash the app or reach outside the opened folders. | Bounded inputs (sidecar size, listing size, session size, numbers clamped), links inside a shoot can't lead out, the page reloads at most three times. Apple's decoders run in the app process, inside the sandbox. | `SetsIngestBoundsTests`, `SetsIngestLinksTests`, `SetsBridgeOpsTests`, Q4 hostile-input runs | holds for the tested inputs; Q1 to Q5 stress runs open |

## What Lumina does not protect against

- Another program running as the same user. It can read the photos and the container already.
- Someone with the Mac unlocked. The container is not encrypted beyond FileVault.
- A compromised page using the bridge as designed: it could write sidecars into the opened
  folders, put an export where the user picks, or fill the bug-report draft with text. It can't
  write anything else, read outside the opened folders, delete outside the container, or send
  anything; the user still has to press Send on a mail draft.
- Apple's own channels: crash logs shared with developers if the user allows it, and a
  sysdiagnose the user sends (Lumina's names and paths are private there).
- While D2 is open, a WebKit bug that bypasses all three page layers. The native UI (no network
  entitlement) is the fix that makes the system enforce I5.

## Adding something

Each row of the inventory answers "what can this reach, and why". When you add:

- **a bridge op**: validate every field (`SetsNumber`, the shoot id rule, paths through
  `resolve`), bound its sizes, add a row and a `SetsBridgeOpsTests` case;
- **an entitlement or a permission prompt** (camera, Photos, USB for a phone import): a threat
  review in `THREAT-MODEL.md`, the README's section, the App Store privacy answers, and a row;
- **a place the app sends the user**: `SetsExternalLinks`, its tests, and a row;
- **a file the app writes**: the files table, and Remove Working Files if it is in the container;
- **a log line**: `LuminaLog`, with `privacy: .private` on anything a user named;
- **a dependency or vendored file**: pinned by hash, licence in `THIRD-PARTY-NOTICES.txt`, a row.

## Inventory

Checked by `Scripts/trust_check.py`: the first column of each table below must match the code
exactly (add or remove rows with the code).

### Entitlements

Keys in `Config/Lumina-Sets.entitlements` (what ships) and `Config/Lumina.entitlements`.

| Key | Why | Reaches |
|---|---|---|
| `com.apple.security.app-sandbox` | The sandbox. | Limits everything else to the rows here. |
| `com.apple.security.files.user-selected.read-write` | The folders the user picks: read RAWs, write sidecars and exports. | Only folders chosen in an Open or Save panel. |
| `com.apple.security.files.bookmarks.app-scope` | Open Recent. | The same folders, after a relaunch. |
| `com.apple.security.network.client` | WebKit does not start in a sandboxed app without it (measured 2026-10-01). Only in `Lumina-Sets.entitlements`. | Outgoing connections. Lumina makes none; the page is held by I5. Decision D2. |

### Permission prompts

`NS…UsageDescription` keys in the project or the xcconfig files.

| Key | Why |
|---|---|

### Bridge ops (`SetsBridge`, page → native)

| Op | Reads | Writes |
|---|---|---|
| `ready` | — | — (closes any open shoot) |
| `cullCard` | the inserted card, after a folder panel | — |
| `openFolder` | a folder the user picks: its listing | — |
| `openCancel` | — | — (stops a listing) |
| `notices` | the bundled licence texts | — |
| `prefetch` | previews in the opened folders, into memory | — |
| `near` | two previews in the opened folders (Vision, on the Mac) | — |
| `dust` | previews in the opened folders, as stored (sensor dust, on the Mac) | — |
| `ingestStats` | read counters | — |
| `shootOpened` | — | the shoot in `shoots/index.json` (name, path, volume, counts, bookmark) |
| `shootHeader` | the shoot's decoder facts | — |
| `decoderUpdate` | — | the shoot's `Lumina.json` |
| `canvasEnter` | a RAW in the opened folders | — (renders on screen) |
| `canvasLeave` | — | — |
| `canvasLayout` | — | — |
| `canvasLook` | — | — |
| `canvasDrag` | — | — |
| `canvasZoom` | — | — |
| `canvasLoupe` | the RAW's region at 100 % | — |
| `canvasStats` | render counters | — |
| `saveSession` | — | `shoots/<id>/session.json` (size capped, id checked) |
| `recents` | `shoots/index.json` | — |
| `reopen` | a recent shoot through its bookmark | — |
| `workingFiles` | sizes in the container | — |
| `removeShoot` | — | deletes `shoots/<id>/` in the container (id checked) |
| `writeInto` | RAWs in the opened folders | an export: `.xmp` bytes or rendered `.jpg` `.tif` `.png`, in a folder the user picks (not the card, not the source), or Handoff's Save to folder when it is one Lumina has access to and neither; the files written are noted in `pick/written.json` |
| `readSidecars` | `.xmp` files in the opened folder | — |
| `writeSidecars` | — | `.xmp` beside its RAW in the opened folder, `.lumina-bak` first; with Handoff's Save to, into that folder instead (one Lumina has access to, or one the folder panel names that is not the opened folder or a card), `.lumina-bak` first, read back; the files written are noted in `pick/written.json` in the container |
| `reveal` | — | — (shows a file in Finder, only inside the opened folders or the last export) |
| `setPrefs` | — | the page's preferences in the app's defaults |
| `pageError` | — | — (the page shows an error in place of its screen, or no longer does: the window offers Reload Page, a button over the page and ⌘R) |
| `skimStore` | Skim's saved shoots, `skim/store.json` in the container (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimSave` | — | one Skim shoot's marks, name and counts in `skim/store.json` in the container (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimCoverGet` | Skim's saved covers and first measures for the clips asked for, `skim/covers/` in the container (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimCoverPut` | — | covers (the page's own JPEGs) and first measures for one shoot in `skim/covers/<hash>/` in the container, capped at 200 MB, the shoot opened longest ago removed first (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimCoverTouch` | — | when a shoot was last opened, in its `skim/covers/<hash>/shoot.json` (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimCoverStat` | the sizes of `skim/covers/` per shoot (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimCoverDrop` | — | deletes `skim/covers/<hash>/` for the shoots named, nothing outside it (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimDrive` | the drive the open Skim shoot was opened from: name, size, free and purgeable space, read only or a card, and its Trash's size when the sandbox lets it be read (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimShowTrash` | — | — (opens that drive's Trash in Finder after a click; never empties it; Debug builds with `LUMINA_PAGE=skim` only) |
| `skimTrashMove` | the opened folder's clips named, and their Sony sidecars | moves them to the system Trash after the user's two clicks (Put Back works), and notes each move in `skim/trash.json` in the container; refused on a camera card, a read-only drive or under `PRIVATE/M4ROOT`, and for any path outside the opened folder; never deletes, never empties the Trash (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimTrashPutBack` | `skim/trash.json` | moves this shoot's files from the Trash back to where they were, while they are still there (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimTrashList` | `skim/trash.json`, and whether each file is still in the Trash (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimHealth` | the Mac's thermal state, Low Power Mode, memory pressure and Lumina's own memory footprint (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimExportPlace` | `skim/export.json` (the Save to folder's bookmark) and whether Final Cut Pro is installed; the open shoot's folder path, for the .fcpxml (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimExportChoose` | — | the folder panel after the user's click; the folder picked is kept as a security-scoped bookmark in `skim/export.json` in the container (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportAsk` | — | removes `skim/export.json`, so each save asks with the save panel (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportSave` | the file just written, read back | a note of it in `skim/exports.json` (its path, size and date, the clips it holds with their marks, a security-scoped bookmark); one new `.fcpxml` or `.txt` (the page's text, at most 16 MB) in the folder the workshop names (inside one Lumina has access to) or the Save to folder, under a free name, or where the user put it in the save panel; never over an existing file (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportCheck` | whether each clip file a .fcpxml points at is on disk (inside the opened folder only), and Final Cut Pro's own FCPXML DTD from its app bundle (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimPlaces` | the drives mounted (name, size, free space, card or read only) and `skim/places.json` (the drives and folders the user gave Lumina access to); nothing inside a drive (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimPlaceAdd` | — | the folder panel after the user's click, opened at the drive or folder named; the folder picked is kept as a security-scoped bookmark in `skim/places.json` (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimPlaceRemove` | — | takes a folder off `skim/places.json`; the folder is not touched (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimDirList` | the folder names, and with `files` the file names and sizes (nothing hidden, nothing opened), directly inside one folder, only inside a folder Lumina has access to (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimDirSize` | the sizes of the files under one folder, added up (names and sizes only, nothing opened), only inside a folder Lumina has access to, after Export's tree lists the folder or the user's Re-read sizes (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimFind` | Export's search: the names of the folders (no files, nothing hidden, no packages, nothing opened) under the folders Lumina has access to whose name holds every word typed; breadth first, at most 200 results, 20,000 folders, 8 levels and 2 s, off the main thread; a newer search stops the older (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimDirMake` | — | one new, empty folder with a plain name inside a folder Lumina has access to, after the user's click; never on a camera card, never over a folder (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimArrangeApply` | the clips the user dragged onto folders in Export's workshop, and their Sony sidecars | moves them into those folders after the user's Apply, only on the same drive (a rename, never a copy and delete), only inside folders Lumina has access to, never on a camera card, a read-only drive or under `PRIVATE/M4ROOT`, never over a file; makes the folders named if they are not there; notes the run in `skim/arrange.json` in the container before anything moves (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimArrangeUndo` | one run from `skim/arrange.json` | moves that run's files back, each only if it is still where Skim put it with the same size and date and its old place is free; removes the folders the run made only when they are empty (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimArrangeList` | `skim/arrange.json` in the container | the runs Arrange kept (when, how many clips, whether undone), read only (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportDefault` | — | `skim/export.json`: a folder of the workshop's tree becomes the Save to folder (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportReveal` | — | — (Finder, with a file this run's Export saved selected; Debug builds with `LUMINA_PAGE=skim` only) |
| `skimOpenInFinalCut` | — | — (hands a `.fcpxml` this run's Export saved to Final Cut Pro, which asks where to import it, after the user's click or the Export option he turned on; Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportsList` | `skim/exports.json` in the container (the files Export saved for this shoot: path, kind, size and date, the clips each holds with their marks, a security-scoped bookmark of each), and whether each file is there now, changed since, gone or in the Trash, found through its bookmark (Debug builds with `LUMINA_PAGE=skim` only) | `skim/exports.json`: the path of a file moved or renamed in Finder |
| `skimExportsForget` | — | takes one file off `skim/exports.json`; the file is not touched (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportsTrash` | — | moves one file Export saved to the system Trash after the user's click, only when it is unchanged since it was saved and not on a camera card; notes where it went in `skim/exports.json` (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportsPutBack` | — | moves that file from the Trash back to where it was, while it is still there and its old place is free (Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportsReveal` | — | — (Finder, with a file on Export's list selected, after the user's click; Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportsOpen` | — | — (hands a `.fcpxml` on Export's list to Final Cut Pro, which asks where to import it, after the user's click; Debug builds with `LUMINA_PAGE=skim` only) |
| `skimExportsRead` | the text of one file on Export's list (at most 16 MB), found through its bookmark, for its preview (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimShowClips` | — | — (Finder, with the clips named selected, inside the opened folder only, after the user's click on Delete in Finder… or on a mark's Show in Finder (Selected, Maybe, Cut, unmarked); the user moves or deletes them there, Lumina moves and deletes nothing; Debug builds with `LUMINA_PAGE=skim` only) |
| `skimShowInFinder` | — | — (Finder, with a folder or file of Export's tree selected, only inside a drive or folder Lumina has access to, after the user's click; Debug builds with `LUMINA_PAGE=skim` only) |
| `filesPlaces` | the drives mounted (name, size, free space, card or read only, whether Lumina may look inside all of one, some folders on it, or none), `skim/places.json` (the drives and folders the user gave Lumina access to) and `pick/saveto.json`; nothing inside a drive | — |
| `filesDirList` | the folder and file names and sizes directly inside one folder (nothing hidden, nothing opened, no sub-folder read), only inside a folder Lumina has access to; for a drive let in only in part, the folders let in on it | — |
| `filesPlaceAdd` | — | the folder panel after the user's click, opened at the drive or folder named; the folder picked is kept as a security-scoped bookmark in `skim/places.json` |
| `filesPlaceRemove` | — | takes a folder off `skim/places.json` (and Save to, when it was that folder); the folder is not touched |
| `filesDirMake` | — | one new, empty folder with a plain name inside a folder Lumina has access to, after the user's click; never on a camera card, never over a folder |
| `filesSaveToChoose` | — | the folder panel after the user's click (a camera card refused); the folder picked is kept as a security-scoped bookmark in `pick/saveto.json` |
| `filesSaveToAsk` | — | `pick/saveto.json`: each save asks with the folder panel |
| `filesSaveToSet` | — | `pick/saveto.json`: a folder of the file view (one Lumina has access to, not a card) becomes Save to; the shoot's own folder means next to each RAW |
| `filesReveal` | — | — (Finder, with the files or folders named selected, only inside folders Lumina has access to, after the user's click or ⌥⌘R; Delete in Finder… selects the rejected RAWs so the user deletes them there; Lumina deletes nothing) |
| `filesSavedCheck` | whether each file of Handoff's Saved files is there and its date, only for files Lumina noted writing or inside folders it has access to | — |
| `filesSavedText` | the text of one `.xmp` Handoff saved (noted in `pick/written.json`, at most 1 MB), for its preview | — |
| `filesDirSearch` | Handoff's search: the names of the folders (no files, nothing hidden, no packages or links, nothing opened) under the folders Lumina has access to whose name holds the query; breadth first, a page at a time (at most 200 results and 6 s a page, 10 levels, 50,000 folders), off the main thread; a new query stops the older | — |
| `filesCopyInto` | the photos named (their RAW and `.xmp`), inside folders Lumina has access to | copies of them (never moves) into a folder Lumina has access to after the user's Apply: streamed with a running SHA-256 and read back before each counts; never over a file (a name already there gets " 2"), never onto a camera card, never into the photo's own folder; the copies are noted in `pick/written.json` in the container |
| `filesDirRename` | — | renames one folder in place after the user's typing, inside a folder Lumina has access to; never a photo, a drive, a folder Lumina was let into, a folder on a camera card or one holding the open shoot; never over a folder |
| `filesTrash` | — | moves files Handoff wrote (noted in `pick/written.json`: its sidecars, JPEGs and copies, a copy's sidecar with it) to the system Trash after the user's click; nothing else; never empties the Trash |
| `filesPutBack` | — | moves files this run of Handoff moved to the Trash back to where they were, while their old place is free |
| `filesOpenInLightroom` | — | — (hands a folder or files Lumina has access to or saved to Lightroom Classic, which asks how to import them, after the user's click or the Then option he turned on) |
| `openSettings` | — | — (opens System Settings ▸ Privacy & Security ▸ Files and Folders) |
| `checkAccess` | whether a refused folder is readable now | — |
| `reopenDenied` | the refused folder, again | — |
| `reopenCurrent` | the open shoot's folder, again | — |

### `lumina://` hosts (`SetsSchemeHandler`)

| Host | Serves |
|---|---|
| `app` | the page files (with the CSP), and photos from the opened folders by byte range (`media/`) |
| `render` | Edit previews rendered from a RAW in the opened folders |
| `vendor` | React and Babel from the bundle |
| `photo` | flat stand-in images for the design's sample shoot |

### Places the app sends the user

Every `NSWorkspace.shared.open` call site. Each hands a URL to another app, after a click.

| File | What |
|---|---|
| `Lumina/LuminaApp.swift` | Help ▸ Report a Bug…, through `SetsExternalLinks` |
| `Lumina/Sets/SetsRootView.swift` | a link clicked in the page, through `SetsExternalLinks` (LinkedIn, X, the bug-report mail) |
| `Lumina/Sets/Core/SetsBridge.swift` | System Settings' Files and Folders pane (`openSettings`); the Trash of the drive Skim's shoot is on, in Finder (`skimShowTrash`); a .fcpxml Skim's Export saved, to Final Cut Pro (`skimOpenInFinalCut`); a folder or files Handoff saved, to Lightroom Classic (`filesOpenInLightroom`) |

### URLs in the app's code

Hosts named in Swift outside comments. None is fetched.

| Host | Why |
|---|---|
| `picsum.photos` | the design's sample photos, rewritten to `lumina://photo` |
| `unpkg.com` | support.js's names for React and Babel, mapped to `lumina://vendor` |
| `www.linkedin.com` | a contact link in `SetsExternalLinks` |
| `x.com` | a contact link in `SetsExternalLinks` |

### Privacy manifest (`Lumina/Resources/PrivacyInfo.xcprivacy`)

No tracking, no tracking domains, no collected data types (checked). Required-reason APIs:

| Category | Why |
|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | the page's preferences |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | sidecar and container file dates |
| `NSPrivacyAccessedAPICategorySystemBootTime` | timing (uptime clocks) |
| `NSPrivacyAccessedAPICategoryDiskSpace` | free space before an export |

### Bundled third-party code (`design/handoff/vendor`)

| File | Pinned by |
|---|---|
| `react.production.min.js` | SRI hash in `support.js`, byte check |
| `react-dom.production.min.js` | SRI hash in `support.js`, byte check |
| `babel.min.js` | SRI hash in `support.js`, byte check |

No Swift packages (checked: no package reference in the project).

### Files Lumina writes

Not checked by the script; keep it current by hand.

| Where | What | Removed by |
|---|---|---|
| Container `shoots/index.json` | recent shoots: name, path, volume UUID, counts, first capture time, last photo's name, bookmark | Remove Working Files (per shoot) |
| Container `shoots/<id>/session.json`, `Lumina.json` | decisions and looks; decoder facts | Remove Working Files |
| Container `skim/store.json` (Debug builds' Skim only) | Skim's marks per shoot, with the folder's name, clip count, size and days | Forget marks in Skim's Working memory |
| Container `skim/covers/` (Debug builds' Skim only) | Skim's covers (the page's JPEGs of the clips' first frame) and first measures per shoot, capped at 200 MB | Clear for shoots not open, Re-measure this shoot, and the cap |
| Container `skim/export.json` (Debug builds' Skim only) | the bookmark of the folder Skim's Export saves into | Export ▸ Save to ▸ Ask each time |
| Container `skim/exports.json` (Debug builds' Skim only) | each file Export saved: its path, size and date, the clips it holds with their marks, a bookmark to find it again, at most 500 | Forget in Export's Saved files; the files themselves stay |
| Container `skim/places.json` (Debug builds' Skim only) | bookmarks of the drives and folders the user gave Lumina access to in Export, at most 24 | Remove access in Export's tree |
| A folder Lumina has access to (Debug builds' Skim only) | new empty folders made with New folder in Export's workshop | the user, in Finder |
| Folder chosen under Export ▸ Save to, or picked in the save panel (Debug builds' Skim only) | new `.fcpxml` and cut-list `.txt` files, never over one that is there | the user, in Finder |
| Container `skim/trash.json` (Debug builds' Skim only) | where each clip Skim moved to the Trash came from and where it went, for Put back | Put back, and dropped from the list once a file is no longer in the Trash |
| Opened Skim folder (Debug builds' Skim only) | nothing written; cut clips and their sidecars moved to the system Trash after two clicks | the user, from the Trash (Put Back) |
| Container `exports/` | one journal per export | after recovery |
| Container preferences | the page's preferences | deleting the app's container |
| Opened folder | `.xmp` sidecars, `.lumina-bak` | the user |
| Export folder | rendered images and `.xmp` copies; temp files while writing (journaled, removed on the next launch after a crash) | the user |

## Checked rules that are not tables

`trust_check.py` also fails on: a networking API in app code (`URLSession`, `NSURLConnection`,
`NWConnection`, `NWListener`, `CFSocket`, BSD sockets, `WKWebsiteDataStore.default()`); `NSLog`
or `print` in app code; a network URL, `WebSocket`, `XMLHttpRequest`, `EventSource` or
`sendBeacon` in `plumbing.js`; an Action not pinned by commit; a Swift package reference.
