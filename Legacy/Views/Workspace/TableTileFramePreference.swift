// QUARANTINED(D40) — legacy quarantine, retired checkpoint-by-checkpoint.
// Contract: design/contract-v6.md D40 · schedule: design/checkpoint-sequence-v6.md
// No new references from outside Legacy/. Enforced by Scripts/lint/quarantine_d40.sh.
// Do not extend, restyle, or re-enter these types under new names.
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
