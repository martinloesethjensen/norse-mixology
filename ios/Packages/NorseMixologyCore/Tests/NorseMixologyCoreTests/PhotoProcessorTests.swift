import XCTest
@testable import NorseMixologyCore

/// Recipe Take spec §2/§4: photos are downsampled without decoding the full bitmap,
/// never upscaled, oriented upright, and bad data is refused rather than stored.
final class PhotoProcessorTests: XCTestCase {
    func testALargePhotoIsDownsampledToTheFullLimitAndAThumbnail() throws {
        let result = try PhotoProcessor.process(TestImages.jpeg(width: 5_000, height: 4_000))

        let full = try XCTUnwrap(TestImages.pixelSize(of: result.full))
        XCTAssertEqual(full.width, 1_600)
        XCTAssertLessThanOrEqual(abs(full.height - 1_280), 1)

        let thumbnail = try XCTUnwrap(TestImages.pixelSize(of: result.thumbnail))
        XCTAssertEqual(thumbnail.width, 320)
        XCTAssertLessThanOrEqual(abs(thumbnail.height - 256), 1)
    }

    func testASmallPhotoIsNeverUpscaled() throws {
        let result = try PhotoProcessor.process(TestImages.jpeg(width: 200, height: 100))

        let full = try XCTUnwrap(TestImages.pixelSize(of: result.full))
        XCTAssertEqual(full.width, 200)
        XCTAssertEqual(full.height, 100)
        let thumbnail = try XCTUnwrap(TestImages.pixelSize(of: result.thumbnail))
        XCTAssertEqual(thumbnail.width, 200)
    }

    func testTheEXIFOrientationIsApplied() throws {
        // 400×200 tagged "rotate 90°" is a portrait photo.
        let result = try PhotoProcessor.process(TestImages.jpeg(width: 400, height: 200, orientation: 6))

        let full = try XCTUnwrap(TestImages.pixelSize(of: result.full))
        XCTAssertEqual(full.width, 200)
        XCTAssertEqual(full.height, 400)
    }

    func testDataThatIsNotAnImageIsRefused() {
        XCTAssertThrowsError(try PhotoProcessor.process(Data("not an image".utf8))) { error in
            XCTAssertEqual(error as? PhotoError, .unreadable)
        }
    }

    func testEmptyDataIsRefused() {
        XCTAssertThrowsError(try PhotoProcessor.process(Data())) { error in
            XCTAssertEqual(error as? PhotoError, .unreadable)
        }
    }

    func testOutputsAreJPEGAndTheThumbnailIsSmaller() throws {
        let result = try PhotoProcessor.process(TestImages.jpeg(width: 3_000, height: 2_000))

        XCTAssertEqual(Array(result.full.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(Array(result.thumbnail.prefix(2)), [0xFF, 0xD8])
        XCTAssertLessThan(result.thumbnail.count, result.full.count)
    }
}
