import Foundation

// The probe inside the App Sandbox (`bash Scripts/probe.sh sandbox <mode>`, release task R1a).
//
// What runs: this same executable, copied into a minimal LuminaProbe.app (a sandboxed process
// needs a bundle id) and signed ad hoc with Config/Lumina-Sets.entitlements, the file the app
// ships with. Nothing is added to those entitlements: no temporary exceptions, no home-relative
// paths. So the bridge (Lumina/Sets/Core, compiled in) meets the sandbox the app will meet.
//
// The problem that leaves: the harness itself needs files outside the container (the checkout,
// the fixtures in ~/LuminaEvidence, the evidence folder), and the app gets its folders from
// NSOpenPanel, which the probe scripts instead of showing. Both are solved the way macOS solves
// them, with sandbox extensions. An unsandboxed launcher (`lumina-probe sandbox-launch`, the
// parent of the sandboxed probe) plays the part of the powerbox: over an inherited socket it
// issues an extension token for a path (`sandbox_extension_issue_file`, the call behind
// NSOpenPanel's grant), and the sandboxed probe consumes it. Three kinds of grant, kept apart so
// the app code never holds more than the app would:
//
//   bundle    read-only on the checkout, for the whole run. Stands in for the app bundle: the
//             page, plumbing.js, rules-v1.json and the scenario files are read from there.
//   picked    read-write on one folder, from the moment the scripted chooser "picks" it (an open
//             panel or a destination panel) until the next relaunch. `reload` is the scenarios'
//             relaunch, and a new process has no grants: what must survive is the app's bookmark.
//             `nativeOpen` (bridge.open: the card flow, a reopen) gets no grant, as in the app.
//   harness   read-write on the evidence folder and read-only on the fixture folders, held only
//             while the harness itself touches files (copyTree, writeFile, fs, snap, the report)
//             and released straight after. The shoot a scenario opens lives under ${OUT}; a
//             standing grant there would hide every denial this mode exists to find. Extensions
//             are per process, so app code running on another thread during those few
//             milliseconds could slip through; the steps are sequential and it has not mattered.
//
// A real relaunch, where one is needed: a child this process spawns shares its sandbox (and the
// grants consumed in it), so the export worker's destination grant stays visible here. The journal
// recovery of a "next launch" therefore runs in a fresh process the launcher starts
// (`launchFresh` → `recover-journal`), holding only the journal folder.
//
// The app's support folder (sessions, Lumina.json, the export journal) is inside the container,
// as it is for the app; scenario paths under ${OUT}/support are redirected there, and the folder
// is copied into the evidence when the scenario ends.
//
// Denials. On macOS 26.5 the kernel does not log App Sandbox file denials: a refused open(2)
// returns EPERM and nothing reaches `log show` (measured with a 30-line tool under the same
// entitlements; other processes' `Sandbox: … deny(1)` lines are visible, an app sandbox's are
// not). So the probe asks itself, after every step, for each path the app needs at that point
// (the folder the bridge has open, the card volume, the support folder): does open(2) /
// access(2) fail with EPERM? Those are real attempts by this process, answered by the kernel.
// It also keeps what the bridge reported ("access denied …"). probe.sh still reads the log for
// the pid: any `Sandbox: … deny` line, "Sandbox is preventing …", and WebKit helpers that crash or
// cannot start. (Signed without network.client, the probe logs "Application does not have
// permission to communicate with network resources", the web process fails to launch, the GPU
// process exits with reason=Crash, and the page never loads; with it, none of that.)

@_silgen_name("sandbox_extension_issue_file")
private func sandbox_extension_issue_file(_ cls: UnsafePointer<CChar>, _ path: UnsafePointer<CChar>, _ flags: UInt32) -> UnsafeMutablePointer<CChar>?
@_silgen_name("sandbox_extension_consume")
private func sandbox_extension_consume(_ token: UnsafePointer<CChar>) -> Int64
@_silgen_name("sandbox_extension_release")
private func sandbox_extension_release(_ handle: Int64) -> Int32

