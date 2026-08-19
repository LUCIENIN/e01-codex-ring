import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import CodexRingCore

final class RingCardRendererTests: XCTestCase {
    func testQuotaHealthUsesReadableGoodWatchAndLowBands() {
        XCTAssertEqual(QuotaHealthStatus(remainingPercent: 100), .good)
        XCTAssertEqual(QuotaHealthStatus(remainingPercent: 50), .good)
        XCTAssertEqual(QuotaHealthStatus(remainingPercent: 49), .watch)
        XCTAssertEqual(QuotaHealthStatus(remainingPercent: 20), .watch)
        XCTAssertEqual(QuotaHealthStatus(remainingPercent: 19), .low)
        XCTAssertEqual(QuotaHealthStatus(remainingPercent: 0), .low)
    }

    func testDashboardBuildsMetricsInGlanceablePriorityOrder() {
        let dashboard = QuotaDashboardPresentation(
            codex: UsagePresentation(
                primary: DisplayedWindow(remainingPercent: 25, resetsAt: nil),
                secondary: nil,
                freshness: .fresh
            ),
            kimi: KimiUsagePresentation(
                weekly: DisplayedWindow(remainingPercent: 91, resetsAt: nil),
                fiveHour: DisplayedWindow(remainingPercent: 18, resetsAt: nil),
                freshness: .fresh
            )
        )

        XCTAssertEqual(dashboard.metrics.map(\.label), ["CODEX", "KIMI WEEK", "KIMI 5H"])
        XCTAssertEqual(dashboard.metrics.map(\.remainingPercent), [25, 91, 18])
        XCTAssertEqual(dashboard.metrics.map(\.status), [.watch, .good, .low])
    }

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

    func testRendererWritesCombinedCodexAndKimiDashboard() throws {
        let dashboard = QuotaDashboardPresentation(
            codex: UsagePresentation(
                primary: DisplayedWindow(remainingPercent: 32, resetsAt: nil),
                secondary: nil,
                freshness: .fresh
            ),
            kimi: KimiUsagePresentation(
                weekly: DisplayedWindow(remainingPercent: 91, resetsAt: nil),
                fiveHour: DisplayedWindow(remainingPercent: 82, resetsAt: nil),
                freshness: .fresh
            )
        )

        let data = try RingCardRenderer().renderDashboard(
            dashboard,
            size: CGSize(width: 368, height: 368),
            now: Date(timeIntervalSince1970: 1_789_500_000)
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])

        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 368)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 368)
        XCTAssertGreaterThan(data.count, 1_000)
    }
}
