import Foundation

public enum E01KnownDeviceRecovery {
    public static func shouldClearAfterTimeout(
        stage: String,
        consecutiveFailures: Int
    ) -> Bool {
        guard consecutiveFailures >= 3 else { return false }
        switch stage {
        case "connecting",
             "discovering_service",
             "discovering_characteristics",
             "enabling_primary_notification",
             "enabling_auxiliary_notification",
             "enabling_rcsp_notification",
             "writing_bind_request",
             "waiting_for_bind_response":
            return true
        default:
            return false
        }
    }

    public static func stageTimeout(for stage: String) -> TimeInterval? {
        switch stage {
        case "waiting_for_bluetooth", "connecting":
            return 15
        case "scanning":
            return 30
        default:
            return nil
        }
    }
}

public struct E01KnownDeviceStore: Sendable {
    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".codex/e01-known-device-id")

    private let url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    public func load() -> UUID? {
        guard let value = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func save(_ identifier: UUID) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "\(identifier.uuidString)\n".write(to: url, atomically: true, encoding: .utf8)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
