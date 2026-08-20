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

    func testCleanupPreparesTheDeletionEnvironmentAfterAuthentication() {
        XCTAssertEqual(
            E01DisplayPreparation.nextStepAfterAuthentication(
                hasMedia: false,
                cleanupFileName: "CODEXA.AVI",
                shouldFormatMedia: false
            ),
            .prepareDeletion("CODEXA.AVI")
        )
    }

    func testReplacementContinuesToStorageAfterDeletingTheActiveFile() {
        XCTAssertEqual(
            E01DisplayPreparation.nextStepAfterDeletion(hasMedia: true),
            .queryStorage
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
