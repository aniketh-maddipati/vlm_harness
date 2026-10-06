import AppKit
import UniformTypeIdentifiers
import WebKit

/// Serves the page from local files under `lumina://`. Nothing loads from the network.
///
/// - `lumina://app/<file>`     the design's page files, byte-identical
/// - `lumina://vendor/<file>`  React / Babel (support.js asks for them via `window.__resources`)
/// - `lumina://app/media/{head,preview,thumb}?p=<folder/file>&o=&l=&ori=`  the opened folder's
///   photos, read natively by byte range (SetsIngest). Same origin as the page, so it can measure
///   them on a canvas. Never a whole RAW, never the network.
/// - `lumina://photo/seed/<seed>/<w>/<h>`  stand-in photos for the design's sample shoot (the
///   page's picsum URLs are pointed here). Debug fixture data only; off once the sample goes.
/// - `lumina://render/<folder/file>?look=<look string>&px=<long edge>&seq=<n>[&tier=small][&decoder=8]`
///   the Edit step's preview when the native canvas isn't available (the image fallback path):
///   the RAW through LookPipeline (LookRenderer: developed once per (file, px, decoder), the look
///   per request, one render at a time). `tier=small` renders a quarter of `px` on each edge (the
///   drag tier). A request overtaken by a newer `seq` for the same file answers 409 without
///   rendering; a bad look string 400; a file outside the opened folders 404.
nonisolated final class SetsSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "lumina"
    static let pageFile = "Lumina Sets v8.dc.html"
    /// Edit is its own page, which support.js fetches when Sets mounts it (`<dc-import name="Lumina Edit v21">`).
    static let editPageFile = "Lumina Edit v21.dc.html"
    static let vendorFiles = ["react.production.min.js", "react-dom.production.min.js", "babel.min.js"]
    /// What `lumina://app/<file>` serves. Debug builds and the probe: the same list as
    /// Scripts/page_files.sh, with the design's self-test, which the page asks for only with
    /// `?selftest` (`probe.sh selftest`). The app's Release build does not serve the self-test
    /// (S4): the file stays in the bundle, because the page files ship byte for byte, but the
    /// binary has no name for it, so `?selftest` gets "not served" and the page runs as usual.
    #if DEBUG || LUMINA_TOOLS
    static let pageFiles = [pageFile, editPageFile, "support.js", "lumina-core-v4.js", "lumina-v4-data.js", "lumina-measure.js", "lumina-selftest.js"]
    #else
    static let pageFiles = [pageFile, editPageFile, "support.js", "lumina-core-v4.js", "lumina-v4-data.js", "lumina-measure.js"]
    #endif

    /// support.js's CDN URLs → local. Passed to the page as `window.__resources`.
    static let resources: [String: String] = [
        "https://unpkg.com/react@18.3.1/umd/react.production.min.js": "\(scheme)://vendor/react.production.min.js",
        "https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js": "\(scheme)://vendor/react-dom.production.min.js",
        "https://unpkg.com/@babel/standalone@7.29.0/babel.min.js": "\(scheme)://vendor/babel.min.js",
    ]

    let pageRoot: URL
    let vendorRoot: URL
    let standInPhotos: Bool
    /// The opened folders' reader. Nil in the prototype (the page reads its own files there).
    let ingest: SetsIngest?
    private let lock = NSLock()
    private var _served: [String] = []
    private var stopped: Set<ObjectIdentifier> = []
    var served: [String] { lock.withLock { _served } }
    /// Made on the first render request (compiles the Metal kernels), nil when the rules file is
    /// missing from the bundle (the probe without LUMINA_RULES).
    private var _renderer: LookRenderer?
    private var rendererTried = false
    var renderStats: LookRenderer.Stats? { lock.withLock { _renderer?.stats } }

    init(pageRoot: URL, vendorRoot: URL, standInPhotos: Bool, ingest: SetsIngest? = nil) {
        self.pageRoot = pageRoot
        self.vendorRoot = vendorRoot
        self.standInPhotos = standInPhotos
        self.ingest = ingest
    }

    static var pageURL: URL {
        URL(string: "\(scheme)://app/\(pageFile.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host else { return fail(task) }
        let path = Self.path(url)
        let isMedia = (host == "app" && path.hasPrefix("media/")) || host == "render"
        if !isMedia { lock.withLock { _served.append(url.absoluteString) } }
        switch host {
        case "app" where isMedia:
            media(task, url, String(path.dropFirst("media/".count)))
        case "render":
            render(task, url, path)
        case "app":
            guard Self.pageFiles.contains(path), var data = try? Data(contentsOf: pageRoot.appendingPathComponent(path)) else { return fail(task) }
            if standInPhotos, path == Self.pageFile || path == Self.editPageFile, let text = String(data: data, encoding: .utf8) {
                data = Data(text.replacingOccurrences(of: "https://picsum.photos/", with: "\(Self.scheme)://photo/").utf8)
            }
            respond(task, url, data, mime(path))
        case "vendor":
            guard Self.vendorFiles.contains(path), let data = try? Data(contentsOf: vendorRoot.appendingPathComponent(path)) else { return fail(task) }
            respond(task, url, data, "text/javascript")
        case "photo" where standInPhotos:
            let parts = path.split(separator: "/").map(String.init)      // seed/<seed>/<w>/<h>
            guard parts.count == 4, let w = Int(parts[2]), let h = Int(parts[3]),
                  let data = StandInPhoto.jpeg(seed: parts[1], width: w, height: h) else { return fail(task) }
            respond(task, url, data, "image/jpeg")
        default:
            fail(task)
        }
    }

    /// The URL's path without its leading slash, percent-decoded once. Decoding twice would turn a
    /// file named "50%41.ARW" (sent as "50%2541.ARW") into "50A.ARW".
    static func path(_ url: URL) -> String {
        String(url.path(percentEncoded: false).dropFirst())
    }

    /// The query as name → value (the first of a repeated name). A `+` is a space, as in
    /// application/x-www-form-urlencoded (what URLSearchParams writes); plumbing.js sends
    /// encodeURIComponent, where a space is %20 and a real `+` is %2B, so both read the same.
    /// URLComponents.queryItems alone keeps `+` as a plus: a folder named "with space" was 404.
    static func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
        let decode = { (s: String) in s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding }
        var out: [String: String] = [:]
        for i in items {
            guard let name = decode(i.name), let raw = i.value, let value = decode(raw), out[name] == nil else { continue }
            out[name] = value
        }
        return out
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        lock.withLock { _ = stopped.insert(ObjectIdentifier(task)) }
    }

    /// Photo bytes, read off the main thread on the ingest's bounded queue. Errors carry a status
    /// the page can tell apart: 404 not in an opened folder, 410 the card went away, 422 unreadable.
    private func media(_ task: WKURLSchemeTask, _ url: URL, _ kind: String) {
        guard let ingest else { return fail(task) }
        let q = Self.query(url)
        guard let rel = q["p"] else { return status(task, url, 404, "no file") }
        let preview = SetsIngest.Preview(rel: rel, offset: SetsNumber.fileRange(q["o"]), length: SetsNumber.fileRange(q["l"]), orientation: SetsNumber.orientation(q["ori"]))
        let work: () throws -> Data
        switch kind {
        case "head": work = { try ingest.head(rel) }
        case "preview": work = { try ingest.preview(preview) }
        case "thumb": work = { try ingest.thumb(preview) }
        default: return status(task, url, 404, "unknown media \(kind)")
        }
        ingest.enqueue(work) { [weak self] r in
            guard let self, !self.lock.withLock({ self.stopped.remove(ObjectIdentifier(task)) != nil }) else { return }
            switch r {
            case .success(let data):
                self.respond(task, url, data, kind == "head" ? "application/octet-stream" : "image/jpeg")
            case .failure(let e as SetsIngest.Failure):
                self.status(task, url, e.kind == .gone ? 410 : e.kind == .notFound ? 404 : 422, e.description)
            case .failure(let e):
                self.status(task, url, 422, "\(e)")
            }
        }
    }

    private func lookRenderer() -> LookRenderer? {
        lock.withLock {
            if !rendererTried {
                rendererTried = true
                _renderer = try? LookRenderer(rules: LookRules.bundled())
            }
            return _renderer
        }
    }

    /// The Edit preview. Rendered on the renderer's own serial queue; the page's `seq` decides
    /// which requests still matter.
    private func render(_ task: WKURLSchemeTask, _ url: URL, _ rel: String) {
        guard let ingest else { return fail(task) }
        let q = Self.query(url)
        guard !rel.isEmpty, let file = ingest.resolve(rel) else { return status(task, url, 404, "not in an opened folder") }
        guard let renderer = lookRenderer() else { return status(task, url, 503, "no look pipeline (rules-v1.json missing)") }
        let look = q["look"] ?? "", seq = SetsNumber.seq(q["seq"], text: true)
        // `tier=small` is the image fallback path's drag tier (addendum §7): a quarter of the
        // asked size on each edge, the same rule the native canvas's `small` texture follows.
        var px = SetsNumber.renderEdge(q["px"])
        if q["tier"] == "small" { px = max(64, px / 4) }
        let decoder = SetsNumber.decoder(q["decoder"])
        // `o`, `l`, `ori`: the embedded JPEG's range (the page's parseHead), the stand-in when the RAW can't be developed.
        var preview: LookBases.PreviewFallback?
        let o = SetsNumber.fileRange(q["o"]), l = SetsNumber.fileRange(q["l"])
        if o > 0, l > 0 { preview = LookBases.PreviewFallback(offset: o, length: l, orientation: SetsNumber.orientation(q["ori"])) }
        renderer.requested(rel: rel, seq: seq)
        renderer.enqueue({ try renderer.renderJPEG(url: file, rel: rel, look: look, px: px, seq: seq, decoder: decoder, preview: preview) }) { [weak self] r in
            guard let self, !self.lock.withLock({ self.stopped.remove(ObjectIdentifier(task)) != nil }) else { return }
            switch r {
            case .success(let data):
                self.respond(task, url, data, "image/jpeg")
            case .failure(is LookRenderer.Stale):
                self.status(task, url, 409, "superseded by a newer request")
            case .failure(let e as Look.ParseError):
                self.status(task, url, 400, e.description)
            case .failure(let e):
                self.status(task, url, FileManager.default.fileExists(atPath: file.path) ? 422 : 410, "\(e)")
            }
        }
    }

    /// An HTTP error the page's fetch() can read (a failed task would look like a network error).
    private func status(_ task: WKURLSchemeTask, _ url: URL, _ code: Int, _ text: String) {
        let body = Data(text.utf8)
        let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/plain; charset=utf-8", "Content-Length": "\(body.count)"])!
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    private func respond(_ task: WKURLSchemeTask, _ url: URL, _ data: Data, _ mime: String) {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask) {
        task.didFailWithError(NSError(domain: "lumina", code: 404,
                                      userInfo: [NSLocalizedDescriptionKey: "not served: \(task.request.url?.absoluteString ?? "?")"]))
    }

    private func mime(_ file: String) -> String {
        UTType(filenameExtension: (file as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

/// Flat, seeded stand-ins for the sample shoot: one colour per photo, its hue from the seed.
/// No edge inside the picture (a sky and ground used to meet at a horizon): the screens twins draw
/// the same stand-in from differently sized decodes (the app decodes ahead of a scroll, the
/// prototype does not), and an edge resampled from two sources lands on two different blended rows
/// (the large view's filmstrip differed by that row alone). A flat colour resamples to itself.
nonisolated enum StandInPhoto {
    static func jpeg(seed: String, width: Int, height: Int) -> Data? {
        let w = max(1, min(width, 6000)), h = max(1, min(height, 6000))
        var hash: UInt32 = 2166136261
        for b in seed.utf8 { hash = (hash ^ UInt32(b)) &* 16777619 }
        let hue = CGFloat(hash % 360) / 360
        let fill = NSColor(hue: hue, saturation: 0.35 + CGFloat((hash >> 9) % 20) / 100, brightness: 0.45 + CGFloat((hash >> 17) % 40) / 100, alpha: 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(fill.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
