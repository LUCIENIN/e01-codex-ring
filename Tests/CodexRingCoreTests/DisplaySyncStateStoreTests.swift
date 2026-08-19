import Foundation
import XCTest
@testable import CodexRingCore

final class DisplaySyncStateStoreTests: XCTestCase {
    func testRoundTripsTheLastSuccessfulDisplayState() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DisplaySyncStateStore(url: root.appending(path: "display-state.json"))
        var state = DisplaySyncState()
        state.recordSuccessfulPush(
            remainingPercent: 32,
            at: Date(timeIntervalSince1970: 1_000),
            activeMediaFileName: "CODEXA001.AVI"
        )

        try store.save(state)

        XCTAssertEqual(try store.load(), state)
    }

    func testMissingStateStartsFreshAndMalformedStateIsReported() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "display-state.json")
        let store = DisplaySyncStateStore(url: url)

        XCTAssertNil(try store.load())
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "not-json".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load())
    }
}
