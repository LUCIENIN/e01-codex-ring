import Foundation

public struct DisplaySyncState: Equatable, Sendable {
    private var lastPushedRemainingPercent: Int?

    public init() {}

    public func shouldPush(remainingPercent: Int) -> Bool {
        lastPushedRemainingPercent != remainingPercent
    }

    public mutating func recordSuccessfulPush(remainingPercent: Int) {
        lastPushedRemainingPercent = remainingPercent
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
        regularInterval: TimeInterval
    ) -> TimeInterval {
        outcome == .failed ? 1 : regularInterval
    }
}
