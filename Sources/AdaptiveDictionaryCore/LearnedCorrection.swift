import Foundation

public struct LearnedCorrection: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var source: String
    public var replacement: String
    public var observationCount: Int
    public var applicationCount: Int
    public var isEnabled: Bool
    public var bundleIdentifiers: Set<String>
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        source: String,
        replacement: String,
        observationCount: Int = 1,
        applicationCount: Int = 0,
        isEnabled: Bool = true,
        bundleIdentifiers: Set<String> = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.replacement = replacement
        self.observationCount = observationCount
        self.applicationCount = applicationCount
        self.isEnabled = isEnabled
        self.bundleIdentifiers = bundleIdentifiers
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isCasingOnly: Bool {
        source != replacement && source.canonicalComparison == replacement.canonicalComparison
    }

    public func isActive(minimumConfirmations: Int) -> Bool {
        isEnabled && (isCasingOnly || observationCount >= max(1, minimumConfirmations))
    }
}

public struct CorrectionCandidate: Sendable, Equatable {
    public let source: String
    public let replacement: String

    public init(source: String, replacement: String) {
        self.source = source
        self.replacement = replacement
    }
}

public struct CorrectionApplication: Sendable, Equatable {
    public let text: String
    public let appliedRuleIDs: Set<UUID>

    public init(text: String, appliedRuleIDs: Set<UUID>) {
        self.text = text
        self.appliedRuleIDs = appliedRuleIDs
    }
}

extension String {
    var canonicalWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var canonicalComparison: String {
        canonicalWhitespace.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
