#if !LUMINA_SHIPPING_APP
import AppKit
import Foundation
import SwiftUI

/// Scroll latency on the time table — `--p0-scroll-live [output-dir] [--p0-open <FOLDER>]`.
///
/// Opens a shoot, mounts the Elastic shell in a real window on the time route,
/// drives the table's scroll view through three passes and reports, per pass,
/// what the main thread paid per scroll step and whether any realized tile had
/// nothing resident to draw. Same shape as `P0EditLiveRunner`'s `rapidScrub` —
/// p50/p95/p99 with the window they cover, plus a `blankSeen` flag — so runs
/// compare across commits.
///
/// Five passes, by distance rather than by time so a taller card does not
/// change what "a flick" means:
/// - `glide`  — 1 screen/s for 5 screens: reading pace.
/// - `flick`  — 6 screens/s to the bottom: the case that outruns decode.
/// - `return` — 6 screens/s back to the top: what was behind the cursor is
///   now ahead of it.
/// - `dart` / `recoil` — 6 screens/s for 4 screens and straight back: the
///   reversal, where prefetch issued ahead of the dart must be cancelled.
///
/// Two numbers per pass, deliberately different instruments:
/// - `p0.scroll.tick_ms.<pass>` — wall time of one scroll step on the main
///   thread: the offset change, SwiftUI's layout pass, and the AppKit display
///   pass. A decode reached synchronously from a tile's `body` lands here.
/// - `p0.scroll.frame` — the display link's interval between presented frames
///   while scrolling (`P0RenderInstruments`). A dropped frame the layout timer
///   cannot see shows up here.
///
/// A well is a realized tile with nothing resident at the grid tier at the
/// moment the step finished. `blankSeen` is true when any step saw one.
///
/// Measure warm: the first open of a fresh card reports `previews 0/N` while
/// extraction runs. The report says which it was (`coldExtraction`).
@MainActor
enum P0ScrollLiveRunner {
    static let launchFlag = "--p0-scroll-live"

    /// Steps per second the runner attempts. 120 Hz is the display the frame
    /// budget is stated against.
    private static let tickHz: Double = 120

    /// `LUMINA_SCROLL_FILM=1` writes a PNG of the window after every step of
    /// every pass, for stitching into a recording at the tick rate the run
    /// actually achieved. A step that saw a well is written twice, the second
    /// copy suffixed `-well`, so the frames that matter can be found without
    /// scrubbing. Capturing costs main-thread time, so a filmed run's numbers
    /// are not a baseline — the report says `filmed: true`.
    private static var filming: Bool {
        ProcessInfo.processInfo.environment["LUMINA_SCROLL_FILM"] == "1"
    }

    private struct Pass {
        let name: String
        let screensPerSecond: Double
        /// Screens to travel; nil means to the end, in the sign of the velocity.
        let screens: Double?
    }

