import Foundation

public struct E01VideoDialInfo: Equatable, Sendable {
    public let size: E01PictureSize
    public let backgroundSupportFlag: Int
    public let backgroundStateFlag: Int

    public init(size: E01PictureSize, backgroundSupportFlag: Int, backgroundStateFlag: Int) {
        self.size = size
        self.backgroundSupportFlag = backgroundSupportFlag
        self.backgroundStateFlag = backgroundStateFlag
    }
}

/// Parses the vendor video-capability response. Its width and height are little-endian.
public enum E01VideoInfoResponse {
    public static func parse(_ frame: [UInt8]) -> E01PictureSize? {
        parseDetails(frame)?.size
    }

    public static func parseDetails(_ frame: [UInt8]) -> E01VideoDialInfo? {
        guard frame.count >= 14,
              frame[0] == 0x9E,
              frame[3] == 0x49,
              frame.dropFirst(2).reduce(UInt8(0), &+) == frame[1]
        else {
            return nil
        }

        let payloadLength = Int(frame[4]) | (Int(frame[5]) << 8)
        guard payloadLength >= 8, frame.count == payloadLength + 6 else {
            return nil
        }

        let width = Int(frame[6]) | (Int(frame[7]) << 8)
        let height = Int(frame[8]) | (Int(frame[9]) << 8)
        guard width > 0, height > 0 else { return nil }

        let backgroundSupportFlag = Int(frame[10]) | (Int(frame[11]) << 8)
        let backgroundStateFlag = Int(frame[12]) | (Int(frame[13]) << 8)
        return E01VideoDialInfo(
            size: E01PictureSize(width: width, height: height),
            backgroundSupportFlag: backgroundSupportFlag,
            backgroundStateFlag: backgroundStateFlag
        )
    }
}
