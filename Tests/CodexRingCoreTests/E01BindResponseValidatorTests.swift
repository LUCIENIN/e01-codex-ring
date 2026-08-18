import XCTest
@testable import CodexRingCore

final class E01BindResponseValidatorTests: XCTestCase {
    func testAcceptsAValidatedBindResponseFrame() {
        XCTAssertTrue(E01BindResponseValidator.isExplicitBindResponse([0x9E, 0x62, 0x00, 0x61, 0x01, 0x00, 0x00]))
    }

    func testRejectsRequestsFailuresBadChecksumsAndOtherCommands() {
        XCTAssertFalse(E01BindResponseValidator.isExplicitBindResponse([0x9E, 0x61, 0x00, 0x60, 0x01, 0x00, 0x00]))
        XCTAssertFalse(E01BindResponseValidator.isExplicitBindResponse([0x9E, 0x64, 0x00, 0x61, 0x01, 0x00, 0x02]))
        XCTAssertFalse(E01BindResponseValidator.isExplicitBindResponse([0x9E, 0x63, 0x00, 0x61, 0x01, 0x00, 0x00]))
        XCTAssertFalse(E01BindResponseValidator.isExplicitBindResponse([0x9E, 0x62, 0x00, 0x61]))
    }
}
