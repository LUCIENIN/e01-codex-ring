import XCTest
@testable import CodexRingCore

final class E01VideoDialProtocolTests: XCTestCase {
    func testWrapsAVIInTheVendorVideoDialEnvelope() {
        let wrapped = E01VideoDialProtocol.wrapAVI(
            [0x52, 0x49, 0x46, 0x46],
            width: 368,
            height: 368,
            backgroundSupportFlag: 1
        )

        XCTAssertEqual(Array(wrapped.prefix(27)), [
            0xBC, 0xAF, 0x0C, 0x01, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x0C, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x4C, 0x2A,
        ])
        XCTAssertEqual(Array(wrapped.dropFirst(27)), [
            0x41, 0x56, 0x70, 0x01, 0x70, 0x01, 0x10, 0x80,
            0x52, 0x49, 0x46, 0x46,
        ])
    }

    func testUsesElectronicBadgeVideoHeaderWhenAnimationFlagIsDisabled() {
        let wrapped = E01VideoDialProtocol.wrapAVI(
            [0x52, 0x49, 0x46, 0x46],
            width: 368,
            height: 368,
            backgroundSupportFlag: 0,
            usesAnimatedHeader: false
        )

        XCTAssertEqual(Array(wrapped[27...28]), [0x30, 0x56])
    }

    func testWrapsRGB565AsAStaticDial() {
        let wrapped = E01VideoDialProtocol.wrapRGB565(
            [0xF8, 0x00, 0x07, 0xE0],
            width: 2,
            height: 1,
            dialIndex: 0
        )

        XCTAssertEqual(Array(wrapped[27..<35]), [0x42, 0x4D, 0x02, 0x00, 0x01, 0x00, 0x10, 0x80])
        XCTAssertEqual(Array(wrapped.suffix(4)), [0xF8, 0x00, 0x07, 0xE0])
        XCTAssertEqual(wrapped[2], 0x05)
    }

    func testBuildsAndParsesTheUpdateHandshake() {
        let header = [UInt8](repeating: 0, count: 27)
        XCTAssertEqual(
            E01VideoDialProtocol.commandPacket(
                command: 0xC0,
                payload: header,
                serialNumber: 0
            ).prefix(6),
            [0x9E, 0xE0, 0x05, 0xC0, 0x1B, 0x00]
        )

        let request = E01NormalDataFrame.packet(
            command: 0xC1,
            payload: [0x01, 0xF4, 0x01, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00],
            serialNumber: 4
        )
        XCTAssertEqual(
            E01VideoDialProtocol.parseUpdateRequest(request),
            .init(status: 1, allowedLength: 500, offset: 32)
        )

        let progress = E01NormalDataFrame.packet(
            command: 0xC3,
            payload: [0x00, 0x08, 0x01, 0x00, 0x00],
            serialNumber: 5
        )
        XCTAssertEqual(
            E01VideoDialProtocol.parseProgress(progress),
            .init(status: 0, offset: 264)
        )
    }
}
