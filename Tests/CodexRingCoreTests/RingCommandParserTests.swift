import Foundation
import XCTest
@testable import CodexRingCore

final class RingCommandParserTests: XCTestCase {
    func testPreviewUsesSpecifiedPathsAndCanvasSize() throws {
        let command = try RingCommandParser.parse(
            arguments: [
                "preview",
                "--sessions", "/tmp/sessions",
                "--output", "/tmp/card.png",
                "--width", "466",
                "--height", "466",
            ],
            homeDirectory: URL(filePath: "/Users/example"),
            workingDirectory: URL(filePath: "/tmp/project")
        )

        XCTAssertEqual(command.kind, .preview)
        XCTAssertEqual(command.options.sessionsDirectory.path, "/tmp/sessions")
        XCTAssertEqual(command.options.outputURL.path, "/tmp/card.png")
        XCTAssertEqual(command.options.size, CGSize(width: 466, height: 466))
    }

    func testWatchNeverRefreshesMoreOftenThanThirtySeconds() throws {
        let command = try RingCommandParser.parse(
            arguments: ["watch", "--interval", "2"],
            homeDirectory: URL(filePath: "/Users/example"),
            workingDirectory: URL(filePath: "/tmp/project")
        )

        XCTAssertEqual(command.kind, .watch)
        XCTAssertEqual(command.options.interval, 30)
    }

    func testRejectsOutOfRangeCanvasSize() {
        XCTAssertThrowsError(
            try RingCommandParser.parse(
                arguments: ["preview", "--width", "63"],
                homeDirectory: URL(filePath: "/Users/example"),
                workingDirectory: URL(filePath: "/tmp/project")
            )
        )
    }

    func testScanUsesBoundedTimeout() throws {
        let command = try RingCommandParser.parse(
            arguments: ["scan", "--timeout", "10"],
            homeDirectory: URL(filePath: "/Users/example"),
            workingDirectory: URL(filePath: "/tmp/project")
        )

        XCTAssertEqual(command.kind, .scan)
        XCTAssertEqual(command.options.scanTimeout, 10)
    }

    func testBindUsesTheSameBoundedTimeoutOption() throws {
        let command = try RingCommandParser.parse(
            arguments: ["bind", "--timeout", "12"],
            homeDirectory: URL(filePath: "/Users/example"),
            workingDirectory: URL(filePath: "/tmp/project")
        )

        XCTAssertEqual(command.kind, .bind)
        XCTAssertEqual(command.options.scanTimeout, 12)
    }

    func testDisplayIsAnExplicitLiveMediaCommand() throws {
        let command = try RingCommandParser.parse(
            arguments: ["display", "--timeout", "30"],
            homeDirectory: URL(filePath: "/Users/example"),
            workingDirectory: URL(filePath: "/tmp/project")
        )

        XCTAssertEqual(command.kind, .display)
        XCTAssertEqual(command.options.scanTimeout, 30)
    }

    func testDisplayWatchUsesTheBoundedRefreshInterval() throws {
        let command = try RingCommandParser.parse(
            arguments: ["display-watch", "--interval", "5", "--timeout", "30"],
            homeDirectory: URL(filePath: "/Users/example"),
            workingDirectory: URL(filePath: "/tmp/project")
        )

        XCTAssertEqual(command.kind, .displayWatch)
        XCTAssertEqual(command.options.interval, 30)
        XCTAssertEqual(command.options.scanTimeout, 30)
    }
}
