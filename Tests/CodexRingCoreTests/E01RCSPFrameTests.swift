import Foundation
import XCTest
@testable import CodexRingCore

final class E01RCSPFrameTests: XCTestCase {
    func testEncodesGetTargetInfoRequestLikeOfficialRCSPPacketBuilder() {
        XCTAssertEqual(
            E01RCSPFrame.command(
                opcode: 0x03,
                serialNumber: 0,
                parameter: [0xFF, 0xFF, 0xFF, 0xFF, 0x00]
            ),
            [
                0xFE, 0xDC, 0xBA,
                0xC0, 0x03, 0x00, 0x06,
                0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x00,
                0xEF,
            ]
        )
    }

    func testParsesOneCompleteResponseAndPreservesRemainder() {
        var parser = E01RCSPFrame.Parser()

        XCTAssertTrue(parser.append([0x00, 0xFE, 0xDC]).isEmpty)
        let packets = parser.append([
            0xBA, 0x00, 0x03, 0x00, 0x03, 0x00, 0x00, 0x11, 0xEF,
            0xFE, 0xDC,
        ])

        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].opcode, 0x03)
        XCTAssertEqual(packets[0].serialNumber, 0)
        XCTAssertEqual(packets[0].status, 0)
        XCTAssertEqual(packets[0].parameter, [0x11])

        let second = parser.append([
            0xBA, 0x00, 0x21, 0x00, 0x02, 0x00, 0x01, 0xEF,
        ])
        XCTAssertEqual(second.map(\.opcode), [0x21])
    }

    func testRejectsInvalidTailWithoutLosingFollowingPacket() {
        var parser = E01RCSPFrame.Parser()
        let packets = parser.append([
            0xFE, 0xDC, 0xBA, 0x00, 0x03, 0x00, 0x02, 0x00, 0x00, 0xEE,
            0xFE, 0xDC, 0xBA, 0x00, 0x03, 0x00, 0x02, 0x00, 0x00, 0xEF,
        ])
        XCTAssertEqual(packets.map(\.opcode), [0x03])
    }

    func testEncodesResponseToDeviceCommand() {
        XCTAssertEqual(
            E01RCSPFrame.response(
                opcode: 0x20,
                serialNumber: 7,
                status: 0,
                parameter: [0x41, 0x56, 0x49]
            ),
            [0xFE, 0xDC, 0xBA, 0x00, 0x20, 0x00, 0x05, 0x00, 0x07, 0x41, 0x56, 0x49, 0xEF]
        )
    }
}
