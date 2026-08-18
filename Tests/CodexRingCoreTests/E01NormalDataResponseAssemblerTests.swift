import XCTest
@testable import CodexRingCore

final class E01NormalDataResponseAssemblerTests: XCTestCase {
    private let completeBindFrame: [UInt8] = [
        0x9E, 0x79, 0x04, 0x61, 0x17, 0x00,
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
        0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16,
    ]

    func testReturnsACompleteChecksummedFrameFromOneNotification() {
        var assembler = E01NormalDataResponseAssembler()

        XCTAssertEqual(assembler.append(completeBindFrame), completeBindFrame)
    }

    func testReassemblesAFrameFromTheHeaderFragmentAndRawContinuation() {
        var assembler = E01NormalDataResponseAssembler()

        XCTAssertNil(assembler.append(Array(completeBindFrame.prefix(20))))
        XCTAssertEqual(assembler.append(Array(completeBindFrame.dropFirst(20))), completeBindFrame)
    }

    func testDropsABadChecksumAndCanAcceptTheNextValidFrame() {
        var assembler = E01NormalDataResponseAssembler()
        var corrupted = completeBindFrame
        corrupted[1] = 0x89

        XCTAssertNil(assembler.append(Array(corrupted.prefix(20))))
        XCTAssertNil(assembler.append(Array(corrupted.dropFirst(20))))
        XCTAssertEqual(assembler.append(completeBindFrame), completeBindFrame)
    }
}
