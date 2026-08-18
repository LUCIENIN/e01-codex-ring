import Foundation

public struct E01PictureSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Parses the map-image dimensions from the vendor's `0xDB` response payload.
public enum E01PictureSizeResponse {
    public static func parse(_ frame: [UInt8]) -> E01PictureSize? {
        guard frame.count >= 26,
              frame[0] == 0x9E,
              frame[3] == 0xDB,
              frame.dropFirst(2).reduce(UInt8(0), &+) == frame[1]
        else {
            return nil
        }

        let payloadLength = Int(frame[4]) | (Int(frame[5]) << 8)
        guard payloadLength >= 20, frame.count == payloadLength + 6 else {
            return nil
        }

        let width = (Int(frame[22]) << 8) | Int(frame[23])
        let height = (Int(frame[24]) << 8) | Int(frame[25])
        guard width > 0, height > 0 else { return nil }

        return E01PictureSize(width: width, height: height)
    }
}
