import XCTest
@testable import CodexRingCore

final class E01DisplayPreparationTests: XCTestCase {
    func testMediaTransferAuthenticatesRCSPImmediatelyAfterBadgeInfo() {
        XCTAssertEqual(
            E01DisplayPreparation.nextStepAfterBadgeInfo(),
            .authenticateRCSP
        )
    }
}
