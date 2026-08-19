import Foundation

public actor CorrectionStore {
    private struct Database: Codable {
        var schemaVersion = 2
        var rules: [LearnedCorrection]
        var history: [DictationRecord]

        init(rules: [LearnedCorrection], history: [DictationRecord]) {
            self.rules = rules
            self.history = history
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case rules
            case history
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            rules = try container.decodeIfPresent([LearnedCorrection].self, forKey: .rules) ?? []
            history = try container.decodeIfPresent([DictationRecord].self, forKey: .history) ?? []
        }
    }

    private static let maximumHistoryCount = 500
    private let fileURL: URL
    private var rules: [LearnedCorrection]
    private var history: [DictationRecord]

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let database = try decoder.decode(Database.self, from: data)
            rules = database.rules
            history = database.history
        } else {
            rules = []
            history = []
        }
    }

    public func snapshot() -> [LearnedCorrection] {
        sorted(rules)
    }

    public func historySnapshot() -> [DictationRecord] {
        history.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func recordInsertion(
        rawTranscript: String,
        pluginOutput: String,
        profile: DictationProfile,
        now: Date = Date()
    ) throws -> UUID {
        let record = DictationRecord(
            rawTranscript: rawTranscript,
            pluginOutput: pluginOutput,
            finalText: pluginOutput,
            profile: profile,
            createdAt: now
        )
        history.append(record)
        trimHistory()
        try persist()
        return record.id
    }

    public func recordFinalText(_ finalText: String, recordID: UUID?) throws {
        guard let recordID,
            let index = history.firstIndex(where: { $0.id == recordID })
        else { return }
        history[index].finalText = finalText
        try persist()
    }

    public func updateRawTranscript(_ rawTranscript: String, recordID: UUID?) throws {
        guard let recordID,
            let index = history.firstIndex(where: { $0.id == recordID })
        else { return }
        history[index].rawTranscript = rawTranscript
        try persist()
    }

    public func recentStyleExamples(
        profile: DictationProfile,
        limit: Int = 4
    ) -> [LearnedStyleExample] {
        guard limit > 0 else { return [] }
        return history.reversed().compactMap { record in
            guard record.profile == profile,
                record.pluginOutput != record.finalText,
                !record.pluginOutput.isEmpty,
                !record.finalText.isEmpty
            else { return nil }
            return LearnedStyleExample(
                before: record.pluginOutput,
                after: record.finalText,
                profile: profile
            )
        }.prefix(limit).map { $0 }
    }

    @discardableResult
    public func observe(
        original: String,
        corrected: String,
        bundleIdentifier: String?,
        now: Date = Date()
    ) throws -> [LearnedCorrection] {
        try observeLearning(
            original: original,
            corrected: corrected,
            bundleIdentifier: bundleIdentifier,
            now: now
        ).learnedRules
    }

    @discardableResult
    public func observeLearning(
        original: String,
        corrected: String,
        bundleIdentifier: String?,
        now: Date = Date()
    ) throws -> LearningReceipt {
        let candidates = CorrectionExtractor.extract(original: original, corrected: corrected)
        guard !candidates.isEmpty else {
            return LearningReceipt(learnedRules: [], undoChanges: [])
        }

        var affected: [LearnedCorrection] = []
        var undoChanges: [RuleUndoChange] = []
        for candidate in candidates {
            let sourceKey = candidate.source.canonicalComparison
            let replacementKey = candidate.replacement.canonicalWhitespace

            if let index = rules.firstIndex(where: {
                $0.source.canonicalComparison == sourceKey && $0.replacement.canonicalWhitespace == replacementKey
            }) {
                undoChanges.append(
                    RuleUndoChange(ruleID: rules[index].id, previousRule: rules[index])
                )
                rules[index].observationCount += 1
                rules[index].updatedAt = now
                if let bundleIdentifier, !bundleIdentifier.isEmpty {
                    rules[index].bundleIdentifiers.insert(bundleIdentifier)
                }
                affected.append(rules[index])
            } else {
                var bundleIdentifiers: Set<String> = []
                if let bundleIdentifier, !bundleIdentifier.isEmpty {
                    bundleIdentifiers.insert(bundleIdentifier)
                }
                let rule = LearnedCorrection(
                    source: candidate.source,
                    replacement: candidate.replacement,
                    bundleIdentifiers: bundleIdentifiers,
                    createdAt: now,
                    updatedAt: now
                )
                rules.append(rule)
                undoChanges.append(RuleUndoChange(ruleID: rule.id, previousRule: nil))
                affected.append(rule)
            }
        }

        try persist()
        return LearningReceipt(learnedRules: affected, undoChanges: undoChanges)
    }

    public func undo(_ receipt: LearningReceipt) throws {
        guard !receipt.undoChanges.isEmpty else { return }
        for change in receipt.undoChanges {
            if let previousRule = change.previousRule {
                if let index = rules.firstIndex(where: { $0.id == change.ruleID }) {
                    rules[index] = previousRule
                } else {
                    rules.append(previousRule)
                }
            } else {
                rules.removeAll { $0.id == change.ruleID }
            }
        }
        try persist()
    }

    public func apply(to text: String, minimumConfirmations: Int) throws -> CorrectionApplication {
        let application = CorrectionEngine.apply(
            to: text,
            rules: rules,
            minimumConfirmations: minimumConfirmations
        )

        guard !application.appliedRuleIDs.isEmpty else { return application }
        for index in rules.indices where application.appliedRuleIDs.contains(rules[index].id) {
            rules[index].applicationCount += 1
            rules[index].updatedAt = Date()
        }
        try persist()
        return application
    }

    public func setEnabled(_ enabled: Bool, id: UUID) throws {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        rules[index].updatedAt = Date()
        try persist()
    }

    public func delete(id: UUID) throws {
        let oldCount = rules.count
        rules.removeAll { $0.id == id }
        if rules.count != oldCount {
            try persist()
        }
    }

    public func deleteAll() throws {
        guard !rules.isEmpty else { return }
        rules.removeAll()
        try persist()
    }

    public func deleteHistory() throws {
        guard !history.isEmpty else { return }
        history.removeAll()
        try persist()
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Database(rules: sorted(rules), history: history))
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func trimHistory() {
        if history.count > Self.maximumHistoryCount {
            history.removeFirst(history.count - Self.maximumHistoryCount)
        }
    }

    private func sorted(_ rules: [LearnedCorrection]) -> [LearnedCorrection] {
        rules.sorted { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.source.localizedCaseInsensitiveCompare(right.source) == .orderedAscending
        }
    }
}
