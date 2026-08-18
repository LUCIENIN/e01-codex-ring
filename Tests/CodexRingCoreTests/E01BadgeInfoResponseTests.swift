import XCTest
@testable import CodexRingCore

final class E01BadgeInfoResponseTests: XCTestCase {
    func testParsesSuccessfulBadgePictureDimensionsAndMemory() {
        let frame = E01NormalDataFrame.packet(
            command: 0xC7,
            payload: [0x01, 0x70, 0x01, 0x70, 0x01, 0x70, 0x01, 0x70, 0x01, 0x00, 0x00, 0x10, 0x00],
            serialNumber: 2
        )

        XCTAssertEqual(
            E01BadgeInfoResponse.parse(frame),
            E01BadgeInfo(width: 368, height: 368, pictureWidth: 368, pictureHeight: 368, memoryBytes: 1_048_576)
        )
    }

    func testRejectsFailureStateShortPayloadAndWrongCommand() {
        XCTAssertNil(E01BadgeInfoResponse.parse(E01NormalDataFrame.packet(
            command: 0xC7, payload: [UInt8](repeating: 0, count: 13), serialNumber: 2
        )))
        XCTAssertNil(E01BadgeInfoResponse.parse(E01NormalDataFrame.packet(
            command: 0xC7, payload: [UInt8](repeating: 1, count: 12), serialNumber: 2
        )))
        XCTAssertNil(E01BadgeInfoResponse.parse(E01NormalDataFrame.packet(
            command: 0xC6, payload: [UInt8](repeating: 1, count: 13), serialNumber: 2
        )))
    }
}
