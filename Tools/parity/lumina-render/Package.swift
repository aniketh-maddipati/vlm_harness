// swift-tools-version:5.9
import PackageDescription

// lumina-render: the app's LookPipeline as a command line tool for the parity harness
// (Tools/parity). Sources/lumina-render/Look is a symlink to Lumina/Sets/Look, so the tool
// renders through exactly the graph the app ships; SetsNumber.swift links the one bridge file
// the canvas reads page numbers with (Lumina/Sets/Core/SetsNumber.swift). Builds with `swift build` alone; the
// Makefile at the repo root does that (`make parity` / `make render`).
//
// LUMINA_TOOLS: the Makefile and CI build this package in release configuration. The Look
// sources keep their environment switches (LUMINA_RULES in LookRules.bundled, LUMINA_KERNEL_SALT
// in LookKernels) under `#if DEBUG || LUMINA_TOOLS`, so this tool has them and the app's Release
// build, which defines neither, does not (release task S4).
let package = Package(
    name: "lumina-render",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "lumina-render",
            path: "Sources/lumina-render",
            exclude: ["Look/rules-v1.json"],
            swiftSettings: [.define("LUMINA_TOOLS")]
        ),
    ]
)
