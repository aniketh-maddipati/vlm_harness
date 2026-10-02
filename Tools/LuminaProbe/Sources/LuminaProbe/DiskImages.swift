import Foundation

/// Fault injection with throwaway disk images: a "card" that can be pulled mid-read, a destination
/// that fills up, a locked card. Everything lives under the scenario's output folder; a real card is
/// never touched. Images are detached when the run ends.
@MainActor
final class DiskImages {
    struct Image { let dmg: URL; var mount: URL; var device: String? }
    private(set) var images: [String: Image] = [:]
    private(set) var mounted: Set<String> = []
    let root: URL

    init(root: URL) { self.root = root }

    /// Creates an image of `sizeMB` (ExFAT, like a camera card), fills it from `from` (optionally
    /// trimming each ARW to `trimBytes` — header + embedded preview is all the page reads), attaches it.
    func create(name: String, sizeMB: Int, fs: String, from: URL?, trimBytes: Int?, repeatTo: Int?) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dmg = root.appendingPathComponent("\(name).dmg")
        try? FileManager.default.removeItem(at: dmg)
        try hdiutil(["create", "-size", "\(sizeMB)m", "-fs", fs, "-volname", name, dmg.path])
        let mount = try attach(name: name, dmg: dmg, readonly: false)
        if let from {
            let dcim = mount.appendingPathComponent("DCIM/100MSDCF")
            try FileManager.default.createDirectory(at: dcim, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "arw" && !$0.lastPathComponent.hasPrefix("._") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !files.isEmpty else { throw ProbeError("no ARWs in \(from.path)") }
            let total = repeatTo ?? files.count
            for i in 0..<total {
                let src = files[i % files.count]
                var data = try Data(contentsOf: src, options: .alwaysMapped)
                if let trimBytes, data.count > trimBytes { data = data.prefix(trimBytes) }
                try data.write(to: dcim.appendingPathComponent(String(format: "DSC%05d.ARW", i + 1)))
            }
            // A real card arrives with its files: eject and re-insert so the mount notice sees them.
            try detach(name: name)
            return try attach(name: name, dmg: dmg, readonly: false)
        }
        return mount
    }

    @discardableResult
    func attach(name: String, dmg: URL? = nil, readonly: Bool) throws -> URL {
        let image = dmg ?? images[name]?.dmg ?? root.appendingPathComponent("\(name).dmg")
        let mount = root.appendingPathComponent("vol/\(name)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        // Not -nobrowse: a hidden volume wouldn't raise the mount notice a real card does.
        var args = ["attach", image.path, "-mountpoint", mount.path, "-noverify", "-noautofsck"]
        if readonly { args.append("-readonly") }
        // Right after a forced detach the device can still be held: hdiutil answers "Resource busy",
        // and can leave the image attached without our mount point (the system then mounts it under
        // /Volumes, and every later attach is busy too). A re-inserted card lets go of that
        // half-attached image and tries again, for up to 15 s.
        var out = "", tries = 0
        while true {
            do { out = try hdiutil(args); break } catch {
                tries += 1
                guard "\(error)".contains("Resource busy"), tries < 30 else { throw error }
                if let held = attachedDevice(image) { _ = try? hdiutil(["detach", held, "-force"]) }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        let device = out.split(separator: "\n").first.map { String($0.split(separator: "\t").first ?? "").trimmingCharacters(in: .whitespaces) }
        images[name] = Image(dmg: image, mount: mount, device: device)
        mounted.insert(name)
        return mount
    }

    /// Yanks the image like a pulled card (force unmount).
    func detach(name: String) throws {
        guard let img = images[name] else { throw ProbeError("no image \(name)") }
        try hdiutil(["detach", img.device ?? img.mount.path, "-force"])
        mounted.remove(name)
        // The pull is over when the image is no longer attached (so a re-insert finds the device free).
        for _ in 0..<50 where attachedDevice(img.dmg) != nil { Thread.sleep(forTimeInterval: 0.1) }
    }

    /// Detaches every image. `removeImages`: also delete the .dmg files and their empty mount
    /// points. A passing run has no use for them and they are tens of megabytes each (a day of
    /// fault runs left 10 GB behind); a failing run keeps them for a look at what was on the card.
    func detachAll(removeImages: Bool = false) {
        for img in images.values {
            _ = try? hdiutil(["detach", img.device ?? img.mount.path, "-force"])
            // Attached under another device after a busy re-insert: never leave an image behind.
            if let held = attachedDevice(img.dmg) { _ = try? hdiutil(["detach", held, "-force"]) }
        }
        mounted.removeAll()
        guard removeImages else { return }
        // rmdir(2), never a recursive delete: if a detach failed the mount point still holds the
        // image's files, and those must not be walked.
        for img in images.values {
            try? FileManager.default.removeItem(at: img.dmg)          // a file
            rmdir(img.mount.path)
        }
        rmdir(root.appendingPathComponent("vol").path)
        rmdir(root.path)
    }

    /// The whole-disk device this image is attached as right now ("/dev/disk6"), if it is.
    private func attachedDevice(_ dmg: URL) -> String? {
        guard let text = try? hdiutil(["info", "-plist"]), let plist = try? PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: Any],
              let all = plist["images"] as? [[String: Any]] else { return nil }
        let want = dmg.resolvingSymlinksInPath().path
        for image in all where (image["image-path"] as? String).map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }) == want {
            let devs = (image["system-entities"] as? [[String: Any]] ?? []).compactMap { $0["dev-entry"] as? String }
            return devs.min { $0.count < $1.count }
        }
        return nil
    }

    @discardableResult
    private func hdiutil(_ args: [String]) throws -> String {
        // Sandboxed, hdiutil would inherit the probe's sandbox: the launcher runs it instead.
        if let r = ProbeSandbox.runTool("/usr/bin/hdiutil", args) {
            guard r.status == 0 else { throw ProbeError("hdiutil \(args.first ?? "") failed: \(r.err.trimmingCharacters(in: .whitespacesAndNewlines))") }
            return r.out
        }
        // Whatever ends the run (deadline, signal, a lost parent), this image is detached then.
        if args.first == "attach", args.count > 1 { ProbeGuard.noteImage(args[1]) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = args
        let pipe = Pipe(), err = Pipe()
        p.standardOutput = pipe; p.standardError = err
        try p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ProbeError("hdiutil \(args.first ?? "") failed: \(e.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return out
    }
}
