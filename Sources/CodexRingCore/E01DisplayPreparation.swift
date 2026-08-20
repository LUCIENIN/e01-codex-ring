public enum E01DisplayPreparationStep: Equatable, Sendable {
    case authenticateRCSP
}

public enum E01PostAuthenticationStep: Equatable, Sendable {
    case inspectTargetInfo
    case queryStorage
    case prepareDeletion(String)
}

public enum E01PostDeletionStep: Equatable, Sendable {
    case finishCleanup
    case queryStorage
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
            return .prepareDeletion(cleanupFileName)
        }
        if hasMedia || shouldFormatMedia {
            return .queryStorage
        }
        return .inspectTargetInfo
    }

    public static func nextStepAfterDeletion(hasMedia: Bool) -> E01PostDeletionStep {
        hasMedia ? .queryStorage : .finishCleanup
    }
}
