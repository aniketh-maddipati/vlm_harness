import AppKit

let usage = """
lumina-probe — drive the Lumina page in WKWebView

  lumina-probe run <scenario.json>... [--out DIR] [--echo] [--deadline S] [--scenario-deadline S]
      Runs each scenario in a fresh window and web process. Exit 1 if any fails, 3 at a limit:
      600 s for the run (LUMINA_PROBE_DEADLINE), 180 s per scenario (LUMINA_SCENARIO_LIMIT, or the
      scenario's own "deadline"). 75 if another test run owns the screen. Scenarios that mount
      disk images are skipped unless LUMINA_DISK_IMAGES=1.
      Paths inside scenarios resolve against the current directory (run from the repo root).

  lumina-probe export-worker <plan.json>
      Runs one export with the app's own SetsExportJob + journal, then exits. The kill-mid-handoff
      step (killExport) starts it and SIGKILLs it part way.

  lumina-probe sandbox-launch <sandboxed lumina-probe> [--info FILE] -- run <scenario.json>... [--out DIR]
      Starts the sandboxed copy of the probe (Scripts/probe.sh sandbox builds and signs it) and stands
      in for the powerbox: hands it the folder grants it asks for. See Sandbox.swift.

  lumina-probe diff <a.png> <b.png> [--masks a.masks.json] [--scale 1] [--out diff.png]
      Exact pixel diff, photo rects masked. Exit 1 on any differing pixel.
"""

ProbeSandbox.begin()        // sandboxed (Sandbox.swift): back to the checkout, or stop
var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i); return true
}

guard let command = args.first else { print(usage); exit(2) }
args.removeFirst()

switch command {
case "sandbox-launch":
    let info = option("--info")
    guard let exe = args.first, args.count > 2, args[1] == "--" else { print(usage); exit(2) }
    SandboxLauncher.run(exe: exe, info: info, args: Array(args.dropFirst(2)))

case "export-worker":
    ProbeSandbox.adopt()        // sandboxed: the destination and sources the parent was granted
    guard let path = args.first, let data = FileManager.default.contents(atPath: path),
          let plan = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let dest = plan["destination"] as? String, let jdir = plan["journalDir"] as? String,
          let items = plan["items"] as? [[String: String]] else { print("bad plan"); exit(2) }
    let job = SetsExportJob(label: plan["label"] as? String ?? "lr", destination: URL(fileURLWithPath: dest), items: items.compactMap { i in
        guard let name = i["name"] else { return nil }
        if let src = i["copy"] { return .copy(name: name, source: URL(fileURLWithPath: src)) }
        return .bytes(name: name, data: Data((i["text"] ?? "").utf8))
    })
    let r = job.run(journal: SetsExportJournal(directory: URL(fileURLWithPath: jdir)))
    print("\(r.n) written, \(r.bak) bak, \(r.failed.count) failed")
    exit(r.failed.isEmpty ? 0 : 1)

case "diff":
    let masksPath = option("--masks"), scale = Double(option("--scale") ?? "1") ?? 1, out = option("--out")
    guard args.count == 2 else { print(usage); exit(2) }
    do {
        let a = try Pixels.readPNG(URL(fileURLWithPath: args[0])), b = try Pixels.readPNG(URL(fileURLWithPath: args[1]))
        let masks = try masksPath.map { try JSONDecoder().decode([Pixels.Rect].self, from: Data(contentsOf: URL(fileURLWithPath: $0))) } ?? []
        let r = Pixels.diff(a, b, masks: masks, scale: scale, heatmap: out.map { URL(fileURLWithPath: $0) })
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
        print(String(data: try enc.encode(r), encoding: .utf8)!)
        exit(r.differing == 0 ? 0 : 1)
    } catch { print("error: \(error)"); exit(2) }

case "run":
    let outRoot = URL(fileURLWithPath: option("--out") ?? "artifacts/probe/latest")
    let echo = flag("--echo")
    let requireAll = flag("--require-all")      // a SKIP fails the run (CI with fixtures present)
    // Hard ceilings, enforced off the main thread (Guard.swift): the whole run, and each scenario
    // (its own "deadline" when the scenario is known to need longer). A run that reaches one
    // fails, detaches its images and exits; it never waits on.
    let env = ProcessInfo.processInfo.environment
    let deadline = Double(option("--deadline") ?? env["LUMINA_PROBE_DEADLINE"] ?? "") ?? 600
    let scenarioLimit = Double(option("--scenario-deadline") ?? env["LUMINA_SCENARIO_LIMIT"] ?? "") ?? 180
    let scenarios = args.map { URL(fileURLWithPath: $0) }
    guard !scenarios.isEmpty else { print(usage); exit(2) }
    ProbeGuard.takeScreen("lumina-probe run \(scenarios.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: " "))")
    ProbeGuard.install()
    _ = ProbeGuard.deadline(deadline, "the run")
    ProbeSandbox.start(outRoot: outRoot)

    // The probe is an invisible background app. Without this, App Nap throttles its timers, and once
    // the display idles WebKit throttles the page process: a 500 ms wait stretched to 4 minutes.
    let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                                                         reason: "lumina-probe run")
    _ = activity
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)          // no Dock icon, never takes focus from the user
    Task { @MainActor in
        var allPass = true
        var skips: [String] = []
        for s in scenarios {
            let out = outRoot.appendingPathComponent(s.deletingPathExtension().lastPathComponent)
            ProbeSandbox.harness { try? FileManager.default.removeItem(at: out) }
            do {
                let runner = try Runner(scenario: s, outDir: out)
                let limit = ProbeGuard.deadline(max(scenarioLimit, runner.spec["deadline"] as? Double ?? 0), s.deletingPathExtension().lastPathComponent)
                let pass = await runner.run(echo: echo)
                limit.cancel()
                if let why = runner.skipped { skips.append("\(s.lastPathComponent): \(why)") }
                allPass = allPass && pass
            } catch {
                print("FAIL  \(s.lastPathComponent): \(error)"); allPass = false
            }
        }
        if !skips.isEmpty {
            print("\n\(skips.count) SKIPPED — not tested:")
            skips.forEach { print("   \($0)") }
            if requireAll { allPass = false }
        }
        ProbeGuard.cleanup()
        exit(allPass ? 0 : 1)
    }
    app.run()

default:
    print(usage); exit(2)
}
