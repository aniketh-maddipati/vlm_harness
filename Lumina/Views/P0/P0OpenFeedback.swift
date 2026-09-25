import SwiftUI

/// Inline open-failure chip — facts only; never a modal dead-end (D35 / Law 3).
struct P0OpenFeedback: View {
    let message: String
    let onRecover: () -> Void

    private var feedback: P0OpenPresentation.FailureFeedback {
        P0OpenPresentation.failureFeedback(for: message)
    }

    var body: some View {
        RecoveryFactsChip(
            headline: feedback.headline,
            detail: feedback.detail,
            actionTitle: feedback.actionTitle,
            onAction: onRecover
        )
    }
}
