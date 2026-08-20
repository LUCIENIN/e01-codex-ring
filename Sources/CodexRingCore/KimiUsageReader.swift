import Foundation

public enum KimiUsageError: Error, Equatable, Sendable {
    case missingConfiguration
    case invalidConfiguration
    case missingManagedProvider
    case untrustedBaseURL
    case invalidResponse
    case httpStatus(Int)
    case missingQuotaWindow
    case requestFailed
}

struct KimiUsageCredentials: Equatable, Sendable {
    let baseURL: URL
    let apiKey: String
}

enum KimiUsageConfiguration {
    private static let managedBaseURL = URL(string: "https://api.kimi.com/coding/v1")!

    static func parse(_ data: Data) throws -> KimiUsageCredentials {
        guard let source = String(data: data, encoding: .utf8) else {
            throw KimiUsageError.invalidConfiguration
        }

        var providers = [[String: String]]()
        var currentProvider: Int?
        for rawLine in source.split(whereSeparator: \Character.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if line.hasPrefix("[providers."), line.hasSuffix("]") {
                providers.append([:])
                currentProvider = providers.indices.last
                continue
            }
            guard let currentProvider,
                  let separator = line.firstIndex(of: "=")
            else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard let value = parseTOMLString(rawValue) else { continue }
            providers[currentProvider][key] = value
        }

        guard let provider = providers.first(where: {
            $0["type"]?.lowercased() == "kimi" && $0["api_key"]?.isEmpty == false
        }) else {
            throw KimiUsageError.missingManagedProvider
        }

        let rawBaseURL = provider["base_url"] ?? managedBaseURL.absoluteString
        guard isManagedBaseURL(rawBaseURL) else {
            throw KimiUsageError.untrustedBaseURL
        }
        guard let apiKey = provider["api_key"], !apiKey.isEmpty else {
            throw KimiUsageError.missingManagedProvider
        }
        return KimiUsageCredentials(baseURL: managedBaseURL, apiKey: apiKey)
    }

    private static func parseTOMLString(_ rawValue: String) -> String? {
        guard rawValue.first == "\"" else { return nil }
        return try? JSONDecoder().decode(String.self, from: Data(rawValue.utf8))
    }

    private static func isManagedBaseURL(_ rawValue: String) -> Bool {
        guard let components = URLComponents(string: rawValue),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "api.kimi.com",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.port == nil
        else {
            return false
        }
        let normalizedPath = components.path.replacingOccurrences(
            of: #"/+$"#,
            with: "",
            options: .regularExpression
        )
        return normalizedPath == "/coding/v1"
    }
}

public struct KimiUsageQuota: Codable, Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: Date?

    public init(remainingPercent: Int, resetsAt: Date?) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct KimiUsageSnapshot: Codable, Equatable, Sendable {
    public let observedAt: Date
    public let weekly: KimiUsageQuota
    public let fiveHour: KimiUsageQuota

    public init(observedAt: Date, weekly: KimiUsageQuota, fiveHour: KimiUsageQuota) {
        self.observedAt = observedAt
        self.weekly = weekly
        self.fiveHour = fiveHour
    }

    public func presentation(now: Date) -> KimiUsagePresentation {
        KimiUsagePresentation(
            weekly: DisplayedWindow(
                remainingPercent: weekly.remainingPercent,
                resetsAt: weekly.resetsAt
            ),
            fiveHour: DisplayedWindow(
                remainingPercent: fiveHour.remainingPercent,
                resetsAt: fiveHour.resetsAt
            ),
            freshness: now.timeIntervalSince(observedAt) > 600 ? .stale : .fresh
        )
    }
}

public struct KimiUsagePresentation: Equatable, Sendable {
    public let weekly: DisplayedWindow
    public let fiveHour: DisplayedWindow
    public let freshness: Freshness

    public init(weekly: DisplayedWindow, fiveHour: DisplayedWindow, freshness: Freshness) {
        self.weekly = weekly
        self.fiveHour = fiveHour
        self.freshness = freshness
    }
}

public enum QuotaHealthStatus: String, Equatable, Sendable {
    case good = "GOOD"
    case watch = "WATCH"
    case low = "LOW"

    public init(remainingPercent: Int) {
        if remainingPercent >= 50 {
            self = .good
        } else if remainingPercent >= 20 {
            self = .watch
        } else {
            self = .low
        }
    }
}

public struct QuotaDashboardMetric: Equatable, Sendable {
    public let label: String
    public let remainingPercent: Int
    public let status: QuotaHealthStatus

    public init(label: String, remainingPercent: Int) {
        self.label = label
        self.remainingPercent = remainingPercent
        self.status = QuotaHealthStatus(remainingPercent: remainingPercent)
    }
}

