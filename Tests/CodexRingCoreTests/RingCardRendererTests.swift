import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import CodexRingCore

final class RingCardRendererTests: XCTestCase {
    func testRendererWritesRequestedPngDimensions() throws {
        let presentation = UsagePresentation(
            primary: DisplayedWindow(remainingPercent: 76, resetsAt: Date(timeIntervalSince1970: 1_789_561_363)),
            secondary: nil,
            freshness: .fresh
        )

        let data = try RingCardRenderer().render(
            presentation,
            size: CGSize(width: 320, height: 320),
            now: Date(timeIntervalSince1970: 1_789_500_000)
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])

        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 320)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 320)
        XCTAssertGreaterThan(data.count, 1_000)
    }

    func testRendererWritesUnavailableCard() throws {
        let data = try RingCardRenderer().renderUnavailable(
            size: CGSize(width: 240, height: 240),
            now: Date(timeIntervalSince1970: 1_789_500_000)
        )

        XCTAssertGreaterThan(data.count, 1_000)
    }
}
