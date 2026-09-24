import Foundation

nonisolated enum P0ExportControlLayout {
    static let fullSize = 0
    static let smallSize = 2048
    static let largeSize = 4096
    static let defaultQuality = P0ExportSettings().quality
    static let compactQuality = 0.85
    static let maximumQuality = 1.0
}