/// The sandboxed probe's side. Every call is a no-op when the probe was not started by
/// `sandbox-launch`, so the ordinary probe runs exactly as before.
enum ProbeSandbox {
    static let envBroker = "LUMINA_PROBE_BROKER", envTokens = "LUMINA_PROBE_TOKENS"
    private static let brokerFD = ProcessInfo.processInfo.environment[envBroker].flatMap { Int32($0) }
    static var active: Bool { brokerFD != nil }
    /// The process really is in an App Sandbox container (set by the system, not by us).
    static var contained: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }

    struct Denial: Encodable, Hashable { let step: Int; let op: String; let role: String; let path: String; let operation: String; let detail: String }

    private static let lock = NSRecursiveLock()
    private static var harnessRoots: [(path: String, write: Bool)] = []
    private static var harnessHandles: [Int64] = []
    private static var harnessDepth = 0
    private static var picked: [String: Int64] = [:]

    // MARK: Broker

    private static func ask(_ request: [String: Any]) -> [String: Any] {
        guard let fd = brokerFD, var data = try? JSONSerialization.data(withJSONObject: request) else { return [:] }
        lock.lock(); defer { lock.unlock() }
        data.append(0x0A)
        let sent = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent == data.count else { return [:] }
        var line = Data(), byte: UInt8 = 0
        while read(fd, &byte, 1) == 1, byte != 0x0A { line.append(byte) }
        return (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
    }

    private static func consume(_ path: String, write: Bool, why: String) -> Int64? {
        guard let token = ask(["op": "grant", "path": path, "write": write, "why": why])["token"] as? String else { return nil }
        let handle = sandbox_extension_consume(token)
        return handle > 0 ? handle : nil
    }

    /// A tool the sandbox would not let this process run usefully (hdiutil, exiftool): the
    /// launcher runs it. Nil when the probe is not sandboxed (the caller runs it itself).
    static func runTool(_ exe: String, _ args: [String]) -> (status: Int32, out: String, err: String)? {
        guard active else { return nil }
        let r = askServicingMainRunLoop(["op": "run", "exe": exe, "args": args])
        return (Int32(r["status"] as? Int ?? -1), r["out"] as? String ?? "", r["err"] as? String ?? "broker gave no answer")
    }

    /// `ask`, but on the main thread the run loop keeps turning while the launcher works, as it
    /// does in `Process.waitUntilExit` (the unsandboxed probe's way to run hdiutil). Measured: a
    /// `hdiutil detach -force` the launcher ran while the main thread sat in read(2) took 10.4 s
    /// instead of under 2 (Disk Arbitration waits for this process's answer to the unmount until it
    /// times out), and the bridge saw the card go only then, so a pull mid-read came too late.
    /// Not while harness grants are held: the run loop would run app code (the card watcher's
    /// mount notice) under them, and the app would see a card it may not read yet as readable.
    private static func askServicingMainRunLoop(_ request: [String: Any]) -> [String: Any] {
        lock.lock(); let harnessHeld = harnessDepth > 0; lock.unlock()
        guard Thread.isMainThread, !harnessHeld else { return ask(request) }
        final class Box: @unchecked Sendable { var answer: [String: Any]?; let lock = NSLock() }
        let box = Box()
        let payload = (try? JSONSerialization.data(withJSONObject: request)) ?? Data()
        Thread.detachNewThread {
            let req = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
            let a = ask(req)
            box.lock.lock(); box.answer = a; box.lock.unlock()
        }
        while true {
            box.lock.lock(); let a = box.answer; box.lock.unlock()
            if let a { return a }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: Grants

    static let envDirectory = "LUMINA_PROBE_CWD"

    /// First thing in main, before any relative path is resolved. Refuses to go on if the launcher
    /// asked for a sandbox and the system did not apply one: a "sandbox" run that is not sandboxed
    /// proves nothing. The sandbox starts a process in its container; scenarios name their files
    /// relative to the checkout, so the probe goes back there (with the bundle grant to read it).
    static func begin() {
        guard active else { return }
        guard contained else { print("FAIL  sandbox: started by sandbox-launch, but this process has no App Sandbox container"); exit(2) }
        guard let dir = ProcessInfo.processInfo.environment[envDirectory], consume(dir, write: false, why: "bundle") != nil, chdir(dir) == 0 else {
            print("FAIL  sandbox: no grant for the checkout, or cannot work from it"); exit(2)
        }
    }

    /// Before the first scenario: which folders the harness may open for itself.
    static func start(outRoot: URL) {
        guard active else { return }
        harnessRoots = [(outRoot.path, true)]
        for name in ["LUMINA_FIXTURE_ROOT", "LUMINA_CARD_DIR", "LUMINA_SCROLL_DIR", "LUMINA_EDIT_DIR", "LUMINA_READ_DIR"] {
            if let p = ProcessInfo.processInfo.environment[name], !p.isEmpty { harnessRoots.append((p, false)) }
        }
    }

    private static func enter() {
        lock.lock(); defer { lock.unlock() }
        harnessDepth += 1
        guard harnessDepth == 1 else { return }
        harnessHandles = harnessRoots.compactMap { consume($0.path, write: $0.write, why: "harness") }
    }

    private static func leave() {
        lock.lock(); defer { lock.unlock() }
        harnessDepth -= 1
        guard harnessDepth == 0 else { return }
        harnessHandles.forEach { _ = sandbox_extension_release($0) }
        harnessHandles = []
    }

    /// The harness touching its own files (never app code): its grants are held for `body` only.
    static func harness<T>(_ body: () throws -> T) rethrows -> T {
        guard active else { return try body() }
        enter(); defer { leave() }
        return try body()
    }

    static func harnessAsync<T>(_ body: () async throws -> T) async rethrows -> T {
        guard active else { return try await body() }
        enter(); defer { leave() }
        return try await body()
    }

    /// The user picked this folder in a panel: read-write until the next relaunch, as NSOpenPanel
    /// gives with `com.apple.security.files.user-selected.read-write`.
    static func userPicked(_ url: URL) {
        guard active else { return }
        lock.lock(); defer { lock.unlock() }
        let path = url.standardizedFileURL.path
        guard picked[path] == nil, let h = consume(path, write: true, why: "picked") else { return }
        picked[path] = h
    }

    /// A relaunch: the grants the panels gave the last process are gone. Returns, for the log,
    /// each dropped folder and whether this process can still read it (it should not: a reopen
    /// that works after this went through the app's bookmark).
    @discardableResult
    static func relaunch() -> [String] {
        guard active else { return [] }
        lock.lock(); defer { lock.unlock() }
        picked.values.forEach { _ = sandbox_extension_release($0) }
        defer { picked = [:] }
        return picked.keys.sorted().map { "\($0): " + (refused($0, write: false).isEmpty ? "still readable" : "now refused") }
    }

    /// Tokens for a child that is sandboxed in its own right (the export worker): it consumes
    /// them at start (`adopt`), the way an app passes a grant to its helper.
    static func tokens(for paths: [(URL, Bool)]) -> String? {
        guard active else { return nil }
        let all = paths.compactMap { ask(["op": "grant", "path": $0.0.path, "write": $0.1, "why": "picked (worker)"])["token"] as? String }
        return (try? JSONSerialization.data(withJSONObject: all)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// A fresh sandboxed process, as the app's next launch: the launcher starts another
    /// `lumina-probe sandbox-launch` of this same bundle with `args`. That process holds none of
    /// this one's grants (extensions are per process), so whatever this run was given (the export
    /// worker's destination) is out of its reach unless the app kept a bookmark. A child spawned
    /// by this process would share its sandbox instead. Nil when not sandboxed.
    static func launchFresh(_ args: [String], info: String? = nil) -> (status: Int32, out: String, err: String)? {
        guard active else { return nil }
        var req: [String: Any] = ["op": "launch", "args": args]
        if let info { req["info"] = info }
        let r = ask(req)
        return (Int32(r["status"] as? Int ?? -1), r["out"] as? String ?? "", r["err"] as? String ?? "broker gave no answer")
    }

    /// One grant held for the rest of this process (a fresh process's stand-in for a folder that
    /// is inside the app's container in the real app). False when the launcher issued none.
    @discardableResult
    static func hold(_ url: URL, write: Bool, why: String) -> Bool {
        guard active else { return true }
        return consume(url.path, write: write, why: why) != nil
    }

    static func adopt() {
        guard let text = ProcessInfo.processInfo.environment[envTokens], let list = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String] else { return }
        list.forEach { _ = sandbox_extension_consume($0) }
    }

    // MARK: Places and checks

    /// A folder inside the container, where the app keeps its own files.
    static func container(_ sub: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LuminaProbe/\(sub)", isDirectory: true)
    }

    /// The operations the sandbox refuses on `path` right now: real open(2) / access(2) calls
    /// by this process. EPERM is the sandbox's answer; a missing file or a permission bit is not.
    static func refused(_ path: String, write: Bool) -> [(operation: String, detail: String)] {
        guard active else { return [] }
        var out: [(String, String)] = []
        let fd = open(path, O_RDONLY)
        if fd >= 0 { close(fd) } else if errno == EPERM { out.append(("file-read-data", "open(O_RDONLY): Operation not permitted")) }
        if write, access(path, W_OK) != 0, errno == EPERM { out.append(("file-write-data", "access(W_OK): Operation not permitted")) }
        return out
    }
}

/// The launcher: not sandboxed, the parent of the sandboxed probe. It issues the extension
/// tokens the probe asks for (and logs each one), runs hdiutil / exiftool for it, waits, and
/// writes what happened to `--info` for probe.sh: pid, start, end, exit, grants.
enum SandboxLauncher {
    private static let tools: Set<String> = ["/usr/bin/hdiutil", "/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"]
    /// What `ProbeSandbox.launchFresh` may start (main.swift).
    private static let freshCommands: Set<String> = ["recover-journal"]

    static func run(exe: String, info: String?, args: [String]) -> Never {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else { print("sandbox-launch: socketpair failed"); exit(2) }
        _ = fcntl(fds[0], F_SETFD, FD_CLOEXEC)
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addinherit_np(&actions, fds[1])
        ProbeGuard.takeScreen("lumina-probe sandbox-launch")      // the sandboxed probe cannot reach the lock file
        var env = ProcessInfo.processInfo.environment
        env[ProbeGuard.heldKey] = env[ProbeGuard.heldKey] ?? "\(getpid())"
        env[ProbeSandbox.envBroker] = "\(fds[1])"
        env[ProbeSandbox.envDirectory] = FileManager.default.currentDirectoryPath
        let cArgs = ([exe] + args).map { strdup($0) } + [nil]
        let cEnv = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        var pid: pid_t = 0
        let started = Date()
        let rc = posix_spawn(&pid, exe, &actions, nil, cArgs, cEnv)
        guard rc == 0 else { print("sandbox-launch: cannot start \(exe): \(String(cString: strerror(rc)))"); exit(2) }
        close(fds[1])
        // A stopped run (Ctrl-C, a timeout in probe.sh) takes the sandboxed probe with it.
        var sources: [DispatchSourceSignal] = []
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            s.setEventHandler { kill(pid, SIGKILL) }
            s.resume(); sources.append(s)
        }
        ProbeGuard.watchParent { kill(pid, SIGKILL) }             // so does a driver that is gone
        var grants: [[String: Any]] = []
        let lock = NSLock()
        let broker = Thread {
            let fd = fds[0]
            var line = Data(), byte: UInt8 = 0
            while read(fd, &byte, 1) == 1 {
                if byte != 0x0A { line.append(byte); continue }
                let req = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
                line = Data()
                var answer: [String: Any] = [:]
                switch req["op"] as? String {
                case "grant":
                    let path = real(req["path"] as? String ?? ""), write = req["write"] as? Bool ?? false
                    if let t = sandbox_extension_issue_file(write ? "com.apple.app-sandbox.read-write" : "com.apple.app-sandbox.read", path, 0) {
                        answer["token"] = String(cString: t); free(t)
                    }
                    lock.lock()
                    grants.append(["t": Date().timeIntervalSince(started), "path": path, "write": write, "why": req["why"] as? String ?? "", "issued": answer["token"] != nil])
                    lock.unlock()
                case "run":
                    if let tool = req["exe"] as? String, tools.contains(tool) {
                        let p = Process(), out = Pipe(), err = Pipe()
                        p.executableURL = URL(fileURLWithPath: tool); p.arguments = req["args"] as? [String] ?? []
                        if tool.hasSuffix("/hdiutil"), let a = p.arguments, a.first == "attach", a.count > 1 { ProbeGuard.noteImage(a[1]) }
                        p.standardOutput = out; p.standardError = err
                        do {
                            try p.run()
                            let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
                            p.waitUntilExit()
                            answer = ["status": Int(p.terminationStatus), "out": String(data: o, encoding: .utf8) ?? "", "err": String(data: e, encoding: .utf8) ?? ""]
                        } catch { answer = ["status": -1, "err": "\(error)"] }
                    } else { answer = ["status": -1, "err": "not a tool the launcher runs"] }
                case "launch":
                    // A fresh sandboxed process of the same bundle, through this same launcher
                    // (unsandboxed, so the child gets a sandbox of its own and none of the
                    // asker's grants). Only the probe's own one-shot commands.
                    let sub = req["args"] as? [String] ?? []
                    if let first = sub.first, freshCommands.contains(first), let me = Bundle.main.executableURL {
                        let p = Process(), out = Pipe(), err = Pipe()
                        p.executableURL = me
                        p.arguments = ["sandbox-launch", exe] + ((req["info"] as? String).map { ["--info", $0] } ?? []) + ["--"] + sub
                        p.standardOutput = out; p.standardError = err
                        do {
                            try p.run()
                            let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
                            p.waitUntilExit()
                            answer = ["status": Int(p.terminationStatus), "out": String(data: o, encoding: .utf8) ?? "", "err": String(data: e, encoding: .utf8) ?? ""]
                        } catch { answer = ["status": -1, "err": "\(error)"] }
                    } else { answer = ["status": -1, "err": "not a command the launcher starts fresh"] }
                    lock.lock()
                    grants.append(["t": Date().timeIntervalSince(started), "launch": sub, "status": answer["status"] ?? -1])
                    lock.unlock()
                default: break
                }
                var data = (try? JSONSerialization.data(withJSONObject: answer)) ?? Data("{}".utf8)
                data.append(0x0A)
                _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            }
        }
        broker.start()
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
        let signalled = (status & 0x7f) != 0, code = signalled ? 128 + (status & 0x7f) : (status >> 8) & 0xff
        ProbeGuard.detachLeftovers()        // a probe that was killed could not detach its own images
        if let info {
            lock.lock()
            let record: [String: Any] = ["pid": Int(pid), "exe": exe, "start": started.timeIntervalSince1970, "end": Date().timeIntervalSince1970,
                                         "exit": Int(code), "signal": signalled ? Int(status & 0x7f) : 0, "grants": grants]
            lock.unlock()
            let url = URL(fileURLWithPath: info)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        }
        exit(code)
    }

    /// The real path (extensions are matched on it): symlinks resolved for the part that exists.
    private static func real(_ path: String) -> String {
        var url = URL(fileURLWithPath: path).standardizedFileURL, tail: [String] = []
        while url.path != "/" {
            if let r = realpath(url.path, nil) {
                defer { free(r) }
                return tail.reversed().reduce(URL(fileURLWithPath: String(cString: r))) { $0.appendingPathComponent($1) }.path
            }
            tail.append(url.lastPathComponent); url.deleteLastPathComponent()
        }
        return path
    }
}
