import AppKit
import LuminaCore

/// `lumina-snap --golden <state|a,b,…|all|list>`: renders golden states offscreen and diffs them
/// with the goldens captured from the prototype (`capture-goldens.mjs`, laid out as
/// `<goldens>/<size>/<state>.png` + `manifest.json`). One line per state, then a summary:
///
///   PASS  edit-help              over   0.84%  mean  1.92  pixel
///   FAIL  save-ready             over   7.80%  mean  9.10  pixel     (gated: more than 2.00% over 16/255)
///   INFO  edit-loaded            over  31.20%  mean 22.40  scaled    (native S 1.13 at this size: not gated)
///   EYE   cull-mid               over  12.00%  mean  8.00  layout    (LAYOUT_SIZING overrides: by eye)
///   MISS  open-empty             no golden at …                      (rendered, nothing to diff)
///   ERR   edit-crop              overlay none, not crop              (the steps didn't reach the state)
///   goldens: 1100x760 · 22 gated: 18 pass, 4 fail · 6 by eye · 0 informational · 0 missing · 0 errors · worst save-ready 7.80% · images …
///
/// Writes `<out-dir>/<state>.png` (native) and, with a golden, `<out-dir>/<state>.cmp.png`
/// (golden | native | diff). Exit 0 when every gated state has its golden and passes and nothing
/// errs; 1 otherwise;
/// 2 for bad arguments.
@MainActor
enum GoldenRun {
    struct Manifest: Decodable {
        struct Tolerance: Decodable { let pixel: Double?; let perPixelDelta: Int? }
        struct Shot: Decodable { let state: String; let size: String; let error: String? }
        let tolerance: Tolerance?
        let shots: [Shot]?
    }

    static var defaultGoldens: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("LuminaEvidence/native-ui/goldens") }

    static func main(spec: String, sizeID: String, goldens: URL, outDir: URL, scale: Double?, extraSettle: Double) -> Int32 {
        guard let size = GoldenSize.named(sizeID) else { say("lumina-snap: bad --size \(sizeID) (WxH)"); return 2 }
        if spec == "list" {
            for s in GoldenStates.all { say("\(pad(s.name, 22)) \(GoldenCompare.of(state: s.name, size: size).rawValue)") }
            return 0
        }
        let names = spec == "all" ? GoldenStates.all.map(\.name) : spec.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let unknown = names.filter { GoldenStates.named($0) == nil }
        guard unknown.isEmpty else { say("lumina-snap: no golden state \(unknown.joined(separator: ", ")) (--golden list)"); return 2 }

        let manifest = (try? Data(contentsOf: goldens.appendingPathComponent("manifest.json"))).flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
        let limit = manifest?.tolerance?.pixel ?? 0.02, threshold = manifest?.tolerance?.perPixelDelta ?? 16
        let px = scale ?? size.dpr, nativeS = LayoutScale.scale(for: size.size)
        if !FileManager.default.fileExists(atPath: goldens.appendingPathComponent(size.id).path) {
            say("note: no goldens at \(goldens.appendingPathComponent(size.id).path): rendering only. Capture them with design/handoff/lumina-app/parity/capture/capture-goldens.mjs and copy goldens/ there.")
        }

        var pass = 0, fail = 0, eye = 0, info = 0, missing = 0, missingGated = 0, errors = 0
        var worst: (String, Double)?
        for name in names {
            guard let state = GoldenStates.named(name) else { continue }
            let compare = GoldenCompare.of(state: name, size: size)
            let driver = GoldenDriver(state, window: size.size)
            let screen = Offscreen(model: driver.model, size: size.size)
            driver.pump = { screen.pump($0) }
            let problems = driver.run()
            screen.settle(state.settle + extraSettle, clock: driver.clock)
            let native = screen.capture(scale: px)
            screen.close()

            let nativeURL = outDir.appendingPathComponent("\(name).png")
            guard let native else { say(line("ERR", name, "nothing captured")); errors += 1; continue }
            do { try PNG.write(native, to: nativeURL) } catch { say(line("ERR", name, "can't write \(nativeURL.path): \(error)")); errors += 1; continue }
            if !problems.isEmpty { say(line("ERR", name, problems.joined(separator: "; ") + "  → \(nativeURL.path)")); errors += 1; continue }

            if let shot = manifest?.shots?.first(where: { $0.state == name && $0.size == size.id }), let e = shot.error {
                say(line("MISS", name, "the golden capture failed: \(e)")); missing += 1; if compare == .pixel { missingGated += 1 }; continue
            }
            let goldenURL = goldens.appendingPathComponent(size.id).appendingPathComponent("\(name).png")
            guard let golden = PNG.read(goldenURL) else { say(line("MISS", name, "no golden at \(goldenURL.path)  → \(nativeURL.path)")); missing += 1; if compare == .pixel { missingGated += 1 }; continue }
            guard let d = GoldenDiff(golden: golden, native: native, threshold: threshold) else { say(line("ERR", name, "diff failed")); errors += 1; continue }
            let cmpURL = outDir.appendingPathComponent("\(name).cmp.png")
            try? PNG.write(d.sideBySide, to: cmpURL)

            let numbers = "over \(fmt(d.over * 100, 6))%  mean \(fmt(d.mean, 5))  \(pad(compare.rawValue, 6))"
            let note = d.resized ? "  (native \(native.width)x\(native.height) scaled to \(golden.width)x\(golden.height))" : ""
            switch compare {
            case .pixel:
                if d.over <= limit { pass += 1; say(line("PASS", name, numbers + note)) }
                else { fail += 1; say(line("FAIL", name, numbers + "  (more than \(fmt(limit * 100, 0))% over \(threshold)/255)" + note)) }
                if worst.map({ d.over > $0.1 }) ?? true { worst = (name, d.over) }
            case .scaled: info += 1; say(line("INFO", name, numbers + "  (native S \(fmt(Double(nativeS), 0)) here: not gated)" + note))
            case .layout: eye += 1; say(line("EYE", name, numbers + "  (LAYOUT_SIZING overrides: by eye)" + note))
            }
        }
        let worstText = worst.map { " · worst \($0.0) \(fmt($0.1 * 100, 0))%" } ?? ""
        say("goldens: \(size.id) @\(fmt(px, 0))x · \(pass + fail) gated: \(pass) pass, \(fail) fail · \(eye) by eye · \(info) informational · \(missing) missing · \(errors) errors\(worstText) · images \(outDir.path)")
        return fail == 0 && errors == 0 && missingGated == 0 ? 0 : 1
    }

    private static func line(_ verdict: String, _ name: String, _ rest: String) -> String { "\(pad(verdict, 5)) \(pad(name, 22)) \(rest)" }
    private static func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
    /// Two decimals, right-aligned to `width` (0 = no padding).
    private static func fmt(_ v: Double, _ width: Int) -> String {
        let s = String(format: "%.2f", v)
        return s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }
    private static func say(_ s: String) { print(s); fflush(stdout) }
}
