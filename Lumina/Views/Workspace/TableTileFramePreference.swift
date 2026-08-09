import SwiftUI

/// Collects photograph tile frames for rubber-band hit testing on the table.
enum TableTileFramePreference {
    struct Key: PreferenceKey {
        static var defaultValue: [AssetID: CGRect] { [:] }
        static func reduce(value: inout [AssetID: CGRect], nextValue: () -> [AssetID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, new in new })
        }
    }
}

extension View {
    func reportsTableTileFrame(id: AssetID, in space: CoordinateSpace = .global) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: TableTileFramePreference.Key.self,
                    value: [id: geo.frame(in: space)]
                )
            }
        }
    }
}
