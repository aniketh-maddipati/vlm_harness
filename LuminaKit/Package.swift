// swift-tools-version: 5.10
import PackageDescription

// The native Lumina UI (design/handoff/lumina-app). Two libraries so the rules can be tested
// without a window: LuminaCore (models, stores, key table, layout maths; no SwiftUI) and LuminaUI
// (the views). Folders under Sources/ are owned one per work package (see LuminaKit/README.md):
// adding a file never touches the Xcode project, so parallel workers don't conflict.
let flags: [SwiftSetting] = [.define("LUMINA_UITEST", .when(configuration: .debug))]

let package = Package(
    name: "LuminaKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LuminaCore", targets: ["LuminaCore"]),
        .library(name: "LuminaUI", targets: ["LuminaUI"]),
    ],
    targets: [
        .target(name: "LuminaCore", swiftSettings: flags),
        .target(name: "LuminaUI", dependencies: ["LuminaCore"], swiftSettings: flags),
        .executableTarget(name: "lumina-snap", dependencies: ["LuminaUI"], swiftSettings: flags),
        .testTarget(name: "LuminaCoreTests", dependencies: ["LuminaCore"], swiftSettings: flags),
    ]
)
