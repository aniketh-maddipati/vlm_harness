import AppKit
import UniformTypeIdentifiers
import WebKit

/// Serves the page from disk under `lumina-ref://`, so nothing loads from the network.
///
/// - `lumina-ref://app/<path>`      files under the page root (unchanged bytes, except the
///                                  prototype's picsum placeholder URLs, rewritten to `photo/`)
/// - `lumina-ref://vendor/<file>`   vendored React / Babel
/// - `lumina-ref://photo/seed/<seed>/<w>/<h>`  a deterministic stand-in photo
final class ProbeSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "lumina-ref"
    let pageRoot: URL
    let vendorRoot: URL
    private(set) var served: [String] = []

    init(pageRoot: URL, vendorRoot: URL) {
        self.pageRoot = pageRoot
        self.vendorRoot = vendorRoot
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host else { return fail(task) }
        let path = url.path.removingPercentEncoding ?? url.path
        served.append(url.absoluteString)
        switch host {
        case "app":
            let file = pageRoot.appendingPathComponent(String(path.dropFirst()))
            guard var data = try? Data(contentsOf: file) else { return fail(task) }
            if file.pathExtension == "html", let text = String(data: data, encoding: .utf8) {
                data = Data(text.replacingOccurrences(of: "https://picsum.photos/", with: "\(Self.scheme)://photo/").utf8)
            }
            respond(task, url, data, mime(file))
        case "vendor":
            let file = vendorRoot.appendingPathComponent(String(path.dropFirst()))
            guard let data = try? Data(contentsOf: file) else { return fail(task) }
            respond(task, url, data, "text/javascript")
        case "photo":
            // /seed/<seed>/<w>/<h>
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count == 4, let w = Int(parts[2]), let h = Int(parts[3]),
                  let data = StandInPhoto.jpeg(seed: parts[1], width: w, height: h)
            else { return fail(task) }
            respond(task, url, data, "image/jpeg")
        default:
            fail(task)
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func respond(_ task: WKURLSchemeTask, _ url: URL, _ data: Data, _ mime: String) {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)",
                                                      "Access-Control-Allow-Origin": "*"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask) {
        task.didFailWithError(NSError(domain: "lumina-probe", code: 404,
                                      userInfo: [NSLocalizedDescriptionKey: "not served: \(task.request.url?.absoluteString ?? "?")"]))
    }

    private func mime(_ file: URL) -> String {
        UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}

/// Flat, seeded stand-in images: a sky/ground split with a hue from the seed. Photo areas
/// are masked out of pixel diffs, so these only need to be stable and plausible.
enum StandInPhoto {
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
