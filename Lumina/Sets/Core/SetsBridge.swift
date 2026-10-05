import AppKit
import WebKit

/// Where folders come from. The app asks the user (NSOpenPanel); the probe answers from a script.
@MainActor
protocol SetsChooser: AnyObject {
    /// The page asked to open a folder of ARWs (its `<input webkitdirectory>`).
    func chooseSource(allowsDirectories: Bool) async -> URL?
    /// Export needs a destination. `refusal` is set when the previous pick was refused.
    func chooseDestination(label: String, suggested: URL?, refusal: String?) async -> URL?
    /// "Cull this card" in the App Sandbox, the first time for this card (T10): the folder panel,
    /// opened `at` the card's DCIM (or its root), asking for the card named `name`. `refusal` is
    /// set when the previous pick was not on that card.
    func chooseCard(name: String, at: URL, refusal: String?) async -> URL?
    /// Folders and photos for the open shoot ("Add to shoot", the page's own file inputs, a source
    /// to find again): the panel opened `at` a folder (nil: where the panel likes), `files` whether
    /// single photos may be picked beside folders, `multiple` whether more than one.
    func chooseSources(at: URL?, files: Bool, multiple: Bool, prompt: String, message: String) async -> [URL]
    /// The Downloads folder, to watch it for AirDrop arrivals: the panel opened `at` it. The pick
    /// is the grant (App Sandbox); it is asked once and kept as a bookmark.
    func chooseDownloads(at: URL) async -> URL?
}

extension SetsChooser {
    /// A chooser with one folder panel (the probe's scripted one) answers both from it.
    func chooseSources(at: URL?, files: Bool, multiple: Bool, prompt: String, message: String) async -> [URL] {
        await chooseSource(allowsDirectories: true).map { [$0] } ?? []
    }
    func chooseDownloads(at: URL) async -> URL? { await chooseSource(allowsDirectories: true) }

    /// A chooser with no panel of its own for cards (the probe's scripted one) answers from its
    /// source queue.
    func chooseCard(name: String, at: URL, refusal: String?) async -> URL? { await chooseSource(allowsDirectories: true) }
}

