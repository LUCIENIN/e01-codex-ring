import Foundation

/// The payload for the vendor's normal-data-service bind initialization command.
/// This deliberately excludes the transport frame, QR binding, media, and OTA paths.
public struct E01BindRequest: Equatable, Sendable {
    public static let command: UInt8 = 0x60

    public let timestampMilliseconds: UInt64
    public let usesNonChineseLocale: Bool
    public let uses12HourClock: Bool

    public init(
        timestampMilliseconds: UInt64,
        usesNonChineseLocale: Bool,
        uses12HourClock: Bool
    ) {
        self.timestampMilliseconds = timestampMilliseconds
        self.usesNonChineseLocale = usesNonChineseLocale
        self.uses12HourClock = uses12HourClock
    }

    public var payload: [UInt8] {
        let flags = (usesNonChineseLocale ? UInt8(1 << 1) : 0)
            | (uses12HourClock ? UInt8(1 << 2) : 0)
        let timestamp = (0..<6).map { shift in
            UInt8(truncatingIfNeeded: timestampMilliseconds >> UInt64(shift * 8))
        }

        return [flags] + timestamp + timestamp
    }
}
