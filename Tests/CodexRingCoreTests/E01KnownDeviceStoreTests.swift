import Foundation
import XCTest
@testable import CodexRingCore

final class E01KnownDeviceStoreTests: XCTestCase {
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
