public enum E01DisplayPreparationStep: Equatable, Sendable {
    case authenticateRCSP
}

public enum E01PostAuthenticationStep: Equatable, Sendable {
    case inspectTargetInfo
    case queryStorage
    case deleteFile(String)
}

public enum E01DisplayPreparation {
    public static func nextStepAfterBadgeInfo() -> E01DisplayPreparationStep {
        .authenticateRCSP
    }

    public static func nextStepAfterAuthentication(
        hasMedia: Bool,
        cleanupFileName: String?,
        shouldFormatMedia: Bool
    ) -> E01PostAuthenticationStep {
        if let cleanupFileName {
            return .deleteFile(cleanupFileName)
        }
        if hasMedia || shouldFormatMedia {
            return .queryStorage
        }
        return .inspectTargetInfo
    }
}
