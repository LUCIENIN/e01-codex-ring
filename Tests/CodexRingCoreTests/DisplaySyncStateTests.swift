import XCTest
@testable import CodexRingCore

final class DisplaySyncStateTests: XCTestCase {
    func testPushesInitiallyAndOnlyAfterTheDisplayedPercentageChanges() {
        var state = DisplaySyncState()

        XCTAssertTrue(state.shouldPush(remainingPercent: 35))
        state.recordSuccessfulPush(remainingPercent: 35)
        XCTAssertFalse(state.shouldPush(remainingPercent: 35))
        XCTAssertTrue(state.shouldPush(remainingPercent: 32))
    }

    func testFailedPushDoesNotSuppressTheNextRetry() {
        var state = DisplaySyncState()

        XCTAssertTrue(state.shouldPush(remainingPercent: 32))
        XCTAssertTrue(state.shouldPush(remainingPercent: 32))
        state.recordSuccessfulPush(remainingPercent: 32)
        XCTAssertFalse(state.shouldPush(remainingPercent: 32))
    }

    func testFailedConnectionRetriesWithoutAThirtySecondBlindWindow() {
        XCTAssertEqual(DisplaySyncSchedule.delay(after: .failed, regularInterval: 30), 1)
        XCTAssertEqual(DisplaySyncSchedule.delay(after: .pushed, regularInterval: 30), 30)
        XCTAssertEqual(DisplaySyncSchedule.delay(after: .unchanged, regularInterval: 30), 30)
        XCTAssertEqual(DisplaySyncSchedule.delay(after: .noData, regularInterval: 30), 30)
    }
}
