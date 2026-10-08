# Lumina: trust model

This is the list of what Lumina promises the people who use it, how each promise is held, and
everything the app can reach. `python3 Scripts/trust_check.py` compares the inventory below with
the code on every pull request (the `design handoff` job). A change that adds anything the
inventory lists (a bridge op, an entitlement, a permission prompt, a place the app sends the user,
a URL in the code, a dependency) fails until a row is added here. That row is the review.

The README's "Trust and privacy" section is the short version for users. `THREAT-MODEL.md` keeps
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
| `writeInto` | RAWs in the opened folders | an export: `.xmp` bytes or rendered `.jpg` `.tif` `.png`, in a folder the user picks (not the card, not the source) |
| `readSidecars` | `.xmp` files in the opened folder | — |
| `writeSidecars` | — | `.xmp` beside its RAW in the opened folder, `.lumina-bak` first |
| `reveal` | — | — (shows a file in Finder, only inside the opened folders or the last export) |
| `setPrefs` | — | the page's preferences in the app's defaults |
| `skimStore` | Skim's saved shoots, `skim/store.json` in the container (Debug builds with `LUMINA_PAGE=skim` only) | — |
| `skimSave` | — | one Skim shoot's marks, name and counts in `skim/store.json` in the container (Debug builds with `LUMINA_PAGE=skim` only) |
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
| `Lumina/Sets/Core/SetsBridge.swift` | System Settings' Files and Folders pane (`openSettings`) |

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
| Container `exports/` | one journal per export | after recovery |
| Container preferences | the page's preferences | deleting the app's container |
| Opened folder | `.xmp` sidecars, `.lumina-bak` | the user |
| Export folder | rendered images and `.xmp` copies; temp files while writing (journaled, removed on the next launch after a crash) | the user |

## Checked rules that are not tables

`trust_check.py` also fails on: a networking API in app code (`URLSession`, `NSURLConnection`,
`NWConnection`, `NWListener`, `CFSocket`, BSD sockets, `WKWebsiteDataStore.default()`); `NSLog`
or `print` in app code; a network URL, `WebSocket`, `XMLHttpRequest`, `EventSource` or
`sendBeacon` in `plumbing.js`; an Action not pinned by commit; a Swift package reference.
