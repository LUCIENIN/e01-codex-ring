import XCTest
@testable import CodexRingCore

final class E01MediaEncodingProfileTests: XCTestCase {
    func testEncodesStaticDashboardAsOneBadgeSizedJPEG() {
        let arguments = E01MediaEncodingProfile.ffmpegJPEGArguments(
            imagePath: "/tmp/card.png",
            jpegPath: "/tmp/card.jpg"
        )

        XCTAssertTrue(arguments.contains("-nostdin"))
        XCTAssertEqual(value(after: "-frames:v", in: arguments), "1")
        XCTAssertEqual(value(after: "-c:v", in: arguments), "mjpeg")
        XCTAssertEqual(value(after: "-q:v", in: arguments), "5")
        XCTAssertEqual(value(after: "-pix_fmt", in: arguments), "yuvj420p")
        XCTAssertEqual(value(after: "-vf", in: arguments), "scale=368:368:force_original_aspect_ratio=disable,setsar=1")
        XCTAssertEqual(arguments.last, "/tmp/card.jpg")
    }

    func testUsesAtMostThreeRepeatedFramesForLowSpaceAtomicUpdates() throws {
        let arguments = E01MediaEncodingProfile.ffmpegArguments(
            imagePath: "/tmp/card.png",
            moviePath: "/tmp/card.avi"
        )

        XCTAssertTrue(arguments.contains("-nostdin"))
        XCTAssertEqual(value(after: "-pix_fmt", in: arguments), "yuvj420p")
        XCTAssertEqual(value(after: "-c:v", in: arguments), "mjpeg")
        XCTAssertEqual(value(after: "-q:v", in: arguments), "5")
        XCTAssertEqual(value(after: "-t", in: arguments), "1")

        let inputRate = try XCTUnwrap(Int(try XCTUnwrap(value(after: "-framerate", in: arguments))))
        let outputRate = try XCTUnwrap(Int(try XCTUnwrap(value(after: "-r", in: arguments))))
        let duration = try XCTUnwrap(Int(try XCTUnwrap(value(after: "-t", in: arguments))))
        XCTAssertEqual(inputRate, outputRate)
        XCTAssertLessThanOrEqual(outputRate * duration, 3)
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
