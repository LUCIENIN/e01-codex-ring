public enum E01DisplayPreparationStep: Equatable, Sendable {
    case authenticateRCSP
}

public enum E01DisplayPreparation {
    public static func nextStepAfterBadgeInfo() -> E01DisplayPreparationStep {
        .authenticateRCSP
    }
}
