import XCTest
@testable import Lumina

final class P0OpenPresentationTests: XCTestCase {

    func testChooserActionMatchesPointAtItAgainNotRetryVerbs() {
        XCTAssertEqual(P0OpenPresentation.chooserActionTitle, CopyContract.pointedFolderMovedAction)
        XCTAssertNotEqual(P0OpenPresentation.chooserActionTitle, CopyContract.diskFullAction)
        XCTAssertNotEqual(P0OpenPresentation.chooserActionTitle, CopyContract.cardEjectedEarlyAction)
    }

    func testDiskFullPreservesMessageAndOpensChooser() {
        let message = "Disk full — could not write"
        let feedback = P0OpenPresentation.failureFeedback(for: message)
        XCTAssertEqual(feedback.headline, CopyContract.diskFullHeadline)
        XCTAssertEqual(feedback.detail, message)
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointedFolderMovedAction)
        XCTAssertNotEqual(feedback.actionTitle, CopyContract.diskFullAction)
    }

    func testEjectedPreservesMessageAndOpensChooser() {
        let message = "Card ejected early — originals unavailable"
        let feedback = P0OpenPresentation.failureFeedback(for: message)
        XCTAssertEqual(feedback.headline, CopyContract.cardEjectedEarlyHeadline)
        XCTAssertEqual(feedback.detail, message)
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointedFolderMovedAction)
        XCTAssertNotEqual(feedback.actionTitle, CopyContract.cardEjectedEarlyAction)
    }

    func testEmptyMessageUsesOpenFailureFallbackNotDropCopy() {
        let feedback = P0OpenPresentation.failureFeedback(for: "   ")
        XCTAssertEqual(feedback.headline, CopyContract.pointedFolderMoved)
        XCTAssertEqual(feedback.detail, CopyContract.pointedFolderMovedBody)
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointedFolderMovedAction)
        XCTAssertNotEqual(feedback.headline, CopyContract.dropPhotographsOrFolder)
        XCTAssertNotEqual(feedback.detail, CopyContract.dropPhotographsOrFolder)
    }

    func testImportableDropMessageStripsBannedWordingKeepsFact() {
        let message = "No importable photos in drop."
        let feedback = P0OpenPresentation.failureFeedback(for: message)
        XCTAssertEqual(feedback.headline, "No photos in drop.")
        XCTAssertEqual(feedback.detail, "")
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointedFolderMovedAction)
        XCTAssertFalse(feedback.headline.lowercased().contains("import"))
        XCTAssertNotEqual(feedback.headline, CopyContract.dropPhotographsOrFolder)
        XCTAssertNotEqual(feedback.detail, CopyContract.dropPhotographsOrFolder)
    }

    func testPointedFolderMovedPreservesMessageAndChooserAction() {
        let message = "The folder you pointed at is no longer where it was."
        let feedback = P0OpenPresentation.failureFeedback(for: message)
        XCTAssertEqual(feedback.headline, CopyContract.pointedFolderMoved)
        XCTAssertEqual(feedback.detail, message)
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointedFolderMovedAction)
    }

    func testGenericOpenFailureKeepsFactAndChooserAction() {
        let message = "Shoot decode failed: corrupt header"
        let feedback = P0OpenPresentation.failureFeedback(for: message)
        XCTAssertEqual(feedback.headline, message)
        XCTAssertEqual(feedback.detail, "")
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointedFolderMovedAction)
        XCTAssertNotEqual(feedback.detail, CopyContract.dropPhotographsOrFolder)
    }

    func testSanitizedFactRemovesImportTokensOnly() {
        XCTAssertEqual(
            P0OpenPresentation.sanitizedFact("No importable photos in drop."),
            "No photos in drop."
        )
        XCTAssertEqual(
            P0OpenPresentation.sanitizedFact("Shoot decode failed: corrupt header"),
            "Shoot decode failed: corrupt header"
        )
    }
    func testSanitizedFactPreservesArbitraryWordsPathsAndCase() {
        for message in [
            "An important photograph failed to decode",
            "Unable to read /Photos/import/important.CR3",
            "NO IMPORTABLE PHOTOS IN DROP."
        ] {
            XCTAssertEqual(P0OpenPresentation.sanitizedFact(message), message)
            XCTAssertEqual(P0OpenPresentation.failureFeedback(for: message).headline, message)
        }
    }

}
