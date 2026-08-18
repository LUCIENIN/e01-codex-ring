import Foundation

public struct E01BadgeInfo: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pictureWidth: Int
    public let pictureHeight: Int
    public let memoryBytes: UInt32

    public init(
        width: Int,
        height: Int,
        pictureWidth: Int,
        pictureHeight: Int,
        memoryBytes: UInt32
    ) {
        self.width = width
        self.height = height
        self.pictureWidth = pictureWidth
        self.pictureHeight = pictureHeight
        self.memoryBytes = memoryBytes
    }
}

/// Parses the dedicated electronic-badge `0xC7` response from the vendor app protocol.
public enum E01BadgeInfoResponse {
    public static func parse(_ frame: [UInt8]) -> E01BadgeInfo? {
        guard frame.count == 19,
              frame[0] == 0x9E,
              frame[3] == 0xC7,
              frame.dropFirst(2).reduce(UInt8(0), &+) == frame[1],
              (Int(frame[4]) | (Int(frame[5]) << 8)) == 13,
              frame[6] == 0x01
        else {
            return nil
        }

        let width = littleEndian16(frame[7], frame[8])
        let height = littleEndian16(frame[9], frame[10])
        let pictureWidth = littleEndian16(frame[11], frame[12])
        let pictureHeight = littleEndian16(frame[13], frame[14])
        let memoryBytes = UInt32(frame[15])
            | (UInt32(frame[16]) << 8)
            | (UInt32(frame[17]) << 16)
            | (UInt32(frame[18]) << 24)

        guard width > 0, height > 0, pictureWidth > 0, pictureHeight > 0 else {
            return nil
        }

        return E01BadgeInfo(
            width: width,
            height: height,
            pictureWidth: pictureWidth,
            pictureHeight: pictureHeight,
            memoryBytes: memoryBytes
        )
    }

    private static func littleEndian16(_ low: UInt8, _ high: UInt8) -> Int {
        Int(low) | (Int(high) << 8)
    }
}
