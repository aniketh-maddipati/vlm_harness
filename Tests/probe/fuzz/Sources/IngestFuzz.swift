import Darwin
import Foundation
import ImageIO

/// `hostile-ingest`: the app's own `SetsIngest` (compiled from `Lumina/Sets/Core`, unchanged) fed
/// the seeded cases `cases.mjs` writes: heads cut at every 4 KB boundary, preview ranges past the
/// end / 0 / negative / 2 GB / over the head, bad orientations, bad EXIF counts, damaged JPEGs.
///
///   hostile-ingest forge <dir>                                  synthetic base ARWs + JPEGs
///   hostile-ingest run <cases.jsonl> <bases> <work> [--from N]  one JSON line per case on stdout
///
/// Each case: the mutated file is written into `<work>/shoot`, then `head`, and for each request
/// (the one the page's parseHead makes, or a hostile one) `preview` and `thumb`, as the scheme
/// handler calls them. A case that runs over 5 s exits the process (code 3, a `hang` line); one
/// that takes the footprint over 1.5 GB exits it (code 4, a `memory` line). The driver (`fuzz.mjs`)
/// starts again after the case that stopped it.
@main
enum IngestFuzz {
    static func main() {
        let a = CommandLine.arguments
        guard a.count >= 3 else { fputs("usage: hostile-ingest forge <dir> | run <cases.jsonl> <bases> <work> [--from N]\n", stderr); exit(2) }
        switch a[1] {
        case "forge": forge(URL(fileURLWithPath: a[2]))
        case "run" where a.count >= 5:
            let from = a.firstIndex(of: "--from").flatMap { Int(a[$0 + 1]) } ?? 0
            run(cases: URL(fileURLWithPath: a[2]), bases: URL(fileURLWithPath: a[3]), work: URL(fileURLWithPath: a[4]), from: from)
        default: fputs("unknown mode\n", stderr); exit(2)
        }
    }

