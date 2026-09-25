import XCTest
@testable import Lumina

final class PhoneBodySensingTests: XCTestCase {

    func testIPhoneProRAWIsPhoneNotCamera() {
        let evidence = PhoneBodySensing.Evidence(
            make: "Apple", model: "iPhone 16 Pro", filename: "IMG_0001.DNG"
        )
        XCTAssertEqual(PhoneBodySensing.classify(evidence), .phone)
        XCTAssertTrue(PhoneBodySensing.isPhone(evidence))
    }

    func testIPhoneHEICIsPhone() {
        let evidence = PhoneBodySensing.Evidence(
            make: "Apple", model: "iPhone 15 Pro Max", filename: "IMG_0002.HEIC"
        )
        XCTAssertEqual(PhoneBodySensing.classify(evidence), .phone)
    }

    func testSonyARWIsCamera() {
        let evidence = PhoneBodySensing.Evidence(
            make: "SONY", model: "ILCE-7M4", filename: "DSC01234.ARW"
        )
        XCTAssertEqual(PhoneBodySensing.classify(evidence), .camera)
    }

    func testCameraJPEGIsNotPhone() {
        let evidence = PhoneBodySensing.Evidence(
            make: "Canon", model: "EOS R6m2", filename: "IMG_9001.JPG"
        )
        XCTAssertEqual(PhoneBodySensing.classify(evidence), .camera)
        XCTAssertFalse(PhoneBodySensing.isPhone(evidence))
    }

    func testJPEGWithoutIdentityIsUnknownNotPhone() {
        // Old heuristic: non-RAW → phone. That false-tagged every camera JPEG.
        let evidence = PhoneBodySensing.Evidence(filename: "export.jpg")
        XCTAssertEqual(PhoneBodySensing.classify(evidence), .unknown)
        XCTAssertFalse(PhoneBodySensing.isPhone(evidence))
    }

    func testDNGWithoutMakeIsUnknown() {
        let evidence = PhoneBodySensing.Evidence(filename: "converted.DNG")
        XCTAssertEqual(PhoneBodySensing.classify(evidence), .unknown)
    }

    func testPixelAndGalaxyPhoneMakes() {
        XCTAssertEqual(
            PhoneBodySensing.classify(.init(make: "Google", model: "Pixel 8 Pro", filename: "PXL.jpg")),
            .phone
        )
        XCTAssertEqual(
            PhoneBodySensing.classify(.init(make: "samsung", model: "SM-S918B", filename: "20240101.jpg")),
            .phone
        )
    }

    func testAssetRecordManualOverridesSensed() {
        var asset = AssetRecord(
            id: UUID(),
            sourceKey: "k",
            source: SourceReference(
                originalPath: "/proof/a.ARW",
                relativePath: "a.ARW",
                volumeID: "PROOF",
                availability: .available
            ),
            filename: "a.ARW",
            captureMake: "sony",
            captureModel: "ilce-7m4",
            sensedIsPhone: false
        )
        XCTAssertFalse(asset.isPhoneBody)
        asset.manualIsPhone = true
        XCTAssertTrue(asset.isPhoneBody, "hand mark and sensing share one phone treatment")
        asset.manualIsPhone = nil
        XCTAssertFalse(asset.isPhoneBody)
    }

    func testAssetRecordUsesSensedWhenPresent() {
        let phone = AssetRecord(
            id: UUID(),
            sourceKey: "k",
            source: SourceReference(
                originalPath: "/proof/p.HEIC",
                relativePath: "p.HEIC",
                volumeID: "PROOF",
                availability: .available
            ),
            filename: "p.HEIC",
            sensedIsPhone: true
        )
        XCTAssertTrue(phone.isPhoneBody)
    }
}
