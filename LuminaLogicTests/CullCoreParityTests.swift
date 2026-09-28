import JavaScriptCore
import XCTest
@testable import Lumina

/// Differential proof of the Swift port: the prototype's own `lumina-core.js`, run unchanged in
/// JavaScriptCore, against `CullCore*` on seeded random inputs. Fixtures cover the cases someone
/// thought of; this covers ties, odd dates, malformed TIFFs and XMP spellings nobody listed.
final class CullCoreParityTests: XCTestCase {

    private var js: JSContext!
    private var jsFailure: String?

    override func setUpWithError() throws {
        js = try XCTUnwrap(JSContext())
        js.exceptionHandler = { [weak self] _, exception in self?.jsFailure = exception?.toString() ?? "exception" }
        // Browser-only pieces of the core: Blob (zip), canvas (measure), TextEncoder (zip names).
        js.evaluateScript("""
        globalThis.Blob = function (parts) { let n = 0; parts.forEach(p => n += p.length);
          const out = new Uint8Array(n); let o = 0; parts.forEach(p => { out.set(p, o); o += p.length; }); this.bytes = out; };
        if (typeof TextEncoder === 'undefined') globalThis.TextEncoder = function () { this.encode = s => {
          const b = unescape(encodeURIComponent(s)), u = new Uint8Array(b.length);
          for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i); return u; }; };
        globalThis.__px = null;
        globalThis.document = { createElement() { return { getContext() { return {
          drawImage() {}, getImageData() { return { data: globalThis.__px }; } }; } }; } };
        """)
        let source = try String(contentsOf: CullCoreFixtureTests.handoff.appendingPathComponent("lumina-core.js"), encoding: .utf8)
        js.evaluateScript(source)
        js.evaluateScript("""
        const LC = globalThis.LuminaCore;
        globalThis.pShoot = (list, cuts) => { const d = LC.buildShoot(list, cuts); return JSON.stringify({
          photos: Object.values(d.byId).map(p => ({ id: p.id, file: p.file, mi: p.mi, time: p.time, hh: p.hh, light: p.light,
            sharp: p.sharp, clip: p.clip, blown: p.blown, shake: p.shake, start: p.start, soft: !!p.soft, slight: !!p.slight,
            bk: p.bk, rank: p.rank, bn: p.bn, kind: p.kind, gid: p.gid, ss: p.ss, fl: p.fl })),
          moments: d.M.map(m => ({ id: m.id, time: m.time, hh: m.hh, light: m.light, groups: m.groups.map(g => g.gid),
            subs: m.subs.map(s => ({ id: s.id, kind: s.kind, ids: s.ids })) })),
          groups: Object.values(d.G).map(g => ({ gid: g.gid, kind: g.kind, frames: g.frames.map(f => f.id), ranked: g.ranked.map(f => f.id) })),
          nodes: d.N.map(n => ({ id: n.id, type: n.type, mi: n.mi, ids: n.ids, kind: n.kind || null })),
          sub: d.sub, keep: Object.keys(d.sugKeep), order: d.order }); };
        globalThis.pHead = (bytes, size) => { const o = LC.parseHead(new Uint8Array(bytes), size); return JSON.stringify(o ? {
          date: o.date ?? null, exp: o.exp ?? null, fl: o.fl ?? null, ev: o.ev ?? null, iso: o.iso ?? null,
          orient: o.orient ?? null, preview: o.preview } : null); };
        globalThis.pMeasure = (px, w, h) => { globalThis.__px = new Uint8ClampedArray(px);
          const m = LC.measure({ width: w, height: h }); return JSON.stringify({ lum: m.lum, focus: m.focus, clip: m.clip }); };
        globalThis.pZip = files => JSON.stringify(Array.from(LC.zip(files.map(f => ({ name: f.name, data: new Uint8Array(f.data) }))).bytes));
        globalThis.pCrc = bytes => LC.crc32(new Uint8Array(bytes));
        """)
        if let jsFailure { XCTFail("lumina-core.js failed to load: \(jsFailure)") }
    }

    private func call(_ fn: String, _ args: [Any]) throws -> Any {
        let value = try XCTUnwrap(js.objectForKeyedSubscript(fn).call(withArguments: args), fn)
        if let jsFailure { self.jsFailure = nil; XCTFail("\(fn) threw: \(jsFailure)") }
        return value
    }

