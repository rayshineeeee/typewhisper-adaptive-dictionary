import Foundation

public actor CorrectionStore {
    private struct Database: Codable {
        var schemaVersion = 1
        var rules: [LearnedCorrection]
    }

    private let fileURL: URL
    private var rules: [LearnedCorrection]

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            rules = try decoder.decode(Database.self, from: data).rules
        } else {
            rules = []
        }
    }

    public func snapshot() -> [LearnedCorrection] {
        sorted(rules)
    }

    @discardableResult
    public func observe(
        original: String,
        corrected: String,
        bundleIdentifier: String?,
        now: Date = Date()
    ) throws -> [LearnedCorrection] {
        let candidates = CorrectionExtractor.extract(original: original, corrected: corrected)
        guard !candidates.isEmpty else { return [] }

        var affected: [LearnedCorrection] = []
        for candidate in candidates {
            let sourceKey = candidate.source.canonicalComparison
            let replacementKey = candidate.replacement.canonicalWhitespace

            if let index = rules.firstIndex(where: {
                $0.source.canonicalComparison == sourceKey && $0.replacement.canonicalWhitespace == replacementKey
            }) {
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
                affected.append(rule)
            }
        }

        try persist()
        return affected
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
        let data = try encoder.encode(Database(rules: sorted(rules)))
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func sorted(_ rules: [LearnedCorrection]) -> [LearnedCorrection] {
        rules.sorted { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.source.localizedCaseInsensitiveCompare(right.source) == .orderedAscending
        }
    }
}
