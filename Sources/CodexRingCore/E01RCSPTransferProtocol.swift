import Foundation

public enum E01RCSPTransferProtocol {
    public struct ReadRequest: Equatable, Sendable {
        public let offset: Int
        public let length: Int

        public init(offset: Int, length: Int) {
            self.offset = offset
            self.length = length
        }
    }

    /// Jieli's native CRC16 uses the CCITT/XMODEM polynomial (0x1021), seed 0.
    public static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = crc & 0x8000 == 0 ? crc << 1 : (crc << 1) ^ 0x1021
            }
        }
        return crc
    }

    public static func getStorageParameter() -> [UInt8] {
        [0xFF, 0x00, 0x00, 0x00, 0x04]
    }

    public static func sdCardOneHandler(fromGetSysInfoParameter parameter: [UInt8]) -> UInt32? {
        guard parameter.count >= 3 else { return nil }
        var index = 1 // first byte is the sys-info function
        while index < parameter.count {
            let attributeLength = Int(parameter[index])
            guard attributeLength >= 1, index + 1 + attributeLength <= parameter.count else { return nil }
            let type = parameter[index + 1]
            if type == 0x02 {
                let data = Array(parameter[(index + 2)..<(index + 1 + attributeLength)])
                // Legacy DevStorageInfo: online mask, then handlers for USB, SD0, SD1,
                // flash and line-in. SD1 is storage index 2.
                guard data.count >= 13, data[0] & 0b0000_0100 != 0 else { return nil }
                return readUInt32BE(data, at: 9)
            }
            index += 1 + attributeLength
        }
        return nil
    }

    public static func deviceExtendParameter(deviceHandler: UInt32) -> [UInt8] {
        [0x00] + uint32BE(deviceHandler) + [0x01]
    }

    public static func startParameter(fileSize: Int, crc16: UInt16, temporaryPath: String) -> [UInt8] {
        precondition(fileSize >= 0 && fileSize <= Int(UInt32.max))
        return uint32BE(UInt32(fileSize))
            + [UInt8(crc16 >> 8), UInt8(crc16 & 0xFF)]
            + Array((temporaryPath + "\0").utf8)
    }

    public static func readRequest(from parameter: [UInt8]) -> ReadRequest? {
        guard parameter.count >= 7, parameter[0] == 0 else { return nil }
        let length = (Int(parameter[1]) << 8) | Int(parameter[2])
        guard let offset = readUInt32BE(parameter, at: 3) else { return nil }
        return ReadRequest(offset: Int(offset), length: length)
    }

    public static func dataPayloads(
        _ data: [UInt8],
        packetSize: Int,
        usesCRC16: Bool
    ) -> [[UInt8]] {
        guard packetSize > 0 else { return [] }
        var payloads: [[UInt8]] = []
        var offset = 0
        var packetIndex: UInt8 = 0
        while offset < data.count {
            let end = min(offset + packetSize, data.count)
            let chunk = Array(data[offset..<end])
            var payload = [packetIndex]
            if usesCRC16 {
                let crc = crc16(chunk)
                payload += [UInt8(crc >> 8), UInt8(crc & 0xFF)]
            }
            payload += chunk
            payloads.append(payload)
            packetIndex &+= 1
            offset = end
        }
        return payloads
    }

    private static func uint32BE(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ]
    }

    private static func readUInt32BE(_ bytes: [UInt8], at index: Int) -> UInt32? {
        guard index >= 0, index + 4 <= bytes.count else { return nil }
        return (UInt32(bytes[index]) << 24)
            | (UInt32(bytes[index + 1]) << 16)
            | (UInt32(bytes[index + 2]) << 8)
            | UInt32(bytes[index + 3])
    }
}