    /// The p* helpers return JSON text (undefined → null, NaN → null); JSON.parse back inside JSC and
    /// bridge with `toObject`, because Foundation's JSON reader can land a double one ulp off.
    private func callJSON(_ fn: String, _ args: [Any]) throws -> Any {
        let text = try XCTUnwrap(try call(fn, args) as? JSValue)
        let parsed = try XCTUnwrap(js.objectForKeyedSubscript("JSON").invokeMethod("parse", withArguments: [text]))
        return parsed.isNull ? NSNull() : try XCTUnwrap(parsed.toObject())
    }

    private func assertSame(_ swift: Any, _ jsValue: Any, _ what: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let a = NSArray(object: swift), b = NSArray(object: jsValue)
        if a.isEqual(b) { return true }
        func text(_ v: Any) -> String {
            (try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .fragmentsAllowed]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "\(v)"
        }
        XCTFail("\(what)\n swift \(text(swift).prefix(1500))\n js    \(text(jsValue).prefix(1500))", file: file, line: line)
        return false
    }

    private func num(_ v: Double?) -> Any { v.flatMap { $0.isFinite ? $0 : nil } ?? NSNull() }

    // MARK: - buildShoot

    func testBuildShootMatchesJavaScript() throws {
        var rng = SplitMix64(seed: 0xC011_0001)
        for trial in 0..<400 {
            let count = rng.int(1...40)
            var clock = 1_790_000_000.0 + rng.double() * 86_400  // 2026-09 UTC
            var list: [CullCoreShoot.Input] = []
            let paths = ["100MSDCF", "101MSDCF", "a", "B", "_x", "dsc", "Dsc", "z-1", "z10", "z2"]
            for i in 0..<count {
                let steps: [Double] = [0, 0, 0.4, 0.9, 1, 1.5, 30, 90, 91, 400, 4000]
                clock += steps.randomElement(using: &rng)!
                let evPool: [Double] = [-2, -1.7, -1, -0.3, 0, 0.3, 0.7, 1, 2, 0.05, 0.15]
                let expPool: [Double] = [0, 1.0 / 8000, 1.0 / 500, 1.0 / 60, 1.0 / 30, 0.1, 1, 2.5, 30, 1.0 / 333]
                let flPool: [Double] = [0, 12, 24, 35, 50.5, 85, 200, 600]
                let clipPool: [Double] = [0, 0.05, 0.25, 0.15, 1.95, 2, 2.05, 3.3, 12]
                let ev: Double? = rng.chance(0.2) ? nil : evPool.randomElement(using: &rng)
                let exposure: Double? = rng.chance(0.15) ? nil : expPool.randomElement(using: &rng)
                let focal: Double? = rng.chance(0.15) ? nil : flPool.randomElement(using: &rng)
                let divisor: Double = [1, 10, 3].randomElement(using: &rng)!
                let focus: Double = rng.chance(0.2) ? 100 : (rng.double() * 1000).rounded() / divisor
                let name = String(format: "DSC%05d.ARW", i)
                let path = paths.randomElement(using: &rng)! + "/" + String(format: "DSC%05d.ARW", rng.int(0...30))
                let date = dateString(clock, &rng)
                list.append(CullCoreShoot.Input(
                    name: name, path: path, date: date, exposure: exposure, focalLength: focal, exposureBias: ev,
                    luminance: rng.double(), focus: focus, clip: clipPool.randomElement(using: &rng)!
                ))
            }
            var cuts: [String: Bool] = [:]
            for _ in 0..<rng.int(0...3) { cuts["f\(rng.int(0...(count - 1)))"] = rng.chance(0.5) }

            let jsList: [[String: Any]] = list.map { p in
                var o: [String: Any] = ["name": p.name, "path": p.path, "lum": p.luminance, "focus": p.focus, "clip": p.clip]
                if let v = p.date { o["date"] = v }
                if let v = p.exposure { o["exp"] = v }
                if let v = p.focalLength { o["fl"] = v }
                if let v = p.exposureBias { o["ev"] = v }
                return o
            }
            let want = try callJSON("pShoot", [jsList, cuts])
            if !assertSame(project(CullCoreShoot.build(list, cuts: cuts)), want, "buildShoot trial \(trial)") { return }
        }
    }

