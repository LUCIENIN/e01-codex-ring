import Foundation

/// Validates the normal-service response which the vendor dispatches to its bind parser.
public enum E01BindResponseValidator {
    public static func isExplicitBindResponse(_ data: [UInt8]) -> Bool {
        guard data.count >= 7, data[0] == 0x9E, data[3] == 0x61 else {
            return false
        }

        let payloadLength = Int(data[4]) | (Int(data[5]) << 8)
        guard data.count == payloadLength + 6, data[6] == 0x00 else {
            return false
        }

        return data.dropFirst(2).reduce(0, &+) == data[1]
    }
}
