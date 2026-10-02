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
//
// LUMINA_TOOLS: Scripts/probe.sh builds this package in release configuration, and the scenarios
// need what the app's Release build leaves out (release task S4): the environment switches
// (LUMINA_RULES, LUMINA_KERNEL_SALT, LUMINA_CANVAS, LUMINA_CANVAS_WARM, LUMINA_SLOW_DIR_MS,
// LUMINA_INGEST_WORKERS) and the design's self-test served with `?selftest`. In the app's sources
// those sit under `#if DEBUG || LUMINA_TOOLS`; the app's Release build defines neither.
let package = Package(
    name: "LuminaProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "lumina-probe",
            path: "Sources/LuminaProbe",
            exclude: ["SetsLook/rules-v1.json"],
            resources: [.copy("probe.js")],
            swiftSettings: [.define("LUMINA_TOOLS")]
        ),
    ]
)
