import Foundation
import XCTest
@testable import CodexRingCore

final class E01KnownDeviceStoreTests: XCTestCase {
    func testKeepsKnownDeviceDuringTheFirstTwoPreBindTimeouts() {
        for stage in [
            "connecting",
            "discovering_service",
            "discovering_characteristics",
            "enabling_primary_notification",
            "enabling_auxiliary_notification",
            "enabling_rcsp_notification",
            "writing_bind_request",
            "waiting_for_bind_response",
        ] {
            XCTAssertFalse(
                E01KnownDeviceRecovery.shouldClearAfterTimeout(
                    stage: stage,
                    consecutiveFailures: 1
                ),
                "Unexpected early reset for \(stage)"
            )
            XCTAssertFalse(
                E01KnownDeviceRecovery.shouldClearAfterTimeout(
                    stage: stage,
                    consecutiveFailures: 2
                ),
                "Unexpected second-attempt reset for \(stage)"
            )
        }
    }

    func testClearsKnownDeviceAfterThreeConsecutivePreBindTimeouts() {
        XCTAssertTrue(
            E01KnownDeviceRecovery.shouldClearAfterTimeout(
                stage: "connecting",
                consecutiveFailures: 3
            )
        )
    }

    func testConnectingUsesAShortStageTimeout() {
        XCTAssertEqual(
            E01KnownDeviceRecovery.stageTimeout(for: "connecting"),
            15
        )
        XCTAssertEqual(
            E01KnownDeviceRecovery.stageTimeout(for: "waiting_for_bluetooth"),
            15
        )
        XCTAssertEqual(
            E01KnownDeviceRecovery.stageTimeout(for: "scanning"),
            30
        )
        XCTAssertNil(E01KnownDeviceRecovery.stageTimeout(for: "waiting_for_transfer_requests"))
    }

    func testKeepsKnownDeviceAfterTheBindHandshakeHasCompleted() {
        for stage in [
            "writing_badge_info_request",
            "writing_badge_media_type",
            "writing_rcsp_auth",
            "waiting_for_transfer_requests",
        ] {
            XCTAssertFalse(
                E01KnownDeviceRecovery.shouldClearAfterTimeout(
                    stage: stage,
                    consecutiveFailures: 3
                ),
                "Unexpected recovery for \(stage)"
            )
        }
    }

    func testRoundTripsKnownPeripheralIdentifier() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = E01KnownDeviceStore(url: root.appending(path: "device-id"))
        let identifier = UUID()

        try store.save(identifier)

        XCTAssertEqual(store.load(), identifier)
    }

    func testIgnoresMissingAndMalformedIdentifiers() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "device-id")
        let store = E01KnownDeviceStore(url: url)

        XCTAssertNil(store.load())
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "not-a-uuid\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(store.load())
    }

    func testClearsAStoredIdentifier() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = E01KnownDeviceStore(url: root.appending(path: "device-id"))
        try store.save(UUID())

        try store.clear()

        XCTAssertNil(store.load())
    }
}
