import WebKit
import XCTest
@testable import Lumina

/// Photo paths in `lumina://` URLs (S9): a folder or file name with a space, `+`, `#`, `&`, `%`, `?`,
/// `=`, or an accent in either Unicode form must reach the same file the native listing named.
/// The page builds media URLs in plumbing.js; these requests are built the way a browser encodes them.
final class SetsSchemeHandlerURLTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sets-scheme-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    // MARK: Encoders, as the page's JavaScript writes them

    /// `encodeURIComponent`: everything but A–Z a–z 0–9 - _ . ! ~ * ' ( ) as UTF-8 %XX.
    static func uriComponent(_ s: String) -> String {
        let ok = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: ok)!
    }

    /// `URLSearchParams.toString()` (application/x-www-form-urlencoded): a space is `+`, everything
    /// but A–Z a–z 0–9 * - . _ is %XX.
    static func formComponent(_ s: String) -> String {
        let ok = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*-._ ")
        return s.addingPercentEncoding(withAllowedCharacters: ok)!.replacingOccurrences(of: " ", with: "+")
    }

    // MARK: A fake task

    private final class Task: NSObject, WKURLSchemeTask {
        let request: URLRequest
        var status = 0
        var body = Data()
        var failed = false
        let done: XCTestExpectation
        init(_ url: URL, _ done: XCTestExpectation) { request = URLRequest(url: url); self.done = done }
        func didReceive(_ response: URLResponse) { status = (response as? HTTPURLResponse)?.statusCode ?? -1 }
        func didReceive(_ data: Data) { body.append(data) }
        func didFinish() { done.fulfill() }
        func didFailWithError(_ error: Error) { failed = true; done.fulfill() }
    }

    private func handler(rooted roots: [URL]) -> SetsSchemeHandler {
        let ingest = SetsIngest(workers: 2)
        for r in roots { ingest.register(r) }
        return SetsSchemeHandler(pageRoot: dir, vendorRoot: dir, standInPhotos: false, ingest: ingest)
    }

    private func get(_ h: SetsSchemeHandler, _ s: String, file: StaticString = #filePath, line: UInt = #line) -> (Int, Data) {
        guard let url = URL(string: s) else { XCTFail("not a URL: \(s)", file: file, line: line); return (0, Data()) }
        let done = expectation(description: s)
        let task = Task(url, done)
        h.webView(WKWebView(), start: task)
        wait(for: [done], timeout: 10)
        return (task.failed ? -1 : task.status, task.body)
    }

    /// Writes `<root>/<name>` with bytes that name it, so a hit on the wrong file shows.
    @discardableResult
    private func photo(_ root: URL, _ name: String) throws -> Data {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(("ARW " + name).utf8)
        try data.write(to: url)
        return data
    }

    // MARK: The repro

    /// The bug as reported: a folder named "with space" never finished loading. plumbing.js built
    /// `/media/head?p=with+space%2FDSC00001.ARW` with URLSearchParams, and the handler read `+` as a
    /// plus, so every head of that folder answered 404.
    func testFormEncodedSpaceInFolderNameReachesTheFile() throws {
        let root = dir.appendingPathComponent("with space", isDirectory: true)
        let bytes = try photo(root, "DSC00001.ARW")
        let h = handler(rooted: [root])
        let (code, body) = get(h, "lumina://app/media/head?" + "p=" + Self.formComponent("with space/DSC00001.ARW"))
        XCTAssertEqual(code, 200)
        XCTAssertEqual(body, bytes)
    }

    // MARK: Awkward names, both encoders

    static let nfd = "Cafe\u{0301}"                                  // é as e + combining accent (APFS hands names back as given)
    static let awkward = [
        "Shoot 2026 #1 & 50% (é) + more/DSC00001.ARW",
        "Shoot 2026 #1 & 50% (é) + more/sub dir/a+b=c?d&e#f 50%41.ARW",
        "\(nfd) ?=/\(nfd) x=1?y.ARW",
        "plain/C++ 100% ~'!*.ARW",
    ]

    func testHeadAndPreviewReachEveryAwkwardNameWithEitherEncoder() throws {
        var bytes: [String: Data] = [:]
        var roots: [URL] = []
        for rel in Self.awkward {
            let parts = rel.split(separator: "/", maxSplits: 1).map(String.init)
            let root = dir.appendingPathComponent(parts[0], isDirectory: true)
            if !roots.contains(root) { roots.append(root) }
            bytes[rel] = try photo(root, parts[1])
        }
        let h = handler(rooted: roots)
        for rel in Self.awkward {
            for (label, enc) in [("encodeURIComponent", Self.uriComponent), ("URLSearchParams", Self.formComponent)] {
                let (code, body) = get(h, "lumina://app/media/head?p=" + enc(rel))
                XCTAssertEqual(code, 200, "\(label): \(rel)")
                XCTAssertEqual(body, bytes[rel], "\(label): \(rel)")
                // A byte range, as the preview asks for it (the stored bytes are not a JPEG, so 422,
                // which only a found file can answer; 404 would mean the name was lost).
                let (pcode, _) = get(h, "lumina://app/media/preview?p=" + enc(rel) + "&o=1&l=4&ori=1")
                XCTAssertNotEqual(pcode, 404, "\(label) preview: \(rel)")
            }
        }
    }

    func testNFCAndNFDSpellingsReachTheSameFile() throws {
        let root = dir.appendingPathComponent("\(Self.nfd) shoot", isDirectory: true)
        let bytes = try photo(root, "\(Self.nfd).ARW")
        let h = handler(rooted: [root])
        let nfd = "\(Self.nfd) shoot/\(Self.nfd).ARW"
        for rel in [nfd, nfd.precomposedStringWithCanonicalMapping] {
            let (code, body) = get(h, "lumina://app/media/head?p=" + Self.uriComponent(rel))
            XCTAssertEqual(code, 200, rel.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: " "))
            XCTAssertEqual(body, bytes)
        }
    }

    func testQueryDecodesOnceAndKeepsARealPlus() throws {
        let rel = "a+b & c=d?e #f 50%41 é/x.ARW"
        let js = URL(string: "lumina://render/r?p=" + Self.uriComponent(rel) + "&look=" + Self.uriComponent("ev:+0.50 con:+12") + "&px=900")!
        XCTAssertEqual(SetsSchemeHandler.query(js), ["p": rel, "look": "ev:+0.50 con:+12", "px": "900"])
        let form = URL(string: "lumina://app/media/head?p=" + Self.formComponent(rel))!
        XCTAssertEqual(SetsSchemeHandler.query(form)["p"], rel)
        XCTAssertEqual(SetsSchemeHandler.query(URL(string: "lumina://app/media/head?p=a&p=b&e=")!), ["p": "a", "e": ""])
    }

    /// `lumina://render/<rel>`: renderURL encodes each path segment with encodeURIComponent. The
    /// path is decoded once (twice turned "50%41" into "50A"); the page file's own %20s still decode.
    func testPathDecodesOnce() throws {
        for rel in Self.awkward + ["Shoot/50%25.ARW", "Shoot/%41%42.ARW"] {
            let url = URL(string: "lumina://render/" + rel.split(separator: "/").map { Self.uriComponent(String($0)) }.joined(separator: "/") + "?look=&px=900")!
            XCTAssertEqual(SetsSchemeHandler.path(url), rel)
        }
        XCTAssertEqual(SetsSchemeHandler.path(SetsSchemeHandler.pageURL), SetsSchemeHandler.pageFile)
    }
}
