import Foundation

/// Builds the vendor envelope for bounded normal-service control requests.
/// It cannot construct QR, media payload, control-point, or OTA packets.
public enum E01NormalDataFrame {
    public static func firstBindPacket(_ request: E01BindRequest) -> [UInt8] {
        packet(command: E01BindRequest.command, payload: request.payload, serialNumber: 0)
    }

    public static func packet(command: UInt8, payload: [UInt8], serialNumber: UInt8) -> [UInt8] {
        let flag = ((serialNumber & 0x0F) << 3) | 0b0000_0110
        return packet(command: command, payload: payload, flag: flag)
    }

    public static func requestPacket(command: UInt8, payload: [UInt8], serialNumber: UInt8) -> [UInt8] {
        let longPacketBit: UInt8 = payload.count + 6 > 20 ? 0b0000_0100 : 0
        let flag = ((serialNumber & 0x0F) << 3) | 0b1000_0010 | longPacketBit
        return packet(command: command, payload: payload, flag: flag)
    }

    private static func packet(command: UInt8, payload: [UInt8], flag: UInt8) -> [UInt8] {
        let encapsulated = [flag, command] + littleEndianLength(payload.count) + payload
        let checksum = encapsulated.reduce(0, &+)

        return [0x9E, checksum] + encapsulated
    }

    private static func littleEndianLength(_ length: Int) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: length),
            UInt8(truncatingIfNeeded: length >> 8),
        ]
    }
}
