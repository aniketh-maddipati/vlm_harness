import Foundation

/// A probe run ends, and leaves nothing behind. It ends at its deadline, on a signal, when the
/// process that started it is gone, or normally; whichever it is, the disk images it attached are
/// detached and the workers it started are stopped. And only one probe owns the screen at a time:
/// the lock is the one Scripts/test_guard.py takes (~/LuminaEvidence/.screen.lock, flock, so a
/// dead holder never keeps it), taken here too so a script that calls the binary directly cannot
/// run two.
enum ProbeGuard {
    static let heldKey = "LUMINA_SCREEN_LOCK_HELD"
    private static let lock = NSLock(), ending = NSLock()
    private static var images: Set<String> = []
    private static var children: Set<pid_t> = []
    private static var sources: [DispatchSourceSignal] = []
    private static var parentTimer: DispatchSourceTimer?
    private static var screenFD: Int32 = -1

    /// Disk images show in Finder for a moment and beep when pulled: a scenario mounts one only
    /// when the run asked for that (LUMINA_DISK_IMAGES=1), and is skipped otherwise.
    static var diskImagesAllowed: Bool { ProcessInfo.processInfo.environment["LUMINA_DISK_IMAGES"] == "1" }

    static func noteImage(_ path: String) { lock.lock(); images.insert(real(path)); lock.unlock() }
    static func noteChild(_ pid: pid_t) { lock.lock(); children.insert(pid); lock.unlock() }
    static func forgetChild(_ pid: pid_t) { lock.lock(); children.remove(pid); lock.unlock() }

    /// The screen, or exit 75 with who has it. A child of a holder (the sandboxed probe, a run
    /// under test_guard.py) finds `heldKey` set and goes on.
    static func takeScreen(_ name: String) {
        guard ProcessInfo.processInfo.environment[heldKey] == nil else { return }
        let dir = ProcessInfo.processInfo.environment["LUMINA_GUARD_DIR"] ?? NSHomeDirectory() + "/LuminaEvidence"
        // The kill switch (Scripts/stop_tests.sh --off): nothing starts while it is there.
        if FileManager.default.fileExists(atPath: dir + "/.tests-off") {
            print("REFUSED  tests are switched off on this Mac (\(dir)/.tests-off). Only the user turns them back on: bash Scripts/stop_tests.sh --on")
            exit(75)
        }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/.screen.lock"
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { print("FAIL  cannot open \(path): \(String(cString: strerror(errno)))"); exit(2) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let who = FileManager.default.contents(atPath: path).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
            print("REFUSED  the screen is in use by another test run: \(who). One at a time; `bash Scripts/stop_tests.sh` stops it.")
            exit(75)
        }
        let record: [String: Any] = ["pid": Int(getpid()), "name": name, "since": DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium),
                                     "cwd": FileManager.default.currentDirectoryPath]
        if let data = try? JSONSerialization.data(withJSONObject: record) {
            ftruncate(fd, 0)
            _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        }
        screenFD = fd
        setenv(heldKey, "\(getpid())", 1)
    }

    /// Signals stop the run through `end`; so does losing the parent (a killed driver or a closed
    /// terminal must not leave a probe running on its own).
    static func install() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            s.setEventHandler { end(128 + sig, "stopped by signal \(sig)") }
            s.resume(); sources.append(s)
        }
        watchParent { end(4, "FAIL  the process that started this probe is gone: stopping") }
    }

    static func watchParent(_ gone: @escaping () -> Void) {
        let parent = getppid()
        guard parent > 1 else { return }
        let t = DispatchSource.makeTimerSource(queue: .global())
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { if getppid() != parent { gone() } }
        t.resume(); parentTimer = t
    }

    /// A wall-clock limit on `what`, enforced off the main thread (a wedged page cannot outlive it).
    /// Cancel the returned item when `what` is done.
    static func deadline(_ seconds: Double, _ what: String) -> DispatchWorkItem {
        let item = DispatchWorkItem {
            end(3, "FAIL  \(what) reached its limit of \(Int(seconds)) s (main thread wedged or scenario too slow): the run stops here")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
        return item
    }

    /// Stops the run from any thread: workers killed, images detached, then the process exits.
    static func end(_ code: Int32, _ message: String) -> Never {
        ending.lock()               // never unlocked: a second caller waits for the exit
        print(message)
        cleanup()
        fflush(stdout)
        _exit(code)
    }

    /// Before any exit: nothing of this run stays attached or running.
    static func cleanup() {
        lock.lock(); let kids = children; children = []; lock.unlock()
        kids.forEach { kill($0, SIGKILL) }
        detachLeftovers()
    }

    /// Force-detaches the images this process attached that are still attached (by image file,
    /// as hdiutil reports it: never by a mount point, so never a real volume).
    static func detachLeftovers() {
        lock.lock(); let mine = images; lock.unlock()
        guard !mine.isEmpty, let text = tool("/usr/bin/hdiutil", ["info", "-plist"]),
              let plist = try? PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: Any],
              let all = plist["images"] as? [[String: Any]] else { return }
        for image in all {
            guard let path = image["image-path"] as? String, mine.contains(real(path)) else { continue }
            let devs = (image["system-entities"] as? [[String: Any]] ?? []).compactMap { $0["dev-entry"] as? String }
            guard let dev = devs.min(by: { $0.count < $1.count }) else { continue }
            _ = tool("/usr/bin/hdiutil", ["detach", dev, "-force"])
            print("detached \(dev) (\(path))")
        }
    }

    private static func real(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }

    private static func tool(_ exe: String, _ args: [String], limit: Double = 20) -> String? {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit) { if p.isRunning { p.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
