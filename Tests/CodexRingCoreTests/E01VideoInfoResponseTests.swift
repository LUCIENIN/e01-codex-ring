import XCTest
@testable import CodexRingCore

final class E01VideoInfoResponseTests: XCTestCase {
    func testParsesLittleEndianVideoDimensions() {
        let frame = E01NormalDataFrame.packet(
            command: 0x49,
            payload: [0x70, 0x01, 0x70, 0x01, 0x01, 0x00, 0x00, 0x00],
            serialNumber: 3
        )

        XCTAssertEqual(E01VideoInfoResponse.parse(frame), E01PictureSize(width: 368, height: 368))
        XCTAssertEqual(
            E01VideoInfoResponse.parseDetails(frame),
            E01VideoDialInfo(
                size: E01PictureSize(width: 368, height: 368),
                backgroundSupportFlag: 1,
                backgroundStateFlag: 0
            )
        )
    }

    func testRejectsWrongCommandShortPayloadAndZeroDimensions() {
        XCTAssertNil(E01VideoInfoResponse.parse(E01NormalDataFrame.packet(
            command: 0x48, payload: [UInt8](repeating: 1, count: 8), serialNumber: 3
        )))
        XCTAssertNil(E01VideoInfoResponse.parse(E01NormalDataFrame.packet(
            command: 0x49, payload: [UInt8](repeating: 1, count: 7), serialNumber: 3
        )))
        XCTAssertNil(E01VideoInfoResponse.parse(E01NormalDataFrame.packet(
            command: 0x49, payload: [UInt8](repeating: 0, count: 8), serialNumber: 3
        )))
    }
}
