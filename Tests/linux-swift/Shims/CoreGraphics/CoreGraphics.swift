import Foundation

// Stand-ins for the CoreGraphics the app's image decode uses. Linux sandbox only: nothing here draws,
// so SetsIngest.upright() returns nil on Linux and its tests stay on the Mac.
public typealias CFData = Data
public typealias CFString = String
public typealias CFDictionary = [String: Any]

public final class CGImage { public let width = 0; public let height = 0 }
public final class CGColorSpace {
    public static let sRGB = "sRGB"
    public init?(name: String) { return nil }
}
public enum CGImageAlphaInfo: UInt32 { case noneSkipLast = 5 }
public final class CGContext {
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace, bitmapInfo: UInt32) { return nil }
    public func translateBy(x: CGFloat, y: CGFloat) {}
    public func rotate(by: CGFloat) {}
    public func draw(_ image: CGImage, in: CGRect) {}
    public func makeImage() -> CGImage? { nil }
}
