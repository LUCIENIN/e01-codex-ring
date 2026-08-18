import Foundation

public enum E01ConnectionPhase: Equatable, Sendable {
    case disconnected
    case discovering
    case unbound
    case bound
    case ready
    case sending
    case failed
}

public struct MediaUploadGate: Sendable {
    public let phase: E01ConnectionPhase
    public let userApprovedLiveSend: Bool

    public init(phase: E01ConnectionPhase, userApprovedLiveSend: Bool) {
        self.phase = phase
        self.userApprovedLiveSend = userApprovedLiveSend
    }

    public var canSendMedia: Bool {
        phase == .ready && userApprovedLiveSend
    }
}

public enum E01SafetyPolicy {
    public static let dataServiceUUID = "C2E6FD00-E966-1000-8000-BEF9C223DF6A"
    public static let rcspServiceUUID = "0000AE00-0000-1000-8000-00805F9B34FB"
    public static let rcspWriteCharacteristicUUID = "0000AE01-0000-1000-8000-00805F9B34FB"
    public static let rcspNotifyCharacteristicUUID = "0000AE02-0000-1000-8000-00805F9B34FB"
    public static let regularDataServiceAliases = [
        dataServiceUUID,
        "FD00",
    ]

    public static let allowedCharacteristicUUIDs: Set<String> = [
        "C2E6FD01-E966-1000-8000-BEF9C223DF6A",
        "C2E6FD02-E966-1000-8000-BEF9C223DF6A",
        "C2E6FD03-E966-1000-8000-BEF9C223DF6A",
    ]

    public static func canUse(serviceUUID: String, characteristicUUID: String) -> Bool {
        serviceUUID.uppercased() == dataServiceUUID
            && allowedCharacteristicUUIDs.contains(characteristicUUID.uppercased())
    }

    public static func isRegularDataService(_ serviceUUID: String) -> Bool {
        regularDataServiceAliases.contains(serviceUUID.uppercased())
    }

    public static func canUseRCSP(serviceUUID: String, characteristicUUID: String) -> Bool {
        let service = serviceUUID.uppercased()
        let characteristic = characteristicUUID.uppercased()
        let serviceMatches = service == "AE00" || service == rcspServiceUUID
        return serviceMatches && [
            "AE01", rcspWriteCharacteristicUUID,
            "AE02", rcspNotifyCharacteristicUUID,
        ].contains(characteristic)
    }
}
