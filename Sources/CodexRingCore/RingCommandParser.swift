import Foundation

public enum RingCommandKind: Equatable, Sendable {
    case preview
    case watch
    case scan
    case bind
    case probe
    case display
    case displayWatch
}

public struct RingCommandOptions: Equatable, Sendable {
    public let sessionsDirectory: URL
    public let outputURL: URL
    public let size: CGSize
    public let interval: TimeInterval
    public let scanTimeout: TimeInterval

    public init(
        sessionsDirectory: URL,
        outputURL: URL,
        size: CGSize,
        interval: TimeInterval,
        scanTimeout: TimeInterval
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.outputURL = outputURL
        self.size = size
        self.interval = interval
        self.scanTimeout = scanTimeout
    }
}

public struct RingCommand: Equatable, Sendable {
    public let kind: RingCommandKind
    public let options: RingCommandOptions

    public init(kind: RingCommandKind, options: RingCommandOptions) {
        self.kind = kind
        self.options = options
    }
}

public enum RingCommandError: Error, Equatable {
    case missingCommand
    case unknownCommand(String)
    case missingValue(String)
    case invalidOption(String)
    case invalidDimension(String)
    case invalidInterval(String)
}

public enum RingCommandParser {
    public static func parse(
        arguments: [String],
        homeDirectory: URL,
        workingDirectory: URL
    ) throws -> RingCommand {
        guard let commandName = arguments.first else {
            throw RingCommandError.missingCommand
        }
        let kind: RingCommandKind
        switch commandName {
        case "preview":
            kind = .preview
        case "watch":
            kind = .watch
        case "scan":
            kind = .scan
        case "bind":
            kind = .bind
        case "probe":
            kind = .probe
        case "display":
            kind = .display
        case "display-watch":
            kind = .displayWatch
        default:
            throw RingCommandError.unknownCommand(commandName)
        }

        var sessionsDirectory = homeDirectory.appending(path: ".codex/sessions")
        var outputURL = workingDirectory.appending(path: ".runtime/codex-ring-preview.png")
        var width = 320
        var height = 320
        var interval: TimeInterval = 30
        var scanTimeout: TimeInterval = 10
        var index = 1

        while index < arguments.count {
            let option = arguments[index]
            index += 1
            guard index < arguments.count else {
                throw RingCommandError.missingValue(option)
            }
            let value = arguments[index]
            index += 1

            switch option {
            case "--sessions":
                sessionsDirectory = resolvePath(value, relativeTo: workingDirectory)
            case "--output":
                outputURL = resolvePath(value, relativeTo: workingDirectory)
            case "--width":
                width = try parseDimension(value)
            case "--height":
                height = try parseDimension(value)
            case "--interval":
                interval = try parseInterval(value)
            case "--timeout":
                scanTimeout = try parseScanTimeout(value)
            default:
                throw RingCommandError.invalidOption(option)
            }
        }

        return RingCommand(
            kind: kind,
            options: RingCommandOptions(
                sessionsDirectory: sessionsDirectory,
                outputURL: outputURL,
                size: CGSize(width: width, height: height),
                interval: interval,
                scanTimeout: scanTimeout
            )
        )
    }

    private static func parseDimension(_ value: String) throws -> Int {
        guard let dimension = Int(value), (64...2_048).contains(dimension) else {
            throw RingCommandError.invalidDimension(value)
        }
        return dimension
    }

    private static func parseInterval(_ value: String) throws -> TimeInterval {
        guard let interval = TimeInterval(value), interval.isFinite, interval > 0 else {
            throw RingCommandError.invalidInterval(value)
        }
        return max(30, interval)
    }

    private static func parseScanTimeout(_ value: String) throws -> TimeInterval {
        guard let timeout = TimeInterval(value), timeout.isFinite, (1...30).contains(timeout) else {
            throw RingCommandError.invalidInterval(value)
        }
        return timeout
    }

    private static func resolvePath(_ value: String, relativeTo workingDirectory: URL) -> URL {
        if value.hasPrefix("/") {
            return URL(filePath: value)
        }
        return workingDirectory.appending(path: value)
    }
}
