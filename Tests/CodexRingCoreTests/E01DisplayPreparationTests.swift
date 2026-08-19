import XCTest
@testable import CodexRingCore

final class E01DisplayPreparationTests: XCTestCase {
    func testMediaTransferAuthenticatesRCSPImmediatelyAfterBadgeInfo() {
        XCTAssertEqual(
            E01DisplayPreparation.nextStepAfterBadgeInfo(),
            .authenticateRCSP
        )
    }

    func testMediaTransferQueriesStorageImmediatelyAfterAuthentication() {
        XCTAssertEqual(
            E01DisplayPreparation.nextStepAfterAuthentication(
                hasMedia: true,
                cleanupFileName: nil,
                shouldFormatMedia: false
            ),
            .queryStorage
        )
    }

    func testExplicitProbeStillInspectsTargetInfoAfterAuthentication() {
        XCTAssertEqual(
            E01DisplayPreparation.nextStepAfterAuthentication(
                hasMedia: false,
                cleanupFileName: nil,
                shouldFormatMedia: false
            ),
            .inspectTargetInfo
        )
    }

    func testCleanupDeletesFileImmediatelyAfterAuthentication() {
        XCTAssertEqual(
            E01DisplayPreparation.nextStepAfterAuthentication(
                hasMedia: false,
                cleanupFileName: "CODEXA.AVI",
                shouldFormatMedia: false
            ),
            .deleteFile("CODEXA.AVI")
        )
    }

    func testFormatQueriesStorageImmediatelyAfterAuthentication() {
        XCTAssertEqual(
            E01DisplayPreparation.nextStepAfterAuthentication(
                hasMedia: false,
                cleanupFileName: nil,
                shouldFormatMedia: true
            ),
            .queryStorage
        )
    }
}
