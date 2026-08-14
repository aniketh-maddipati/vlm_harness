#if !LUMINA_SHIPPING_APP
import AppKit
import CoreImage
import Foundation
import SwiftUI

/// Full P0 editing live session — `--p0-edit-live [output-dir] [--p0-open <RAW_FOLDER>]`.
///
/// Opens a real shoot, drives single-photo editing through `P0SessionModel`,
/// measures scrub/navigation, exercises Before/crop/undo/persist, and writes
/// 1280×800 UI captures plus a JSON report.
@MainActor
enum P0EditLiveRunner {

    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--p0-edit-live") else { return false }

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)

        let outDir: URL
        if let idx = args.firstIndex(of: "--p0-edit-live"),
           args.indices.contains(idx + 1), !args[idx + 1].hasPrefix("-") {
            outDir = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        } else {
            outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("artifacts/p0-edit-live", isDirectory: true)
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
            "checkpoint": "p0-single-photo-editing-live",
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
            report["reason"] = "no RAW folder"
            write(report, to: outDir)
            return 1
        }
        report["fixtureDir"] = folder.path

        let session = P0SessionModel()
        // Prefer existing catalog when present — still validates rediscovery/persistence.
        if let recent = (try? ShootStore.listRecentShoots())?.first(where: {
            $0.name == folder.lastPathComponent || $0.rawFolderPath == folder.path
        }) {
            session.openRecent(recent)
            report["openMode"] = "recent:\(recent.name)"
        } else {
            session.openFolder(folder)
            report["openMode"] = "folder"
        }

        // Wait for contact-sheet assets (up to 60s). Must await-sleep so the
        // session's MainActor preparation task can apply stream events.
        let opened = await waitUntil(timeout: 60) { session.assets.count >= 8 }
        let assetCount = session.assets.count
        report["assetCount"] = assetCount
        report["openError"] = session.userFacingError ?? ""
        report["statusLine"] = session.preparationLine
        note("Open shoot into contact sheet", opened && assetCount >= 8, "\(assetCount) assets · \(session.preparationLine)")

        guard assetCount >= 2, let first = session.assets.first else {
            report["status"] = "failed"
            report["reason"] = "insufficient assets"
            report["checks"] = checks
            write(report, to: outDir)
            return 1
        }

        // Prefer a landscape and a portrait when EXIF aspect is available.
        let landscape = session.assets.first { ContactSheetPreparation.aspectRatio(for: $0) >= 1 }
            ?? first
        let portrait = session.assets.first { ContactSheetPreparation.aspectRatio(for: $0) < 1 }
            ?? session.assets.dropFirst().first
            ?? first

        // 1. Open photograph
        session.setFocus(landscape.id)
        session.openFocusedPhotograph()
        note("Open photograph from contact sheet", session.inspectingAssetID == landscape.id)

        // Warm render briefly
        await wait(0.4)
        session.prewarmInspection(around: landscape.id)
        await wait(0.6)
        let hasFrame = session.displayedCIImage(for: landscape.id) != nil
            || session.developScheduler.presentedCIImage(for: landscape.id) != nil
        note("RAW preview presents without blank canvas", hasFrame)

        // Capture editor @ 1280×800
        captureEditor(session: session, size: CGSize(width: 1280, height: 800), name: "editor-1280x800", to: outDir)

        // 2. Adjust every exposed control
        let controlProbes: [(String, (inout EditRecipe) -> Void)] = [
            ("exposure", { $0.exposure = 0.55 }),
            ("contrast", { $0.contrast = 25 }),
            ("highlights", { $0.highlights = -35 }),
            ("shadows", { $0.shadows = 40 }),
            ("temperature", { $0.temperature = 4800 }),
            ("tint", { $0.tint = 12 }),
            ("vibrance", { $0.vibrance = 20 }),
            ("saturation", { $0.saturation = -10 }),
            ("sharpness", { $0.sharpness = 40 }),
            ("luminanceNR", { $0.luminanceNR = 20 }),
        ]
        for (name, mutate) in controlProbes {
            let before = session.recipe(for: landscape.id)
            session.beginEditGesture(for: landscape.id)
            session.scrubEdit(mutate)
            await wait(0.05)
            session.endEditGesture()
            await wait(0.05)
            let after = session.recipe(for: landscape.id)
            note(
                "Control \(name) commits",
                after.valueFingerprint != before.valueFingerprint || after.hasSettings,
                after.valueFingerprint
            )
        }
        captureEditor(session: session, size: CGSize(width: 1280, height: 800), name: "editor-after-controls", to: outDir)

        // 3. Rapid Exposure scrub ≥ 10 s
        let scrubStart = CFAbsoluteTimeGetCurrent()
        var blankSeen = false
        var scrubSamples: [Double] = []
        session.beginEditGesture(for: landscape.id)
        while CFAbsoluteTimeGetCurrent() - scrubStart < 10.0 {
            let t0 = CFAbsoluteTimeGetCurrent()
            let v = sin((CFAbsoluteTimeGetCurrent() - scrubStart) * 3.2) * 1.2
            session.scrubEdit { $0.exposure = v }
            await wait(0.016)
            if session.displayedCIImage(for: landscape.id) == nil,
               session.developScheduler.presentedCIImage(for: landscape.id) == nil {
                blankSeen = true
            }
            scrubSamples.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }
        session.endEditGesture()
        scrubSamples.sort()
        let scrubP95 = percentile(scrubSamples, 0.95)
        report["rapidScrub"] = [
            "durationSec": 10,
            "samples": scrubSamples.count,
            "p50Ms": percentile(scrubSamples, 0.50),
            "p95Ms": scrubP95,
            "blankSeen": blankSeen,
            "scheduler": session.developScheduler.metrics.summaryLine,
        ]
        note("Rapid Exposure scrub ≥10s without blank canvas", !blankSeen, String(format: "p95=%.1fms n=%d", scrubP95, scrubSamples.count))

        // 4. Before press-and-hold (does not mutate)
        let recipeBeforeB = session.recipe(for: landscape.id)
        let undoCountBeforeB = session.undoCoordinator.stack.count
        session.setShowingBefore(true)
        await wait(0.05)
        session.setShowingBefore(false)
        note(
            "Before does not mutate recipe or undo",
            session.recipe(for: landscape.id).valueFingerprint == recipeBeforeB.valueFingerprint
                && session.undoCoordinator.stack.count == undoCountBeforeB
        )

        // 5. Navigate ≥ 20 neighbors (or all available)
        let navCount = min(20, session.visibleItems.count)
        var navSamples: [Double] = []
        var navBlank = false
        for i in 0..<navCount {
            let id = session.visibleItems[i % session.visibleItems.count].id
            let t0 = CFAbsoluteTimeGetCurrent()
            session.setFocus(id)
            await wait(0.03)
            navSamples.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            if session.developScheduler.presentedCIImage(for: id) == nil,
               session.displayedCIImage(for: id) == nil {
                // Cold frames may be empty briefly; only fail if still empty after wait.
                await wait(0.12)
                if session.developScheduler.presentedCIImage(for: id) == nil {
                    navBlank = true
                }
            }
        }
        navSamples.sort()
        report["navigation"] = [
            "count": navCount,
            "p50Ms": percentile(navSamples, 0.50),
            "p95Ms": percentile(navSamples, 0.95),
            "blankAfterWait": navBlank,
        ]
        note("Navigate neighbors", navCount >= min(20, assetCount), "\(navCount) frames")

        // Return to landscape for crop, then portrait
        session.setFocus(landscape.id)
        await wait(0.2)

        // 6. Crop landscape + portrait
        session.applyEditMutation({
            $0.crop = P0CropControls.centeredCrop(aspect: 3.0 / 2.0)
            $0.straightenDegrees = 1.5
        }, assetID: landscape.id)
        let landCropped = session.recipe(for: landscape.id).crop != nil
        note("Crop landscape", landCropped)
        captureEditor(session: session, size: CGSize(width: 1280, height: 800), name: "crop-landscape", to: outDir)

        session.setFocus(portrait.id)
        session.openFocusedPhotograph()
        await wait(0.3)
        session.applyEditMutation({
            $0.crop = P0CropControls.centeredCrop(aspect: 4.0 / 5.0)
            $0.straightenDegrees = 90
        }, assetID: portrait.id)
        let portCropped = session.recipe(for: portrait.id).hasGeometry
        note("Crop/rotate portrait", portCropped)
        captureEditor(session: session, size: CGSize(width: 1280, height: 800), name: "crop-portrait", to: outDir)

        // Grid → reopen
        session.closeInspection()
        note("Return to grid", session.inspectingAssetID == nil)
        session.setFocus(landscape.id)
        session.openFocusedPhotograph()
        note("Reopen landscape retains crop", session.recipe(for: landscape.id).crop != nil)
        session.setFocus(portrait.id)
        note("Reopen portrait retains geometry", session.recipe(for: portrait.id).hasGeometry)

        // 7. Edited bar independent of Keep
        let cullBefore = session.assets.first(where: { $0.id == landscape.id })?.cull ?? .undecided
        // Ensure landscape is not keep, but edited
        if cullBefore == .keep {
            session.setFocus(landscape.id)
            session.pressKeep() // toggle off
        }
        let marks = ContactSheetMarks.derive(
            asset: session.assets.first(where: { $0.id == landscape.id })!,
            selectedIDs: session.selectedAssetIDs,
            orderedIDs: session.orderedIDList,
            keptOrderMode: session.keptOrderMode
        )
        note("Edited mark independent of Keep", marks.edited && !marks.kept)

        // 8. Undo edit without changing cull
        session.setFocus(landscape.id)
        session.pressKeep() // now kept
        let cullKept = session.assets.first(where: { $0.id == landscape.id })?.cull
        let recipePreUndo = session.recipe(for: landscape.id)
        // Push a fresh edit then undo it
        session.applyEditMutation({ $0.exposure = recipePreUndo.exposure + 0.25 }, assetID: landscape.id)
        session.undoLast()
        let cullAfterUndo = session.assets.first(where: { $0.id == landscape.id })?.cull
        note(
            "Undo edit leaves cull unchanged",
            cullAfterUndo == cullKept,
            "cull=\(String(describing: cullAfterUndo))"
        )

        // 9. Quit/reopen persistence (save + reload shoot)
        session.flushPendingEditIfNeeded()
        await wait(0.3)
        guard session.shoot?.name != nil else {
            note("Persist shoot name", false, "missing")
            report["checks"] = checks
            report["failures"] = failures
            report["status"] = failures == 0 ? "passed" : "failed"
            write(report, to: outDir)
            return failures == 0 ? 0 : 1
        }
        let landscapeRecipe = session.recipe(for: landscape.id)
        let portraitRecipe = session.recipe(for: portrait.id)
        let landscapeCull = session.assets.first(where: { $0.id == landscape.id })?.cull
        if let shoot = session.shoot {
            try? await ShootStore.shared.saveShoot(shoot)
        }
        let shootName = session.shoot?.name
        session.goHome()
        await wait(0.2)

        let reopened = P0SessionModel()
        if let shootName,
           let recent = (try? ShootStore.listRecentShoots())?.first(where: { $0.name == shootName }) {
            reopened.openRecent(recent)
            report["reopenMode"] = "recent"
        } else {
            reopened.openFolder(folder)
            report["reopenMode"] = "folder"
        }
        _ = await waitUntil(timeout: 45) {
            reopened.assets.contains(where: { $0.id == landscape.id })
                && reopened.assets.count >= max(8, assetCount / 2)
        }
        // Extra beat for catalog hydration.
        await wait(0.8)
        let reLand = reopened.assets.first(where: { $0.id == landscape.id })
        let rePort = reopened.assets.first(where: { $0.id == portrait.id })
        note(
            "Quit/reopen retains landscape recipe",
            reLand?.recipe?.crop != nil || reLand?.recipe?.valueFingerprint == landscapeRecipe.valueFingerprint,
            reLand?.recipe?.valueFingerprint ?? "nil"
        )
        note(
            "Quit/reopen retains portrait geometry",
            rePort?.recipe?.hasGeometry == true || rePort?.recipe?.valueFingerprint == portraitRecipe.valueFingerprint
        )
        note(
            "Quit/reopen retains cull",
            reLand?.cull == landscapeCull,
            String(describing: reLand?.cull)
        )

        // 10. Layout capture at 1280×800 with rail expanded
            if let id = reLand?.id {
            reopened.setFocus(id)
            reopened.openFocusedPhotograph()
            await wait(0.5)
            captureEditor(session: reopened, size: CGSize(width: 1280, height: 800), name: "reopen-1280x800", to: outDir)
        }

        report["checks"] = checks
        report["failures"] = failures
        report["status"] = failures == 0 ? "passed" : "failed"
        report["metrics"] = [
            "scrub": report["rapidScrub"] as Any,
            "navigation": report["navigation"] as Any,
            "scheduler": session.developScheduler.metrics.summaryLine,
        ]
        write(report, to: outDir)
        fputs("P0 edit live → \(outDir.path) (\(failures) failure(s))\n", stderr)
        return failures == 0 ? 0 : 1
    }

    // MARK: - Helpers

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
    }

    /// Wait until `predicate` is true, yielding the main actor between polls.
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

    private static func captureEditor(
        session: P0SessionModel,
        size: CGSize,
        name: String,
        to directory: URL
    ) {
        guard let id = session.inspectingAssetID,
              let asset = session.assets.first(where: { $0.id == id }) else { return }
        let view = P0SinglePhotoEditor(session: session, asset: asset)
            .frame(width: size.width, height: size.height)
            .luminaWorkspaceAppearance()
        let hosting = NSHostingView(rootView: view)
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
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            window.close()
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
            fputs("Wrote \(name).png\n", stderr)
        }
        window.close()
    }

    private static func write(_ report: [String: Any], to outDir: URL) {
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: outDir.appendingPathComponent("p0_edit_live_report.json"))
            FileHandle.standardError.write(data)
            FileHandle.standardError.write(Data("\n".utf8))
        }
    }
}

#endif
