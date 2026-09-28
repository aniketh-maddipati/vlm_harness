// swift-tools-version:5.9
import PackageDescription

// Drives the Lumina page (prototype or app) inside the same WKWebView engine the app ships,
// the way Playwright drives a browser: real key and mouse events, screenshots with photo
// masks, state dumps, folder picker and downloads, a seeded key fuzzer, crash/hang/resource
// watchdogs. Kept outside Lumina.xcodeproj so it builds with `swift build` alone.
let package = Package(
    name: "LuminaProbe",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "lumina-probe",
            path: "Sources/LuminaProbe",
            resources: [.copy("probe.js")]
        ),
    ]
)
