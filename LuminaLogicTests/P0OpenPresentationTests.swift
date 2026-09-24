import XCTest
@testable import Lumina

final class P0OpenPresentationTests: XCTestCase {

    func testChooserActionIsPointAtFolderNotRetryVerbs() {
        XCTAssertEqual(P0OpenPresentation.chooserActionTitle, CopyContract.pointAtFolder)
        XCTAssertNotEqual(P0OpenPresentation.chooserActionTitle, CopyContract.diskFullAction)
        XCTAssertNotEqual(P0OpenPresentation.chooserActionTitle, CopyContract.cardEjectedEarlyAction)
    }

    func testDiskFullPreservesMessageAndOpensChooser() {
        let message = "Disk full — could not write"
        let feedback = P0OpenPresentation.failureFeedback(for: message)
        XCTAssertEqual(feedback.headline, CopyContract.diskFullHeadline)
        XCTAssertEqual(feedback.detail, message)
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointAtFolder)
        XCTAssertNotEqual(feedback.actionTitle, CopyContract.diskFullAction)
    }

    func testEjectedPreservesMessageAndOpensChooser() {
        let message = "Card ejected early — originals unavailable"
        let feedback = P0OpenPresentation.failureFeedback(for: message)
        XCTAssertEqual(feedback.headline, CopyContract.cardEjectedEarlyHeadline)
        XCTAssertEqual(feedback.detail, message)
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointAtFolder)
        XCTAssertNotEqual(feedback.actionTitle, CopyContract.cardEjectedEarlyAction)
    }

    func testEmptyMessageUsesOpenFailureFallbackNotDropCopy() {
        let feedback = P0OpenPresentation.failureFeedback(for: "   ")
        XCTAssertEqual(feedback.headline, CopyContract.pointedFolderMoved)
        XCTAssertEqual(feedback.detail, CopyContract.pointedFolderMovedBody)
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointAtFolder)
        XCTAssertNotEqual(feedback.headline, CopyContract.dropPhotographsOrFolder)
        XCTAssertNotEqual(feedback.detail, CopyContract.dropPhotographsOrFolder)
    }

    func testImportableDropMessageIsPreservedNotReplacedWithDropCopy() {
        let message = "No importable photos in drop."
        let feedback = P0OpenPresentation.failureFeedback(for: message)
        XCTAssertEqual(feedback.headline, message)
        XCTAssertEqual(feedback.detail, "")
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointAtFolder)
        XCTAssertNotEqual(feedback.headline, CopyContract.dropPhotographsOrFolder)
        XCTAssertNotEqual(feedback.detail, CopyContract.dropPhotographsOrFolder)
    }

    func testPointedFolderMovedMapsToContract() {
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
        XCTAssertEqual(feedback.actionTitle, CopyContract.pointAtFolder)
        XCTAssertNotEqual(feedback.detail, CopyContract.dropPhotographsOrFolder)
    }
}