/// Native side of the page's plumbing (see Web/plumbing.js). Owns the folders the user opened,
/// the card watcher and every export.
@MainActor
final class SetsBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var webView: WKWebView?
    let chooser: SetsChooser
    let supportDir: URL
    let cards = SetsCardWatcher()
    /// Reads the opened folders for the page (listing, heads, previews). It also holds the opened
    /// folders by name: the page knows files as "<folder>/<file>".
    let ingest = SetsIngest()
    /// How alike two photos' previews are, for the page's retake stacks (`lumina.near`).
    private(set) lazy var near = SetsNear(ingest: ingest)
    private var pendingSource: URL?
    /// The recent shoot `pendingSource` reopens: the folder keeps that shoot's id wherever its
    /// bookmark found it (renamed or moved), instead of becoming a second shoot.
    private var pendingShoot: String?
    /// `pendingSource` is opened as some files of that folder, not the folder (a root of single
    /// files): the root's name and the files; `nid` when the shoot's source list already has them.
    private var pendingLoose: (name: String, only: Set<String>, nid: String?)?
    /// What the open shoot's first source is to the page's Sources panel ("drop", "phone"…), when
    /// it is not just a folder or a card.
    private var pendingKind: String?
    /// The open shoot's first source, as `pendingKind` named it (kept for a read started again).
    private var openKind: String?
    private var lastOpened: URL?
    /// The folder the user picked for the last export in this run: with the opened folders, the
    /// only places Show in Finder opens (`revealURL`).
    private var lastExport: URL?
    /// The open folder's shoot id, volume and place (`SetsShootStore.id(for:)`), taken while it was
    /// being opened. All come from the volume's UUID, which is gone once a card is pulled: asked
    /// again then, the same card would be another shoot and the decisions made while it was out
    /// would be filed under that one. `bookmark` is made then too, while the grant is fresh; nil
    /// for a reopen (the index keeps the one it came through).
    private var lastOpenedKey: (id: String, volume: String?, place: String, bookmark: Data?)?
    /// Security-scoped access: the only caller of start / stop (T9).
    let access: SetsAccess
    /// The folder macOS last refused to list (SAFETY.md 5): checkAccess and reopen use it.
    private var deniedFolder: URL?
    /// The folder being listed now. Opening another one cancels it (threat model T5).
    private var listing: Task<(Bool, SetsIngest.Listing), Never>?
    /// The largest session the page may store (threat model T5). A session is a few maps keyed by
    /// path ("100MSDCF/DSC01234.ARW") plus a look string per edited photo: about 280 bytes a photo
    /// with every map set and a look on each, so 16 MB holds about 58,000 photos, more than the
    /// listing lets through as RAW + sidecar pairs (100,000 entries / 2).
    static let maxSessionBytes = 16 << 20
    /// What `shootOpened` takes as a shoot's bodies (T5): a camera's EXIF model name is under 32
    /// bytes, its RAW's path inside the folder under a path's limit, and a shoot has a handful.
    static let maxModelBytes = 64
    static let maxRelBytes = 4096
    static let maxBodies = 16

    /// Why the page's session can't be stored, or nil when it can.
    static func sessionRefusal(_ json: String) -> String? {
        let n = json.utf8.count
        return n > maxSessionBytes ? "session too big: \(n) bytes, the limit is \(maxSessionBytes)" : nil
    }
    let shoots: SetsShootStore
    /// The open shoot's roots, the first one first: each a folder, or some files of one, under the
    /// name the page's paths start with. `nid`: its entry in the shoot's source list.
    struct OpenRoot { var name: String; var url: URL; var only: Set<String>?; var nid: String? }
    private(set) var shootRoots: [OpenRoot] = []
    /// The sources a shoot has besides its first folder, with their bookmarks.
    let sources: SetsShootSources
    /// Access started for sources reached through their bookmarks, let go with the shoot.
    private var sourceHolds: [Int] = []
    /// What the user handed the app in this run and the page may name: dropped items, picks of the
    /// page's own file inputs. Newest last. Only these are ever matched to the page's `File`s.
    private var granted: [(url: URL, isDirectory: Bool)] = []
    static let maxGranted = 4096
    /// AirDrop watch (BRIDGE.md "Phone upload"): the Downloads folder the user granted, the files
    /// that arrived while watching (the only ones readable as "AirDrop/<name>"), the watcher.
    private let downloads = SetsDownloadsWatcher()
    private var airdropFolder: URL?
    private var airdropHold: Int?
    private var airdropNames: Set<String> = []
    static let airdropName = "AirDrop"
    private(set) var ready = false
    var onEvent: ((String) -> Void)?
    /// The recent-shoots list changed (File ▸ Open Recent).
    var onShootsChanged: (() -> Void)?
    /// The Edit canvas (addendum §2): native pixels over the page's canvas rect, or the image
    /// fallback path when there is no Metal device. Made by `attachCanvas` once the web view is up.
    private(set) var canvas: LookCanvasController?
    private var canvasError: String?
    /// The open shoot's id and header (`Lumina.json`): the decoder map per body and the pin.
    private(set) var shootId: String?
    private(set) var header = LookShootHeader()
    private var probing: Set<String> = []
    /// The body of the photo on the Edit canvas ("?" when the page read no model), so a decoder
    /// map that lands after `canvasEnter` reaches it.
    private var canvasModel: String?
    /// ⌘R: Finder, with the file selected. The probe swaps this out so a fuzz run never brings
    /// Finder forward on the desktop of whoever is using the Mac.
    var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

    init(chooser: SetsChooser, supportDir: URL, access: SetsAccess? = nil) {
        self.chooser = chooser
        self.supportDir = supportDir
        self.shoots = SetsShootStore(supportDir: supportDir)
        self.sources = SetsShootSources(supportDir: supportDir)
        self.access = access ?? SetsAccess()
        super.init()
        SetsAccess.removeLegacyBookmarks(supportDir: supportDir)
        self.access.onLog = { [weak self] in self?.onEvent?("access: \($0)") }
        cards.onChange = { [weak self] card, removed in self?.cardChanged(card, removed: removed) }
        // A card the sandbox will not let the app list (T10): the grant kept for it, if any; and
        // its hold let go when it goes.
        cards.grant = { [weak self] uuid, volume in self?.cardGrant(uuid: uuid, volume: volume) }
        cards.release = { [weak self] uuid in self?.access.releaseCard(uuid) }
        cards.onWillUnmount = { [weak self] volume in
            guard let self else { return }
            let stopped = self.ingest.markGone(volume: volume)
            if !stopped.isEmpty { self.onEvent?("eject: stopped reading \(stopped.joined(separator: ", "))") }
        }
    }

    func install(in conf: WKWebViewConfiguration) {
        conf.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "lumina")
    }

    // MARK: The Edit canvas

    /// Lays the canvas overlay into `host` (above the web view). Nil host, no rules file or no
    /// Metal device → the image path, which plumbing drives through `lumina://render`.
    func attachCanvas(host: NSView?) {
        guard canvas == nil else { return }
        // LUMINA_CANVAS=image forces the image path (the probe measures both). Debug builds and
        // the probe only; the app's Release build has no such read (S4).
        #if DEBUG || LUMINA_TOOLS
        let host = ProcessInfo.processInfo.environment["LUMINA_CANVAS"] == "image" ? nil : host
        #endif
        do {
            let pipe = try LookPipeline(rules: LookRules.bundled())
            let c = LookCanvasController(pipeline: pipe, host: host)
            c.onFacts = { [weak self] facts in self?.push("__lumina.editFacts(\(Self.json(facts)))") }
            c.onStats = { [weak self] stats in self?.push("__lumina.editStats(\(Self.json(stats)))") }
            c.onPresented = { [weak self] seq in self?.push("__lumina.editPresented(\(seq))") }
            c.onDecoderFallback = { [weak self] rel, from, to in self?.onEvent?("raw \(from) failed for \(rel): using raw \(to)") }
            canvas = c
            onEvent?("canvas: \(c.path.rawValue)")
        } catch {
            canvasError = "\(error)"
            onEvent?("canvas: image (\(error))")
        }
    }

    private func push(_ js: String) {
        guard ready else { return }
        webView?.evaluateJavaScript("window.__lumina && \(js)", completionHandler: nil)
    }

    static func json(_ v: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed])).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    private func preview(_ d: Any?) -> LookBases.PreviewFallback? {
        guard let p = d as? [String: Any] else { return nil }
        let o = SetsNumber.fileRange(p["o"]), l = SetsNumber.fileRange(p["l"])
        guard o > 0, l > 0 else { return nil }
        return LookBases.PreviewFallback(offset: o, length: l, orientation: SetsNumber.orientation(p["ori"]))
    }

    /// A photo's embedded preview as the page names it: `{p, o, l, ori}` (numbers or strings).
    nonisolated static func ingestPreview(_ d: Any?) -> SetsIngest.Preview? {
        guard let i = d as? [String: Any], let rel = i["p"] as? String else { return nil }
        return SetsIngest.Preview(rel: rel, offset: SetsNumber.fileRange(i["o"]), length: SetsNumber.fileRange(i["l"]),
                                  orientation: SetsNumber.orientation(i["ori"]))
    }

    private func roi(_ d: Any?) -> LookCanvasSchedule.ROI? {
        SetsNumber.roi(d).map { LookCanvasSchedule.ROI(x: $0.x, y: $0.y, w: $0.w, h: $0.h) }
    }

    /// What the page's facts line and the probe read: the canvas path, the shoot's decoder map,
    /// the pin and whether an update is on offer.
    func editFacts() -> [String: Any] {
        let orNull = { (v: Int?) -> Any in v.map { $0 as Any } ?? NSNull() }
        var out: [String: Any] = ["canvas": canvas?.path.rawValue ?? "image", "raw9": header.raw9Active, "raw9Present": header.bodies.values.contains(where: \.raw9),
                                  "decoder": orNull(header.decoderVersion), "newest": orNull(header.newest), "offerUpdate": header.offersUpdate,
                                  "slowed": LookDecoderProbe.slowed,
                                  "bodies": header.bodies.mapValues { ["supported": $0.supported, "raw9": $0.raw9, "fastest": orNull($0.fastest), "developMs": $0.developMs] as [String: Any] }]
        if let e = canvasError { out["canvasError"] = e }
        return out
    }

    /// The decoder versions for one body: the canvas tier and the region / export tier.
    private func decoders(for model: String?) -> (canvas: Int?, region: Int?) {
        let body = model.flatMap { header.bodies[$0] }
        return (LookRawPolicy.version(for: .canvas, body: body, pinned: header.decoderVersion), LookRawPolicy.version(for: .region, body: body, pinned: header.decoderVersion))
    }

    /// Measures the decoder map for bodies not yet in the header, at `.utility`, one RAW per
    /// body; then pins the shoot (first open only) and tells the page.
    private func probeBodies(_ bodies: [String: String]) {
        guard let id = shootId else { return }
        let todo = bodies.filter { header.bodies[$0.key] == nil && !probing.contains($0.key) }.compactMap { m, rel in ingest.resolve(rel).map { (m, $0) } }
        guard !todo.isEmpty else { return }
        for (m, _) in todo { probing.insert(m) }
        let rules = canvas?.pipeline.rules ?? (try? LookRules.bundled()) ?? LookRules()
        Task.detached(priority: .utility) { [weak self] in
            var found: [(String, LookDecoderInfo)] = []
            for (m, url) in todo { found.append((m, LookDecoderProbe.probe(url: url, rules: rules))) }
            let done = found
            await MainActor.run {
                guard let self, self.shootId == id else { return }
                for (m, info) in done { self.header.bodies[m] = info; self.probing.remove(m) }
                if self.header.decoderVersion == nil, let pin = LookRawPolicy.pin(for: self.header.bodies) {
                    self.header.decoderVersion = pin
                    self.header.pinnedAt = Date()
                    self.header.pinnedOn = ProcessInfo.processInfo.operatingSystemVersionString
                }
                try? self.shoots.saveHeader(id, self.header)
                if let m = self.canvasModel, done.contains(where: { $0.0 == m }) {
                    let d = self.decoders(for: m)
                    self.canvas?.setDecoders(decoder: d.canvas, regionDecoder: d.region)
                }
                self.onEvent?("decoders: " + done.map { "\($0.0) \($0.1.supported) raw9=\($0.1.raw9) fastest=\($0.1.fastest ?? 0)" }.joined(separator: "; ") + " · pinned \(self.header.decoderVersion ?? 0)")
                self.push("__lumina.editHeader(\(Self.json(self.editFacts())))")
            }
        }
    }

    // MARK: Opening folders

    /// Called from the web view's UI delegate for the page's folder input.
    func openPanel(allowsDirectories: Bool) async -> [URL]? {
        let url: URL?
        let reopening: String?
        var loose = pendingLoose
        let kind = pendingKind
        if let pending = pendingSource { url = pending; reopening = pendingShoot; pendingSource = nil; pendingShoot = nil; pendingLoose = nil; pendingKind = nil }
        else { url = await chooser.chooseSource(allowsDirectories: allowsDirectories); reopening = nil; loose = nil; pendingLoose = nil; pendingKind = nil }
        guard let url else { return nil }
        // The shoot open before is let go with its added sources.
        releaseSources()
        // A shoot of single files reopened: its files are reached through their own bookmarks.
        if let l = loose, let nid = l.nid, let id = reopening, let entry = sources.load(id).entries.first(where: { $0.nid == nid }),
           let found = activate(entry, shoot: id) { loose = (l.name, found.only ?? l.only, nid) }
        // The open shoot is this folder now. A reopen already started its access (scoped); a
        // panel's pick needs none, and the shoot open before is let go either way.
        access.openShoot(url, scoped: false)
        ingest.register(url, as: loose?.name, only: loose?.only)
        lastOpened = url
        let volume = SetsFileOps.volumeID(url)
        let place = loose.map { SetsShootSources.loosePlace(folder: SetsShootStore.id(for: url), names: $0.only) } ?? SetsShootStore.id(for: url)
        // A recent's own id; else the shoot that is at this place; else a recent renamed or moved
        // here since (its bookmark follows it); else a new shoot.
        let id = reopening ?? shoots.index().first(where: { $0.currentPlace == place })?.id
            ?? (loose == nil ? access.movedShoot(to: url, volume: volume, in: shoots)?.id : nil) ?? shoots.shootID(at: place)
        // The bookmark the index keeps, made while the grant is fresh. The only one: there is no
        // second copy elsewhere. Single files have theirs in the shoot's source list instead.
        lastOpenedKey = (id, volume, place, reopening == nil && loose == nil ? try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) : nil)
        var first = OpenRoot(name: loose?.name ?? url.lastPathComponent, url: url, only: loose?.only, nid: loose?.nid)
        if let l = loose, l.nid == nil {
            // Opened from single files for the first time: they are the shoot's first source.
            var stored = sources.load(id)
            stored.entries.removeAll { $0.isPrimary }
            let entry = makeEntry(&stored, url: url, only: l.only, name: l.name, kind: kind ?? "drop", label: l.name, primary: true)
            stored.entries.insert(entry, at: 0)
            try? sources.save(id, stored)
            first.nid = entry.nid
        }
        shootRoots = [first]
        openKind = kind
        onEvent?("opened \(url.path)")      // exactly this: the probe's sandbox checks read the path from it
        if id != place { onEvent?("shoot \(id) is at a new place \(place)" + (reopening == nil ? " (picked)" : " (reopened)")) }
        return [url]
    }

    /// Opens a folder in the page as if the user picked it (menu, "Cull this card", a recent).
    /// `shoot`: the recent shoot this is, whatever its folder is called now.
    func open(_ url: URL, shoot: String? = nil) {
        pendingSource = url
        pendingShoot = shoot
        pendingLoose = nil
        pendingKind = nil
        webView?.evaluateJavaScript("window.__lumina && __lumina.openFolder()", completionHandler: nil)
    }

    /// No shoot is open any more (File ▸ Close Shoot, or the page started over): its folder's
    /// access is stopped.
    func closeShoot() {
        access.closeShoot()
        releaseSources()
        shootRoots = []
    }

    func resolve(_ rel: String) -> URL? { ingest.resolve(rel) }      // no ../ escapes

    // MARK: Cards

    private func cardChanged(_ card: SetsCardWatcher.Card?, removed: SetsCardWatcher.Card?) {
        // Pulled: stop every read on it first, then tell the page what it has.
        let stopped = removed.map { ingest.markGone(volume: $0.volume) } ?? []
        if let card, !ingest.revive(volume: card.volume).isEmpty { onEvent?("card back: its folders read again") }
        let names = (try? JSONSerialization.data(withJSONObject: stopped)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        // Whether the open shoot lives on the volume that came or went (SAFETY.md 3).
        let ours = { (volume: URL) -> Bool in
            guard let open = self.lastOpened else { return false }
            let v = SetsIngest.plainPath(volume), o = SetsIngest.plainPath(open)
            return o == v || o.hasPrefix(v + "/")
        }
        var js: String
        if let card {
            js = "window.__lumina && __lumina.card(true, \(cardJSON(card)))"
            if ours(card.volume) { js += "; window.__lumina && __lumina.cardBack()" }
        } else {
            js = "window.__lumina && __lumina.cardGone(\(names), \(removed.map { ours($0.volume) } ?? false))"
        }
        if ready { webView?.evaluateJavaScript(js, completionHandler: nil) }
        // A source of the open shoot on that volume is "not connected" now, or connected again.
        if shootRoots.count > 1 { push("__lumina.sources(\(Self.json(sourcesStatus())))") }
        onEvent?(card.map { "card in \($0.uuid)" } ?? "card out \(removed?.uuid ?? "?")" + (stopped.isEmpty ? "" : " · stopped reading \(stopped.joined(separator: ", "))"))
    }

    /// The page's card: `{name, photos, bytes, sony, uuid, path}` as before, plus `known` and
    /// `grant`. A card the app may not read yet (sandbox, first time) has `known: false` and
    /// `photos`, `bytes`, `sony` null: they cannot be known before the user picks it.
    func cardJSON(_ c: SetsCardWatcher.Card) -> String {
        let none = NSNull()
        let o: [String: Any] = ["name": c.name, "photos": c.known ? c.arwCount : none, "bytes": c.known ? c.bytes : none, "sony": c.known ? c.sony : none,
                                "uuid": c.uuid, "path": c.volume.path, "known": c.known, "grant": c.grant ?? none]
        return (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    private var cardGrants: SetsCardGrants { SetsCardGrants(supportDir: supportDir) }

    /// A grant kept for this card, its access started and held while it is in: the bookmark made
    /// when it was picked for "Cull this card" (`cards.json`, by volume UUID), else a recent shoot
    /// opened at the card's root or DCIM (File ▸ Open on the card; its bookmark is in the index).
    /// How it was found, or nil.
    private func cardGrant(uuid: String, volume: URL) -> String? {
        if let data = cardGrants.bookmark(uuid) {
            if let r = access.holdCard(uuid, bookmark: data) {
                if r.stale, let renewed = access.makeBookmark(r.url) { try? cardGrants.save(uuid, bookmark: renewed, path: r.url.path) }
                onEvent?("card \(uuid): granted by its bookmark (\(r.url.lastPathComponent))")
                return "bookmark"
            }
        }
        let v = SetsIngest.plainPath(volume)
        for s in shoots.index() where s.volumeUUID == uuid {
            guard let data = s.bookmark, let at = access.peek(data) else { continue }
            let p = SetsIngest.plainPath(at)
            guard p == v || p.lowercased() == v.lowercased() + "/dcim", access.holdCard(uuid, bookmark: data) != nil else { continue }
            onEvent?("card \(uuid): granted by recent shoot \(s.id)")
            return "recent"
        }
        return nil
    }

    /// Why a folder picked for "Cull this card" is refused (the panel asks again with it), or nil:
    /// only the card's own root or its DCIM folder will do.
    nonisolated static func cardPickRefusal(_ picked: URL, volume: URL, name: String) -> String? {
        let p = SetsIngest.plainPath(picked), v = SetsIngest.plainPath(volume)
        if p == v || p.lowercased() == v.lowercased() + "/dcim" { return nil }
        if p.hasPrefix(v + "/") { return "Choose the card \(name) itself, or its DCIM folder." }
        return "That folder is not on the card \(name). Choose the card."
    }

    /// "Cull this card": the card's DCIM folder, read in place. In the App Sandbox the first time
    /// for a card, the panel opens on it first; the pick is held while the card is in and kept as a
    /// bookmark by volume UUID, so the next time needs no panel. True when the page should not
    /// fall back to its own action (opened, or the user cancelled the panel).
    func cullCard() async -> Bool {
        guard let card = cards.current else { return false }
        if !card.known {
            let dcim = card.volume.appendingPathComponent("DCIM")
            let at = FileManager.default.fileExists(atPath: dcim.path) ? dcim : card.volume
            var refusal: String?
            while true {
                onEvent?("card panel at \(at.path)" + (refusal == nil ? "" : " (again)"))
                guard let picked = await chooser.chooseCard(name: card.name, at: at, refusal: refusal) else { onEvent?("card panel cancelled"); return true }
                guard cards.current?.uuid == card.uuid else { onEvent?("card panel: the card went meanwhile"); return true }
                if let why = Self.cardPickRefusal(picked, volume: card.volume, name: card.name) { refusal = why; onEvent?("refused card pick \(picked.path)"); continue }
                access.holdCard(card.uuid, picked: picked)
                if let data = access.makeBookmark(picked) {
                    do { try cardGrants.save(card.uuid, bookmark: data, path: picked.path) } catch { onEvent?("card \(card.uuid): bookmark not saved (\(error))") }
                } else { onEvent?("card \(card.uuid): no bookmark for \(picked.path)") }
                onEvent?("card \(card.uuid): granted by panel (\(picked.lastPathComponent))")
                guard cards.granted(card.uuid) else { access.releaseCard(card.uuid); return false }
                break
            }
        }
        guard let now = cards.current, now.known, let dcim = now.folders.first?.deletingLastPathComponent() else { return false }
        open(dcim)
        return true
    }

    // MARK: Page → native

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return (nil, "bad message") }
        switch op {
        case "ready":
            if let gaps = body["missing"] as? [String], !gaps.isEmpty {
                // A design sync removed or renamed something the plumbing needs.
                onEvent?("plumbing contract broken: \(gaps.joined(separator: ", "))")
                NSLog("Lumina plumbing contract broken: %@", gaps.joined(separator: ", "))
                return (false, nil)
            }
            ready = true
            // A page that starts (a launch, a reload after its process stopped) has no shoot open.
            closeShoot()
            stopAirdrop()
            webView?.evaluateJavaScript("window.__lumina && __lumina.card(\(cards.current != nil), \(cards.current.map(cardJSON) ?? "null"))", completionHandler: nil)
            onEvent?("ready")
            return (true, nil)
        case "cullCard":
            return (await cullCard(), nil)
        case "openFolder":
            return (await openListing(), nil)
        case "addFrom":
            // The Sources panel's Add (BRIDGE.md "Native recipe"): the panel, then what was picked
            // joins the open shoot (or is opened, when there is none).
            return (await addFrom(where: body["where"] as? String ?? "folder", add: body["add"] as? Bool ?? false, shoot: body["id"] as? String), nil)
        case "claimFiles":
            // The page was handed `File`s (a drop, its own file input, AirDrop arrivals) and is about
            // to read them: the same items, read by the Mac instead. Null when none of them is
            // something the user handed the app.
            return (await claimFiles(body["files"] as? [[String: Any]] ?? [], add: body["add"] as? Bool ?? false, shoot: body["id"] as? String,
                                     kind: body["kind"] as? String, label: body["label"] as? String), nil)
        case "shootSources":
            return (keepSources(shoot: body["id"] as? String ?? "", list: body["sources"] as? [[String: Any]] ?? []), nil)
        case "sourcesStatus":
            return (sourcesStatus(), nil)
        case "sourceReconnect":
            return (await reconnectSource(body["nid"] as? String ?? "", shoot: body["id"] as? String ?? ""), nil)
        case "watchAirdrop":
            return (await watchAirdrop(body["on"] as? Bool ?? false), nil)
        case "prefetch":
            let items = (body["items"] as? [[String: Any]] ?? []).compactMap(Self.ingestPreview)
            ingest.prefetch(items)
            return (items.count, nil)
        case "near":
            // How alike two photos are (Prompt 2 C): the page stacks retakes on it. Null when either
            // preview can't be measured; the page then keeps its own rule.
            guard let a = Self.ingestPreview(body["a"]), let b = Self.ingestPreview(body["b"]), let d = await near.distance(a, b) else { return (NSNull(), nil) }
            return (d, nil)
        case "ingestStats":
            return (ingest.snapshot.dictionary, nil)
        case "shootOpened":
            // The page finished reading a folder: remember it and hand back its saved session.
            guard let url = lastOpened ?? ingest.root(named: body["name"] as? String ?? "") else { return (nil, nil) }
            let key = url == lastOpened ? lastOpenedKey : nil
            let place = key?.place ?? SetsShootStore.id(for: url)
            let id = key?.id ?? shoots.shootID(at: place)
            // A shoot of single files is called what its root is (the folder is not the shoot).
            let looseName = url == lastOpened ? shootRoots.first.flatMap { $0.only == nil ? nil : $0.name } : nil
            // The bookmark made at open (nil for a reopen: upsert keeps the one it came through).
            let shoot = SetsShootStore.Shoot(id: id, title: looseName ?? (url.lastPathComponent == "DCIM" ? (cards.current?.name ?? "Card") : url.lastPathComponent),
                                             path: url.path, volumeUUID: key?.volume ?? SetsFileOps.volumeID(url), photos: SetsNumber.count(body["n"]) ?? 0,
                                             firstCapture: body["date"] as? String ?? "", opened: Date(),
                                             bookmark: key.map { $0.bookmark } ?? (looseName == nil ? try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) : nil),
                                             place: place)
            try? shoots.upsert(shoot)
            onShootsChanged?()
            onEvent?("shoot \(id) \(url.path)")
            let session = shoots.session(id).flatMap { String(data: $0, encoding: .utf8) }
            // The shoot header: the decoder map per body (measured once, at .utility) and the pin.
            shootId = id
            header = shoots.header(id)
            canvas?.leave()
            // A body is keyed by its EXIF model ("ILCE-7RM5") and kept in the shoot's header: a name
            // no camera writes, or more bodies than a shoot has, is neither measured nor stored (T5).
            if let bodies = body["bodies"] as? [String: String] {
                let real = bodies.filter { $0.key.utf8.count <= Self.maxModelBytes && $0.value.utf8.count <= Self.maxRelBytes }
                probeBodies(Dictionary(uniqueKeysWithValues: real.sorted { $0.key < $1.key }.prefix(Self.maxBodies).map { ($0.key, $0.value) }))
            }
            return (["id": id, "session": session ?? NSNull(), "header": editFacts()] as [String: Any], nil)
        case "shootHeader":
            return (editFacts(), nil)
        case "decoderUpdate":
            // The facts line's offer: move the pin to the newest decoder any body offers (§7).
            guard let id = shootId, let newest = header.newest else { return (false, nil) }
            header.decoderVersion = newest
            header.pinnedAt = Date()
            header.pinnedOn = ProcessInfo.processInfo.operatingSystemVersionString
            try? shoots.saveHeader(id, header)
            canvas?.tiles.drop()
            onEvent?("decoder pinned to \(newest)")
            return (editFacts(), nil)
        case "canvasEnter":
            // Entering Edit for a photo: bases for it now, its neighbours' at .utility.
            guard let rel = body["rel"] as? String, let url = resolve(rel) else { return (nil, "not in an opened folder") }
            // The page keys a body without a model "?" in shootOpened; the same here.
            let model = body["model"] as? String ?? "?"
            // The body's decoder map is measured right after the shoot opens: wait for it (briefly)
            // rather than build this photo's bases twice. A map that lands later still reaches the
            // canvas (probeBodies → setDecoders).
            let deadline = Date().addingTimeInterval(2)
            while probing.contains(model), Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
            canvasModel = model
            let d = decoders(for: model)
            let neighbours: [LookCanvasController.Neighbour] = ["prev", "next"].compactMap { k in
                guard let r = body[k] as? String, let u = resolve(r) else { return nil }
                return LookCanvasController.Neighbour(rel: r, url: u, preview: preview(body[k + "Preview"]))
            }
            // The photo's as-shot white balance (the page's temperature slider rests on it, plumbing's
            // `lookString`): in this answer when the photo's base is already developed, else pushed
            // through `__lumina.editHeader` when the base lands. Read off the base the canvas builds
            // anyway: no develop of its own, nothing waited for. No key at all for the embedded JPEG
            // standing in or a file without a readable value.
            canvas?.onAsShot = { [weak self] rel, wb in self?.push("__lumina.editHeader(\(Self.json(LookCanvasController.asShotHeader(rel: rel, wb))))") }
            canvas?.enter(rel: rel, url: url, look: body["look"] as? String ?? "", decoder: d.canvas, regionDecoder: d.region, preview: preview(body["preview"]), neighbours: neighbours)
            var out = editFacts()
            out["decoderCanvas"] = d.canvas.map { $0 as Any } ?? NSNull(); out["decoderRegion"] = d.region.map { $0 as Any } ?? NSNull()
            if let a = canvas?.asShotForReply() { out.merge(LookCanvasController.asShotHeader(rel: a.rel, a.wb)) { $1 } }
            return (out, nil)
        case "canvasLeave":
            canvasModel = nil
            canvas?.leave()
            return (true, nil)
        case "canvasLayout":
            // The page's canvas rect (CSS px, from the web view's top-left) and whether Edit shows.
            guard let c = canvas else { return (["path": "image"], nil) }
            // A rect that is not finite, or larger than any display (SetsNumber.canvasRect), is refused:
            // the canvas hides and keeps its size (`.null` is the rect LookCanvasController.layable refuses).
            let rect = SetsNumber.canvasRect(body)
            if rect == nil { onEvent?("canvasLayout refused: not a rect") }
            // `holes`: the page's chrome over the photo, at most 16, left see-through (LookCanvasHoles).
            let holes = rect.map { LookCanvasHoles.parse(body["holes"], in: $0) } ?? []
            c.layout(rect: rect ?? .null, visible: rect != nil && (body["visible"] as? Bool ?? false), dpr: CGFloat(SetsNumber.dpr(body["dpr"])), holes: holes)
            return (["path": c.path.rawValue], nil)
        case "canvasLook":
            guard let c = canvas, let look = body["look"] as? String else { return (0, nil) }
            let seq = c.look(look, drag: body["drag"] as? Bool ?? false, key: body["key"] as? Bool ?? false, roi: roi(body["roi"]), at: SetsNumber.pageClock(body["t"]),
                             pageSeq: SetsNumber.seq(body["seq"]))
            return (seq, nil)
        case "canvasDrag":
            if body["start"] as? Bool ?? false { canvas?.dragStart() } else { canvas?.dragEnd() }
            return (true, nil)
        case "canvasLoupe":
            canvas?.loupe(on: body["on"] as? Bool ?? false, roi: roi(body["roi"]))
            return (true, nil)
        case "canvasStats":
            var out = canvas?.snapshot() ?? ["path": "image"]
            out["facts"] = editFacts()
            if body["reset"] as? Bool ?? false { canvas?.resetMeasures() }
            return (out, nil)
        case "saveSession":
            guard let id = body["id"] as? String, let json = body["json"] as? String else { return (false, nil) }
            if let refusal = Self.sessionRefusal(json) {
                onEvent?("session refused: \(refusal)")
                return (false, refusal)
            }
            do {
                try shoots.saveSession(id, Data(json.utf8))
                if let sum = body["summary"] as? [String: Any] {
                    try shoots.saveSummary(id, photos: SetsNumber.count(sum["n"]), seen: SetsNumber.count(sum["dec"]), keepers: SetsNumber.count(sum["kp"]), last: sum["last"] as? String)
                }
                return (true, nil)
            } catch { return (false, "\(error)") }
        case "recents":
            return (shoots.index().map { recent($0) }, nil)
        case "reopen":
            return (reopen(id: body["id"] as? String ?? ""), nil)
        case "workingFiles":
            guard let id = body["id"] as? String else { return (0, nil) }
            return (shoots.workingBytes(id), nil)
        case "removeWorkingFiles":
            // The page's "clear" (v7, any step): Lumina's own files for the shoot go, its decisions stay
            // (BRIDGE.md: "keep the session until saved"). File ▸ Remove Working Files… is `removeShoot` (plumbing's `__lumina.removeWorkingFiles`).
            guard let id = body["id"] as? String, SetsShootStore.isID(id) else { return (false, nil) }
            return (shoots.removeWorking(id), nil)
        case "removeShoot":
            guard let id = body["id"] as? String, SetsShootStore.isID(id) else { return (false, nil) }
            try? shoots.remove(id)
            sources.remove(id)
            onShootsChanged?()
            return (true, nil)
        case "writeInto":
            return (await writeInto(label: body["label"] as? String ?? "", files: body["files"] as? [[String: Any]] ?? []), nil)
        case "readSidecars":
            return (await readSidecars(root: body["root"] as? String ?? "", files: body["files"] as? [String] ?? []), nil)
        case "writeSidecars":
            return (await writeSidecars(root: body["root"] as? String ?? "", files: body["files"] as? [[String: Any]] ?? []), nil)
        case "reveal":
            guard let url = revealURL(body["path"] as? String ?? "") else { return (false, nil) }
            reveal(url)
            onEvent?("reveal \(url.path)")
            return (true, nil)
        case "storeSet":
            // One of the page's stored keys that outlive a launch (`SetsPageStore`: tour seen, names, seen-before).
            guard let key = body["key"] as? String else { return (false, nil) }
            return (SetsPageStore(supportDir: supportDir).set(key, body["value"] as? String), nil)
        case "setPrefs":
            guard let prefs = body["prefs"] as? [String: Any] else { return (false, nil) }
            return (Self.savePrefs(prefs), nil)
        case "openSettings":
            // Privacy & Security → Files and Folders. Opening System Settings is the user's own click.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") { NSWorkspace.shared.open(url) }
            return (true, nil)
        case "checkAccess":
            guard let folder = deniedFolder else { return (true, nil) }
            return (await Task.detached(priority: .userInitiated) { !SetsIngest.accessDenied(folder) }.value, nil)
        case "reopenDenied":
            guard let url = deniedFolder else { return (false, nil) }
            deniedFolder = nil
            open(url)
            return (true, nil)
        case "reopenCurrent":
            // The card with the open shoot came back after a read it cut short: read it again.
            guard let url = lastOpened, FileManager.default.fileExists(atPath: url.path) else { return (false, nil) }
            let first = shootRoots.first
            open(url, shoot: lastOpenedKey?.id)
            if let first, let only = first.only { pendingLoose = (first.name, only, first.nid) }
            pendingKind = openKind
            return (true, nil)
        default:
            return (nil, "unknown op \(op)")
        }
    }

    /// Opens a recent shoot again through its security-scoped bookmark (`SetsAccess.reopen`: access
    /// started and held while it is the open shoot, a stale bookmark renewed). A folder renamed or
    /// moved on its volume is followed and stays the same shoot. False when the bookmark cannot be
    /// resolved or the folder is not there (card out, folder gone, a refusal): no fallback to the
    /// stored path, which is for display only.
    func reopen(id: String) -> Bool {
        guard let shoot = shoots.index().first(where: { $0.id == id }) else { return false }
        // A shoot opened from single files: back through their bookmarks (its folder was never granted).
        var stored = sources.load(id)
        if let first = stored.entries.first(where: { $0.isPrimary }), let names = first.files {
            // Where its files' bookmarks point; whether they are there is seen once the shoot holds them (openPanel).
            let found = zip(first.refs, names).compactMap { ref, name -> URL? in
                guard let url = Self.locate(ref, in: &stored), url.lastPathComponent == name else { return nil }
                return url
            }
            guard let folder = found.first?.deletingLastPathComponent() else { onEvent?("reopen \(id): none of its files can be found"); return false }
            open(folder, shoot: shoot.id)
            pendingLoose = (first.name, Set(found.filter { $0.deletingLastPathComponent().path == folder.path }.map(\.lastPathComponent)), first.nid)
            pendingKind = first.kind
            return true
        }
        guard let url = access.reopen(shoot, store: shoots) else { return false }
        open(url, shoot: shoot.id)
        return true
    }

    /// A recent shoot in the page's own SHOOTS shape: d, n, dec, kp, last, where (+ id, which the
    /// plumbing's libOpen reopens natively).
    private func recent(_ s: SetsShootStore.Shoot) -> [String: Any] {
        let day = s.firstCapture.split(separator: " ").first.map { $0.replacingOccurrences(of: ":", with: "-") } ?? ""
        return ["id": s.id, "d": day.isEmpty ? s.title : day, "n": s.photos, "dec": s.seen ?? 0, "kp": s.keepers ?? 0, "last": s.last ?? "", "where": s.path]
    }

    /// Show in Finder, only for what the user already pointed the app at (threat model T8, Q4
    /// finding F8): an opened folder's name, a page path inside one ("<folder>/sub/DSC.ARW", no
    /// links, as every native read), or an absolute path that is, links resolved, an opened folder,
    /// the folder of the last export, or something inside one of them (what Save and the export
    /// hand back to the page as `path` / `folder`). Anything else is nil and the op answers false:
    /// no other path, no fallback to the open folder.
    private func revealURL(_ path: String) -> URL? {
        let fm = FileManager.default
        guard !path.isEmpty else { return nil }
        guard path.hasPrefix("/") else {
            // A root of single files is not a folder to show: only its files are.
            let url = path.contains("/") ? resolve(path) : (ingest.allowed(named: path) == nil ? ingest.root(named: path) : nil)
            return url.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard fm.fileExists(atPath: url.path) else { return nil }
        let real = url.resolvingSymlinksInPath().path
        let opened = shootRoots.first?.only == nil ? lastOpened : nil      // not the folder single files came from
        let folders = ingest.rootURLs + [opened, lastExport].compactMap { $0 }
        let inside = folders.contains { folder in
            let f = folder.standardizedFileURL.resolvingSymlinksInPath().path
            return real == f || real.hasPrefix(f.hasSuffix("/") ? f : f + "/")
        }
        if inside { return url }
        return ingest.looseURLs.contains { $0.standardizedFileURL.resolvingSymlinksInPath().path == real } ? url : nil
    }

    /// The volume's name for the access banner: "SONY-A7M4", or the folder's name on the startup disk.
    static func volumeName(_ url: URL) -> String {
        let v = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeIsRootFileSystemKey])
        if v?.volumeIsRootFileSystem == true { return url.lastPathComponent }
        return v?.volumeName ?? url.lastPathComponent
    }

    // MARK: Settings (MENUS.md): stored per user

    static let prefsKey = "lumina-prefs"

    static var prefs: [String: Any]? {
        guard let text = UserDefaults.standard.string(forKey: prefsKey), let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// False, and nothing stored, when the settings hold a number JSON has no form for (NaN,
    /// ±Infinity: the page can send either). `JSONSerialization` raises on one instead of throwing.
    @discardableResult
    static func savePrefs(_ prefs: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(prefs),
              let data = try? JSONSerialization.data(withJSONObject: prefs, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) else { return false }
        UserDefaults.standard.set(text, forKey: prefsKey)
        return true
    }

    // MARK: Sources (BRIDGE.md "Sources", "Native recipe", "Phone upload")

    /// The page's `openFolder`, read by the Mac: the pending folder or the panel's pick becomes the
    /// open shoot and is listed before anything is read. NSNull for a cancelled pick; `denied` /
    /// `tooBig` as the page shows them; else the listing, with `source` (what the first source is
    /// to the Sources panel) and `more`, the shoot's other sources as they were kept, each listed
    /// the same way or marked `missing`.
    private func openListing() async -> Any {
        guard let url = await openPanel(allowsDirectories: true)?.first, let first = shootRoots.first else { return NSNull() }
        // The access check lists the folder too. On a disk that was just mounted, or is asleep, that
        // first directory read can take many seconds (13.9 s measured on a USB exFAT disk), so it runs
        // off the main thread with the listing, and the time reported covers both.
        let t0 = Date()
        // One listing at a time: a folder picked while another is still being listed stops that one,
        // whose call answers the page as a cancelled pick.
        self.listing?.cancel()
        let task = Task.detached(priority: .userInitiated) { () -> (Bool, SetsIngest.Listing) in
            // Single files: their folder was not granted and is not listed, so nothing to refuse here.
            if first.only == nil, SetsIngest.accessDenied(url) { return (true, SetsIngest.Listing(name: first.name)) }
            return (false, SetsIngest.list(url, name: first.name, only: first.only))
        }
        self.listing = task
        let (denied, listing) = await task.value
        if self.listing == task { self.listing = nil }
        if task.isCancelled || listing.stopped == .cancelled {
            onEvent?("listing stopped: another folder opened · \(url.path)")
            return NSNull()
        }
        if let stop = listing.stopped {
            // `/`, a home folder, a whole disk: refused whole rather than listed in part.
            let limits = SetsIngest.Limits()
            onEvent?("too big \(url.path): \(stop.rawValue)")
            return ["tooBig": ["name": listing.name, "why": stop.rawValue, "files": limits.entries, "depth": limits.depth]]
        }
        if denied {
            deniedFolder = url
            onEvent?("access denied \(url.path)")
            return ["denied": Self.volumeName(url)]
        }
        deniedFolder = nil
        onEvent?("listed \(listing.files.count) ARW + \(listing.xmp.count) xmp + \(listing.others.count) other\(listing.skippedXmp.isEmpty ? "" : " · \(listing.skippedXmp.count) xmp over 1 MB skipped")\(listing.onCard ? " (card)" : "") in \(Int(Date().timeIntervalSince(t0) * 1000)) ms · \(ingest.workers) readers")
        var d = listing.dictionary
        d["workers"] = ingest.workers
        d["source"] = ["kind": openKind ?? (listing.onCard ? "card" : "folder")]
        if let id = lastOpenedKey?.id {
            let more = await restoreSources(shoot: id, opened: url)
            if !more.isEmpty { d["more"] = more }
        }
        return d
    }

    /// Makes a root of the open shoot readable under its name. The watched Downloads folder's
    /// arrivals share the name "AirDrop" with a shoot's AirDrop source: both sets stay readable.
    private func register(_ root: OpenRoot) {
        var only = root.only
        if only != nil, root.name == Self.airdropName, let folder = airdropFolder, Self.same(folder, root.url) { only?.formUnion(airdropNames) }
        ingest.register(root.url, as: root.name, only: only)
    }

    /// Lets go of the access started for the open shoot's added sources.
    private func releaseSources() {
        for t in sourceHolds { access.release(t) }
        sourceHolds = []
    }

    /// A new entry for the shoot's source list, with a bookmark for the folder or for each file.
    /// A file that gives no bookmark (outside the sandbox's grant) is left out of the entry: it
    /// is read now and not found again after a relaunch.
    private func makeEntry(_ stored: inout SetsShootSources.Stored, url: URL, only: Set<String>?, name: String, kind: String, label: String, primary: Bool = false) -> SetsShootSources.Entry {
        var entry = SetsShootSources.Entry(nid: SetsShootSources.newID(), name: name, kind: kind, label: label, files: nil, refs: [], primary: primary ? true : nil)
        if let only {
            var files: [String] = []
            for file in only.sorted().prefix(SetsShootSources.maxFiles) {
                guard let s = try? stored.grants.add(url: url.appendingPathComponent(file), kind: kind, label: file) else { continue }
                files.append(file); entry.refs.append(s.id)
            }
            entry.files = files
        } else if let s = try? stored.grants.add(url: url, kind: kind, label: label) {
            entry.refs = [s.id]
        }
        return entry
    }

    /// Where a kept bookmark points now, a stale one renewed in `stored`. Not checked to be
    /// there: in the App Sandbox that can only be asked once the URL's access is started
    /// (`activate` does both). (`SetsSources` with its own calls, minus its look at the disk.)
    private static let unchecked: SetsAccess.Calls = {
        var c = SetsAccess.Calls.system
        c.exists = { _ in true }
        return c
    }()

    private static func locate(_ ref: String, in stored: inout SetsShootSources.Stored) -> URL? {
        var all = SetsSources(sources: stored.grants.sources, calls: unchecked)
        guard let url = all.reconnect(ref) else { return nil }
        stored.grants = SetsSources(sources: all.sources)
        return url
    }

    /// Reaches a kept source through its bookmarks and holds its access for the open shoot: the
    /// folder, or the folder its files are in and those of them that are there. Nil: not connected.
    private func activate(_ entry: SetsShootSources.Entry, shoot id: String) -> (url: URL, only: Set<String>?)? {
        var stored = sources.load(id)
        let before = stored.grants.sources
        defer { if stored.grants.sources != before { try? sources.save(id, stored) } }      // a stale bookmark was renewed
        let fm = FileManager.default
        if let names = entry.files {
            var folder: URL?, found = Set<String>()
            for (ref, name) in zip(entry.refs, names) {
                guard let url = Self.locate(ref, in: &stored), url.lastPathComponent == name else { continue }
                let parent = url.deletingLastPathComponent()
                if let folder, folder.standardizedFileURL.path != parent.standardizedFileURL.path { continue }
                let token = access.hold(url, scoped: true)
                var dir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &dir), !dir.boolValue else { access.release(token); continue }
                sourceHolds.append(token)
                folder = parent; found.insert(name)
            }
            return folder.map { ($0, found) }
        }
        guard let ref = entry.refs.first, let url = Self.locate(ref, in: &stored) else { return nil }
        let token = access.hold(url, scoped: true)
        var dir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &dir), dir.boolValue else { access.release(token); return nil }
        sourceHolds.append(token)
        return (url, nil)
    }

    /// One source's listing for the page: the listing's own fields plus what the Sources panel and
    /// the session need (`nid`, `kind`, `label`, and for a kept one `offset`, `n`).
    private func listed(_ root: OpenRoot, kind: String, label: String, entry: SetsShootSources.Entry? = nil) async -> [String: Any] {
        let t0 = Date()
        let (denied, listing) = await Task.detached(priority: .userInitiated) { () -> (Bool, SetsIngest.Listing) in
            if root.only == nil, SetsIngest.accessDenied(root.url) { return (true, SetsIngest.Listing(name: root.name)) }
            return (false, SetsIngest.list(root.url, name: root.name, only: root.only))
        }.value
        var d: [String: Any]
        if let stop = listing.stopped {
            let limits = SetsIngest.Limits()
            onEvent?("too big \(root.url.path): \(stop.rawValue)")
            d = ["name": root.name, "tooBig": ["name": listing.name, "why": stop.rawValue, "files": limits.entries, "depth": limits.depth]]
        } else if denied {
            onEvent?("access denied \(root.url.path)")
            d = ["name": root.name, "denied": Self.volumeName(root.url)]
        } else {
            onEvent?("source \(root.name): listed \(listing.files.count) RAW + \(listing.xmp.count) xmp + \(listing.others.count) other\(listing.onCard ? " (card)" : "") in \(Int(Date().timeIntervalSince(t0) * 1000)) ms · \(root.url.path)")
            d = listing.dictionary
            d["workers"] = ingest.workers
        }
        d["nid"] = root.nid ?? NSNull(); d["kind"] = kind; d["label"] = label
        if let o = entry?.offset { d["offset"] = o }
        if let n = entry?.n { d["n"] = n }
        return d
    }

    /// The open shoot's other sources, as kept: each reached through its bookmark, registered under
    /// its name and listed; one that is not there is `missing` and the rest still open.
    private func restoreSources(shoot id: String, opened: URL) async -> [[String: Any]] {
        var out: [[String: Any]] = []
        for entry in sources.load(id).entries.prefix(SetsShootSources.maxEntries) where !entry.isPrimary {
            let gone: [String: Any] = ["nid": entry.nid, "name": entry.name, "kind": entry.kind, "label": entry.label, "missing": true,
                                       "n": entry.n ?? 0, "offset": entry.offset ?? NSNull()]
            guard !shootRoots.contains(where: { $0.name == entry.name }), let found = activate(entry, shoot: id) else {
                onEvent?("source \(entry.name): not connected")
                out.append(gone); continue
            }
            let root = OpenRoot(name: entry.name, url: found.url, only: found.only, nid: entry.nid)
            register(root)
            shootRoots.append(root)
            let d = await listed(root, kind: entry.kind, label: entry.label, entry: entry)
            guard lastOpened == opened else { return out }       // another shoot opened meanwhile
            out.append(d["files"] == nil ? gone : d)
        }
        return out
    }

    private static func same(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.resolvingSymlinksInPath().path == b.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Folders, or files of a folder, that join the open shoot (`add`) or are opened: with no
    /// shoot open the first is opened as a shoot and the rest join it. `sources`: one listing per
    /// item, the opened one marked `primary`.
    private func adopt(_ items: [SetsShootSources.Claim], add: Bool, shoot: String?, kind: String, label: String?) async -> [String: Any] {
        var out: [[String: Any]] = []
        var adding = add && !shootRoots.isEmpty
        // The page's shoot id when the Mac has one too; its own otherwise (a shoot being opened).
        var sid = shoot.flatMap { SetsShootStore.isID($0) ? $0 : nil } ?? lastOpenedKey?.id
        for item in items.prefix(SetsShootSources.maxEntries) {
            if !adding {
                pendingSource = item.url; pendingShoot = nil
                pendingLoose = item.only.map { (SetsShootSources.alias(item.base, taken: []), $0, nil) }
                pendingKind = kind
                guard var d = await openListing() as? [String: Any] else { continue }
                d["primary"] = true; d["kind"] = kind; d["label"] = label ?? NSNull()
                out.append(d)
                if d["files"] != nil { adding = true; sid = lastOpenedKey?.id }
                continue
            }
            var root: OpenRoot
            if let i = shootRoots.firstIndex(where: { Self.same($0.url, item.url) && $0.only == nil }) {
                // Already a folder of this shoot: listed again under its name (new files join; the page skips the rest).
                root = OpenRoot(name: shootRoots[i].name, url: shootRoots[i].url, only: item.only, nid: shootRoots[i].nid)
            } else if let only = item.only, let i = shootRoots.firstIndex(where: { Self.same($0.url, item.url) && $0.only != nil && $0.name.hasPrefix(item.base) }) {
                // More files of a folder some files already came from: one root, the files together.
                shootRoots[i].only = (shootRoots[i].only ?? []).union(only)
                register(shootRoots[i])
                if let sid, let nid = shootRoots[i].nid {
                    var stored = sources.load(sid)
                    if let k = stored.entries.firstIndex(where: { $0.nid == nid }) {
                        for file in only.sorted() where !(stored.entries[k].files ?? []).contains(file) && (stored.entries[k].files ?? []).count < SetsShootSources.maxFiles {
                            guard let s = try? stored.grants.add(url: item.url.appendingPathComponent(file), kind: kind, label: file) else { continue }
                            stored.entries[k].files = (stored.entries[k].files ?? []) + [file]; stored.entries[k].refs.append(s.id)
                        }
                        try? sources.save(sid, stored)
                    }
                }
                root = OpenRoot(name: shootRoots[i].name, url: shootRoots[i].url, only: only, nid: shootRoots[i].nid)
            } else {
                let name = SetsShootSources.alias(item.base, taken: Set(shootRoots.map(\.name)))
                root = OpenRoot(name: name, url: item.url, only: item.only, nid: nil)
                if let sid {
                    var stored = sources.load(sid)
                    let entry = makeEntry(&stored, url: item.url, only: item.only, name: name, kind: kind, label: label ?? name)
                    if stored.entries.count < SetsShootSources.maxEntries, !entry.refs.isEmpty {
                        stored.entries.append(entry)
                        do { try sources.save(sid, stored); root.nid = entry.nid } catch { onEvent?("source \(name): not kept (\(error))") }
                    } else { onEvent?("source \(name): not kept (no bookmark)") }
                }
                register(root)
                shootRoots.append(root)
            }
            out.append(await listed(root, kind: kind, label: label ?? root.name))
        }
        return ["sources": out]
    }

    /// `lumina.addFrom(where)`: the panel, opened in Pictures / Downloads / Desktop for those three
    /// (the panel's own place for 'folder'); folders and RAW files, several at once.
    private func addFrom(where place: String, add: Bool, shoot: String?) async -> Any {
        let fm = FileManager.default
        let at: URL? = ["pictures": FileManager.SearchPathDirectory.picturesDirectory, "downloads": .downloadsDirectory, "desktop": .desktopDirectory][place]
            .flatMap { fm.urls(for: $0, in: .userDomainMask).first }
        let adding = add && !shootRoots.isEmpty
        let picked = await chooser.chooseSources(at: at, files: true, multiple: true, prompt: adding ? "Add to shoot" : "Open",
                                                 message: adding ? "Choose folders or photos to add to this shoot. Lumina only reads them." : "Choose a folder of photos. Lumina only reads it.")
        guard !picked.isEmpty else { return NSNull() }
        grant(picked)
        let kind = ["pictures", "downloads", "desktop"].contains(place) ? place : "folder"
        return await adopt(Self.claims(of: picked), add: add, shoot: shoot, kind: kind, label: nil)
    }

    /// Picked or dropped URLs as roots: each folder whole, single files together per folder.
    nonisolated static func claims(of urls: [URL]) -> [SetsShootSources.Claim] {
        var out: [SetsShootSources.Claim] = [], loose: [String: Int] = [:]
        for url in urls {
            var dir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) else { continue }
            if dir.boolValue { out.append(.init(url: url, only: nil, base: url.lastPathComponent)); continue }
            let parent = url.deletingLastPathComponent(), key = parent.standardizedFileURL.path
            if let i = loose[key] { out[i].only?.insert(url.lastPathComponent) }
            else { loose[key] = out.count; out.append(.init(url: parent, only: [url.lastPathComponent], base: parent.lastPathComponent)) }
        }
        return out
    }

    /// The user handed the app these (a drop on the window, a pick in a panel): the only things
    /// the page's `File`s are ever matched to (`claimFiles`).
    func grant(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            var dir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) else { continue }
            granted.removeAll { $0.url == url }
            granted.append((url, dir.boolValue))
        }
        if granted.count > Self.maxGranted { granted.removeFirst(granted.count - Self.maxGranted) }
        if !urls.isEmpty { onEvent?("granted \(urls.count): \(urls.prefix(3).map(\.lastPathComponent).joined(separator: ", "))") }
    }

    /// The panel for one of the page's own file inputs (the phone page's "choose"): what is
    /// picked is granted, and the page gets it as `File`s. The open shoot is not touched.
    func inputPanel(allowsDirectories: Bool, allowsMultipleSelection: Bool) async -> [URL]? {
        let picked = await chooser.chooseSources(at: nil, files: true, multiple: allowsMultipleSelection, prompt: "Choose", message: "Choose photos. Lumina only reads them.")
        guard !picked.isEmpty else { return nil }
        grant(picked)
        return picked
    }

    private func claimFiles(_ files: [[String: Any]], add: Bool, shoot: String?, kind: String?, label: String?) async -> Any {
        let rels = files.prefix(SetsIngest.Limits().entries).compactMap { $0["rel"] as? String }.filter { $0.utf8.count <= Self.maxRelBytes }
        // AirDrop arrivals are named "AirDrop/<name>" by the Mac itself: those of them that arrived.
        let prefix = Self.airdropName + "/"
        let arrived = Set(rels.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }).intersection(airdropNames)
        var items = SetsShootSources.claims(files: rels.filter { !($0.hasPrefix(prefix) && arrived.contains(String($0.dropFirst(prefix.count)))) }, granted: granted)
        if let folder = airdropFolder, !arrived.isEmpty { items.insert(.init(url: folder, only: arrived, base: Self.airdropName), at: 0) }
        guard !items.isEmpty else { return NSNull() }
        let k = kind.flatMap { ["card", "phone", "downloads", "desktop", "pictures", "drop", "folder"].contains($0) ? $0 : nil } ?? "drop"
        return await adopt(items, add: add, shoot: shoot, kind: k, label: label.map { SetsShootStore.capped($0, SetsShootStore.Cap.name) })
    }

    /// The page's source list after an add, a restore or a clock shift: `{nid, offset, n}` for
    /// every source in use. Entries the page did not keep (an add that brought nothing new) go;
    /// the shoot's first source stays. Answers the status list.
    private func keepSources(shoot id: String, list: [[String: Any]]) -> [[String: Any]] {
        guard SetsShootStore.isID(id) else { return [] }
        var stored = sources.load(id)
        let keep = Dictionary(list.prefix(SetsShootSources.maxEntries * 4).compactMap { d in (d["nid"] as? String).map { ($0, d) } }, uniquingKeysWith: { a, _ in a })
        let before = stored
        for e in stored.entries where !e.isPrimary && keep[e.nid] == nil { for r in e.refs { stored.grants.remove(r) } }
        stored.entries.removeAll { !$0.isPrimary && keep[$0.nid] == nil }
        for i in stored.entries.indices {
            guard let d = keep[stored.entries[i].nid] else { continue }
            if let n = SetsNumber.count(d["n"]) { stored.entries[i].n = n }
            let off = (d["offset"] as? NSNumber)?.doubleValue
            stored.entries[i].offset = off.flatMap { $0.isFinite && abs($0) <= 86_400 * 366 && $0 != 0 ? Int($0) : nil }
        }
        if stored.entries != before.entries { try? sources.save(id, stored) }
        return sourcesStatus()
    }

    /// `[{nid, missing}]` for the open shoot's added sources: missing when its folder (or every
    /// one of its files) is not there now, or its volume went.
    func sourcesStatus() -> [[String: Any]] {
        var out: [[String: Any]] = []
        let open = Dictionary(shootRoots.compactMap { r in r.nid.map { ($0, r) } }, uniquingKeysWith: { a, _ in a })
        let listed = (lastOpenedKey?.id).map { sources.load($0).entries } ?? []
        for e in listed where !e.isPrimary {
            guard let r = open[e.nid], !ingest.isGone(r.name + "/") else { out.append(["nid": e.nid, "missing": true]); continue }
            let there = r.only.map { $0.contains { FileManager.default.fileExists(atPath: r.url.appendingPathComponent($0).path) } } ?? FileManager.default.fileExists(atPath: r.url.path)
            out.append(["nid": e.nid, "missing": !there])
        }
        return out
    }

    /// The Sources panel's Reconnect: the bookmark again; when that fails, the panel to find the
    /// folder, which then takes the source's place (same name, same decisions). `source`: its
    /// listing. Null: cancelled, or not something that can be found again (single files).
    private func reconnectSource(_ nid: String, shoot id: String) async -> Any {
        guard SetsShootStore.isID(id), lastOpenedKey?.id == id, let entry = sources.load(id).entries.first(where: { $0.nid == nid && !$0.isPrimary }) else { return NSNull() }
        var found = activate(entry, shoot: id)
        if found == nil, entry.files == nil, let ref = entry.refs.first {
            guard let picked = await chooser.chooseSources(at: nil, files: false, multiple: false, prompt: "Reconnect",
                                                           message: "Choose the folder “\(entry.label)” to connect it to this shoot again.").first else { return NSNull() }
            var stored = sources.load(id)
            guard (try? stored.grants.relocate(ref, to: picked)) ?? nil != nil else { return NSNull() }
            try? sources.save(id, stored)
            onEvent?("source \(entry.name): relocated to \(picked.path)")
            found = (picked, nil)
        }
        guard let found else { return NSNull() }
        let root = OpenRoot(name: entry.name, url: found.url, only: found.only, nid: nid)
        register(root)
        shootRoots.removeAll { $0.nid == nid }
        shootRoots.append(root)
        return ["source": await listed(root, kind: entry.kind, label: entry.label, entry: entry)]
    }

    // MARK: AirDrop watch

    private var downloadsBookmark: URL { supportDir.appendingPathComponent("downloads.bookmark") }

    /// `lumina.watchAirdrop(on)`. On: the Downloads folder through the bookmark kept from the
    /// first time, else the panel opened on Downloads (asked once; the pick is the grant), then
    /// the watcher. False when there is no folder to watch (the panel was cancelled).
    func watchAirdrop(_ on: Bool) async -> Bool {
        guard on else { stopAirdrop(); return true }
        if airdropFolder != nil { return true }
        var folder: URL?, hold: Int?
        if let data = try? Data(contentsOf: downloadsBookmark), let url = access.peek(data) {
            let t = access.hold(url, scoped: true)
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &dir), dir.boolValue, !SetsIngest.accessDenied(url) { folder = url; hold = t } else { access.release(t) }
        }
        if folder == nil {
            let at = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
            guard let picked = await chooser.chooseDownloads(at: at) else { onEvent?("airdrop: no folder to watch"); return false }
            var dir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: picked.path, isDirectory: &dir), dir.boolValue else { return false }
            if let data = access.makeBookmark(picked) {
                try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
                try? SetsFileOps.replaceOwn(data, at: downloadsBookmark)
            }
            folder = picked
        }
        guard let folder else { return false }
        airdropFolder = folder; airdropHold = hold; airdropNames = []
        onEvent?("airdrop: watching \(folder.path)")
        downloads.start(folder: folder) { [weak self] batch in
            Task { @MainActor in self?.arrived(batch, in: folder) }
        }
        return true
    }

    private func stopAirdrop() {
        downloads.stop()
        if let t = airdropHold { access.release(t) }
        if airdropFolder != nil { onEvent?("airdrop: stopped") }
        airdropFolder = nil; airdropHold = nil
    }

    /// Complete RAWs arrived in the watched folder: readable as "AirDrop/<name>" from now on, and
    /// handed to the page's `luminaPhoneArrived` with the count of HEIC / JPEG arrivals.
    private func arrived(_ batch: SetsDownloadsWatcher.Batch, in folder: URL) {
        guard airdropFolder == folder else { return }
        let names = batch.raws.map(\.name).filter(SetsIngest.isPlainName)
        airdropNames.formUnion(names)
        // The name may already be a root of the open shoot (earlier arrivals added to it): those stay readable.
        let inShoot = shootRoots.first(where: { $0.name == Self.airdropName && Self.same($0.url, folder) })?.only ?? []
        if !shootRoots.contains(where: { $0.name == Self.airdropName && !Self.same($0.url, folder) }) {
            ingest.register(folder, as: Self.airdropName, only: airdropNames.union(inShoot))
        }
        let files = batch.raws.filter { SetsIngest.isPlainName($0.name) }.map { ["rel": Self.airdropName + "/" + $0.name, "size": $0.size] as [String: Any] }
        onEvent?("airdrop: \(files.count) RAW, \(batch.lossy) other")
        push("__lumina.phoneArrived(\(Self.json(files)), \(batch.lossy))")
    }

    // MARK: Save (SAFETY.md 1)

    /// The sidecars Save is about to merge into, as they are on disk now: `{ name, text, base }`
    /// per name inside the shoot folder (`text` null when there is no file; an entry with only its
    /// name when it can't be read). The text the page holds is from the open, and another app
    /// (Lightroom) may have written the file since; `base` goes back with the write.
    private func readSidecars(root name: String, files: [String]) async -> [[String: Any]]? {
        guard let root = ingest.root(named: name) ?? lastOpened.flatMap({ $0.lastPathComponent == name ? $0 : nil }) else {
            onEvent?("readSidecars: \(name) is not an opened folder")
            return nil
        }
        let allowed = ingest.root(named: name) == nil ? nil : ingest.allowed(named: name)
        return await Task.detached(priority: .userInitiated) { () -> [[String: Any]] in
            files.map { rel in
                guard Self.sidecarAllowed(rel, among: allowed), let s = try? SetsFileOps.readSidecar(rel: rel, root: root) else { return ["name": rel] }
                return ["name": rel, "text": s.text ?? NSNull(), "base": s.base]
            }
        }.value
    }

    /// Save writes one .xmp sidecar per keeper INTO the shoot folder (`root`, an opened folder's
    /// name), next to its RAW. Every file goes through SetsFileOps.writeSidecar; nothing is retried
    /// silently. Refused wholesale when the folder is on a card. A file's `base` (from
    /// `readSidecars`) is what its bytes were merged from: when the sidecar on disk is no longer
    /// that, it is left alone and reported "changed on disk".
    private func writeSidecars(root name: String, files: [[String: Any]]) async -> [String: Any]? {
        guard let root = ingest.root(named: name) ?? lastOpened.flatMap({ $0.lastPathComponent == name ? $0 : nil }) else {
            onEvent?("writeSidecars: \(name) is not an opened folder")
            return nil
        }
        onEvent?("writeSidecars \(files.count) → \(root.path)")
        let items: [(String, Data?, String?)] = files.map { ($0["name"] as? String ?? "", ($0["b64"] as? String).flatMap { Data(base64Encoded: $0) }, $0["base"] as? String) }
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Lumina save")
        let allowed = ingest.root(named: name) == nil ? nil : ingest.allowed(named: name)
        let (n, bak, errors) = await Task.detached(priority: .userInitiated) { () -> (Int, Int, [[String: String]]) in
            var n = 0, bak = 0, errors: [[String: String]] = []
            let onCard = SetsFileOps.isCard(root)
            for (rel, data, base) in items {
                let stem = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
                guard let data else { errors.append(["name": stem, "reason": "failed"]); continue }
                // A root of single files: a sidecar only beside one of them, never elsewhere in that folder.
                guard Self.sidecarAllowed(rel, among: allowed) else { errors.append(["name": stem, "reason": "refused"]); continue }
                if onCard { errors.append(["name": stem, "reason": "on the card"]); continue }
                do {
                    if try SetsFileOps.writeSidecar(data, rel: rel, root: root, base: base).backedUp { bak += 1 }
                    n += 1
                } catch let e as SetsFileOps.SidecarError {
                    errors.append(["name": e.name, "reason": e.reason])
                } catch {
                    errors.append(["name": stem, "reason": SetsFileOps.reason(error)])
                }
            }
            return (n, bak, errors)
        }.value
        ProcessInfo.processInfo.endActivity(activity)
        onEvent?("sidecars → \(root.path): \(n) written, \(bak) bak, \(errors.count) failed\(errors.first.map { " — \($0["name"] ?? "") · \($0["reason"] ?? "")" } ?? "")")
        return ["n": n, "bak": bak, "folder": root.lastPathComponent, "path": root.path, "errors": errors]
    }

    /// Whether a sidecar name may be read or written in a root limited to `files` (nil: a whole
    /// folder, where `SetsFileOps` decides): only beside one of those files, by its stem.
    nonisolated static func sidecarAllowed(_ rel: String, among files: Set<String>?) -> Bool {
        guard let files else { return true }
        guard SetsIngest.isPlainName(rel) else { return false }
        let stem = (rel as NSString).deletingPathExtension
        return files.contains { ($0 as NSString).deletingPathExtension == stem && ["arw", "dng"].contains(($0 as NSString).pathExtension.lowercased()) }
    }

    /// What an export may write, by the name's extension (threat model T8, S4): bytes the page
    /// hands over are sidecars and nothing else; a look render is an image.
    static let bytesExtensions: Set<String> = ["xmp"]
    static let renderExtensions: Set<String> = ["jpg", "jpeg", "tif", "tiff", "png"]
    /// What a `copy` item may be: a RAW pick copied whole (v7: DNG picks go to `Picks/`, because
    /// Lightroom ignores sidecars for DNG).
    static let copyExtensions: Set<String> = ["dng", "arw"]

    /// The page's export into a folder the user picks. v5 sends one kind of item, the Edit step's
    /// renders (plumbing's `writeInto(files, 'jpeg')`); Save goes through `writeSidecars`. Items:
    /// `{name, look: {src, look, px?, model?}}`, the name ending in .jpg / .jpeg / .tif / .tiff /
    /// .png, and `{name, b64}`, the name ending in .xmp. Anything else stops the export before a
    /// folder is asked for: v3's `src` (a RAW copied out) and `jpg` (the CSS look) are gone.
    private func writeInto(label: String, files: [[String: Any]]) async -> [String: Any] {
        onEvent?("writeInto \(label): \(files.count) files")
        var items: [SetsExportJob.Item] = []
        let sources: [URL] = ingest.rootURLs
        for f in files {
            // No NUL either: the file system would end the name there, before the extension checked below.
            guard let name = f["name"] as? String, !name.contains(".."), !name.hasPrefix("/"), !name.utf8.contains(0) else { return ["aborted": true, "say": "export stopped · bad file name"] }
            let ext = (name as NSString).pathExtension.lowercased()
            if let b = f["b64"] as? String, let data = Data(base64Encoded: b) {
                guard Self.bytesExtensions.contains(ext) else { return ["aborted": true, "say": "export stopped · bad file name"] }
                items.append(.bytes(name: name, data: data))
            } else if let l = f["look"] as? [String: Any], let rel = l["src"] as? String {
                // The Edit step's render: {name, look: {src, look: "<look string>", px?, model?}} → LookPipeline
                // at full size, with the decoder the shoot pins for that body (RAW 9 when it has it).
                guard Self.renderExtensions.contains(ext) else { return ["aborted": true, "say": "export stopped · bad file name"] }
                guard let src = resolve(rel) else { return ["aborted": true, "say": "export stopped · can't find \(rel)"] }
                let px = SetsNumber.exportEdge(l["px"])
                let decoder = LookRawPolicy.version(for: .export, body: (l["model"] as? String).flatMap { header.bodies[$0] }, pinned: header.decoderVersion)
                items.append(.look(name: name, source: src, look: l["look"] as? String ?? "", px: px, decoder: decoder))
            } else if let rel = f["copy"] as? String {
                // v7's DNG picks: {name: "Picks/<file>.DNG", copy: "<rel>"} → a streamed, SHA-256 verified
                // copy of the original (never a move; `SetsFileOps.copyVerified`).
                // The original is a RAW too, of the same kind as the name it lands under: a page cannot ask
                // for any other file in an opened folder to be copied out as a "pick".
                guard Self.copyExtensions.contains(ext), (rel as NSString).pathExtension.lowercased() == ext else { return ["aborted": true, "say": "export stopped · bad file name"] }
                guard let src = resolve(rel) else { return ["aborted": true, "say": "export stopped · can't find \(rel)"] }
                items.append(.copy(name: name, source: src))
            } else {
                // Not an item the page has: nothing is written and no folder is asked for.
                onEvent?("writeInto \(label): an item that is neither a look render nor sidecar bytes, nothing written")
                return ["aborted": true]
            }
        }
        // Pick the destination; refuse the card and the source folder, and ask again.
        var refusal: String?
        var dest: URL?
        while dest == nil {
            guard let picked = await chooser.chooseDestination(label: label, suggested: (shootRoots.first?.url ?? ingest.rootURLs.first)?.deletingLastPathComponent(), refusal: refusal) else {
                return ["aborted": true]
            }
            if let why = SetsFileOps.refusal(destination: picked, sources: sources) { refusal = why; onEvent?("refused \(picked.path)"); continue }
            dest = picked
        }
        lastExport = dest       // what Show in Finder may open after this export (`revealURL`)
        let job = SetsExportJob(label: label, destination: dest!, items: items)
        let journal = SetsExportJournal(directory: supportDir.appendingPathComponent("exports", isDirectory: true))
        // Keep the export at full speed when Lumina is in the background (App Nap) and the Mac awake.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Lumina export")
        // Look renders run at .utility (RAW 9 §4); copies and sidecars stay .userInitiated.
        let hasLooks = items.contains { if case .look = $0 { return true } else { return false } }
        let result = await Task.detached(priority: hasLooks ? .utility : .userInitiated) { [sources] in job.run(journal: journal, sources: sources) }.value
        ProcessInfo.processInfo.endActivity(activity)
        onEvent?("export \(label) → \(dest!.path): \(result.n) written, \(result.bak) bak, \(result.failed.count) failed\(result.failed.first.map { " — " + $0 } ?? "")\(result.decoders.isEmpty ? "" : " · " + result.decoderSummary)")
        // Copies report per file (BRIDGE.md: `{n, folder, path, errors: [{name, reason}]}`): the page lists
        // them and keeps those picks unsaved. Renders and bytes keep their one-line stop.
        if label == "picks" {
            return ["n": result.n, "folder": result.folder, "path": result.folder, "renamed": result.renamed,
                    "errors": result.errors.map { ["name": $0.name, "reason": $0.reason] }]
        }
        if let first = result.failed.first {
            return ["aborted": true, "say": result.n > 0 ? "export stopped after \(result.n) · \(first)" : first]
        }
        var out: [String: Any] = ["n": result.n, "bak": result.bak, "folder": result.folder]
        if !result.decoders.isEmpty {
            // The result block names the decoder used (§2) and, when slowed, says so (§4).
            out["decoder"] = result.decoderSummary + (LookDecoderProbe.slowed ? " · slowed by thermal state" : "")
            out["decoders"] = result.decoders
            out["fallbacks"] = result.fallbacks
            out["renderMs"] = result.renderMs
        }
        return out
    }
}

