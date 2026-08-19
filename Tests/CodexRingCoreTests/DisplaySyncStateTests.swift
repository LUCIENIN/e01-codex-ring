import Foundation
import XCTest
@testable import CodexRingCore

final class DisplaySyncStateTests: XCTestCase {
    func testPushesInitiallyAndAfterTheDisplayedPercentageChanges() {
        var state = DisplaySyncState()
        let firstPush = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(
            state.shouldPush(
                remainingPercent: 35,
                now: firstPush,
                maximumUnchangedAge: 300
            )
        )
        state.recordSuccessfulPush(
            remainingPercent: 35,
            at: firstPush,
            activeMediaFileName: "CODEXA.AVI"
        )
        XCTAssertFalse(
            state.shouldPush(
                remainingPercent: 35,
                now: firstPush.addingTimeInterval(299),
                maximumUnchangedAge: 300
            )
        )
        XCTAssertTrue(
            state.shouldPush(
                remainingPercent: 32,
                now: firstPush.addingTimeInterval(30),
                maximumUnchangedAge: 300
            )
        )
    }

    func testReassertsAnUnchangedPercentageAfterTheMaximumAge() {
        var state = DisplaySyncState()
        let firstPush = Date(timeIntervalSince1970: 1_000)
        state.recordSuccessfulPush(
            remainingPercent: 32,
            at: firstPush,
            activeMediaFileName: "CODEXA.AVI"
        )

        XCTAssertFalse(
            state.shouldPush(
                remainingPercent: 32,
                now: firstPush.addingTimeInterval(299),
                maximumUnchangedAge: 300
            )
        )
        XCTAssertTrue(
            state.shouldPush(
                remainingPercent: 32,
                now: firstPush.addingTimeInterval(300),
                maximumUnchangedAge: 300
            )
        )
    }

    func testPushesWhenOnlyTheCompositeQuotaSignatureChanges() {
        var state = DisplaySyncState()
        let firstPush = Date(timeIntervalSince1970: 1_000)
        state.recordSuccessfulPush(
            contentSignature: "codex:32|kimi-week:91|kimi-5h:82",
            at: firstPush,
            activeMediaFileName: "CODEXA.AVI"
        )

        XCTAssertFalse(
            state.shouldPush(
                contentSignature: "codex:32|kimi-week:91|kimi-5h:82",
                now: firstPush.addingTimeInterval(30),
                maximumUnchangedAge: 300
            )
        )
        XCTAssertTrue(
            state.shouldPush(
                contentSignature: "codex:32|kimi-week:90|kimi-5h:82",
                now: firstPush.addingTimeInterval(30),
                maximumUnchangedAge: 300
            )
        )
    }

    func testAlternatesManagedMediaNames() {
        var state = DisplaySyncState()
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(state.nextPreferredMediaFileName, "CODEXA.AVI")
        state.recordSuccessfulPush(
            remainingPercent: 32,
            at: now,
            activeMediaFileName: "CODEXA.AVI"
        )
        XCTAssertEqual(state.nextPreferredMediaFileName, "CODEXB.AVI")
        state.recordSuccessfulPush(
            remainingPercent: 31,
            at: now.addingTimeInterval(30),
            activeMediaFileName: "CODEXB001.AVI"
        )
        XCTAssertEqual(state.nextPreferredMediaFileName, "CODEXA.AVI")
    }

    func testFailedConnectionUsesBoundedBackoff() {
        XCTAssertEqual(
            DisplaySyncSchedule.delay(after: .failed, consecutiveFailures: 1, regularInterval: 30),
            5
        )
        XCTAssertEqual(
            DisplaySyncSchedule.delay(after: .failed, consecutiveFailures: 2, regularInterval: 30),
            15
        )
        XCTAssertEqual(
            DisplaySyncSchedule.delay(after: .failed, consecutiveFailures: 3, regularInterval: 30),
            30
        )
        XCTAssertEqual(
            DisplaySyncSchedule.delay(after: .failed, consecutiveFailures: 20, regularInterval: 30),
            60
        )
        XCTAssertEqual(
            DisplaySyncSchedule.delay(after: .pushed, consecutiveFailures: 0, regularInterval: 30),
            30
        )
    }
}
