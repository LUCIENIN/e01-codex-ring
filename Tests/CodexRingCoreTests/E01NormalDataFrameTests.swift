import XCTest
@testable import CodexRingCore

final class E01NormalDataFrameTests: XCTestCase {
    func testFirstBindPacketUsesOnlyTheNormalDataEnvelope() {
        let request = E01BindRequest(
            timestampMilliseconds: 0,
            usesNonChineseLocale: false,
            uses12HourClock: false
        )

        XCTAssertEqual(
            E01NormalDataFrame.firstBindPacket(request),
            [
                0x9E, 0x73,
                0x06, 0x60, 0x0D, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            ]
        )
    }

    func testPacketChecksumIsTheModulo256SumOfTheEncapsulatedData() {
        let request = E01BindRequest(
            timestampMilliseconds: 0x0000_0000_0000_0001,
            usesNonChineseLocale: true,
            uses12HourClock: true
        )
        let packet = E01NormalDataFrame.firstBindPacket(request)

        XCTAssertEqual(packet[0], 0x9E)
        XCTAssertEqual(packet[1], packet.dropFirst(2).reduce(0, &+))
        XCTAssertEqual(packet[2], 0x06)
        XCTAssertEqual(packet[3], E01BindRequest.command)
        XCTAssertEqual(packet[4...5], [0x0D, 0x00])
    }

    func testPictureSizeRequestUsesTheNextSerialNumberAndNormalCommandEnvelope() {
        let packet = E01NormalDataFrame.packet(command: 0xDA, payload: [], serialNumber: 1)

        XCTAssertEqual(packet, [0x9E, 0xE8, 0x0E, 0xDA, 0x00, 0x00])
    }

    func testVideoInfoRequestUsesTheVendorRequestFlag() {
        let packet = E01NormalDataFrame.requestPacket(command: 0x49, payload: [], serialNumber: 2)

        XCTAssertEqual(packet, [0x9E, 0xDB, 0x92, 0x49, 0x00, 0x00])
    }

    func testBadgeInfoRequestUsesNormalDataCharacteristic() {
        let packet = E01NormalDataFrame.packet(command: 0xC6, payload: [0x01], serialNumber: 1)

        XCTAssertEqual(packet, [0x9E, 0xD6, 0x0E, 0xC6, 0x01, 0x00, 0x01])
    }
}
