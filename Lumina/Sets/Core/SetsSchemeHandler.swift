import AppKit
import UniformTypeIdentifiers
import WebKit

/// Serves the page from local files under `lumina://`. Nothing loads from the network.
///
/// - `lumina://app/<file>`     the design's page files, byte-identical
/// - `lumina://vendor/<file>`  React / Babel (support.js asks for them via `window.__resources`)
/// - `lumina://photo/seed/<seed>/<w>/<h>`  stand-in photos for the design's sample shoot (the
///   page's picsum URLs are pointed here). Debug fixture data only; off once the sample goes.
nonisolated final class SetsSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "lumina"
    static let pageFile = "Lumina Sets v3.dc.html"
    static let vendorFiles = ["react.production.min.js", "react-dom.production.min.js", "babel.min.js"]
    static let pageFiles = [pageFile, "support.js", "lumina-core.js"]

    /// support.js's CDN URLs → local. Passed to the page as `window.__resources`.
    static let resources: [String: String] = [
        "https://unpkg.com/react@18.3.1/umd/react.production.min.js": "\(scheme)://vendor/react.production.min.js",
        "https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js": "\(scheme)://vendor/react-dom.production.min.js",
        "https://unpkg.com/@babel/standalone@7.29.0/babel.min.js": "\(scheme)://vendor/babel.min.js",
    ]

    let pageRoot: URL
    let vendorRoot: URL
    let standInPhotos: Bool
    private let lock = NSLock()
    private var _served: [String] = []
    var served: [String] { lock.withLock { _served } }

    init(pageRoot: URL, vendorRoot: URL, standInPhotos: Bool) {
        self.pageRoot = pageRoot
        self.vendorRoot = vendorRoot
        self.standInPhotos = standInPhotos
    }

    static var pageURL: URL {
        URL(string: "\(scheme)://app/\(pageFile.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host else { return fail(task) }
        let path = String((url.path.removingPercentEncoding ?? url.path).dropFirst())
        lock.withLock { _served.append(url.absoluteString) }
        switch host {
        case "app":
            guard Self.pageFiles.contains(path), var data = try? Data(contentsOf: pageRoot.appendingPathComponent(path)) else { return fail(task) }
            if standInPhotos, path == Self.pageFile, let text = String(data: data, encoding: .utf8) {
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

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

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

/// Flat, seeded stand-ins for the sample shoot: sky and ground with a hue from the seed.
nonisolated enum StandInPhoto {
    static func jpeg(seed: String, width: Int, height: Int) -> Data? {
        let w = max(1, min(width, 6000)), h = max(1, min(height, 6000))
        var hash: UInt32 = 2166136261
        for b in seed.utf8 { hash = (hash ^ UInt32(b)) &* 16777619 }
        let hue = CGFloat(hash % 360) / 360
        let sky = NSColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1)
        let ground = NSColor(hue: (hue + 0.33).truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: 0.4, alpha: 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let horizon = CGFloat(h) * (0.35 + CGFloat((hash >> 9) % 30) / 100)
        ctx.setFillColor(ground.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: Int(horizon)))
        ctx.setFillColor(sky.cgColor); ctx.fill(CGRect(x: 0, y: Int(horizon), width: w, height: h))
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
