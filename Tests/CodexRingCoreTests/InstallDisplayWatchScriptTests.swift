import Foundation
import XCTest

final class InstallDisplayWatchScriptTests: XCTestCase {
    func testInstallerCopiesTheSwiftPMResourceBundleBesideTheExecutable() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let installerURL = repositoryRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("install-display-watch.zsh")
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let buildDirectory = fixtureRoot.appendingPathComponent("build", isDirectory: true)
        let sourceBinary = buildDirectory.appendingPathComponent("codex-ring")
        let sourceBundle = buildDirectory.appendingPathComponent(
            "CodexRing_CodexRingCore.bundle",
            isDirectory: true
        )
        let destination = fixtureRoot.appendingPathComponent("runtime", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try FileManager.default.createDirectory(
            at: sourceBundle,
            withIntermediateDirectories: true
        )
        try Data("#!/bin/zsh\n".utf8).write(to: sourceBinary)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: sourceBinary.path
        )
        try Data("auth fixture".utf8).write(
            to: sourceBundle.appendingPathComponent("jl_auth_2.0.0.js")
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [installerURL.path, "--stage-runtime", destination.path]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "E01_BUILD_BINARY": sourceBinary.path,
            "E01_BUILD_RESOURCES": sourceBundle.path,
        ]) { _, override in override }
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let application = destination.appendingPathComponent("CodexRing.app", isDirectory: true)
        let executable = application
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent("codex-ring")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: executable.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: application
                    .appendingPathComponent("Contents/Resources", isDirectory: true)
                    .appendingPathComponent("jl_auth_2.0.0.js")
                    .path
            )
        )
        let info = try XCTUnwrap(
            NSDictionary(
                contentsOf: application.appendingPathComponent("Contents/Info.plist")
            ) as? [String: Any]
        )
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "com.lucien.e01-codex-ring")
        XCTAssertEqual(info["CFBundleExecutable"] as? String, "codex-ring")
        XCTAssertNotNil(info["NSBluetoothAlwaysUsageDescription"] as? String)
    }
}
