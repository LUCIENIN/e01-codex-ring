import Foundation

public struct UsageWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let observedAt: Date
    public let primary: UsageWindow
    public let secondary: UsageWindow?

    public init(observedAt: Date, primary: UsageWindow, secondary: UsageWindow?) {
        self.observedAt = observedAt
        self.primary = primary
        self.secondary = secondary
    }

    public func presentation(now: Date) -> UsagePresentation {
        UsagePresentation(
            primary: DisplayedWindow(
                remainingPercent: Self.remainingPercent(from: primary.usedPercent),
                resetsAt: primary.resetsAt
            ),
            secondary: secondary.map {
                DisplayedWindow(
                    remainingPercent: Self.remainingPercent(from: $0.usedPercent),
                    resetsAt: $0.resetsAt
                )
            },
            freshness: now.timeIntervalSince(observedAt) > 600 ? .stale : .fresh
        )
    }

    private static func remainingPercent(from usedPercent: Double) -> Int {
        Int((100 - usedPercent).rounded()).clamped(to: 0...100)
    }
}

public enum Freshness: Equatable, Sendable {
    case fresh
    case stale
    case unavailable
}

public struct DisplayedWindow: Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: Date?

    public init(remainingPercent: Int, resetsAt: Date?) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct UsagePresentation: Equatable, Sendable {
    public let primary: DisplayedWindow
    public let secondary: DisplayedWindow?
    public let freshness: Freshness

    public init(primary: DisplayedWindow, secondary: DisplayedWindow?, freshness: Freshness) {
        self.primary = primary
        self.secondary = secondary
        self.freshness = freshness
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
