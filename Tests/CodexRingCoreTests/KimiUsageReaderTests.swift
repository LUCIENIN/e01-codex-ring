import Foundation
import XCTest
@testable import CodexRingCore

final class KimiUsageReaderTests: XCTestCase {
    func testLoadsCredentialsOnlyFromTheManagedKimiProvider() throws {
        let config = Data(
            """
            default_model = "kimi-for-coding"

            [providers."unrelated"]
            type = "openai"
            base_url = "https://example.com/v1"
            api_key = "must-not-be-selected"

            [providers."kimi-code-api-key"]
            type = "kimi"
            base_url = "https://api.kimi.com/coding/v1/"
            api_key = "test-kimi-secret"
            """.utf8
        )

        let credentials = try KimiUsageConfiguration.parse(config)

        XCTAssertEqual(credentials.baseURL.absoluteString, "https://api.kimi.com/coding/v1")
        XCTAssertEqual(credentials.apiKey, "test-kimi-secret")
    }

    func testRejectsAProxyBeforeAnApiKeyCanBeSent() throws {
        let config = Data(
            """
            [providers."kimi-code-api-key"]
            type = "kimi"
            base_url = "https://proxy.example.com/coding/v1"
            api_key = "test-kimi-secret"
            """.utf8
        )

        XCTAssertThrowsError(try KimiUsageConfiguration.parse(config)) { error in
            XCTAssertEqual(error as? KimiUsageError, .untrustedBaseURL)
        }
    }

    func testParsesWeeklyAndFiveHourRemainingPercentages() throws {
        let observedAt = Date(timeIntervalSince1970: 1_787_200_000)
        let payload = Data(
            """
            {
              "usage": {
                "used": "9",
                "limit": "100",
                "remaining": "91",
                "resetTime": "2026-08-23T16:49:26.558665Z"
              },
              "limits": [
                {
                  "window": {"duration": "300", "timeUnit": "TIME_UNIT_MINUTE"},
                  "detail": {
                    "used": "18",
                    "limit": "100",
                    "remaining": "82",
                    "resetTime": "2026-08-20T05:49:26.558665Z"
                  }
                }
              ]
            }
            """.utf8
        )

        let snapshot = try KimiUsagePayloadParser.parse(payload, observedAt: observedAt)

        XCTAssertEqual(snapshot.weekly.remainingPercent, 91)
        XCTAssertEqual(snapshot.fiveHour.remainingPercent, 82)
        XCTAssertEqual(snapshot.observedAt, observedAt)
        XCTAssertEqual(
            try XCTUnwrap(snapshot.weekly.resetsAt).timeIntervalSince1970,
            1_787_503_766.558665,
            accuracy: 0.001
        )
    }

    func testRejectsPayloadWithoutBothRequiredQuotaWindows() throws {
        let payload = Data(#"{"usage":{"used":"9","limit":"100"},"limits":[]}"#.utf8)

        XCTAssertThrowsError(
            try KimiUsagePayloadParser.parse(
                payload,
                observedAt: Date(timeIntervalSince1970: 1_787_200_000)
            )
        ) { error in
            XCTAssertEqual(error as? KimiUsageError, .missingQuotaWindow)
        }
    }

    func testDashboardSignatureChangesWhenOnlyKimiUsageChanges() {
        let codex = UsagePresentation(
            primary: DisplayedWindow(remainingPercent: 32, resetsAt: nil),
            secondary: nil,
            freshness: .fresh
        )
        let first = QuotaDashboardPresentation(
            codex: codex,
            kimi: KimiUsagePresentation(
                weekly: DisplayedWindow(remainingPercent: 91, resetsAt: nil),
                fiveHour: DisplayedWindow(remainingPercent: 82, resetsAt: nil),
                freshness: .fresh
            )
        )
        let changed = QuotaDashboardPresentation(
            codex: codex,
            kimi: KimiUsagePresentation(
                weekly: DisplayedWindow(remainingPercent: 90, resetsAt: nil),
                fiveHour: DisplayedWindow(remainingPercent: 82, resetsAt: nil),
                freshness: .fresh
            )
        )

        XCTAssertEqual(
            first.contentSignature,
            "design:glanceable-v2|codex:32|kimi-week:91|kimi-5h:82"
        )
        XCTAssertNotEqual(first.contentSignature, changed.contentSignature)
    }

    func testSanitizedSnapshotCacheSurvivesAServiceRestart() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = KimiUsageSnapshotStore(url: root.appending(path: "kimi-usage.json"))
        let snapshot = KimiUsageSnapshot(
            observedAt: Date(timeIntervalSince1970: 1_787_200_000),
            weekly: KimiUsageQuota(remainingPercent: 91, resetsAt: nil),
            fiveHour: KimiUsageQuota(remainingPercent: 82, resetsAt: nil)
        )

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
        let savedText = try String(contentsOf: root.appending(path: "kimi-usage.json"), encoding: .utf8)
        XCTAssertFalse(savedText.contains("api_key"))
        XCTAssertFalse(savedText.contains("Bearer"))
    }

    func testKimiRefreshIsNotAcceleratedByBluetoothRetryBackoff() {
        let firstAttempt = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(KimiUsageRefreshSchedule.shouldRefresh(lastAttemptAt: nil, now: firstAttempt))
        XCTAssertFalse(
            KimiUsageRefreshSchedule.shouldRefresh(
                lastAttemptAt: firstAttempt,
                now: firstAttempt.addingTimeInterval(29)
            )
        )
        XCTAssertTrue(
            KimiUsageRefreshSchedule.shouldRefresh(
                lastAttemptAt: firstAttempt,
                now: firstAttempt.addingTimeInterval(30)
            )
        )
    }
}
