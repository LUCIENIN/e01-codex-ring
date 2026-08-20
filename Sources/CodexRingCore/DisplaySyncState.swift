import Foundation

public struct DisplaySyncMediaUpdate: Equatable, Sendable {
    public let fileNameToReplace: String?
    public let destinationFileName: String
}

public struct DisplaySyncState: Codable, Equatable, Sendable {
    private var lastPushedRemainingPercent: Int?
    private var lastPushedContentSignature: String?
    private var lastSuccessfulPushAt: Date?
    public private(set) var activeMediaFileName: String?

    public init() {}

    public func shouldPush(
        remainingPercent: Int,
        now: Date,
        maximumUnchangedAge: TimeInterval
    ) -> Bool {
        guard lastPushedRemainingPercent == remainingPercent,
              let lastSuccessfulPushAt
        else {
            return true
        }
        return now.timeIntervalSince(lastSuccessfulPushAt) >= max(1, maximumUnchangedAge)
    }

    public mutating func recordSuccessfulPush(
        remainingPercent: Int,
        at date: Date,
        activeMediaFileName: String
    ) {
        lastPushedRemainingPercent = remainingPercent
        lastSuccessfulPushAt = date
        self.activeMediaFileName = activeMediaFileName
    }

    public func shouldPush(
        contentSignature: String,
        now: Date,
        maximumUnchangedAge: TimeInterval
    ) -> Bool {
        guard lastPushedContentSignature == contentSignature,
              let lastSuccessfulPushAt
        else {
            return true
        }
        return now.timeIntervalSince(lastSuccessfulPushAt) >= max(1, maximumUnchangedAge)
    }

    public mutating func recordSuccessfulPush(
        contentSignature: String,
        at date: Date,
        activeMediaFileName: String
    ) {
        lastPushedContentSignature = contentSignature
        lastSuccessfulPushAt = date
        self.activeMediaFileName = activeMediaFileName
    }

    public var nextPreferredMediaFileName: String {
        if activeMediaFileName?.uppercased().hasPrefix("CODEXA") == true {
            return "CODEXB.JPG"
        }
        return "CODEXA.JPG"
    }

    public var nextMediaUpdate: DisplaySyncMediaUpdate {
        DisplaySyncMediaUpdate(
            fileNameToReplace: activeMediaFileName,
            destinationFileName: nextPreferredMediaFileName
        )
    }
}

public struct DisplaySyncStateStore: Sendable {
    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".codex/e01-display-sync-state.json")

    private let url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    public func load() throws -> DisplaySyncState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(DisplaySyncState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: DisplaySyncState) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}

public enum DisplaySyncCycleOutcome: Equatable, Sendable {
    case pushed
    case unchanged
    case failed
    case noData
}

public enum DisplaySyncSchedule {
    public static func delay(
        after outcome: DisplaySyncCycleOutcome,
        consecutiveFailures: Int,
        regularInterval: TimeInterval
    ) -> TimeInterval {
        guard outcome == .failed else { return regularInterval }
        let backoff: [TimeInterval] = [5, 15, 30, 60]
        let index = min(max(1, consecutiveFailures), backoff.count) - 1
        return backoff[index]
    }
}
