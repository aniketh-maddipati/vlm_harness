# BRIDGE: page ↔ Mac app

The page checks `window.lumina?.app`. When it is true the page uses the members below; otherwise it falls back to browser behaviour. Inject `window.lumina` at document start, before `support.js` runs. Native calls are async; return Promises.

## Properties the page reads
| Member | Type | Used for |
|---|---|---|
| app | true | switches every fallback off (no sample shoot, no localStorage prefs) |
| debug | bool | shows debug links (open uploads, save golden). **false in release** |
| card | {name, photos, bytes, sony, path, model, range} \| null | Card panel on Open. `sony:false` → quiet "no ARW or DNG" line |
| readingCard | bool | true while reading straight off a mounted card → card warning |
| willPromptAccess | bool | true when macOS will show a Files & Folders prompt → page shows its explainer first |

## Methods the page calls
| Call | Native must | Returns |
|---|---|---|
| workingFiles() | total bytes of Lumina's own files for the open shoot (previews, thumbs, session). Never RAW/.xmp | Promise<number> |
| removeWorkingFiles() | delete those files; keep the session until saved | Promise<bool> |
| reveal(path) | NSWorkspace.activateFileViewerSelecting. `path` is a photo path, a save folder, or `~/Pictures/<shoot>` | void |
| setPrefs(obj) | persist `{rating, adv, enter, tsz, tszSet}` in UserDefaults; restore by injecting into `localStorage['lumina-prefs']` equivalent or a `__luminaConfig.prefs` | void |
| checkAccess() | re-test read access to the last folder/card | Promise<bool> |
| openSettings('files') | open System Settings › Privacy › Files and Folders | void |
| reopen() | reopen the last folder after access is granted | void |

## Hooks native calls on the page
| Global | When |
|---|---|
| luminaCardGone(true\|false) | card unmounted / remounted while a shoot from it is open |
| luminaAccess(denied, what) | access denied (shows banner on Open) / cleared |
| luminaCommand(name) | menu items: open, save, finder, undo, keepRow, faq, tour |
| dispatchEvent(new CustomEvent('lumina:step',{detail:'cull'\|'edit'\|'save'})) | step menu while in Edit |
| luminaDrag(ids) (optional) | if defined, page hands native the dragged photo ids for a real file drag-out |
| luminaUnsaved() | read before quit: number of picks not saved → confirm sheet |
| luminaState() | test/debug snapshot (selftest uses it) |

## Page methods to replace with native I/O (keep names)
- **openFolder / openAt(where) / dropFiles**: show NSOpenPanel (or receive the drop). Pass files to `onDir({target:{files}})` as File-like objects with `name`, `size`, `webkitRelativePath` and `slice(a,b).arrayBuffer()`. Reading only the first 256 KB plus the preview range is the fast path; see `readOne`.
- **writeInto(files, label)**: choose the destination once per shoot, write each `{name, data}` (`data` is Uint8Array for .xmp, a File for `Picks/*.DNG` copies). Keep the existing `.lumina-bak` behaviour for overwritten sidecars. Return `{n, folder, path, errors:[{name, reason}]}`. Copies: stream, then checksum-verify (ROADMAP trust rule 3).
- **download**: not used in the app (writeInto always succeeds or returns errors).

## Changed since v5 (`reference/plumbing.js`)
- The REQUIRED member list there is out of date. Re-derive it from Sets v8: `onKey, setState, setView, say, openFolder, openAt, dropFiles, onDir, writeInto, runExport, reveal, copyPath, fetchWf, cacheRemove, build, forget, saveGolden`.
- The session save keys add `tsz` and `prefs.tszSet`. Session storage is native (`saveSession`). The page's localStorage key in the browser is `lumina-v4-shoot:<name>|<n>|<first>|<last>`.
- Working files: in the app the page shows one segment, "Previews & thumbnails". Return real bytes.
- `card.sony` now means "has ARW or DNG". Rename on the native side if you like, but keep the field.

## Edit (embedded)
> **v0.02:** native Edit rendering ships. The new calls (auto, prefetch, canvas, preview, histogram, facts) are in **BRIDGE-v0.02.md**. That file wins over this section.

