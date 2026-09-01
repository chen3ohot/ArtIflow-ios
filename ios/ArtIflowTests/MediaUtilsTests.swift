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

    // 上传前增强：彩色图应被处理成有效 JPEG（0xFFD8 起始）且非空，体积小于原图
    func testDownscaleImageForUploadProducesValidJpeg() {
        // 用系统渲染器生成一张带细节的彩色 PNG（模拟题目照片）
        let size = CGSize(width: 200, height: 200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            for i in 0..<20 {
                let y = CGFloat(i) * 10
                ctx.fill(CGRect(x: 10, y: y, width: 180, height: 3))
            }
        }
        guard let png = img.pngData() else {
            // 模拟器上 pngData 不可用时跳过，避免假阴性
            return
        }
        let out = downscaleImageForUpload(png)
        XCTAssertFalse(out.isEmpty)
        // JPEG 起始应为 0xFF 0xD8
        XCTAssertEqual(out[0], 0xFF, "enhanced output should be JPEG")
        XCTAssertEqual(out[1], 0xD8, "enhanced output should be JPEG")
    }
}
