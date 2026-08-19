import Foundation
import XCTest
@testable import CodexRingCore

final class CodexSessionReaderTests: XCTestCase {
    func testSelectsNewestValidRateLimitEventAcrossDateDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            """
            {"timestamp":"2026-08-17T10:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":64,"resets_at":1789560000}}}}
            """,
            to: root.appending(path: "2026/08/16/rollout-old.jsonl")
        )
        try write(
            """
            {"timestamp":"2026-08-17T11:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":24,"resets_at":1789561363},"secondary":{"used_percent":8,"resets_at":1789900000}}}}
            """,
            to: root.appending(path: "2026/08/17/rollout-new.jsonl")
        )

        let snapshot = try CodexSessionReader().latestSnapshot(in: root)

        XCTAssertEqual(snapshot?.observedAt, Date(timeIntervalSince1970: 1_786_964_400))
        XCTAssertEqual(snapshot?.primary.usedPercent, 24)
        XCTAssertEqual(snapshot?.secondary?.usedPercent, 8)
        XCTAssertEqual(snapshot?.primary.resetsAt, Date(timeIntervalSince1970: 1_789_561_363))
    }

    func testIgnoresMalformedAndNonTokenCountLines() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            """
            {"timestamp":"2026-08-17T12:00:00Z","payload":{"type":"message"}}
            {"timestamp":"not-a-date","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":50}}}}
            {"timestamp":"2026-08-17T13:00:00Z","payload":{"type":"token_count","rate_limits":
            """,
            to: root.appending(path: "2026/08/17/rollout-invalid.jsonl")
        )

        XCTAssertNil(try CodexSessionReader().latestSnapshot(in: root))
    }

    func testBoundsSearchToRecentDateDirectories() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            """
            {"timestamp":"2026-07-01T12:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":1}}}}
            """,
            to: root.appending(path: "2026/07/01/rollout-old.jsonl")
        )
        try write(
            """
            {"timestamp":"2026-08-17T10:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":24}}}}
            """,
            to: root.appending(path: "2026/08/17/rollout-current.jsonl")
        )

        let snapshot = try CodexSessionReader().latestSnapshot(
            in: root,
            now: Date(timeIntervalSince1970: 1_786_924_800),
            lookbackDays: 14
        )

        XCTAssertEqual(snapshot?.primary.usedPercent, 24)
    }

    func testParsesFractionalSecondSessionTimestamp() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            """
            {"timestamp":"2026-08-17T14:45:59.682Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":24}}}}
            """,
            to: root.appending(path: "2026/08/17/rollout-fractional.jsonl")
        )

        let snapshot = try CodexSessionReader().latestSnapshot(
            in: root,
            now: Date(timeIntervalSince1970: 1_786_924_800),
            lookbackDays: 14
        )

        XCTAssertEqual(snapshot?.primary.usedPercent, 24)
        XCTAssertEqual(snapshot?.observedAt, Date(timeIntervalSince1970: 1_786_977_959.682))
    }

    func testIgnoresNewerModelSpecificLimitWhenReadingMainCodexLimit() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            """
            {"timestamp":"2026-08-17T10:00:00Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":70}}}}
            {"timestamp":"2026-08-17T11:00:00Z","payload":{"type":"token_count","rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":0}}}}
            """,
            to: root.appending(path: "2026/08/17/rollout-mixed-limits.jsonl")
        )

        let snapshot = try CodexSessionReader().latestSnapshot(
            in: root,
            now: Date(timeIntervalSince1970: 1_786_924_800),
            lookbackDays: 14
        )

        XCTAssertEqual(snapshot?.primary.usedPercent, 70)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
