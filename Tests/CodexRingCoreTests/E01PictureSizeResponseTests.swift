import XCTest
@testable import CodexRingCore

final class E01PictureSizeResponseTests: XCTestCase {
    func testParsesMapDimensionsFromVendorBigEndianPayload() {
        var payload = [UInt8](repeating: 0, count: 24)
        payload[16] = 0x01
        payload[17] = 0xD2
        payload[18] = 0x01
        payload[19] = 0xD2
        let frame = E01NormalDataFrame.packet(command: 0xDB, payload: payload, serialNumber: 2)

        XCTAssertEqual(E01PictureSizeResponse.parse(frame), E01PictureSize(width: 466, height: 466))
    }

    func testRejectsWrongCommandShortPayloadAndZeroDimensions() {
        XCTAssertNil(E01PictureSizeResponse.parse(E01NormalDataFrame.packet(
            command: 0xDA,
            payload: [UInt8](repeating: 1, count: 24),
            serialNumber: 2
        )))
        XCTAssertNil(E01PictureSizeResponse.parse(E01NormalDataFrame.packet(
            command: 0xDB,
            payload: [UInt8](repeating: 1, count: 19),
            serialNumber: 2
        )))
        XCTAssertNil(E01PictureSizeResponse.parse(E01NormalDataFrame.packet(
            command: 0xDB,
            payload: [UInt8](repeating: 0, count: 24),
            serialNumber: 2
        )))
    }
}