Edit reads the shoot from `window.luminaShoot()` (set by Sets) and stores looks under its `store-key` prop. Native RAW rendering for Edit and 100% zoom is post-v0.01. The tone mapper port is in "Handoff - Tone mapper.md".

## Sources (new)
The page tracks sources per shoot (`this._sources`, `this._srcOf[path]`) and shows them in the Sources panel. Native supplies:
| Member | Type | Used for |
|---|---|---|
| sources | [{id, missing}] | marks a source "not connected" |
| reconnect(id) | fn | re-resolve the bookmark, or ask the user to locate the folder |
| pending | [{source, n}] \| null | watched-folder files waiting → "N new in Downloads · Pull in" |
| pullPending() | fn | read the pending files and pass them to `onDir({target:{files}, add:true, src:{kind:'downloads'}})` |
| phone | {name, photos, raw, already, cloud} \| null | phone connected by cable (ImageCaptureCore) |
| importPhone('new'\|'choose') | fn | copy RAWs from the phone to the Lumina library, then `onDir(... add:true, src:{kind:'phone'})` |
| addFrom(where) | fn (optional) | native picker for 'phone' \| 'folder' \| 'pictures' \| 'downloads' \| 'desktop' |

`onDir(e)` accepts `e.add` (merge into the open shoot) and `e.src = {kind, label}`. On add, the page:
- skips files already present (path + size)
- drops duplicates by serial + time + size, and reports the count
- runs the second-camera clock check, which awaits the merge preview before building

Native should also hash-confirm duplicates. Card mount: set `card.already` (frames already in the open shoot) so the card panel can say so.

## Folder buttons — REMOVED from Open in v0.0.1
The Open screen no longer has "Go straight to" buttons. It uses ⌘O, drag and drop, and the phone page. The recipe below still applies to the Sources panel Add buttons (`lumina.addFrom`).

## (reference) "Go straight to" buttons and Add buttons
**Do they work today?** They only partly work, and only in a desktop Chrome tab.
- Pictures, Downloads and Desktop open Chrome's folder picker in that folder, and each button remembers its last folder.
- Card can't start on a volume, so Chrome opens the generic picker.
- Inside WKWebView there is no `showDirectoryPicker`, so every button falls back to the generic file input.

**The Mac app must implement them natively.** The page already calls these when `lumina.app` is true:
- `lumina.openAt(where)` on the Open screen (starts a new shoot)
- `lumina.addFrom(where)` in the Sources panel (adds to the open shoot)

`where` is `'card' | 'pictures' | 'downloads' | 'desktop' | 'folder' | 'phone'`.

### Native recipe (Swift, App Sandbox)
1. Start folder per button:
   - pictures → `FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]`
   - downloads → `.downloadsDirectory`
   - desktop → `.desktopDirectory`
   - card → the mounted volume from the card watcher (NSWorkspace.didMountNotification; DCIM present), e.g. `/Volumes/Untitled/DCIM`. If no card is mounted, show the card panel's "Insert a card" state instead of a picker.
   - folder → the last folder used for 'folder'
   - phone → see "Phone" below (not a picker)
2. Remember the last folder per button. Store a security-scoped bookmark per `where` in UserDefaults (`lumina.lastDir.<where>`). If it resolves (not stale), use it as `panel.directoryURL`; otherwise use the default from step 1.
3. Show the panel:
```swift
let p = NSOpenPanel()
p.canChooseDirectories = true; p.canChooseFiles = true; p.allowsMultipleSelection = true
p.directoryURL = startURL(for: where)
p.prompt = isAdd ? "Add to shoot" : "Open"
p.allowedContentTypes = [UTType("com.sony.arw-raw-image")!, .rawImage, UTType("com.adobe.raw-image")!, .folder]
guard p.runModal() == .OK else { return }
```
4. For each chosen URL:
   - `startAccessingSecurityScopedResource()`
   - save a bookmark (`.withSecurityScope`) as a shoot **source** (it reconnects later)
   - enumerate RAWs (ARW/DNG), skipping hidden files and `.lumina-bak`
   - pass them to the page as File-like objects (name, size, webkitRelativePath = "<top folder>/<rel path>", slice().arrayBuffer() backed by FileHandle reads)
   - call `logic.onDir({target:{files}, add:isAdd, src:{kind:where}})`
