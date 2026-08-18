import Foundation

public struct CodexSessionReader: Sendable {
    private static let maximumBytesPerFile: UInt64 = 128 * 1_024

    public init() {}

    public func latestSnapshot(in root: URL) throws -> UsageSnapshot? {
        try latestSnapshot(in: root, now: Date(), lookbackDays: 14)
    }

    public func latestSnapshot(
        in root: URL,
        now: Date,
        lookbackDays: Int
    ) throws -> UsageSnapshot? {
        guard lookbackDays > 0 else {
            return nil
        }

        let fileManager = FileManager.default
        let decoder = JSONDecoder()
        let timestampFormatter = ISO8601DateFormatter()
        let fractionalTimestampFormatter = ISO8601DateFormatter()
        fractionalTimestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let calendar = Calendar.current
        var newest: UsageSnapshot?

        for dayOffset in 0..<lookbackDays {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else {
                continue
            }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else {
                continue
            }
            let directory = root
                .appending(path: String(year))
                .appending(path: String(format: "%02d", month))
                .appending(path: String(format: "%02d", day))
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in urls where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
                guard let contents = try? readTailText(from: url) else {
                    continue
                }

                for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard line.contains("\"rate_limits\""),
                          let event = try? decoder.decode(SessionEvent.self, from: Data(line.utf8)),
                          event.payload?.type == "token_count",
                          let limits = event.payload?.rateLimits,
                          let primary = limits.primary,
                          let usedPercent = primary.usedPercent
                    else {
                        continue
                    }
                    let parsedTimestamp = event.timestamp.flatMap { value in
                        fractionalTimestampFormatter.date(from: value) ?? timestampFormatter.date(from: value)
                    }
                    guard let timestamp = parsedTimestamp else {
                        continue
                    }

                    let snapshot = UsageSnapshot(
                        observedAt: timestamp,
                        primary: UsageWindow(usedPercent: usedPercent, resetsAt: primary.resetDate),
                        secondary: limits.secondary.flatMap { window in
                            window.usedPercent.map {
                                UsageWindow(usedPercent: $0, resetsAt: window.resetDate)
                            }
                        }
                    )

                    if newest == nil || timestamp > newest!.observedAt {
                        newest = snapshot
                    }
                }
            }
        }

        return newest
    }

    private func readTailText(from url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        let offset = fileSize > Self.maximumBytesPerFile ? fileSize - Self.maximumBytesPerFile : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        let text = String(decoding: data, as: UTF8.self)

        guard offset > 0 else {
            return text
        }
        guard let firstNewline = text.firstIndex(of: "\n") else {
            return ""
        }
        return String(text[text.index(after: firstNewline)...])
    }
}

private struct SessionEvent: Decodable {
    let timestamp: String?
    let payload: Payload?

    struct Payload: Decodable {
        let type: String?
        let rateLimits: Limits?

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimits = "rate_limits"
        }
    }

    struct Limits: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    struct Window: Decodable {
        let usedPercent: Double?
        let resetsAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetsAt = "resets_at"
        }

        var resetDate: Date? {
            resetsAt.map(Date.init(timeIntervalSince1970:))
        }
    }
}
