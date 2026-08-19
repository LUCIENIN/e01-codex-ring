import Foundation

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
