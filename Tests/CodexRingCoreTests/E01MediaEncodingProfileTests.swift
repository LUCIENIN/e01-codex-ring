import XCTest
@testable import CodexRingCore

final class E01MediaEncodingProfileTests: XCTestCase {
    func testMatchesZRunBadgeMPEG4EncodingProfile() {
        let arguments = E01MediaEncodingProfile.ffmpegArguments(
            imagePath: "/tmp/card.png",
            moviePath: "/tmp/card.avi"
        )

        XCTAssertTrue(arguments.contains("-nostdin"))
        guard let pixelFormatIndex = arguments.firstIndex(of: "-pix_fmt") else {
            return XCTFail("E01 media encoding must explicitly select a compatible pixel format")
        }
        XCTAssertEqual(arguments[pixelFormatIndex + 1], "yuv420p")
        XCTAssertEqual(value(after: "-framerate", in: arguments), "12")
        XCTAssertEqual(value(after: "-c:v", in: arguments), "mpeg4")
        XCTAssertEqual(value(after: "-r", in: arguments), "12")
        XCTAssertEqual(value(after: "-q:v", in: arguments), "2")
        XCTAssertEqual(value(after: "-t", in: arguments), "1")
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}
