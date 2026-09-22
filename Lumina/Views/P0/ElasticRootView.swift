import SwiftUI

/// The Elastic shell: one continuous surface with two routes.
///
/// Top to bottom: header, the set shelf (once there is a set), the export receipt
/// (once one lands), then the table or the photograph. The table stays mounted under
/// focus — it compresses to the strip — so returning is a scale change rather than a
/// rebuild, and the cursor never moves as a side effect of the transition.
struct ElasticRootView: View {
    @Bindable var session: P0SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var effectiveReduceMotion: Bool { reduceMotion || UITestSupport.reduceMotionForced }

    var body: some View {
        VStack(spacing: 0) {
            ElasticHeader(session: session)

            if !session.finalSetAssetIDs.isEmpty {
                ElasticSetShelf(session: session)
                    .elasticBorn(ElasticLayout.bornTableMs)
            }

            if let receipt = session.elasticExportReceipt {
                ElasticExportReceipt(written: receipt.written, folder: receipt.folder)
                    .elasticBorn(ElasticLayout.bornTableMs)
            }

            if session.route == .focus,
               let id = session.focusedAssetID,
               let asset = session.assets.first(where: { $0.id == id }) {
                ElasticFocusView(session: session, asset: asset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                    // Fade only. `born` is the design's one entrance and it has no
                    // transform — the photograph does not grow into place.
                    .elasticBorn(ElasticLayout.bornTableMs)
                    .accessibilityIdentifier(P0AccessibilityID.elasticFocus)
            }

            // Mounted in both routes: focus is a latch on this table, so the
            // surface is never rebuilt and scroll survives the round trip.
            ElasticTableView(session: session)
                // Pinned rather than capped: the focus view claims the rest of the
                // stack, so a bare `maxHeight` would let the strip be squeezed to
                // nothing instead of holding its 92.
                .frame(
                    maxWidth: .infinity,
                    minHeight: session.route == .focus ? ElasticLayout.filmstripHeight : nil,
                    maxHeight: session.route == .focus
                        ? ElasticLayout.filmstripHeight
                        : .infinity
                )
                .accessibilityIdentifier(P0AccessibilityID.elasticTable)
        }
        .background(LuminaTokens.Elastic.paper.ignoresSafeArea())
        // The route change is a size change on one mounted surface: the table
        // compresses to the strip and back. Animating it here is what keeps that
        // true — nothing is swapped out, so nothing has to be rebuilt.
        .animation(
            LuminaSpringAnimation.transform(
                reduceMotion: effectiveReduceMotion,
                durationMs: Double(HiFiTokens.Motion.routeTransitionMs),
                curve: .easeOut
            ),
            value: session.route
        )
        #if DEBUG
        .workbenchHot()
        #endif
    }
}

/// Wordmark · session · headline · Auto (§3.1).
struct ElasticHeader: View {
    @Bindable var session: P0SessionModel

    var body: some View {
        HStack(spacing: ElasticLayout.headerGap) {
            Text("Lumina")
                .font(ElasticType.serif(ElasticLayout.wordmarkSize))
                .foregroundStyle(LuminaTokens.Elastic.ink)
                .fixedSize()

            Text(session.elasticSessionLabel)
                .font(ElasticType.mono(ElasticLayout.headerTextSize))
                .foregroundStyle(LuminaTokens.Elastic.muted)
                .fixedSize()

            Text(session.elasticHeadline)
                .font(ElasticType.mono(ElasticLayout.headerTextSize))
                .foregroundStyle(LuminaTokens.Elastic.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier(P0AccessibilityID.elasticHeader)

            autoButton
        }
        .padding(.horizontal, ElasticLayout.chromeGutter)
        .frame(height: ElasticLayout.headerHeight)
        .frame(maxWidth: .infinity)
        .background(LuminaTokens.Elastic.shell)
        .overlay(alignment: .bottom) { ElasticHairline() }
    }

    private var autoButton: some View {
        let enabled = session.autoButtonEnabled
        return Button {
            session.applyAutoToTable()
        } label: {
            HStack(spacing: ElasticLayout.autoGap) {
                Text("Auto")
                    .font(ElasticType.sans(ElasticLayout.autoTextSize, weight: .medium))
                Text(session.autoButtonSubLabel)
                    .font(ElasticType.mono(ElasticLayout.autoSubSize))
                    .opacity(ElasticLayout.subLabelOpacity)
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(enabled ? LuminaTokens.Elastic.shell : LuminaTokens.Elastic.muted)
            .padding(.horizontal, ElasticLayout.autoPadding)
            .frame(height: ElasticLayout.autoHeight)
            .background(
                enabled
                    ? LuminaTokens.Elastic.ink
                    : LuminaTokens.Elastic.ink.opacity(ElasticLayout.autoDisabledOpacity)
            )
            .clipShape(RoundedRectangle(cornerRadius: ElasticLayout.autoRadius, style: .continuous))
        }
        .buttonStyle(LuminaElasticButtonStyle())
        .accessibilityIdentifier(P0AccessibilityID.elasticAutoButton)
    }
}

/// `✓ n written · ~/folder` (§3.3).
struct ElasticExportReceipt: View {
    let written: String
    let folder: String

    var body: some View {
        HStack(spacing: ElasticLayout.receiptGap) {
            Text(written).foregroundStyle(LuminaTokens.Elastic.ink)
            Text(folder)
        }
        .font(ElasticType.mono(ElasticLayout.receiptTextSize))
        .foregroundStyle(LuminaTokens.Elastic.muted)
        .lineLimit(1)
        .padding(.horizontal, ElasticLayout.chromeGutter)
        .padding(.top, ElasticLayout.receiptPaddingTop)
        .padding(.bottom, ElasticLayout.receiptPaddingBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuminaTokens.Elastic.shell)
        .overlay(alignment: .bottom) { ElasticHairline() }
    }
}

/// `1px solid rgba(46,46,44,0.08)` — the only border on light chrome.
struct ElasticHairline: View {
    var body: some View {
        Rectangle()
            .fill(LuminaTokens.Elastic.ink.opacity(ElasticLayout.hairlineOpacity))
            .frame(height: ElasticLayout.hairline)
    }
}
