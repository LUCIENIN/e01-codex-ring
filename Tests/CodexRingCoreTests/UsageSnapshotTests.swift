import Foundation
import XCTest
@testable import CodexRingCore

final class UsageSnapshotTests: XCTestCase {
    func testPresentationConvertsUsedPercentIntoRemainingPercent() {
        let reset = Date(timeIntervalSince1970: 1_789_561_363)
        let snapshot = UsageSnapshot(
            observedAt: Date(timeIntervalSince1970: 1_789_500_000),
            primary: UsageWindow(usedPercent: 24, resetsAt: reset),
            secondary: nil
        )

        let presentation = snapshot.presentation(now: Date(timeIntervalSince1970: 1_789_500_060))

        XCTAssertEqual(presentation.primary.remainingPercent, 76)
        XCTAssertNil(presentation.secondary)
        XCTAssertEqual(presentation.freshness, .fresh)
    }

    func testPresentationClampsMalformedPercentages() {
        let now = Date(timeIntervalSince1970: 1_789_500_000)
        let snapshot = UsageSnapshot(
            observedAt: now,
            primary: UsageWindow(usedPercent: 140, resetsAt: nil),
            secondary: UsageWindow(usedPercent: -5, resetsAt: nil)
        )

        let presentation = snapshot.presentation(now: now)

        XCTAssertEqual(presentation.primary.remainingPercent, 0)
        XCTAssertEqual(presentation.secondary?.remainingPercent, 100)
    }
}
