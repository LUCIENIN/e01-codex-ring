import Foundation

public enum E01VideoDialProtocol {
    public struct UpdateRequest: Equatable, Sendable {
        public let status: UInt8
        public let allowedLength: Int
        public let offset: Int

        public init(status: UInt8, allowedLength: Int, offset: Int) {
            self.status = status
            self.allowedLength = allowedLength
            self.offset = offset
        }
    }

    public struct Progress: Equatable, Sendable {
        public let status: UInt8
        public let offset: Int

        public init(status: UInt8, offset: Int) {
            self.status = status
            self.offset = offset
        }
    }

    public static func wrapAVI(
        _ avi: [UInt8],
        width: Int,
        height: Int,
        backgroundSupportFlag: Int,
        usesAnimatedHeader: Bool = true
    ) -> [UInt8] {
        precondition((1...Int(UInt16.max)).contains(width))
        precondition((1...Int(UInt16.max)).contains(height))
        precondition((0...Int(UInt16.max)).contains(backgroundSupportFlag))

        let video = [
            usesAnimatedHeader ? UInt8(0x41) : UInt8(0x30), UInt8(0x56),
            UInt8(truncatingIfNeeded: width), UInt8(truncatingIfNeeded: width >> 8),
            UInt8(truncatingIfNeeded: height), UInt8(truncatingIfNeeded: height >> 8),
            UInt8(0x10), UInt8(0x80),
        ] + avi
        return wrapContent(video, fileType: 0x0C, slot: backgroundSupportFlag)
    }

    public static func wrapRGB565(
        _ rgb565: [UInt8],
        width: Int,
        height: Int,
        dialIndex: Int
    ) -> [UInt8] {
        precondition((1...Int(UInt16.max)).contains(width))
        precondition((1...Int(UInt16.max)).contains(height))
        precondition(rgb565.count == width * height * 2)
        let image = [
            UInt8(0x42), UInt8(0x4D),
            UInt8(truncatingIfNeeded: width), UInt8(truncatingIfNeeded: width >> 8),
            UInt8(truncatingIfNeeded: height), UInt8(truncatingIfNeeded: height >> 8),
            UInt8(0x10), UInt8(0x80),
        ] + rgb565
        return wrapContent(image, fileType: 0x05, slot: dialIndex)
    }

    private static func wrapContent(_ content: [UInt8], fileType: UInt8, slot: Int) -> [UInt8] {
        let crc = crc16(content)
        var header = [UInt8](repeating: 0, count: 27)
        header[0] = 0xBC
        header[1] = 0xAF
        header[2] = fileType
        header[3] = UInt8(truncatingIfNeeded: slot)
        header[4] = UInt8(truncatingIfNeeded: slot >> 8)
        writeUInt32LE(UInt32(content.count), into: &header, at: 13)
        header[25] = UInt8(truncatingIfNeeded: crc)
        header[26] = UInt8(truncatingIfNeeded: crc >> 8)
        return header + content
    }

    public static func commandPacket(
        command: UInt8,
        payload: [UInt8],
        serialNumber: UInt8
    ) -> [UInt8] {
        let isLong = payload.count + 6 > 20
        let flag = ((serialNumber & 0x0F) << 3) | (isLong ? 0x05 : 0x01)
        let body = [
            flag, command,
            UInt8(truncatingIfNeeded: payload.count),
            UInt8(truncatingIfNeeded: payload.count >> 8),
        ] + payload
        return [0x9E, body.reduce(UInt8(0), &+)] + body
    }

    public static func parseUpdateRequest(_ frame: [UInt8]) -> UpdateRequest? {
        guard let payload = payload(from: frame, command: 0xC1), payload.count == 9 else { return nil }
        return UpdateRequest(
            status: payload[0],
            allowedLength: Int(readUInt32LE(payload, at: 1)),
            offset: Int(readUInt32LE(payload, at: 5))
        )
    }

    public static func parseProgress(_ frame: [UInt8]) -> Progress? {
        guard let payload = payload(from: frame, command: 0xC3), payload.count == 5 else { return nil }
        return Progress(status: payload[0], offset: Int(readUInt32LE(payload, at: 1)))
    }

    public static func parseResult(_ frame: [UInt8]) -> UInt8? {
        guard let payload = payload(from: frame, command: 0xC5), payload.count == 1 else { return nil }
        return payload[0]
    }

    public static func dataPayload(data: [UInt8], allowedLength: Int, offset: Int) -> [UInt8]? {
        guard allowedLength > 0, offset >= 0, offset < data.count else { return nil }
        let length = min(allowedLength, data.count - offset)
        var result = [UInt8](repeating: 0, count: 8)
        writeUInt32LE(UInt32(length), into: &result, at: 0)
        writeUInt32LE(UInt32(offset), into: &result, at: 4)
        result += data[offset..<(offset + length)]
        return result
    }

    private static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc = ((crc << 8) | (crc >> 8)) ^ UInt16(byte)
            crc ^= (crc & 0x00FF) >> 4
            crc ^= crc << 12
            crc ^= (crc & 0x00FF) << 5
        }
        return crc
    }

    private static func payload(from frame: [UInt8], command: UInt8) -> [UInt8]? {
        guard frame.count >= 6,
              frame[0] == 0x9E,
              frame[3] == command,
              frame.dropFirst(2).reduce(UInt8(0), &+) == frame[1]
        else { return nil }
        let length = Int(frame[4]) | (Int(frame[5]) << 8)
        guard frame.count == length + 6 else { return nil }
        return Array(frame.dropFirst(6))
    }

    private static func writeUInt32LE(_ value: UInt32, into bytes: inout [UInt8], at index: Int) {
        bytes[index] = UInt8(truncatingIfNeeded: value)
        bytes[index + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[index + 2] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[index + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    private static func readUInt32LE(_ bytes: [UInt8], at index: Int) -> UInt32 {
        UInt32(bytes[index])
            | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16)
            | (UInt32(bytes[index + 3]) << 24)
    }
}
