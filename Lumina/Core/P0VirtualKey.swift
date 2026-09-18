import Foundation

/// Named macOS virtual key codes used by the P0 event monitor.
/// These are hardware identifiers, never layout/design token values.
enum P0VirtualKey {
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let rightCommand: UInt16 = 54
    static let leftCommand: UInt16 = 55
}
