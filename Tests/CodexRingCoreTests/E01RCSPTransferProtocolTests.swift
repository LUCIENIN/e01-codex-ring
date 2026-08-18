import XCTest
@testable import CodexRingCore

final class E01RCSPTransferProtocolTests: XCTestCase {
    func testCRC16MatchesXmodemKnownVector() {
        XCTAssertEqual(E01RCSPTransferProtocol.crc16(Array("123456789".utf8)), 0x31C3)
    }

    func testParsesLegacySDCardOneHandlerFromStorageAttribute() {
        let parameter: [UInt8] = [
            0xFF, // function
            0x17, 0x02, // attribute length and storage-info type
            0b0000_0100, // only SD Card 1 is online
            0x00, 0x00, 0x00, 0x10, // USB
            0x00, 0x00, 0x00, 0x20, // SD Card 0
            0x12, 0x34, 0x56, 0x78, // SD Card 1
            0x00, 0x00, 0x00, 0x40, // flash
            0x00, 0x00, 0x00, 0x60, // line-in
            0x00, // reuse flag
        ]

        XCTAssertEqual(
            E01RCSPTransferProtocol.sdCardOneHandler(fromGetSysInfoParameter: parameter),
            0x1234_5678
        )
    }

    func testBuildsTransferSetupParametersInNetworkByteOrder() {
        XCTAssertEqual(
            E01RCSPTransferProtocol.deviceExtendParameter(deviceHandler: 0x1234_5678),
            [0x00, 0x12, 0x34, 0x56, 0x78, 0x01]
        )
        XCTAssertEqual(
            E01RCSPTransferProtocol.startParameter(
                fileSize: 0x0102_0304,
                crc16: 0xA1B2,
                temporaryPath: "CODEXRNG.tmp"
            ),
            [0x01, 0x02, 0x03, 0x04, 0xA1, 0xB2] + Array("CODEXRNG.tmp\0".utf8)
        )
    }

    func testParsesDeviceReadRequest() {
        XCTAssertEqual(
            E01RCSPTransferProtocol.readRequest(from: [0x00, 0x01, 0x00, 0x00, 0x01, 0x23, 0x45]),
            .init(offset: 0x0001_2345, length: 0x0100)
        )
        XCTAssertNil(E01RCSPTransferProtocol.readRequest(from: [0x01, 0, 1, 0, 0, 0, 0]))
    }

    func testSplitsRequestedBufferIntoIndexedCRCProtectedPackets() {
        let data = Array(0..<10).map(UInt8.init)
        let payloads = E01RCSPTransferProtocol.dataPayloads(
            data,
            packetSize: 4,
            usesCRC16: true
        )

        XCTAssertEqual(payloads.count, 3)
        XCTAssertEqual(Array(payloads[0].prefix(3)), [0, 0x61, 0x31])
        XCTAssertEqual(Array(payloads[0].dropFirst(3)), [0, 1, 2, 3])
        XCTAssertEqual(payloads[1][0], 1)
        XCTAssertEqual(Array(payloads[2].dropFirst(3)), [8, 9])
    }
}
