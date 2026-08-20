import XCTest
@testable import CodexRingCore

final class E01ManagedMediaPolicyTests: XCTestCase {
    func testRecognizesOnlyNamesGeneratedByThisProject() {
        XCTAssertTrue(E01ManagedMediaPolicy.isManagedFileName("codex_push.avi"))
        XCTAssertTrue(E01ManagedMediaPolicy.isManagedFileName("badge001.avi"))
        XCTAssertTrue(E01ManagedMediaPolicy.isManagedFileName("CODEXB003.AVI"))
        XCTAssertTrue(E01ManagedMediaPolicy.isManagedFileName("CODEXA.JPG"))

        XCTAssertFalse(E01ManagedMediaPolicy.isManagedFileName("factory.avi"))
        XCTAssertFalse(E01ManagedMediaPolicy.isManagedFileName("BAG"))
        XCTAssertFalse(E01ManagedMediaPolicy.isManagedFileName("../CODEXA.AVI"))
    }

    func testPreflightCleanupPreservesTheActiveCardAndRemovesDestinationConflicts() {
        let entries = [
            mediaEntry(cluster: 10, name: "CODEXB.AVI"),
            mediaEntry(cluster: 20, name: "CODEXA.AVI"),
            mediaEntry(cluster: 30, name: "badge001.avi"),
        ]

        XCTAssertEqual(
            E01ManagedMediaPolicy.filesToDeleteBeforeUpload(
                entries,
                activeFileName: "CODEXB.AVI",
                destinationFileName: "CODEXA.AVI"
            ).map(\.cluster),
            [20, 30]
        )
    }

    func testPreflightCleanupKeepsTheOnlyExistingCardWhenDestinationIsDifferent() {
        let entries = [mediaEntry(cluster: 10, name: "badge.avi")]

        XCTAssertTrue(
            E01ManagedMediaPolicy.filesToDeleteBeforeUpload(
                entries,
                activeFileName: "CODEXB003.AVI",
                destinationFileName: "CODEXA.AVI"
            ).isEmpty
        )
    }

    func testPostCommitCleanupKeepsOnlyTheNewlyCommittedCard() {
        let entries = [
            mediaEntry(cluster: 10, name: "CODEXB.AVI"),
            mediaEntry(cluster: 20, name: "CODEXA.AVI"),
        ]

        XCTAssertEqual(
            E01ManagedMediaPolicy.filesToDeleteAfterUpload(
                entries,
                committedFileName: "codexa.avi"
            ).map(\.cluster),
            [10]
        )
    }

    private func mediaEntry(cluster: UInt32, name: String) -> E01FileBrowseEntry {
        E01FileBrowseEntry(
            isFile: true,
            deviceIndex: 0,
            cluster: cluster,
            name: name
        )
    }
}
