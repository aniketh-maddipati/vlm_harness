import Foundation
@_exported import CoreGraphics

// ImageIO stand-ins (Linux sandbox only): decoding and encoding always fail.
public final class CGImageSource {}
public final class CGImageDestination {}
public let kCGImageSourceShouldCache = "kCGImageSourceShouldCache"
public let kCGImageSourceShouldCacheImmediately = "kCGImageSourceShouldCacheImmediately"
public let kCGImageDestinationLossyCompressionQuality = "kCGImageDestinationLossyCompressionQuality"
public func CGImageSourceCreateWithData(_ data: CFData, _ options: CFDictionary?) -> CGImageSource? { nil }
public func CGImageSourceGetCount(_ s: CGImageSource) -> Int { 0 }
public func CGImageSourceCreateImageAtIndex(_ s: CGImageSource, _ i: Int, _ o: CFDictionary?) -> CGImage? { nil }
public func CGImageDestinationCreateWithData(_ d: NSMutableData, _ type: CFString, _ n: Int, _ o: CFDictionary?) -> CGImageDestination? { nil }
public func CGImageDestinationAddImage(_ d: CGImageDestination, _ i: CGImage, _ o: CFDictionary?) {}
public func CGImageDestinationFinalize(_ d: CGImageDestination) -> Bool { false }
