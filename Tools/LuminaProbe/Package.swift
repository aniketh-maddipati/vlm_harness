// swift-tools-version:5.9
import PackageDescription

// Drives the Lumina page (prototype or app) inside the same WKWebView engine the app ships,
// the way Playwright drives a browser: real key and mouse events, screenshots with photo
// masks, state dumps, folder picker and downloads, a seeded key fuzzer, crash/hang/resource
// watchdogs. Kept outside Lumina.xcodeproj so it builds with `swift build` alone.
//
// Sources/LuminaProbe/SetsCore and SetsLook are symlinks to the app's own bridge (Lumina/Sets/Core)
// and Edit look pipeline (Lumina/Sets/Look), compiled in: app-mode scenarios exercise the exact
// native code the app ships. rules-v1.json is read from LUMINA_RULES (LookRules.bundled), not bundled.
let package = Package(
    name: "LuminaProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "lumina-probe",
            path: "Sources/LuminaProbe",
            exclude: ["SetsLook/rules-v1.json"],
            resources: [.copy("probe.js")]
        ),
    ]
)
