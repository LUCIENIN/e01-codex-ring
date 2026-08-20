import XCTest
@testable import CodexRingCore

final class E01FileBrowseProtocolTests: XCTestCase {
    func testRootBrowseParameterTargetsTheReportedStorageHandle() {
        XCTAssertEqual(
            E01FileBrowseProtocol.rootBrowseParameter(deviceHandler: 2),
            [
                0x00, 0x0A, 0x00, 0x01,
                0x00, 0x00, 0x00, 0x02,
                0x00, 0x04,
                0x00, 0x00, 0x00, 0x00,
            ]
        )
    }

    func testFolderBrowseParameterIncludesTheFullClusterPath() {
        XCTAssertEqual(
            E01FileBrowseProtocol.browseParameter(
                deviceHandler: 2,
                pathClusters: [0, 2],
                offset: 11,
                readCount: 50
            ),
            [
                0x00, 0x32, 0x00, 0x0B,
                0x00, 0x00, 0x00, 0x02,
                0x00, 0x08,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x02,
            ]
        )
    }

    func testParsesAnASCIIManagedMediaEntryFromTheBrowseStream() throws {
        let entries = try E01FileBrowseProtocol.parseEntries([
            0x0B,
            0x00, 0x00, 0x12, 0x34,
            0x00, 0x01,
            0x0D,
            0x43, 0x4F, 0x44, 0x45, 0x58, 0x42, 0x30, 0x30, 0x33, 0x2E, 0x41, 0x56, 0x49,
        ])

        XCTAssertEqual(
            entries,
            [E01FileBrowseEntry(isFile: true, deviceIndex: 2, cluster: 0x1234, name: "CODEXB003.AVI")]
        )
    }

    func testRejectsATruncatedBrowseEntry() {
        XCTAssertThrowsError(
            try E01FileBrowseProtocol.parseEntries([
                0x0B, 0x00, 0x00, 0x12, 0x34, 0x00, 0x01, 0x0D, 0x43,
            ])
        )
    }

    func testClusterDeleteParameterTargetsOneFileOnTheStorageHandle() {
        XCTAssertEqual(
            E01FileBrowseProtocol.clusterDeleteParameter(
                deviceHandler: 2,
                entryType: 1,
                cluster: 0x1234,
                isLast: true
            ),
            [
                0x01,
                0x00, 0x00, 0x00, 0x02,
                0x01,
                0x00, 0x00, 0x12, 0x34,
            ]
        )
    }

    func testClusterDeletionPlanDeletesInReverseOrderAndMarksOnlyTheFinalCommand() {
        let entries = [
            E01FileBrowseEntry(isFile: true, deviceIndex: 2, cluster: 3, name: "CODEXA.AVI"),
            E01FileBrowseEntry(isFile: true, deviceIndex: 2, cluster: 10, name: "CODEXB.AVI"),
        ]

        XCTAssertEqual(
            E01FileBrowseProtocol.clusterDeletionParameters(
                deviceHandler: 2,
                entries: entries
            ),
            [
                [0x00, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x00, 0x00, 0x0A],
                [0x01, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x00, 0x00, 0x03],
            ]
        )
    }
}
