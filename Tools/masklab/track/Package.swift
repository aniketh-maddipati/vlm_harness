// swift-tools-version:5.9
import PackageDescription

// masklab-track: runs one mask tracker on one clip for Tools/masklab (see its README). No
// dependencies. MaskLabCore is Foundation only (arguments, boxes, masks, instance picking, the
// timing file) and builds and tests on Linux; the executable's AVFoundation / Vision / Core ML
// code is behind `#if canImport(Vision)`, so on Linux the tool builds but only says it needs a Mac.
let package = Package(
    name: "masklab-track",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MaskLabCore", path: "Sources/MaskLabCore"),
        .executableTarget(name: "masklab-track", dependencies: ["MaskLabCore"], path: "Sources/masklab-track"),
        .testTarget(name: "MaskLabCoreTests", dependencies: ["MaskLabCore"], path: "Tests/MaskLabCoreTests"),
    ]
)
