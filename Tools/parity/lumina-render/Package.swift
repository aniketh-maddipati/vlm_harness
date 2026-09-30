// swift-tools-version:5.9
import PackageDescription

// lumina-render: the app's LookPipeline as a command line tool for the parity harness
// (Tools/parity). Sources/lumina-render/Look is a symlink to Lumina/Sets/Look, so the tool
// renders through exactly the graph the app ships. Builds with `swift build` alone; the
// Makefile at the repo root does that (`make parity` / `make render`).
let package = Package(
    name: "lumina-render",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "lumina-render",
            path: "Sources/lumina-render",
            exclude: ["Look/rules-v1.json"]
        ),
    ]
)
