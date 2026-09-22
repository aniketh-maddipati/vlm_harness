import SwiftUI

/// The Elastic shell: one continuous surface with two routes.
///
/// The table stays mounted under focus so returning is a scale change rather than
/// a rebuild, and the cursor never moves as a side effect of the transition.
struct ElasticRootView: View {
    @Bindable var session: P0SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var effectiveReduceMotion: Bool { reduceMotion || UITestSupport.reduceMotionForced }

    var body: some View {
        ZStack {
            LuminaTokens.Elastic.shell.ignoresSafeArea()

            VStack(spacing: 0) {
                if session.route == .focus,
                   let id = session.focusedAssetID,
                   let asset = session.assets.first(where: { $0.id == id }) {
                    ElasticFocusView(session: session, asset: asset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                        .transition(
                            effectiveReduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.985))
                        )
                        .accessibilityIdentifier(P0AccessibilityID.elasticFocus)
                }

                // Mounted in both routes: focus is a latch on this table, so the
                // surface is never rebuilt and scroll survives the round trip.
                ElasticTableView(session: session)
                    .frame(maxWidth: .infinity)
                    .frame(
                        maxHeight: session.route == .focus
                            ? ElasticLayout.filmstripHeight
                            : .infinity
                    )
                    .accessibilityIdentifier(P0AccessibilityID.elasticTable)
            }
        }
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
