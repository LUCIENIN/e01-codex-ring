import Foundation

public enum E01RCSPFrame {
    private static let prefix: [UInt8] = [0xFE, 0xDC, 0xBA]

    public struct Packet: Equatable, Sendable {
        public let isCommand: Bool
        public let requestsResponse: Bool
        public let opcode: UInt8
        public let serialNumber: UInt8
        public let status: UInt8?
        public let parameter: [UInt8]
    }

    public static func command(
        opcode: UInt8,
        serialNumber: UInt8,
        parameter: [UInt8],
        requestsResponse: Bool = true
    ) -> [UInt8] {
        let parameterLength = parameter.count + 1
        precondition(parameterLength <= Int(UInt16.max))
        var bytes = prefix
        bytes.append(0x80 | (requestsResponse ? 0x40 : 0))
        bytes.append(opcode)
        bytes.append(UInt8((parameterLength >> 8) & 0xFF))
        bytes.append(UInt8(parameterLength & 0xFF))
        bytes.append(serialNumber)
        bytes.append(contentsOf: parameter)
        bytes.append(0xEF)
        return bytes
    }

    public static func response(
        opcode: UInt8,
        serialNumber: UInt8,
        status: UInt8,
        parameter: [UInt8] = []
    ) -> [UInt8] {
        let parameterLength = parameter.count + 2
        precondition(parameterLength <= Int(UInt16.max))
        var bytes = prefix
        bytes.append(0x00)
        bytes.append(opcode)
        bytes.append(UInt8((parameterLength >> 8) & 0xFF))
        bytes.append(UInt8(parameterLength & 0xFF))
        bytes.append(status)
        bytes.append(serialNumber)
        bytes.append(contentsOf: parameter)
        bytes.append(0xEF)
        return bytes
    }

    public struct Parser: Sendable {
        private var buffer: [UInt8] = []

        public init() {}

        public mutating func append(_ bytes: [UInt8]) -> [Packet] {
            buffer.append(contentsOf: bytes)
            var packets: [Packet] = []

            while true {
                guard let prefixIndex = findPrefix() else {
                    buffer = Array(buffer.suffix(min(buffer.count, 2)))
                    break
                }
                if prefixIndex > 0 {
                    buffer.removeFirst(prefixIndex)
                }
                guard buffer.count >= 8 else { break }

                let parameterLength = (Int(buffer[5]) << 8) | Int(buffer[6])
                let frameLength = 3 + 4 + parameterLength + 1
                guard buffer.count >= frameLength else { break }
                guard buffer[frameLength - 1] == 0xEF else {
                    buffer.removeFirst()
                    continue
                }

                let flags = buffer[3]
                let isCommand = flags & 0x80 != 0
                let minimumLength = isCommand ? 1 : 2
                guard parameterLength >= minimumLength else {
                    buffer.removeFirst(frameLength)
                    continue
                }
                let payload = Array(buffer[7..<(7 + parameterLength)])
                let parameterStart = isCommand ? 1 : 2
                packets.append(Packet(
                    isCommand: isCommand,
                    requestsResponse: flags & 0x40 != 0,
                    opcode: buffer[4],
                    serialNumber: isCommand ? payload[0] : payload[1],
                    status: isCommand ? nil : payload[0],
                    parameter: Array(payload.dropFirst(parameterStart))
                ))
                buffer.removeFirst(frameLength)
            }
            return packets
        }

        private func findPrefix() -> Int? {
            guard buffer.count >= 3 else { return nil }
            return buffer.indices.dropLast(2).first { index in
                buffer[index] == 0xFE
                    && buffer[index + 1] == 0xDC
                    && buffer[index + 2] == 0xBA
            }
        }
    }
}
