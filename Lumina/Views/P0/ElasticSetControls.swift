import SwiftUI

/// "in set?" — the same press settle as the other buttons. Filled when it is on.
/// A second press takes the frames out, the way a second P clears a mark.
/// Wears an `S` key pill — set membership is also keyboard-first.
struct ElasticSetButton: View {
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ElasticLayout.exportGap) {
                Text(on ? CopyContract.inSetOn : CopyContract.inSetOff)
                    .font(ElasticType.sans(ElasticLayout.badgeTextSize, weight: .medium))
                ElasticControlKeyPill(
                    text: CopyContract.setMembershipKey,
                    onFilledControl: on
                )
            }
            .foregroundStyle(on ? LuminaTokens.Elastic.shell : LuminaTokens.Elastic.ink)
            .padding(.horizontal, ElasticLayout.badgePaddingH)
            .frame(minHeight: ElasticLayout.badgeHeight, maxHeight: ElasticLayout.badgeHeight)
            .background(
                on ? LuminaTokens.Elastic.ink : LuminaTokens.Elastic.shell,
                in: RoundedRectangle(cornerRadius: ElasticLayout.badgeRadius, style: .continuous)
            )
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .accessibilityLabel(on ? CopyContract.inSetOn : CopyContract.inSetOff)
    }
}

/// "phone?" — same press settle. Filled when the frame is a phone. Wears an `H` pill.
struct ElasticPhoneButton: View {
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ElasticLayout.exportGap) {
                Text(on ? CopyContract.phoneOn : CopyContract.phoneOff)
                    .font(ElasticType.sans(ElasticLayout.badgeTextSize, weight: .medium))
                ElasticControlKeyPill(
                    text: CopyContract.phoneMarkKey,
                    onFilledControl: on
                )
            }
            .foregroundStyle(on ? LuminaTokens.Elastic.shell : LuminaTokens.Elastic.ink)
            .padding(.horizontal, ElasticLayout.badgePaddingH)
            .frame(minHeight: ElasticLayout.badgeHeight, maxHeight: ElasticLayout.badgeHeight)
            .background(
                on ? LuminaTokens.Elastic.ink : LuminaTokens.Elastic.shell,
                in: RoundedRectangle(cornerRadius: ElasticLayout.badgeRadius, style: .continuous)
            )
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .accessibilityLabel(on ? CopyContract.phoneOn : CopyContract.phoneOff)
    }
}

/// Key pill on a light or filled control — same settle as the export `⌘E` chip.
struct ElasticControlKeyPill: View {
    let text: String
    /// When the parent control is filled (ink background), the pill inverts.
    var onFilledControl = false

    var body: some View {
        Text(text)
            .font(ElasticType.mono(ElasticLayout.keyPillSize, weight: .semibold))
            .padding(.horizontal, ElasticLayout.keyPillPaddingH)
            .padding(.vertical, ElasticLayout.keyPillPaddingV)
            .background(
                (onFilledControl ? LuminaTokens.Elastic.shell : LuminaTokens.Elastic.ink)
                    .opacity(ElasticLayout.keyPillOpacity),
                in: RoundedRectangle(cornerRadius: ElasticLayout.keyPillRadius, style: .continuous)
            )
            .allowsHitTesting(false)
    }
}

/// Which frames a drag rectangle crosses, in the order the caller supplies.
nonisolated enum ElasticMarqueeSelection {
    static func ids(in rect: CGRect, frames: [UUID: CGRect], order: [UUID]) -> [UUID] {
        guard rect.width > 0 || rect.height > 0 else { return [] }
        return order.filter { frames[$0]?.intersects(rect) == true }
    }
}

/// Drag across the matte between frames. The stroke is drawn by the table, in the
/// same space the tiles report, so this view only records the rectangle.
struct ElasticMarqueeGesture: View {
    @Bindable var session: P0SessionModel
    let space: UUID
    let frames: [UUID: CGRect]
    @Binding var rect: CGRect?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: ElasticLayout.markInset, coordinateSpace: .named(space))
                    .onChanged { value in
                        let next = CGRect(
                            x: min(value.startLocation.x, value.location.x),
                            y: min(value.startLocation.y, value.location.y),
                            width: abs(value.location.x - value.startLocation.x),
                            height: abs(value.location.y - value.startLocation.y)
                        )
                        rect = next
                        session.selectMarquee(
                            ElasticMarqueeSelection.ids(in: next, frames: frames, order: session.assets.map(\.id))
                        )
                    }
                    .onEnded { _ in
                        rect = nil
                    }
            )
    }
}
