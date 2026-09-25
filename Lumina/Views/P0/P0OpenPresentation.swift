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

    /// Chooser recovery label — existing CopyContract action that opens `chooseFolder()`.
    static let chooserActionTitle = CopyContract.pointedFolderMovedAction

    /// One sentence naming the failure, one recovery action that opens the chooser.
    static func failureFeedback(for message: String) -> FailureFeedback {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let fact = sanitizedFact(text)

        if lower.contains("disk full") || lower.contains("no space") {
            return FailureFeedback(
                headline: CopyContract.diskFullHeadline,
                detail: fact.isEmpty ? text : fact,
                actionTitle: chooserActionTitle
            )
        }

        if lower.contains("ejected") {
            return FailureFeedback(
                headline: CopyContract.cardEjectedEarlyHeadline,
                detail: fact.isEmpty ? text : fact,
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
                detail: fact.isEmpty ? CopyContract.pointedFolderMovedBody : fact,
                actionTitle: chooserActionTitle
            )
        }

        // No useful text — open-path fallback from the failure table (not idle drop copy).
        if fact.isEmpty {
            return FailureFeedback(
                headline: CopyContract.pointedFolderMoved,
                detail: CopyContract.pointedFolderMovedBody,
                actionTitle: chooserActionTitle
            )
        }

        // Preserve the fact (banned “import” wording stripped). Drop instructions stay idle-only.
        return FailureFeedback(
            headline: fact,
            detail: "",
            actionTitle: chooserActionTitle
        )
    }

    /// Normalize only the known empty-drop fact; preserve arbitrary diagnostics and paths.
    /// Matching is case-sensitive because this is the session's literal message.
    static func sanitizedFact(_ message: String) -> String {
        message == "No importable photos in drop." ? "No photos in drop." : message
    }
}
