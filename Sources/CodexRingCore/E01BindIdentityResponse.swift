import Foundation

public struct E01BindIdentityResponse: Equatable, Sendable {
    public let protocolVersion: String
    public let firmwareVersion: String
    public let platform: UInt8
    public let modelNumber: UInt16

    public static func parse(_ frame: [UInt8]) -> E01BindIdentityResponse? {
        guard E01BindResponseValidator.isExplicitBindResponse(frame) else { return nil }
        let payload = Array(frame.dropFirst(6))
        guard payload.count >= 23, payload[0] == 0 else { return nil }

        let protocolVersion = trimmedString(payload[1..<4])
        let firmwareVersion = trimmedString(payload[4..<14])
        guard !protocolVersion.isEmpty, !firmwareVersion.isEmpty else { return nil }

        let numericProtocol = Int(protocolVersion.replacingOccurrences(of: ".", with: "")) ?? 23
        var modelNumber = UInt16(payload[15])
        if numericProtocol >= 24 {
            modelNumber |= UInt16(payload[16]) << 8
        }
        return E01BindIdentityResponse(
            protocolVersion: protocolVersion,
            firmwareVersion: firmwareVersion,
            platform: payload[14],
            modelNumber: modelNumber
        )
    }

    private static func trimmedString(_ bytes: ArraySlice<UInt8>) -> String {
        let value = Array(bytes.prefix { $0 != 0 })
        return String(bytes: value, encoding: .utf8) ?? ""
    }
}
