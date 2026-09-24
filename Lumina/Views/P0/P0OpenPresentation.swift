import Foundation

/// Open-surface failure presentation — maps session facts to Law 3 chip copy.
/// Pure; no session mutation. Recovery always opens the folder chooser, so action
/// titles must name that — never “retry” / “reinsert” verbs the button does not do.
enum P0OpenPresentation {
    struct FailureFeedback: Equatable, Sendable {
        var headline: String
        var detail: String
        var actionTitle: String
    }

    /// Chooser recovery label — contract OPEN line; matches `session.chooseFolder()`.
    static let chooserActionTitle = CopyContract.pointAtFolder

    /// One sentence naming the failure, one recovery action that opens the chooser.
    static func failureFeedback(for message: String) -> FailureFeedback {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        if lower.contains("disk full") || lower.contains("no space") {
            return FailureFeedback(
                headline: CopyContract.diskFullHeadline,
                detail: text,
                actionTitle: chooserActionTitle
            )
        }

        if lower.contains("ejected") {
            return FailureFeedback(
                headline: CopyContract.cardEjectedEarlyHeadline,
                detail: text,
                actionTitle: chooserActionTitle
            )
        }

        if lower.contains("bookmark")
            || lower.contains("no longer")
            || lower.contains("moved")
            || lower.contains("offline")
        {
            return FailureFeedback(
                headline: CopyContract.pointedFolderMoved,
                detail: text.isEmpty ? CopyContract.pointedFolderMovedBody : text,
                actionTitle: CopyContract.pointedFolderMovedAction
            )
        }

        // No useful text — open-path fallback from the failure table (not idle drop copy).
        if text.isEmpty {
            return FailureFeedback(
                headline: CopyContract.pointedFolderMoved,
                detail: CopyContract.pointedFolderMovedBody,
                actionTitle: chooserActionTitle
            )
        }

        // Preserve the actual session message (including empty-drop / “import…” strings).
        // Drop instructions stay on the idle hero — never as a failure stand-in.
        return FailureFeedback(
            headline: text,
            detail: "",
            actionTitle: chooserActionTitle
        )
    }
}
