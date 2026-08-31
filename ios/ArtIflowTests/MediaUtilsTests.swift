import XCTest
@testable import ArtIflow

final class MediaUtilsTests: XCTestCase {
    private func data(_ bytes: [UInt8]) -> Data { return Data(bytes) }

    func testDetectImageMimeTypeRecognizesCommonFormats() {
        let jpeg = data([0xFF, 0xD8, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        let png = data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x00])
        let webp = data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50])
        let heic = data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])
        XCTAssertEqual(detectImageMimeType(jpeg), "image/jpeg")
        XCTAssertEqual(detectImageMimeType(png), "image/png")
        XCTAssertEqual(detectImageMimeType(webp), "image/webp")
        XCTAssertEqual(detectImageMimeType(heic), "image/heic")
    }

    func testToImagePayloadsFiltersEmptyImagesAndInfersMimeType() {
        let png = data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x00])
        let payloads = toImagePayloads([Data(), png])
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?.mimeType, "image/png")
        XCTAssertEqual(payloads.first?.bytes, png)
    }
}
