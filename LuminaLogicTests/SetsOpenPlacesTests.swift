import XCTest
@testable import Lumina

final class SetsOpenPlacesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sandbox: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        suiteName = "SetsOpenPlacesTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        sandbox = fm.temporaryDirectory
            .appendingPathComponent("sets-open-places-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fm.removeItem(at: sandbox)
    }

    private func folder(_ name: String) throws -> URL {
        let url = sandbox.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func calls(stale: Bool = false, resolveThrows: Bool = false) -> SetsOpenPlaces.Calls {
        SetsOpenPlaces.Calls(
            resolve: { data in
                if resolveThrows { throw CocoaError(.fileReadNoSuchFile) }
                return (URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true), stale)
            },
            bookmark: { Data($0.path.utf8) },
            directoryExists: { url in
                var directory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
                    && directory.boolValue
            },
            isDirectory: { url in
                var directory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
                    && directory.boolValue
            })
    }

    private func systemDefault(_ directory: FileManager.SearchPathDirectory) -> URL? {
        fm.urls(for: directory, in: .userDomainMask).first
    }

    func testDefaultsForEachPickerPlace() {
        let places = SetsOpenPlaces(defaults: defaults, calls: calls())
        XCTAssertEqual(places.start(for: .pictures, card: nil),
                       .panel(directory: systemDefault(.picturesDirectory)))
        XCTAssertEqual(places.start(for: .downloads, card: nil),
                       .panel(directory: systemDefault(.downloadsDirectory)))
        XCTAssertEqual(places.start(for: .desktop, card: nil),
                       .panel(directory: systemDefault(.desktopDirectory)))
        XCTAssertEqual(places.start(for: .folder, card: nil), .panel(directory: nil))
    }

    func testRememberedFolderWins() throws {
        let chosen = try folder("Chosen")
        let places = SetsOpenPlaces(defaults: defaults, calls: calls())
        places.remember(chosen, for: .pictures)
        XCTAssertEqual(places.start(for: .pictures, card: nil), .panel(directory: chosen))
    }

    func testStaleBookmarkFallsBackAndIsRemoved() throws {
        let chosen = try folder("Stale")
        defaults.set(Data(chosen.path.utf8), forKey: "lumina.lastDir.downloads")
        let places = SetsOpenPlaces(defaults: defaults, calls: calls(stale: true))
        XCTAssertEqual(places.start(for: .downloads, card: nil),
                       .panel(directory: systemDefault(.downloadsDirectory)))
        XCTAssertNil(defaults.data(forKey: "lumina.lastDir.downloads"))
    }

    func testResolveFailureFallsBackAndIsRemoved() throws {
        defaults.set(Data("unreadable".utf8), forKey: "lumina.lastDir.desktop")
        let places = SetsOpenPlaces(defaults: defaults, calls: calls(resolveThrows: true))
        XCTAssertEqual(places.start(for: .desktop, card: nil),
                       .panel(directory: systemDefault(.desktopDirectory)))
        XCTAssertNil(defaults.data(forKey: "lumina.lastDir.desktop"))
    }

    func testDeletedRememberedFolderFallsBackAndIsRemoved() throws {
        let chosen = try folder("Deleted")
        let places = SetsOpenPlaces(defaults: defaults, calls: calls())
        places.remember(chosen, for: .folder)
        try fm.removeItem(at: chosen)
        XCTAssertEqual(places.start(for: .folder, card: nil), .panel(directory: nil))
        XCTAssertNil(defaults.data(forKey: "lumina.lastDir.folder"))
    }

    func testPickingAFileRemembersItsParent() throws {
        let parent = try folder("Files")
        let file = parent.appendingPathComponent("frame.ARW")
        try Data([0, 1, 2]).write(to: file)
        let places = SetsOpenPlaces(defaults: defaults, calls: calls())
        places.remember(file, for: .downloads)
        XCTAssertEqual(defaults.data(forKey: "lumina.lastDir.downloads"), Data(parent.path.utf8))
        XCTAssertEqual(places.start(for: .downloads, card: nil), .panel(directory: parent))
    }

    func testForgetRemovesOnlyThatPlace() throws {
        let pictures = try folder("Pictures")
        let desktop = try folder("Desktop")
        let places = SetsOpenPlaces(defaults: defaults, calls: calls())
        places.remember(pictures, for: .pictures)
        places.remember(desktop, for: .desktop)
        places.forget(.pictures)
        XCTAssertNil(defaults.data(forKey: "lumina.lastDir.pictures"))
        XCTAssertNotNil(defaults.data(forKey: "lumina.lastDir.desktop"))
    }

    func testCardStartsInDCIMWhenPresent() throws {
        let card = try folder("CARD")
        let dcim = card.appendingPathComponent("DCIM", isDirectory: true)
        try fm.createDirectory(at: dcim, withIntermediateDirectories: true)
        let places = SetsOpenPlaces(defaults: defaults, calls: calls())
        XCTAssertEqual(places.start(for: .card, card: card), .panel(directory: dcim))
    }

    func testCardStartsAtVolumeWithoutDCIM() throws {
        let card = try folder("CARD")
        let places = SetsOpenPlaces(defaults: defaults, calls: calls())
        XCTAssertEqual(places.start(for: .card, card: card), .panel(directory: card))
    }

    func testCardWithoutMountedVolumeDoesNotOpenPicker() {
        let places = SetsOpenPlaces(defaults: defaults, calls: calls())
        XCTAssertEqual(places.start(for: .card, card: nil), .noCard)
    }

    func testPhoneIsNotAPicker() {
        let places = SetsOpenPlaces(defaults: defaults, calls: calls())
        XCTAssertEqual(places.start(for: .phone, card: nil), .notAPicker)
    }

    func testUnknownWhereIsRefused() {
        XCTAssertNil(SetsOpenPlaces.Place("camera"))
        XCTAssertEqual(SetsOpenPlaces.Place("pictures"), .pictures)
    }

    func testCardIsNeverWrittenToDefaults() throws {
        let card = try folder("CARD")
        let places = SetsOpenPlaces(defaults: defaults, calls: calls())
        places.remember(card, for: .card)
        XCTAssertNil(defaults.data(forKey: "lumina.lastDir.card"))
    }

    #if canImport(AppKit)
    @MainActor
    func testPanelConfigurationForOpenAndAdd() throws {
        let start = try folder("Start")
        for (add, prompt) in [(false, "Open"), (true, "Add to shoot")] {
            let panel = SetsOpenPlaces.panel(start: start, add: add)
            XCTAssertTrue(panel.canChooseDirectories)
            XCTAssertTrue(panel.canChooseFiles)
            XCTAssertTrue(panel.allowsMultipleSelection)
            XCTAssertEqual(panel.directoryURL, start)
            XCTAssertEqual(panel.prompt, prompt)
            XCTAssertEqual(panel.allowedContentTypes.map(\.identifier), [
                "com.sony.arw-raw-image",
                "public.camera-raw-image",
                "com.adobe.raw-image",
                "public.folder",
            ])
        }
    }
    #endif
}