/// The page's web view, which also notes what is dropped on it. The page still gets the drop (its
/// highlight, its own drop handlers, `File`s); the Mac gets the same items as file URLs, which is
/// what lets it read them itself, and write sidecars beside them, instead of the page.
final class SetsDropWebView: WKWebView {
    var onFiles: (([URL]) -> Void)?

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty { onFiles?(urls) }
        return super.performDragOperation(sender)
    }
}

/// The page's web view: bundled files only, network blocked, plumbing injected.
@MainActor
enum SetsWebView {
    static func make(pageRoot: URL, vendorRoot: URL, plumbing: String, bridge: SetsBridge?, standInPhotos: Bool,
                     config: [String: Any] = [:], extraScripts: [String] = [], frame: CGRect = .zero) async throws -> (WKWebView, SetsSchemeHandler) {
        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = .nonPersistent()
        let scheme = SetsSchemeHandler(pageRoot: pageRoot, vendorRoot: vendorRoot, standInPhotos: standInPhotos, ingest: bridge?.ingest)
        conf.setURLSchemeHandler(scheme, forURLScheme: SetsSchemeHandler.scheme)
        let ucc = conf.userContentController
        let res = String(data: try JSONSerialization.data(withJSONObject: SetsSchemeHandler.resources), encoding: .utf8)!
        ucc.addUserScript(WKUserScript(source: "window.__resources=Object.assign(window.__resources||{},\(res));", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        for s in extraScripts { ucc.addUserScript(WKUserScript(source: s, injectionTime: .atDocumentStart, forMainFrameOnly: true)) }
        // The retake threshold belongs to the Mac's measure (SetsNear), so it reaches the page from here.
        var config = config
        if bridge != nil, config["nearLimit"] == nil, let limit = SetsNear.limit { config["nearLimit"] = limit }
        let cfg = String(data: try JSONSerialization.data(withJSONObject: config), encoding: .utf8)!
        ucc.addUserScript(WKUserScript(source: "window.__luminaConfig=\(cfg);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if bridge != nil { ucc.addUserScript(WKUserScript(source: plumbing, injectionTime: .atDocumentStart, forMainFrameOnly: true)) }
        bridge?.install(in: conf)
        let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        if let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "lumina-offline", encodedContentRuleList: rules) {
            ucc.add(list)
        }
        let wv = SetsDropWebView(frame: frame, configuration: conf)
        wv.onFiles = { [weak bridge] urls in bridge?.grant(urls) }
        bridge?.webView = wv
        return (wv, scheme)
    }
}