5. Entitlements:
   - `com.apple.security.app-sandbox`
   - `com.apple.security.files.user-selected.read-write` (needed to write sidecars next to RAWs)
   - `com.apple.security.files.bookmarks.app-scope`
   - optional, so Pictures/Downloads open without a prompt: `com.apple.security.assets.pictures.read-only` and `com.apple.security.files.downloads.read-write`
   - never Full Disk Access (trust rule 10)
6. Removable volumes:
   - the first read of a card triggers the macOS "removable volume" prompt, so set `lumina.willPromptAccess = true` and the page shows its explainer first
   - add `NSRemovableVolumesUsageDescription` to Info.plist
7. Phone (`where === 'phone'`):
   - use ImageCaptureCore: `ICDeviceBrowser` with `.camera` mask, both local and USB
   - on `didAdd`, set `lumina.phone = {name, photos, raw, already, cloud}`
   - `importPhone('new')` downloads RAW items (UTI dng/raw) to `~/Pictures/Lumina/<shoot>/Phone/` with `ICDownloadOption`, hashes each copy, then adds that folder as a source with `kind:'phone'`
   - never call delete on the device
   - count items whose file size is 0 or that aren't downloadable as `cloud` (iCloud-only)
   - add `NSCameraUsageDescription`; ImageCaptureCore needs it for phones on recent macOS
8. Drag and drop onto the window:
   - accept file URLs in the WKWebView host
   - bookmark them like step 4, then call `onDir` with `add:true` (or a new shoot if none is open), `src:{kind:'drop'}`
9. Test each button with:
   - a fresh install (no bookmarks)
   - after a reboot (bookmarks resolve)
   - after moving the folder (stale bookmark → default folder, with the source showing "Reconnect")
   - with no card mounted

## Phone upload — v0.0.1 scope
Ships as the manual **Phone photos** page: AirDrop, Photos-app export or Android+OpenMTP, then drop / Choose files / Watch Downloads.
- **Native, needed for v0.0.1:** `lumina.watchAirdrop(on)` (FSEvents on Downloads) and `window.luminaPhoneArrived(files, lossyNames)`.
- Everything below marked cable or Photos library is **v0.1**. The page currently hides those cards.

## Phone in the moment (reference, v0.1)
Two ways in, both adding to the open shoot as a `phone` source:
- **AirDrop:** works today in a Chrome tab. "Listen for AirDrop" asks for Downloads once, then checks it every 1.5 s for new DNG/ARW files, skipping partial downloads and files still being written.
  - New RAWs pop up as "N RAWs from phone · Add to shoot (⇧⏎)".
  - HEIC/JPEG arrivals are counted with a tip: "use Options → All Photos Data". iOS sends ProRAW as DNG only with that option.
  - **Native:**
    - `lumina.watchAirdrop(on)` starts or stops an FSEvents watch on `~/Downloads` (user-selected bookmark).
    - On new complete RAW files, call `window.luminaPhoneArrived(files, lossyCount)` with File-like objects whose `webkitRelativePath` is `'AirDrop/<name>'`.
    - Treat a file as complete when its size has been stable for 1 s and it has no `.download` bundle.
- **Cable:** Mac app only.
  - `lumina.phone = {name, photos, raw, already, cloud}` while a trusted phone is connected (ImageCaptureCore).
  - `lumina.importPhone('new')` copies only the RAWs not already in the shoot to `~/Pictures/Lumina/<shoot>/Phone/`, hash-verifies them, then calls `onDir({target:{files}, add:true, src:{kind:'phone', label:'Cable'}})`.
  - Never delete from the device.
- Either way, the page dedupes by serial + time + size and runs the clock-offset check. Phone clocks are network-set, so the camera is usually the one that's off.

