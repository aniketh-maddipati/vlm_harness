// swift-tools-version:6.0
// Linux sandbox for the app's Foundation-only native code (see run.sh). The `Lumina` target compiles
// the app's own files from Lumina/Sets/Core unchanged; Shims/ stands in for the Apple-only modules
// they import (a real SHA-256 for CryptoKit; image decode stubs that return nil). Nothing here ships.
import PackageDescription

let package = Package(
    name: "LuminaLinux",
    targets: [
        .target(name: "CryptoKit", path: "Shims/CryptoKit"),
        .target(name: "CoreGraphics", path: "Shims/CoreGraphics"),
        .target(name: "ImageIO", dependencies: ["CoreGraphics"], path: "Shims/ImageIO"),
        .target(name: "UniformTypeIdentifiers", path: "Shims/UniformTypeIdentifiers"),
        .target(name: "Lumina", dependencies: ["CryptoKit", "CoreGraphics", "ImageIO", "UniformTypeIdentifiers"], path: "Build/Lumina",
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LuminaLogicTests", dependencies: ["Lumina"], path: "Build/Tests", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