    private static let passes: [Pass] = [
        Pass(name: "glide", screensPerSecond: 1, screens: 5),
        Pass(name: "flick", screensPerSecond: 6, screens: nil),
        Pass(name: "return", screensPerSecond: -6, screens: nil),
        // A flick that stops mid-shoot with prefetch still in flight ahead of
        // it, then an immediate reversal: what was ahead is now behind and
        // must be cancelled, and what is behind is already resident.
        Pass(name: "dart", screensPerSecond: 6, screens: 4),
        Pass(name: "recoil", screensPerSecond: -6, screens: 4),
    ]

    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains(launchFlag) else { return false }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)

        let outDir: URL
        if let idx = args.firstIndex(of: launchFlag),
           args.indices.contains(idx + 1), !args[idx + 1].hasPrefix("-") {
            outDir = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        } else {
            outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("artifacts/p0-scroll-live", isDirectory: true)
        }

        let openFolder: URL?
        if let idx = args.firstIndex(of: "--p0-open"),
           args.indices.contains(idx + 1) {
            openFolder = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        } else {
            openFolder = DevelopLabFixtures.resolveRawDirectory()
        }

        var finished = false
        var exitCode: Int32 = 1
        Task { @MainActor in
            exitCode = await run(outDir: outDir, folder: openFolder)
            finished = true
        }
        while !finished {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        exit(exitCode)
    }

    private static func run(outDir: URL, folder: URL?) async -> Int32 {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var report: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "checkpoint": "p2-scroll-latency-live",
            "tickHz": tickHz,
            "filmed": filming,
        ]
        var failures = 0
        var checks: [[String: Any]] = []

        func note(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            checks.append(["name": name, "ok": ok, "detail": detail])
            fputs("\(ok ? "PASS" : "FAIL"): \(name)\(detail.isEmpty ? "" : " — \(detail)")\n", stderr)
        }

        guard let folder, FileManager.default.fileExists(atPath: folder.path) else {
            report["status"] = "blocked"
            report["reason"] = "no shoot folder"
            write(report, to: outDir)
            return 1
        }
        report["fixtureDir"] = folder.path

        let session = P0SessionModel()
        // Match on the folder, never on its name: every generated card keeps
        // its frames in a directory called `frames`, and a name match would
        // reopen whichever card was cut first. A fresh open names the catalog
        // after the card so the next run finds it here.
        let shootName = catalogName(for: folder)
        report["shootName"] = shootName
        if let recent = (try? ShootStore.listRecentShoots())?.first(where: {
            $0.rawFolderPath == folder.path
        }) {
            session.openRecent(recent)
            report["openMode"] = "recent:\(recent.name)"
        } else {
            session.openFolder(folder, shootName: shootName)
            report["openMode"] = "folder"
        }

        // Cold or warm is a fact about this run, not a setting: watch for the
        // extraction phase rather than trusting the second open to be warm.
        //
        // A reopen replays the dates phase and then replaces `assets` wholesale,
        // which rebuilds the whole table. Measuring through that would charge
        // the open to scroll, so readiness also waits for that phase to have
        // been seen and for the status to hold still afterwards.
        let openedAt = CFAbsoluteTimeGetCurrent()
        var sawExtraction = false
        var sawDates = false
        var lastStatus = session.status
        var stableSince = CFAbsoluteTimeGetCurrent()
        let ready = await waitUntil(timeout: 600) {
            // A reopen also runs the preview phase, to fill what is missing;
            // cold means it actually had frames without a preview.
            if session.status.isPreparingPreviews,
               session.status.previewReadyCount < session.status.assetCount {
                sawExtraction = true
            }
            if session.status.isPreparingMetadata { sawDates = true }
            if session.status != lastStatus {
                lastStatus = session.status
                stableSince = CFAbsoluteTimeGetCurrent()
            }
            let settled = CFAbsoluteTimeGetCurrent() - stableSince >= 1.5
            let datesDone = sawDates || CFAbsoluteTimeGetCurrent() - openedAt > 20
            return session.assets.count >= 8
                && !session.status.isPreparingPreviews
                && !session.status.isPreparingMetadata
                && datesDone
                && settled
        }
        report["sawDatesPhase"] = sawDates
        let assetCount = session.assets.count
        report["assetCount"] = assetCount
        report["statusLine"] = session.preparationLine
        report["coldExtraction"] = sawExtraction
        report["secondsToReady"] = CFAbsoluteTimeGetCurrent() - openedAt
        report["openError"] = session.userFacingError ?? ""
        note(
            "Open shoot with previews ready",
            ready && assetCount >= 8,
            "\(assetCount) assets · \(session.preparationLine) · \(sawExtraction ? "cold" : "warm")"
        )
        guard ready, assetCount >= 8 else {
            report["status"] = "failed"
            report["reason"] = "shoot did not become ready"
            report["checks"] = checks
            write(report, to: outDir)
            return 1
        }

        // The same window a person scrolls: the shell on the time route.
        session.route = .time
        let size = CGSize(width: 1280, height: 800)
        let hosting = NSHostingView(
            rootView: ElasticRootView(session: session)
                .frame(width: size.width, height: size.height)
                .luminaWorkspaceAppearance()
        )
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(size)
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()

        P0RenderInstruments.shared.enable()
        P0RenderInstruments.shared.attach(to: hosting)
        // Let the first rows realize and their covers land before measuring,
        // so the glide is judged on scrolling rather than on opening.
        await wait(1.5)
        // The floor warms nearest-first from the moment the shoot opens; a
        // reader who opens and scrolls at once meets it part-way. Wait for it
        // here, and say how long it took, so the passes measure scroll rather
        // than the warm — the cold case is the number below, not a guess.
        let floorWarmStart = CFAbsoluteTimeGetCurrent()
        var floorQueued = await BrowsePixelService.shared.diagnostics().floorQueued
        while floorQueued > 0, CFAbsoluteTimeGetCurrent() - floorWarmStart < 15 {
            await wait(0.1)
            floorQueued = await BrowsePixelService.shared.diagnostics().floorQueued
        }
        let floorDiagnostics = await BrowsePixelService.shared.diagnostics()
        report["floor"] = [
            "residentCount": floorDiagnostics.floorResidentCount,
            "bytes": floorDiagnostics.floorBytes,
            "queuedAtStart": floorQueued,
            "warmSecondsAfterMount": CFAbsoluteTimeGetCurrent() - floorWarmStart + 1.5,
            "budgetBytes": PhotoImageCacheBudget.floorCeilingBytes,
        ]
        note(
            "Floor tier warm before the passes",
            floorQueued == 0,
            String(format: "%d resident · %.1f MB · %.1fs after mount", floorDiagnostics.floorResidentCount,
                   Double(floorDiagnostics.floorBytes) / 1_048_576, CFAbsoluteTimeGetCurrent() - floorWarmStart + 1.5)
        )

        // A tall table lays out lazily; give the document up to ten seconds to
        // grow past the viewport before deciding there is nothing to scroll.
        var scrollViewFound: NSScrollView?
        let scrollDeadline = CFAbsoluteTimeGetCurrent() + 10
        while scrollViewFound == nil, CFAbsoluteTimeGetCurrent() < scrollDeadline {
            scrollViewFound = tableScrollView(in: hosting)
            if scrollViewFound == nil { await wait(0.25) }
        }
        guard let scrollView = scrollViewFound else {
            capture(hosting, name: "00-no-scroll-view", to: outDir)
            let all = allScrollViews(in: hosting).map {
                String(format: "%.0f×%.0f doc %.0f×%.0f", $0.frame.width, $0.frame.height,
                       $0.documentView?.frame.width ?? 0, $0.documentView?.frame.height ?? 0)
            }
            note("Table scroll view found", false, "no vertical NSScrollView taller than its viewport; scroll views: \(all)")
            report["status"] = "failed"
            report["reason"] = "no scroll view"
            report["checks"] = checks
            window.close()
            write(report, to: outDir)
            return 1
        }
        let viewportHeight = scrollView.frame.height
        let documentHeight = scrollView.documentView?.frame.height ?? 0
        let maxOffset = max(0, documentHeight - viewportHeight)
        report["viewport"] = ["width": size.width, "height": viewportHeight]
        report["documentHeightPx"] = documentHeight
        report["screens"] = viewportHeight > 0 ? documentHeight / viewportHeight : 0
        note(
            "Table scroll view found",
            maxOffset > viewportHeight,
            String(format: "document %.0f px · viewport %.0f px · %.1f screens", documentHeight, viewportHeight, documentHeight / max(viewportHeight, 1))
        )

        let tracker = ElasticScrollTracker.shared
        let diagnosticsBefore = await BrowsePixelService.shared.diagnostics()
        report["residentBefore"] = [
            "count": diagnosticsBefore.residentCount,
            "bytes": diagnosticsBefore.residentBytes,
        ]
        let appearBefore = tracker.appearEvents
        capture(hosting, name: "00-before", to: outDir)

        var offset: CGFloat = scrollView.contentView.bounds.origin.y
        var scroll: [String: Any] = [:]
        for (index, pass) in passes.enumerated() {
            if pass.name == "dart" {
                // The dart starts over a cold grid tier and a warm floor: the
                // state after a memory-pressure trim, and the only way the
                // reversal has anything in flight to cancel.
                await BrowsePixelService.shared.dropGridTierForMeasurement()
                let dropped = await BrowsePixelService.shared.diagnostics()
                report["gridTierDroppedBeforeDart"] = [
                    "residentCount": dropped.residentCount,
                    "floorResidentCount": dropped.floorResidentCount,
                ]
            }
            let result = await drive(
                pass,
                scrollView: scrollView,
                hosting: hosting,
                offset: &offset,
                maxOffset: maxOffset,
                viewportHeight: viewportHeight,
                filmDir: filming ? outDir.appendingPathComponent("film-\(pass.name)", isDirectory: true) : nil
            )
            // What the table showed the instant the pass stopped — wells and all.
            capture(hosting, name: String(format: "%02d-%@-end", index + 1, pass.name), to: outDir)
            scroll[pass.name] = result.report
            note(
                "\(pass.name): no well while scrolling",
                !result.blankSeen,
                String(
                    format: "%.1fs · tick p95=%.2fms p99=%.2fms · wells %d/%d ticks · %d tiles of %d sampled · soft (floor) %d tiles · decodes %d · prefetch issued %d cancelled %d · queue stale %d cancelled %d",
                    result.durationSec, result.tickP95, result.tickP99,
                    result.wellTicks, result.ticks, result.wellTiles, result.tilesSampled,
                    result.softTiles, result.decodes,
                    result.report["prefetchIssued"] as? Int ?? 0,
                    result.report["prefetchCancelled"] as? Int ?? 0,
                    result.report["gridStale"] as? Int ?? 0,
                    result.report["gridCancelled"] as? Int ?? 0
                )
            )
            note(
                "\(pass.name): tick p95 within the 120 Hz frame budget",
                result.tickP95 <= LatencyMetrics.frameBudget120HzMs,
                String(format: "p95=%.2fms budget=%.2fms", result.tickP95, LatencyMetrics.frameBudget120HzMs)
            )
        }
        report["scroll"] = scroll
        note(
            "Scrolling realized new rows",
            tracker.appearEvents > appearBefore,
            "\(tracker.appearEvents - appearBefore) plate appearances"
        )

        let diagnosticsAfter = await BrowsePixelService.shared.diagnostics()
        report["residentAfter"] = [
            "count": diagnosticsAfter.residentCount,
            "bytes": diagnosticsAfter.residentBytes,
            "cacheHits": diagnosticsAfter.cacheHits,
            "cacheMisses": diagnosticsAfter.cacheMisses,
        ]

        P0RenderInstruments.shared.detach()
        P0RenderInstruments.shared.disable()
        window.close()

        report["checks"] = checks
        report["failures"] = failures
        report["status"] = failures == 0 ? "passed" : "failed"
        write(report, to: outDir)
        fputs("P0 scroll live → \(outDir.path) (\(failures) failure(s))\n", stderr)
        return failures == 0 ? 0 : 1
    }

    // MARK: - One pass

    private struct PassResult {
        let report: [String: Any]
        let blankSeen: Bool
        let durationSec: Double
        let ticks: Int
        let tickP95: Double
        let tickP99: Double
        let wellTicks: Int
        let wellTiles: Int
        let softTiles: Int
        let tilesSampled: Int
        let decodes: Int
    }

    private static func drive(
        _ pass: Pass,
        scrollView: NSScrollView,
        hosting: NSView,
        offset: inout CGFloat,
        maxOffset: CGFloat,
        viewportHeight: CGFloat,
        filmDir: URL?
    ) async -> PassResult {
        if let filmDir {
            try? FileManager.default.createDirectory(at: filmDir, withIntermediateDirectories: true)
        }
        let tickKey = "p0.scroll.tick_ms.\(pass.name)"
        LatencyMetrics.beginCapture(key: tickKey)
        let frameKey = P0RenderInstruments.Key.scrollFrame
        let frameStart = LatencyMetrics.capturedSamples(for: frameKey).count
        let decodeKey = "browse.pixel.decode_ms"
        let decodeStart = LatencyMetrics.window(for: decodeKey)?.totalRecorded ?? 0
        let diagnosticsStart = await BrowsePixelService.shared.diagnostics()
        let tracker = ElasticScrollTracker.shared
        let appearStart = tracker.appearEvents
        var passPeakSpeed = 0.0

        let velocity = CGFloat(pass.screensPerSecond) * viewportHeight
        let target: CGFloat
        if let screens = pass.screens {
            let signed = CGFloat(screens) * viewportHeight * (velocity < 0 ? -1 : 1)
            target = min(max(offset + signed, 0), maxOffset)
        } else {
            target = velocity < 0 ? 0 : maxOffset
        }

        var ticks = 0
        var wellTicks = 0
        var wellTiles = 0
        var softTicks = 0
        var softTiles = 0
        var tilesSampled = 0
        var maxTickMs = 0.0
        let started = CFAbsoluteTimeGetCurrent()
        var last = started
        while velocity > 0 ? offset < target : offset > target {
            let now = CFAbsoluteTimeGetCurrent()
            let dt = now - last
            last = now
            offset = min(max(offset + velocity * CGFloat(dt), 0), maxOffset)

            let t0 = CFAbsoluteTimeGetCurrent()
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            P0RenderInstruments.shared.noteScrollActivity()
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            let tickMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            LatencyMetrics.record(tickKey, milliseconds: tickMs)
            maxTickMs = max(maxTickMs, tickMs)
            ticks += 1

            let visible = tracker.visiblePaths
            var missing = 0
            var soft = 0
            for path in visible where !BrowsePixelService.shared.isResident(path: path, tier: .grid) {
                if BrowsePixelService.shared.isResident(path: path, tier: .floor) {
                    soft += 1
                } else {
                    missing += 1
                }
            }
            tilesSampled += visible.count
            passPeakSpeed = max(passPeakSpeed, abs(tracker.velocity))
            softTiles += soft
            if soft > 0 { softTicks += 1 }
            if missing > 0 {
                wellTicks += 1
                wellTiles += missing
            }
            if let filmDir {
                let frame = String(format: "%05d", ticks)
                capture(hosting, name: frame, to: filmDir)
                if missing > 0 {
                    capture(hosting, name: "\(frame)-well", to: filmDir)
                }
            }
            await wait(1 / tickHz)
        }
        let durationSec = CFAbsoluteTimeGetCurrent() - started
        LatencyMetrics.endCapture(key: tickKey)

        let tickReading = LatencyMetrics.reading(for: tickKey)
        let frames = Array(LatencyMetrics.capturedSamples(for: frameKey).dropFirst(frameStart)).sorted()
        let decodes = (LatencyMetrics.window(for: decodeKey)?.totalRecorded ?? 0) - decodeStart
        let diagnosticsEnd = await BrowsePixelService.shared.diagnostics()

        let tickP95 = tickReading?.p95 ?? 0
        let tickP99 = tickReading?.p99 ?? 0
        var passReport: [String: Any] = [
            "screensPerSecond": pass.screensPerSecond,
            "durationSec": durationSec,
            "samples": ticks,
            "p50Ms": tickReading?.p50 ?? 0,
            "p95Ms": tickP95,
            "p99Ms": tickP99,
            "maxMs": maxTickMs,
            "window": tickReading?.window.declaration ?? "n=0",
            "blankSeen": wellTicks > 0,
            "wellTicks": wellTicks,
            "wellTiles": wellTiles,
            "tilesSampled": tilesSampled,
            "wellTileFraction": tilesSampled > 0 ? Double(wellTiles) / Double(tilesSampled) : 0,
            "softTicks": softTicks,
            "softTiles": softTiles,
            "floorEvictedDuringPass": diagnosticsEnd.floorEvicted - diagnosticsStart.floorEvicted,
            "prefetchIssued": diagnosticsEnd.prefetchIssued - diagnosticsStart.prefetchIssued,
            "prefetchCancelled": diagnosticsEnd.prefetchCancelled - diagnosticsStart.prefetchCancelled,
            "prefetchActiveAtEnd": diagnosticsEnd.prefetchActive,
            "gridStarted": diagnosticsEnd.gridStarted - diagnosticsStart.gridStarted,
            "gridStale": diagnosticsEnd.gridStale - diagnosticsStart.gridStale,
            "gridCancelled": diagnosticsEnd.gridCancelled - diagnosticsStart.gridCancelled,
            "gridQueuedAtEnd": diagnosticsEnd.gridQueued,
            "peakFramesPerSecond": passPeakSpeed,
            "lastWindowAhead": tracker.lastWindow.ahead.count,
            "decodes": decodes,
            "cacheHits": diagnosticsEnd.cacheHits - diagnosticsStart.cacheHits,
            "cacheMisses": diagnosticsEnd.cacheMisses - diagnosticsStart.cacheMisses,
            "inflightAtEnd": diagnosticsEnd.inflightCount,
            "appearEvents": tracker.appearEvents - appearStart,
            "endOffsetPx": offset,
            "achievedTickHz": durationSec > 0 ? Double(ticks) / durationSec : 0,
        ]
        passReport["frame"] = [
            "p50Ms": percentile(frames, 0.50),
            "p95Ms": percentile(frames, 0.95),
            "p99Ms": percentile(frames, 0.99),
            "maxMs": frames.last ?? 0,
            "sampleCount": frames.count,
            "window": "n=\(frames.count), full pass (display link)",
        ] as [String: Any]

        return PassResult(
            report: passReport,
            blankSeen: wellTicks > 0,
            durationSec: durationSec,
            ticks: ticks,
            tickP95: tickP95,
            tickP99: tickP99,
            wellTicks: wellTicks,
            wellTiles: wellTiles,
            softTiles: softTiles,
            tilesSampled: tilesSampled,
            decodes: decodes
        )
    }

    // MARK: - Helpers

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
    }

    private static func waitUntil(timeout: TimeInterval, predicate: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return predicate()
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
        return sorted[idx]
    }

    /// The table's scroll view: the first vertical `NSScrollView` whose document
    /// is taller than its viewport. The strip is horizontal and unmounted on
    /// the time route; the shelf is absent until there is a set.
    private static func tableScrollView(in view: NSView) -> NSScrollView? {
        // Compare against the scroll view's own frame: SwiftUI's clip view can
        // report bounds as tall as the document, which would hide the table.
        if let scroll = view as? NSScrollView,
           let document = scroll.documentView,
           document.frame.height > scroll.frame.height {
            return scroll
        }
        for child in view.subviews {
            if let match = tableScrollView(in: child) { return match }
        }
        return nil
    }

    /// PNG of the hosted window. Table tiles are AppKit-drawn, so wells and
    /// pixels both show; a Metal photograph would not (`cacheDisplay`).
    private static func capture(_ hosting: NSView, name: String, to directory: URL) {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// `…/card-elastic-v4-stress/frames` → `card-elastic-v4-stress`; any other
    /// folder keeps its own name, which is what the app would do.
    private static func catalogName(for folder: URL) -> String {
        let leaf = folder.lastPathComponent
        guard leaf == "frames" else { return leaf }
        let parent = folder.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? leaf : parent
    }

    private static func allScrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scroll = view as? NSScrollView { found.append(scroll) }
        for child in view.subviews { found += allScrollViews(in: child) }
        return found
    }

    private static func write(_ report: [String: Any], to outDir: URL) {
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: outDir.appendingPathComponent("p0_scroll_live_report.json"))
            FileHandle.standardError.write(data)
            FileHandle.standardError.write(Data("\n".utf8))
        }
    }
}

#endif