    private func dateString(_ seconds: Double, _ rng: inout SplitMix64) -> String? {
        switch rng.int(0...40) {
        case 0: return nil
        case 1: return ""
        case 2: return "garbage"
        case 3: return "2026:13:40 25:61:61"
        case 4: return "0099:01:01 00:00:00"
        case 5: return "2026:00:00 00:00:00"
        default:
            let d = Date(timeIntervalSince1970: seconds.rounded(.down))
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
            return String(format: "%04d:%02d:%02d %02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
                + (rng.chance(0.1) ? ".123" : "")
        }
    }

    private func project(_ d: CullCoreShoot) -> [String: Any] {
        let id = { (n: Int) in d.photos[n].id }
        return [
            "photos": d.photos.map { p -> [String: Any] in
                ["id": p.id, "file": p.input.name, "mi": p.moment, "time": p.time, "hh": p.hour, "light": p.light.rawValue,
                 "sharp": p.sharp, "clip": p.clip, "blown": p.blown, "shake": p.shake, "start": p.start, "soft": p.soft,
                 "slight": p.slight, "bk": p.inBracket, "rank": p.rank, "bn": p.groupSize, "kind": p.kind.rawValue,
                 "gid": p.groupID, "ss": p.shutter, "fl": num(p.focalMM)]
            },
            "moments": d.moments.map { m -> [String: Any] in
                ["id": m.id, "time": m.time, "hh": m.hour, "light": m.light.rawValue, "groups": m.groups,
                 "subs": m.subs.map { ["id": $0.id, "kind": $0.kind.rawValue, "ids": $0.frames.map(id)] }]
            },
            "groups": d.groups.map { ["gid": $0.id, "kind": $0.kind.rawValue, "frames": $0.frames.map(id), "ranked": $0.ranked.map(id)] },
            "nodes": d.nodes.map { n -> [String: Any] in
                ["id": n.id, "type": n.level.rawValue, "mi": n.moment, "ids": n.ids, "kind": n.kind.map { $0.rawValue as Any } ?? NSNull()]
            },
            "sub": d.subOf, "keep": d.suggestedKeeps, "order": d.order,
        ]
    }

    // MARK: - parseHead

    func testParseHeadMatchesJavaScript() throws {
        var rng = SplitMix64(seed: 0xC011_0002)
        for trial in 0..<3000 {
            var bytes = syntheticTIFF(&rng)
            for _ in 0..<[0, 0, 1, 3, 8].randomElement(using: &rng)! where !bytes.isEmpty {
                bytes[rng.int(0...(bytes.count - 1))] = UInt8(rng.int(0...255))
            }
            if rng.chance(0.05) { bytes = (0..<rng.int(8...200)).map { _ in UInt8(rng.int(0...255)) } }
            let size = rng.chance(0.3) ? bytes.count : bytes.count + rng.int(-64...100_000)
            let want = try callJSON("pHead", [bytes.map(Int.init), size])
            let got: Any = CullCoreARWHeader.parse(bytes, fileSize: size).map { h in
                ["date": h.date as Any? ?? NSNull(), "exp": num(h.exposure), "fl": num(h.focalLength), "ev": num(h.exposureBias),
                 "iso": h.iso.map { $0 as Any } ?? NSNull(), "orient": h.orientation.map { $0 as Any } ?? NSNull(),
                 "preview": h.preview.map { [$0.offset, $0.length] as Any } ?? NSNull()] as [String: Any]
            } ?? NSNull()
            if !assertSame(got, want, "parseHead trial \(trial) bytes \(bytes.prefix(64))") { return }
        }
    }

    /// A small TIFF with the tags the parser reads, sub-IFDs, IFD chains and deliberate loops.
    private func syntheticTIFF(_ rng: inout SplitMix64) -> [UInt8] {
        let le = rng.chance(0.5)
        var b = [UInt8](repeating: 0, count: rng.int(64...1600))
        func put16(_ o: Int, _ v: Int) { guard o + 2 <= b.count else { return }
            let v = UInt16(truncatingIfNeeded: v); b[o] = UInt8(le ? v & 0xFF : v >> 8); b[o + 1] = UInt8(le ? v >> 8 : v & 0xFF) }
        func put32(_ o: Int, _ v: Int) { guard o + 4 <= b.count else { return }
            let v = UInt32(truncatingIfNeeded: v)
            for i in 0..<4 { b[o + i] = UInt8((v >> UInt32(le ? 8 * i : 8 * (3 - i))) & 0xFF) } }
        b[0] = le ? 0x49 : 0x4D; b[1] = b[0]; put16(2, 42)
        let ifdCount = rng.int(1...4)
        var ifds = (0..<ifdCount).map { _ in rng.int(8...max(8, b.count - 40)) & ~1 }
        put32(4, ifds[0])
        let tags = [0x0201, 0x0202, 0x8769, 0x9003, 0x829A, 0x920A, 0x9204, 0x8827, 0x0112, 0x0100]
        for (k, off) in ifds.enumerated() {
            let n = rng.int(0...8)
            put16(off, rng.chance(0.03) ? 2000 : n)
            for i in 0..<n {
                let e = off + 2 + i * 12, tag = tags.randomElement(using: &rng)!
                let type = [2, 3, 4, 5, 10].randomElement(using: &rng)!, count = [1, 1, 2, 4, 5, 20].randomElement(using: &rng)!
                put16(e, tag); put16(e + 2, type); put32(e + 4, count)
                let dataAt = rng.int(0...(b.count + 20))
                switch tag {
                case 0x8769: put32(e + 8, ifds.randomElement(using: &rng)!)
                case 0x9003:
                    put32(e + 8, dataAt)
                    for (j, c) in Array("2026:09:26 07:0\(rng.int(0...9)):00 \u{0}".utf8).enumerated() where dataAt + j < b.count { b[dataAt + j] = c }
                case 0x829A, 0x920A, 0x9204:
                    put32(e + 8, dataAt); put32(dataAt, rng.int(-5...600)); put32(dataAt + 4, [0, 1, 10, 500, -3].randomElement(using: &rng)!)
                default: put32(e + 8, rng.chance(0.5) ? rng.int(0...b.count) : rng.int(0...70_000))
                }
            }
            if rng.chance(0.3) { ifds[k] = rng.int(0...b.count) }
            put32(off + 2 + n * 12, k + 1 < ifds.count ? ifds[k + 1] : (rng.chance(0.2) ? ifds[0] : 0))
        }
        return b
    }

    // MARK: - XMP + export

    func testMergeXmpMatchesJavaScript() throws {
        var rng = SplitMix64(seed: 0xC011_0003)
        let merge = try XCTUnwrap(js.objectForKeyedSubscript("LuminaCore").objectForKeyedSubscript("mergeXmp"))
        for trial in 0..<3000 {
            let src = syntheticXMP(&rng), rating = rng.int(-1...5)
            // Lumina labels are the fixed Lightroom set; JS would read `$` in a label as a replacement pattern.
            let label = ["", "Green", "Red", "Yellow", "Blue", "Purple", "5", "12"].randomElement(using: &rng)!
            let want = try XCTUnwrap(merge.call(withArguments: [src, rating, label]).toString())
            if !assertSame(CullCoreXMP.merge(src, rating: rating, label: label), want, "mergeXmp trial \(trial) src \(src)") { return }
        }
    }

    private func syntheticXMP(_ rng: inout SplitMix64) -> String {
        let spaces = ["", " ", "  ", "\n", "\u{00A0}", "\u{2003}", "\u{3000}", "\u{FEFF}"]
        func sp(_ rng: inout SplitMix64) -> String { spaces.randomElement(using: &rng)! }
        var attrs = [" rdf:about=\"\""]
        if rng.chance(0.5) { attrs.append(" xmlns:xmp\(sp(&rng))=\(sp(&rng))\"http://ns.adobe.com/xap/1.0/\"") }
        if rng.chance(0.4) { attrs.append(" xmp:Rating\(sp(&rng))=\(sp(&rng))\"\(rng.int(-1...5))\"") }
        if rng.chance(0.3) { attrs.append(" xmp:Label=\"Red\"") }
        if rng.chance(0.3) { attrs.append(" xmlns:crs=\"http://ns.adobe.com/camera-raw-settings/1.0/\" crs:HasSettings=\"True\" crs:Exposure2012=\"+0.50\"") }
        attrs.shuffle(using: &rng)
        let tag = ["<rdf:Description", "<rdf:Description", "<rdf:DescriptionX", "<rdf:Description\n", "<rdf:Description\t", "<rdf:Description_", "<rdf:Description-"].randomElement(using: &rng)!
        var children = ""
        if rng.chance(0.3) { children += "<xmp:Rating>\(rng.int(0...5))</xmp:Rating>" }
        if rng.chance(0.2) { children += "<a-b:xmp:Label>Blue</a-b:xmp:Label>" }
        if rng.chance(0.1) { children += "<xmp:Rating/>" }
        if rng.chance(0.1) { children += "<xmp:Label>x<y</xmp:Label>" }
        let body = rng.chance(0.1) ? "<x:xmpmeta/>" : tag + attrs.joined() + (children.isEmpty && rng.chance(0.5) ? "/>" : ">" + children + "</rdf:Description>")
        let second = rng.chance(0.15) ? "<rdf:Description rdf:about=\"2\"/>" : ""
        return (rng.chance(0.3) ? "<?xpacket begin=\"\u{FEFF}\"?>" : "")
            + "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF>" + body + second + "</rdf:RDF></x:xmpmeta>"
    }

    func testFreshXmpMatchesJavaScript() throws {
        var rng = SplitMix64(seed: 0xC011_0004)
        let fresh = try XCTUnwrap(js.objectForKeyedSubscript("LuminaCore").objectForKeyedSubscript("freshXmp"))
        let pool: [Double] = [0, -0.0, 0.125, 0.005, 1.005, -0.005, 2.5, -2.5, 0.5, -0.5, 1.45, 10, -20, 99.995, 1e-7, -1e-7,
                              5600.5, -5600.5, 4999.499999, 0.49999999999999994, 1.335, -1.335, 123.456]
        for trial in 0..<3000 {
            func value(_ rng: inout SplitMix64) -> Double? {
                rng.chance(0.15) ? nil : rng.chance(0.6) ? pool.randomElement(using: &rng)! : (rng.double() - 0.5) * 200
            }
            let dev: CullCoreXMP.Develop? = rng.chance(0.2) ? nil : CullCoreXMP.Develop(
                exposure: value(&rng), contrast: value(&rng), highlights: value(&rng), shadows: value(&rng),
                temperature: rng.chance(0.5) ? value(&rng) : (rng.double() * 8000).rounded() / 2)
            var jsDev: Any = NSNull()
            if let dev {
                var o: [String: Any] = [:]
                o["Exposure"] = dev.exposure; o["Contrast"] = dev.contrast; o["Highlights"] = dev.highlights
                o["Shadows"] = dev.shadows; o["Temp"] = dev.temperature
                jsDev = o
            }
            let rating = rng.int(-1...5), label = ["", "Green", "Purple"].randomElement(using: &rng)!
            let want = try XCTUnwrap(fresh.call(withArguments: [rating, label, jsDev]).toString())
            if !assertSame(CullCoreXMP.fresh(rating: rating, label: label, develop: dev), want, "freshXmp trial \(trial) \(String(describing: dev))") { return }
        }
    }

    func testHasDevelopMatchesJavaScript() throws {
        var rng = SplitMix64(seed: 0xC011_0005)
        let has = try XCTUnwrap(js.objectForKeyedSubscript("LuminaCore").objectForKeyedSubscript("hasDevelop"))
        let parts = ["crs:HasSettings=\"True\"", "CRS:hassettings = \"TRUE\"", "crs:HasSettingſ=\"True\"", "crs:HasSettings=\"True\"".uppercased(),
                     "<crs:HasSettings>true<", "<crs:HasSettings>True</crs:HasSettings>", "crs:Exposure2012", "CRS:Exposure2012",
                     "crs:Tint", "xmp:Rating=\"3\"", "crs:HasSettings\u{3000}=\"True\"", "crs:HasSettings=\"False\"", "crs:Temperature",
                     "crs:HasSettings=\"\u{212A}\"", " ", "<x/>"]
        XCTAssertFalse(CullCoreXMP.hasDevelop(nil))
        for trial in 0..<2000 {
            let src = (0..<rng.int(0...3)).map { _ in parts.randomElement(using: &rng)! }.joined(separator: rng.chance(0.5) ? " " : "")
            let want = try XCTUnwrap(has.call(withArguments: [src])).toBool()
            if !assertSame(CullCoreXMP.hasDevelop(src), want, "hasDevelop trial \(trial) \(src)") { return }
        }
    }

    func testExportPlanMatchesJavaScript() throws {
        var rng = SplitMix64(seed: 0xC011_0006)
        let plan = try XCTUnwrap(js.objectForKeyedSubscript("LuminaCore").objectForKeyedSubscript("exportPlan"))
        let files = ["DSC01.ARW", "DSC01", "a.b/c", "x.tar.gz", ".hidden", "dir.x/file", "DSC.ARW\n", "ü.ARW", "trailing."]
        for trial in 0..<1000 {
            let target = CullCoreExportPlan.Target.allCases.randomElement(using: &rng)!
            let items = (0..<rng.int(0...4)).map { _ in
                CullCoreExportPlan.Item(file: files.randomElement(using: &rng)!, xmp: ["DSC01.xmp", "DSC01.XMP"].randomElement(using: &rng)!,
                                        rel: [nil, "", "sub/DSC01.xmp"].randomElement(using: &rng)!)
            }
            let jsItems: [[String: Any]] = items.map { it in
                var o: [String: Any] = ["file": it.file, "xmp": it.xmp]
                o["rel"] = it.rel
                return o
            }
            let shoot = ["Hudson Valley", "", "a/b"].randomElement(using: &rng)!
            let raw = try XCTUnwrap(plan.call(withArguments: [target.rawValue, shoot, jsItems]).toArray())
            let got = CullCoreExportPlan.plan(target, shoot: shoot, items: items).map { ["path": $0.path, "kind": $0.kind.rawValue] }
            if !assertSame(got, raw, "exportPlan trial \(trial) \(target)") { return }
        }
    }

    // MARK: - crc32, zip, measure

    func testCRC32AndZipMatchJavaScript() throws {
        var rng = SplitMix64(seed: 0xC011_0007)
        for trial in 0..<300 {
            let entries = (0..<rng.int(0...4)).map { i in
                CullCoreArchive.Entry(name: ["captions.txt", "Hudson Valley/JPEG/DSC0\(i).jpg", "ümlaut ✓.txt", ""].randomElement(using: &rng)!,
                                      data: Data((0..<rng.int(0...300)).map { _ in UInt8(rng.int(0...255)) }))
            }
            for e in entries {
                let want = try XCTUnwrap(try call("pCrc", [Array(e.data).map(Int.init)]) as? JSValue).toUInt32()
                XCTAssertEqual(CullCoreArchive.crc32(e.data), want, "crc32 trial \(trial)")
            }
            let want = try callJSON("pZip", [entries.map { ["name": $0.name, "data": Array($0.data).map(Int.init)] as [String: Any] }])
            if !assertSame(Array(CullCoreArchive.zip(entries)).map(Int.init), want, "zip trial \(trial)") { return }
        }
    }

    func testMeasureMatchesJavaScript() throws {
        var rng = SplitMix64(seed: 0xC011_0008)
        for trial in 0..<300 {
            let w = rng.int(1...24), h = rng.int(1...24)
            let px = (0..<(w * h * 4)).map { i in i % 4 == 3 ? 255 : (rng.chance(0.1) ? rng.int(248...255) : rng.int(0...255)) }
            let want = try callJSON("pMeasure", [px, w, h])
            let m = CullCoreMeasure.measure(rgba: px.map(UInt8.init), width: w, height: h)
            if !assertSame(["lum": num(m.luminance), "focus": num(m.focus), "clip": num(m.clip)], want, "measure trial \(trial) \(w)x\(h)") { return }
        }
    }
}

/// Deterministic generator so a parity failure reproduces from its trial number.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ r: ClosedRange<Int>) -> Int { Int.random(in: r, using: &self) }
    mutating func double() -> Double { Double.random(in: 0..<1, using: &self) }
    mutating func chance(_ p: Double) -> Bool { double() < p }
}