## Photos library (Mac app, PhotoKit) — v0.1
- `lumina.photos = {recent, raw, heic, cloudOnly}` once Photos access is granted. Count assets from the last 7 days.
  - RAW = `PHAssetResource` of type `.alternatePhoto` or `.photo` with a UTI conforming to `public.camera-raw-image` (ProRAW is `com.adobe.raw-image`).
  - HEIC/JPEG-only assets are counted as `heic` and skipped.
- `lumina.importPhotos('recent'|'choose')`: for each RAW asset, call `PHAssetResourceManager.writeData(for:toFile:options:)` with `isNetworkAccessAllowed = true` (downloads iCloud-only originals, with progress) into `~/Pictures/Lumina/<shoot>/Photos/`. Hash it, then call `onDir({target:{files}, add:true, src:{kind:'phone', label:'Photos'}})`.
- Read-only for v1. No writes to the library. Info.plist: `NSPhotoLibraryUsageDescription`.
- The page labels every arrival as RAW, or HEIC/JPG (dimmed, "not added"), so it's clear from the start which files count.

## As-shot white balance (Edit)
Edit starts the WB sliders from each photo's as-shot values. The app fills two fields on each photo object passed to `onDir` (or from `parseHead` once native decode exists):
| Field | Type | Source |
|---|---|---|
| `wbK` | number, Kelvin | ARW: Sony maker note ColorTemperature. DNG: `AsShotNeutral` (0xC628) converted with the DNG's ColorMatrix/CalibrationIlluminant, or CIRAWFilter `neutralTemperature` |
| `wbTint` | number, −150…150 | DNG/CIRAWFilter `neutralTint`. ARW: maker note tint, if present |

They pass through `buildShoot` → `editShoot()` as `wbShot` and `tintShot`. Missing values fall back to 5500 K and 0.

## MENUS (v7)
The native menu bar calls `window.luminaCommand(name)` (Sets). When Edit is the active step, Edit-menu items call `window.luminaEdit.<fn>()` instead. Items marked — have no menu entry and stay keyboard-only.

**Lumina:** About Lumina · Settings… ⌘, (`settings`) · Show Tour (`tour`) · Quit ⌘Q (native; ask first if `luminaUnsaved() > 0`)

**File:**
- Open… ⌘O (`open`). Inside a shoot this opens Sources, to add.
- Add from Phone… (`phone`)
- Save ⌘⏎ (`save`)
- Show in Finder ⌘R (`finder`)

**Edit:**
| Item | Shortcut | Pick / Open / Save | Edit step |
|---|---|---|---|
| Undo | ⌘Z | Undo (`undo`) | Undo Edit → `luminaEdit.undo()` |
| Redo | ⇧⌘Z | Redo (`redo`) | Redo Edit → `luminaEdit.redo()` |
| Copy | ⌘C | — (disabled) | Copy Settings → `luminaEdit.copy()` (copies the look, not crop/rotation) |
| Paste | ⌘V | — (disabled) | Paste Settings → `luminaEdit.paste()` |

**Pick** (enabled on the Pick step):
- Keep · P (`keep`)
- Keep Row · ⌘A (`keepRow`)
- Show Picks Only · ⇧P (`pass`). This is the second-pass toggle, a checkmark item; with nothing kept it says "keep something first".
- Open Stack · ⏎ (`openStack`) · Close Stack · esc (`closeStack`)
- Next Unseen · ⇧U (`unseen`)

**View:**
- Open ⌘1 (`stepOpen`) · Pick ⌘2 (`stepCull`) · Edit ⌘3 (`stepEdit`) · Save ⌘4 (`stepSave`)
- Large View · Space (`large`)
- Smaller Tiles · − (`smaller`) · Larger Tiles · = (`larger`)
- Show Key Bar · H (`keyBar`)

**Help:** Keyboard Shortcuts · ? (`shortcuts`) · Lumina FAQ (`faq`) · Report a Bug… (mailto anikethcov@gmail.com)


The full command list is: open, save, finder, undo, redo, keepRow, keep, pass, openStack, closeStack, stepOpen, stepCull, stepEdit, stepSave, large, unseen, smaller, larger, keyBar, shortcuts, settings, faq, tour, phone. `keepStack` was removed: in v7, ⇧P toggles Show Picks Only.