public struct QuotaDashboardPresentation: Equatable, Sendable {
    private static let designSignature = "design:glanceable-v2"

    public let codex: UsagePresentation?
    public let kimi: KimiUsagePresentation?

    public init(codex: UsagePresentation?, kimi: KimiUsagePresentation?) {
        self.codex = codex
        self.kimi = kimi
    }

    public var hasData: Bool {
        codex != nil || kimi != nil
    }

    public var metrics: [QuotaDashboardMetric] {
        var result = [QuotaDashboardMetric]()
        if let codex {
            result.append(
                QuotaDashboardMetric(
                    label: "CODEX",
                    remainingPercent: codex.primary.remainingPercent
                )
            )
        }
        if let kimi {
            result.append(
                QuotaDashboardMetric(
                    label: "KIMI WEEK",
                    remainingPercent: kimi.weekly.remainingPercent
                )
            )
            result.append(
                QuotaDashboardMetric(
                    label: "KIMI 5H",
                    remainingPercent: kimi.fiveHour.remainingPercent
                )
            )
        }
        return result
    }

    public var contentSignature: String {
        let codexPart = codex.map { "codex:\($0.primary.remainingPercent)" } ?? "codex:--"
        let kimiPart = kimi.map {
            "kimi-week:\($0.weekly.remainingPercent)|kimi-5h:\($0.fiveHour.remainingPercent)"
        } ?? "kimi-week:--|kimi-5h:--"
        return "\(Self.designSignature)|\(codexPart)|\(kimiPart)"
    }
}

enum KimiUsagePayloadParser {
    static func parse(_ data: Data, observedAt: Date) throws -> KimiUsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let weeklyObject = root["usage"] as? [String: Any],
              let weekly = parseQuota(weeklyObject),
              let limits = root["limits"] as? [[String: Any]],
              let fiveHour = limits.lazy.compactMap(parseFiveHourLimit).first
        else {
            throw KimiUsageError.missingQuotaWindow
        }
        return KimiUsageSnapshot(observedAt: observedAt, weekly: weekly, fiveHour: fiveHour)
    }

    private static func parseFiveHourLimit(_ item: [String: Any]) -> KimiUsageQuota? {
        guard let window = item["window"] as? [String: Any],
              let duration = integer(window["duration"]),
              let unit = window["timeUnit"] as? String,
              (unit == "TIME_UNIT_MINUTE" && duration == 300)
                || (unit == "TIME_UNIT_HOUR" && duration == 5),
              let detail = item["detail"] as? [String: Any]
        else {
            return nil
        }
        return parseQuota(detail)
    }

    private static func parseQuota(_ object: [String: Any]) -> KimiUsageQuota? {
        guard let limit = integer(object["limit"]),
              limit > 0
        else {
            return nil
        }
        let remainingUnits: Int
        if let serverRemaining = integer(object["remaining"]) {
            remainingUnits = serverRemaining
        } else if let used = integer(object["used"]) {
            remainingUnits = limit - used
        } else {
            return nil
        }
        let remaining = Int((Double(remainingUnits) * 100 / Double(limit)).rounded())
        return KimiUsageQuota(
            remainingPercent: min(max(remaining, 0), 100),
            resetsAt: date(object["resetTime"])
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

public struct KimiUsageReader: Sendable {
    public static let defaultConfigurationURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".kimi-code/config.toml")

    private let configurationURL: URL

    public init(configurationURL: URL = Self.defaultConfigurationURL) {
        self.configurationURL = configurationURL
    }

    public func latestSnapshot(observedAt: Date = Date()) async throws -> KimiUsageSnapshot {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            throw KimiUsageError.missingConfiguration
        }
        let credentials = try KimiUsageConfiguration.parse(Data(contentsOf: configurationURL))
        let usageURL = credentials.baseURL.appending(path: "usages")
        var request = URLRequest(url: usageURL, timeoutInterval: 8)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw KimiUsageError.requestFailed
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KimiUsageError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw KimiUsageError.httpStatus(httpResponse.statusCode)
        }
        return try KimiUsagePayloadParser.parse(data, observedAt: observedAt)
    }
}

public struct KimiUsageSnapshotStore: Sendable {
    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".codex/e01-kimi-usage-cache.json")

    private let url: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
    }

    public func load() throws -> KimiUsageSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(KimiUsageSnapshot.self, from: Data(contentsOf: url))
    }

    public func save(_ snapshot: KimiUsageSnapshot) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}

public enum KimiUsageRefreshSchedule {
    public static func shouldRefresh(
        lastAttemptAt: Date?,
        now: Date,
        minimumInterval: TimeInterval = 30
    ) -> Bool {
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= max(30, minimumInterval)
    }
}
