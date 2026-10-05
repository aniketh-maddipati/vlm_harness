import XCTest
@testable import Lumina

final class SetsExternalLinksTests: XCTestCase {
    // Sets v7 encodes this href for HTML; a browser hands native the &amp;-decoded URL.
    private let bugReportHTML = "mailto:anikethcov@gmail.com?subject=Lumina%20beta%200.01%20bug%20report&amp;body=What%20happened%3F%0A%0A"

    private func url(_ text: String) -> URL {
        try! XCTUnwrap(URL(string: text))
    }

    private func assertExternal(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .external = SetsExternalLinks.verdict(for: url(text), userClicked: true) else {
            return XCTFail("expected external: \(text)", file: file, line: line)
        }
    }

    private func assertRefused(_ text: String, userClicked: Bool = true,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard case .refuse = SetsExternalLinks.verdict(for: url(text), userClicked: userClicked) else {
            return XCTFail("expected refusal: \(text)", file: file, line: line)
        }
    }

    func testTheThreePageDestinationsAreAllowedAndCanonicalized() {
        let decodedMail = bugReportHTML.replacingOccurrences(of: "&amp;", with: "&")
        assertExternal(decodedMail)
        XCTAssertEqual(SetsExternalLinks.verdict(for: url("https://www.linkedin.com/in/anikethmaddipati"), userClicked: true),
                       .external(SetsExternalLinks.linkedIn))
        XCTAssertEqual(SetsExternalLinks.verdict(for: url("https://x.com/aniketh745"), userClicked: true),
                       .external(SetsExternalLinks.x))
    }

    func testMailIsRebuiltFromParsedParts() {
        let input = url("mailto:anikethcov%40gmail.com?subject=A%20bug&body=Details")
        guard case .external(let output) = SetsExternalLinks.verdict(for: input, userClicked: true) else {
            return XCTFail("expected external mail URL")
        }
        XCTAssertEqual(output.absoluteString, "mailto:anikethcov@gmail.com?subject=A%20bug&body=Details")
    }

    func testMailRefusals() {
        assertRefused("mailto:other@example.com?subject=Bug")
        assertRefused("mailto:anikethcov@gmail.com,other@example.com?subject=Bug")
        assertRefused("mailto:anikethcov@gmail.com?bcc=other@example.com")
        assertRefused("mailto:anikethcov@gmail.com?cc=other@example.com")
        assertRefused("mailto:anikethcov@gmail.com?to=other@example.com")
        assertRefused("mailto:anikethcov@gmail.com?attach=file:///tmp/photo.arw")
        assertRefused("mailto:anikethcov@gmail.com?subject=One&subject=Two")
        assertRefused("mailto:anikethcov@gmail.com?subject=Bug#fragment")
        assertRefused("mailto:anikethcov@gmail.com?body=\(String(repeating: "x", count: 5_000))")
    }

    func testWebRefusals() {
        assertRefused("https://x.com@evil.io/aniketh745")
        assertRefused("https://x.com:443/aniketh745")
        assertRefused("https://x.com/aniketh745/extra")
        assertRefused("https://x.com/aniketh745?from=lumina")
        assertRefused("https://x.com/aniketh745#profile")
        assertRefused("https://x.com.evil.io/aniketh745")
        assertRefused("https://xn--x-7ga.com/aniketh745")
        assertRefused("https://www.linkedin.com./in/anikethmaddipati/")
        assertRefused("https://www.linkedin.com/in%2Fanikethmaddipati")
        assertRefused("https://evil.io/in/anikethmaddipati")
    }

    func testUppercaseHostsAndTrailingSlashVariantsUseCanonicalConstants() {
        XCTAssertEqual(SetsExternalLinks.verdict(for: url("https://X.COM/aniketh745/"), userClicked: true),
                       .external(SetsExternalLinks.x))
        XCTAssertEqual(SetsExternalLinks.verdict(for: url("https://WWW.LINKEDIN.COM/in/anikethmaddipati"), userClicked: true),
                       .external(SetsExternalLinks.linkedIn))
    }

    func testOtherSchemesAreRefused() {
        assertRefused("http://x.com/aniketh745")
        assertRefused("file:///tmp/photo.arw")
        assertRefused("javascript:alert(1)")
        assertRefused("data:text/plain,hello")
        assertRefused("blob:https://x.com/id")
        assertRefused("tel:+15551234567")
    }

    func testScriptInitiatedExternalLinksAreRefused() {
        let mail = bugReportHTML.replacingOccurrences(of: "&amp;", with: "&")
        assertRefused(mail, userClicked: false)
        assertRefused("https://www.linkedin.com/in/anikethmaddipati/", userClicked: false)
        assertRefused("https://x.com/aniketh745", userClicked: false)
    }

    func testOnlyInPageDestinationsStayInPage() {
        XCTAssertEqual(SetsExternalLinks.verdict(for: url("lumina://app/x"), userClicked: false), .inPage)
        XCTAssertEqual(SetsExternalLinks.verdict(for: url("about:blank"), userClicked: false), .inPage)
        assertRefused("about:srcdoc")
    }
}