    /// The bases every case starts from (`bases.json` names them and where their JPEG is).
    static func forge(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent(".metadata_never_index").path, contents: nil)
        let j0 = Fuzz.jpeg(w: 640, h: 427, seed: 1), j1 = Fuzz.jpeg(w: 1616, h: 1080, seed: 2), j2 = Fuzz.jpeg(w: 160, h: 120, seed: 3)
        let bases: [(String, Data, Int, Int, Int)] = [
            ("b0-head.ARW", j0, 1, 4096, 300_000),              // preview inside the head, as a Sony body
            ("b1-camera.ARW", j1, 6, 4096, 4096 + j1.count + 16), // camera-sized preview, portrait
            ("b2-far.ARW", j0, 3, 300_000, 300_000 + j0.count + 4096), // preview past the head: read from the card
            ("b3-tiny.ARW", j2, 8, 4096, 8192),
        ]
        var meta: [[String: Any]] = []
        for (name, jpeg, ori, at, pad) in bases {
            let d = Fuzz.arw(jpeg: jpeg, orient: ori, jpegAt: at, pad: pad)
            try? d.write(to: dir.appendingPathComponent(name))
            meta.append(["name": name, "size": d.count, "jpegAt": at, "jpegLen": jpeg.count, "orient": ori])
        }
        for (name, jpeg) in [("j0.jpg", j0), ("j1.jpg", j1), ("j2.jpg", j2)] { try? jpeg.write(to: dir.appendingPathComponent(name)) }
        let data = try! JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
        try! data.write(to: dir.appendingPathComponent("bases.json"))
        print("forged \(bases.count) ARWs + 3 JPEGs in \(dir.path)")
    }

    final class Box: @unchecked Sendable { var current = "-" }

    static func run(cases: URL, bases: URL, work: URL, from: Int) {
        let fm = FileManager.default
        let shoot = work.appendingPathComponent("shoot", isDirectory: true)
        try? fm.createDirectory(at: shoot, withIntermediateDirectories: true)
        fm.createFile(atPath: work.appendingPathComponent(".metadata_never_index").path, contents: nil)
        var baseData: [String: Data] = [:]
        let box = Box()
        Fuzz.memoryWatchdog(limit: 1536 << 20) { box.current }
        let ingest = SetsIngest(workers: 2)
        ingest.register(shoot)
        let text = (try? String(contentsOf: cases, encoding: .utf8)) ?? ""
        var lines = 0
        for line in text.split(separator: "\n") { autoreleasepool {
            guard let c = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], let i = c["i"] as? Int else { return }
            lines += 1
            guard i >= from else { return }
            let baseName = c["base"] as? String ?? ""
            if baseData[baseName] == nil { baseData[baseName] = try? Data(contentsOf: bases.appendingPathComponent(baseName)) }
            guard let base = baseData[baseName] else { Fuzz.emit(["i": i, "event": "nobase"]); return }
            let input = Fuzz.mutate(base, trunc: c["trunc"] as? Int, patches: c["patches"] as? [[Any]] ?? [])
            let name = String(format: "C%06d.ARW", i), url = shoot.appendingPathComponent(name), rel = "shoot/" + name
            try? input.write(to: url)
            box.current = "\(i)"
            Fuzz.emit(["i": i, "event": "start"])
            let reqs = c["reqs"] as? [[String: Any]] ?? []
            let done = DispatchSemaphore(value: 0)
            let result = ResultBox()
            let t0 = Date()
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool { result.value = one(ingest: ingest, rel: rel, input: input, reqs: reqs) }
                done.signal()
            }
            if done.wait(timeout: .now() + 5) == .timedOut {
                Fuzz.emit(["i": i, "event": "hang", "seconds": 5])
                _exit(3)
            }
            var o = result.value
            o["i"] = i; o["event"] = "case"; o["ms"] = Int(Date().timeIntervalSince(t0) * 1000); o["fpMB"] = Fuzz.footprint() >> 20
            Fuzz.emit(o)
            try? fm.removeItem(at: url)
        } }
        Fuzz.emit(["event": "end", "cases": lines, "stats": ingest.snapshot.dictionary])
    }

    final class ResultBox: @unchecked Sendable { var value: [String: Any] = [:] }

    static func status(_ e: Error) -> Int {
        guard let f = e as? SetsIngest.Failure else { return 422 }
        return f.kind == .gone ? 410 : f.kind == .notFound ? 404 : 422
    }

    static func decodes(_ d: Data) -> Bool {
        guard let s = CGImageSourceCreateWithData(d as CFData, nil), CGImageSourceGetCount(s) > 0,
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [String: Any], (p[kCGImagePropertyPixelWidth as String] as? Int ?? 0) > 0 else { return false }
        return true
    }

    /// One case through the reader, as the scheme handler calls it, with what each answer must be.
    static func one(ingest: SetsIngest, rel: String, input: Data, reqs: [[String: Any]]) -> [String: Any] {
        var viol: [String] = []
        var out: [String: Any] = [:]
        do {
            let h = try ingest.head(rel)
            out["head"] = h.count
            if h != input.prefix(SetsIngest.headBytes) { viol.append("head bytes differ from the file") }
        } catch { out["head"] = status(error); viol.append("head failed \(status(error)) on a file that is there: \(error)") }
        var answers: [[String: Any]] = []
        for r in reqs {
            let o = (r["o"] as? NSNumber)?.intValue ?? 0, l = (r["l"] as? NSNumber)?.intValue ?? 0, ori = (r["ori"] as? NSNumber)?.intValue ?? 1
            let src = r["src"] as? String ?? "?"
            let valid = o > 0 && l > 0 && l <= 64 << 20 && o <= input.count && l <= input.count - o
            var a: [String: Any] = ["src": src, "o": o, "l": l, "ori": ori]
            // What plumbing asks first: the preview as stored (ori 1); then the grid thumbnail.
            for (kind, askOri) in [("preview", 1), ("previewUpright", ori), ("thumb", ori)] {
                if kind == "previewUpright" && ![3, 6, 8].contains(ori) { continue }
                let p = SetsIngest.Preview(rel: rel, offset: o, length: l, orientation: askOri)
                do {
                    let d = kind == "thumb" ? try ingest.thumb(p) : try ingest.preview(p)
                    a[kind] = 200
                    if !valid { viol.append("\(kind) 200 for a range outside the file (o \(o) l \(l) size \(input.count))") }
                    if kind == "preview", valid, d != input.subdata(in: o ..< o + l) { viol.append("preview bytes are not the file's range") }
                    if kind != "preview", !decodes(d) { viol.append("\(kind) 200 but not an image") }
                } catch {
                    let s = status(error)
                    a[kind] = s
                    if s != 422 { viol.append("\(kind) \(s) (not 422) for a file that is there: \(error)") }
                    if kind == "preview", valid { viol.append("preview refused a range inside the file: \(error)") }
                }
            }
            answers.append(a)
        }
        out["reqs"] = answers
        if !viol.isEmpty { out["viol"] = viol }
        return out
    }
}
