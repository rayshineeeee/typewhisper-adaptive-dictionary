import Foundation

public struct DictationRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var rawTranscript: String
    public let pluginOutput: String
    public var finalText: String
    public let profile: DictationProfile
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        rawTranscript: String,
        pluginOutput: String,
        finalText: String,
        profile: DictationProfile,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.rawTranscript = rawTranscript
        self.pluginOutput = pluginOutput
        self.finalText = finalText
        self.profile = profile
        self.createdAt = createdAt
    }
}

public struct RuleUndoChange: Sendable, Equatable {
    public let ruleID: UUID
    public let previousRule: LearnedCorrection?

    public init(ruleID: UUID, previousRule: LearnedCorrection?) {
        self.ruleID = ruleID
        self.previousRule = previousRule
    }
}

public struct LearningReceipt: Sendable, Equatable {
    public let id: UUID
    public let learnedRules: [LearnedCorrection]
    public let undoChanges: [RuleUndoChange]

    public init(
        id: UUID = UUID(),
        learnedRules: [LearnedCorrection],
        undoChanges: [RuleUndoChange]
    ) {
        self.id = id
        self.learnedRules = learnedRules
        self.undoChanges = undoChanges
    }
}
