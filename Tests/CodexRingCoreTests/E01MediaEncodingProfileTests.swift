import XCTest
@testable import CodexRingCore

final class E01MediaEncodingProfileTests: XCTestCase {
    func testRequestsDeviceCompatibleMJPEG420PixelFormat() {
        let arguments = E01MediaEncodingProfile.ffmpegArguments(
            imagePath: "/tmp/card.png",
            moviePath: "/tmp/card.avi"
        )

        guard let pixelFormatIndex = arguments.firstIndex(of: "-pix_fmt") else {
            return XCTFail("E01 media encoding must explicitly select a compatible pixel format")
        }
        XCTAssertEqual(arguments[pixelFormatIndex + 1], "yuvj420p")
    }
}
