import XCTest
@testable import CodexRingCore

final class E01BindRequestTests: XCTestCase {
    func testPayloadUsesVendorFlagBitsForLocaleAndClockFormat() {
        XCTAssertEqual(
            E01BindRequest(
                timestampMilliseconds: 0,
                usesNonChineseLocale: false,
                uses12HourClock: false
            ).payload,
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        )

        XCTAssertEqual(
            E01BindRequest(
                timestampMilliseconds: 0,
                usesNonChineseLocale: true,
                uses12HourClock: true
            ).payload.first,
            0b0000_0110
        )
    }

    func testPayloadRepeatsTheLowerSixTimestampBytesInLittleEndianOrder() {
        let request = E01BindRequest(
            timestampMilliseconds: 0x1122_3344_5566_7788,
            usesNonChineseLocale: false,
            uses12HourClock: false
        )

        XCTAssertEqual(
            request.payload,
            [0, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33]
        )
    }

    func testBindCommandIsTheVendorBindRequestCommand() {
        XCTAssertEqual(E01BindRequest.command, 0x60)
    }
}
