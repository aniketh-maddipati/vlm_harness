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
}

extension SetsChooser {
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
        if let pending = pendingSource { url = pending; reopening = pendingShoot; pendingSource = nil; pendingShoot = nil }
        else { url = await chooser.chooseSource(allowsDirectories: allowsDirectories); reopening = nil }
        guard let url else { return nil }
        // The open shoot is this folder now. A reopen already started its access (scoped); a
        // panel's pick needs none, and the shoot open before is let go either way.
        access.openShoot(url, scoped: false)
        ingest.register(url)
        lastOpened = url
        let place = SetsShootStore.id(for: url), volume = SetsFileOps.volumeID(url)
        // A recent's own id; else the shoot that is at this place; else a recent renamed or moved
        // here since (its bookmark follows it); else a new shoot.
        let id = reopening ?? shoots.index().first(where: { $0.currentPlace == place })?.id
            ?? access.movedShoot(to: url, volume: volume, in: shoots)?.id ?? shoots.shootID(at: place)
        // The bookmark the index keeps, made while the grant is fresh. The only one: there is no
        // second copy elsewhere.
        lastOpenedKey = (id, volume, place, reopening == nil ? try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) : nil)
        onEvent?("opened \(url.path)")      // exactly this: the probe's sandbox checks read the path from it
        if id != place { onEvent?("shoot \(id) is at a new place \(place)" + (reopening == nil ? " (picked)" : " (reopened)")) }
        return [url]
    }

    /// Opens a folder in the page as if the user picked it (menu, "Cull this card", a recent).
    /// `shoot`: the recent shoot this is, whatever its folder is called now.
    func open(_ url: URL, shoot: String? = nil) {
        pendingSource = url
        pendingShoot = shoot
        webView?.evaluateJavaScript("window.__lumina && __lumina.openFolder()", completionHandler: nil)
    }

    /// No shoot is open any more (File ▸ Close Shoot, or the page started over): its folder's
    /// access is stopped.
    func closeShoot() { access.closeShoot() }

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
            webView?.evaluateJavaScript("window.__lumina && __lumina.card(\(cards.current != nil), \(cards.current.map(cardJSON) ?? "null"))", completionHandler: nil)
            onEvent?("ready")
            return (true, nil)
        case "cullCard":
            return (await cullCard(), nil)
        case "openFolder":
            // Native ingest: pick (or take the pending folder), then list it before reading anything.
            guard let url = await openPanel(allowsDirectories: true)?.first else { return (NSNull(), nil) }
            // The access check lists the folder too. On a disk that was just mounted, or is asleep, that
            // first directory read can take many seconds (13.9 s measured on a USB exFAT disk), so it runs
            // off the main thread with the listing, and the time reported covers both.
            let t0 = Date()
            // One listing at a time: a folder picked while another is still being listed stops that one,
            // whose call answers the page as a cancelled pick.
            self.listing?.cancel()
            let task = Task.detached(priority: .userInitiated) { () -> (Bool, SetsIngest.Listing) in
                if SetsIngest.accessDenied(url) { return (true, SetsIngest.Listing(name: url.lastPathComponent)) }
                return (false, SetsIngest.list(url))
            }
            self.listing = task
            let (denied, listing) = await task.value
            if self.listing == task { self.listing = nil }
            if task.isCancelled || listing.stopped == .cancelled {
                onEvent?("listing stopped: another folder opened · \(url.path)")
                return (NSNull(), nil)
            }
            if let stop = listing.stopped {
                // `/`, a home folder, a whole disk: refused whole rather than listed in part.
                let limits = SetsIngest.Limits()
                onEvent?("too big \(url.path): \(stop.rawValue)")
                return (["tooBig": ["name": listing.name, "why": stop.rawValue, "files": limits.entries, "depth": limits.depth]], nil)
            }
            if denied {
                deniedFolder = url
                onEvent?("access denied \(url.path)")
                return (["denied": Self.volumeName(url)], nil)
            }
            deniedFolder = nil
            onEvent?("listed \(listing.files.count) ARW + \(listing.xmp.count) xmp + \(listing.others.count) other\(listing.skippedXmp.isEmpty ? "" : " · \(listing.skippedXmp.count) xmp over 1 MB skipped")\(listing.onCard ? " (card)" : "") in \(Int(Date().timeIntervalSince(t0) * 1000)) ms · \(ingest.workers) readers")
            var d = listing.dictionary
            d["workers"] = ingest.workers
            return (d, nil)
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
            // The bookmark made at open (nil for a reopen: upsert keeps the one it came through).
            let shoot = SetsShootStore.Shoot(id: id, title: url.lastPathComponent == "DCIM" ? (cards.current?.name ?? "Card") : url.lastPathComponent,
                                             path: url.path, volumeUUID: key?.volume ?? SetsFileOps.volumeID(url), photos: SetsNumber.count(body["n"]) ?? 0,
                                             firstCapture: body["date"] as? String ?? "", opened: Date(),
                                             bookmark: key.map { $0.bookmark } ?? (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)),
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
            // The photo's as-shot white balance, for a temperature slider to rest on: in this answer
            // when the photo's base is already developed, else pushed through `__lumina.editHeader`
            // when the base lands. Read off the base the canvas builds anyway: no develop of its own,
            // nothing waited for. No key at all for the embedded JPEG standing in or a file without
            // a readable value.
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
            return (shoots.bytes(id), nil)
        case "removeShoot":
            guard let id = body["id"] as? String, SetsShootStore.isID(id) else { return (false, nil) }
            try? shoots.remove(id)
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
            open(url)
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
        guard let shoot = shoots.index().first(where: { $0.id == id }), let url = access.reopen(shoot, store: shoots) else { return false }
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
            let url = path.contains("/") ? resolve(path) : ingest.root(named: path)
            return url.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard fm.fileExists(atPath: url.path) else { return nil }
        let real = url.resolvingSymlinksInPath().path
        let folders = ingest.rootURLs + [lastOpened, lastExport].compactMap { $0 }
        let inside = folders.contains { folder in
            let f = folder.standardizedFileURL.resolvingSymlinksInPath().path
            return real == f || real.hasPrefix(f.hasSuffix("/") ? f : f + "/")
        }
        return inside ? url : nil
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
        return await Task.detached(priority: .userInitiated) { () -> [[String: Any]] in
            files.map { rel in
                guard let s = try? SetsFileOps.readSidecar(rel: rel, root: root) else { return ["name": rel] }
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
        let (n, bak, errors) = await Task.detached(priority: .userInitiated) { () -> (Int, Int, [[String: String]]) in
            var n = 0, bak = 0, errors: [[String: String]] = []
            let onCard = SetsFileOps.isCard(root)
            for (rel, data, base) in items {
                let stem = ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
                guard let data else { errors.append(["name": stem, "reason": "failed"]); continue }
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

    /// What an export may write, by the name's extension (threat model T8, S4): bytes the page
    /// hands over are sidecars and nothing else; a look render is an image.
    static let bytesExtensions: Set<String> = ["xmp"]
    static let renderExtensions: Set<String> = ["jpg", "jpeg", "tif", "tiff", "png"]

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
            } else {
                // Not an item v5 has: nothing is written and no folder is asked for.
                onEvent?("writeInto \(label): an item that is neither a look render nor sidecar bytes, nothing written")
                return ["aborted": true]
            }
        }
        // Pick the destination; refuse the card and the source folder, and ask again.
        var refusal: String?
        var dest: URL?
        while dest == nil {
            guard let picked = await chooser.chooseDestination(label: label, suggested: ingest.rootURLs.first?.deletingLastPathComponent(), refusal: refusal) else {
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
        // One rule per scheme: content-rule patterns have no alternation. WebSockets are blocked too,
        // since the page has no network use (THREAT-MODEL S1); the navigation policy covers the rest.
        let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},"#
            + #"{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}},"#
            + #"{"trigger":{"url-filter":"^ftp://"},"action":{"type":"block"}}]"#
        if let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "lumina-offline", encodedContentRuleList: rules) {
            ucc.add(list)
        }
        let wv = WKWebView(frame: frame, configuration: conf)
        bridge?.webView = wv
        return (wv, scheme)
    }
}
