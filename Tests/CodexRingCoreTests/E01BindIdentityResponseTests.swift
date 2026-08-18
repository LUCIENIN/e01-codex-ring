import XCTest
@testable import CodexRingCore

final class E01BindIdentityResponseTests: XCTestCase {
    func testParsesOfficialBindIdentityLayout() {
        let payload: [UInt8] = [
            0x00,
            0x32, 0x2E, 0x39,
            0x56, 0x31, 0x2E, 0x32, 0x2E, 0x33, 0x00, 0x00, 0x00, 0x00,
            0x07,
            0xB3, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        let frame = E01NormalDataFrame.packet(command: 0x61, payload: payload, serialNumber: 0)

        XCTAssertEqual(
            E01BindIdentityResponse.parse(frame),
            .init(protocolVersion: "2.9", firmwareVersion: "V1.2.3", platform: 7, modelNumber: 179)
        )
    }

    func testRejectsShortOrFailedResponses() {
        XCTAssertNil(E01BindIdentityResponse.parse(
            E01NormalDataFrame.packet(command: 0x61, payload: [0], serialNumber: 0)
        ))
        XCTAssertNil(E01BindIdentityResponse.parse(
            E01NormalDataFrame.packet(command: 0x61, payload: [2], serialNumber: 0)
        ))
    }
}
