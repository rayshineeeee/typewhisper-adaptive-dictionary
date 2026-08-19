import Foundation

public enum CorrectionExtractor {
    private struct Token: Equatable {
        let text: String
    }

    private enum DiffOperation {
        case unchanged
        case removed(Token)
        case added(Token)
    }

    private static let tokenPattern = #"[\p{L}\p{M}\p{N}]+(?:['’.-][\p{L}\p{M}\p{N}]+)*"#
    private static let riskySingleWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from", "i", "in",
        "is", "it", "of", "on", "or", "that", "the", "this", "to", "was", "were", "with",
    ]

    public static func extract(
        original: String,
        corrected: String,
        maximumCandidates: Int = 3,
        maximumWordsPerSide: Int = 4
    ) -> [CorrectionCandidate] {
        guard original != corrected,
            !original.isEmpty,
            !corrected.isEmpty,
            original.count <= 1_200,
            corrected.count <= 1_200,
            maximumCandidates > 0,
            maximumWordsPerSide > 0
        else {
            return []
        }

        let originalTokens = tokens(in: original)
        let correctedTokens = tokens(in: corrected)
        guard !originalTokens.isEmpty, !correctedTokens.isEmpty else { return [] }

        let operations = diff(original: originalTokens, corrected: correctedTokens)
        var candidates: [CorrectionCandidate] = []
        var removed: [Token] = []
        var added: [Token] = []

        func flush() -> Bool {
            defer {
                removed.removeAll(keepingCapacity: true)
                added.removeAll(keepingCapacity: true)
            }

            guard !removed.isEmpty,
                !added.isEmpty,
                removed.count <= maximumWordsPerSide,
                added.count <= maximumWordsPerSide
            else {
                return true
            }

            let source = removed.map(\.text).joined(separator: " ").canonicalWhitespace
            let replacement = added.map(\.text).joined(separator: " ").canonicalWhitespace
            let removedKeys = removed.map { $0.text.canonicalComparison }
            let addedKeys = added.map { $0.text.canonicalComparison }
            guard !isExpansionOfSource(removedKeys, addedKeys) else { return true }
            guard isSafe(source: source, replacement: replacement) else { return true }

            candidates.append(CorrectionCandidate(source: source, replacement: replacement))
            return candidates.count <= maximumCandidates
        }

        for operation in operations {
            switch operation {
            case .unchanged:
                guard flush() else { return [] }
            case .removed(let token):
                removed.append(token)
            case .added(let token):
                added.append(token)
            }
        }
        guard flush(), !candidates.isEmpty else { return [] }

        let unchangedCount = operations.reduce(into: 0) { count, operation in
            if case .unchanged = operation { count += 1 }
        }
        let largestSide = max(originalTokens.count, correctedTokens.count)
        if unchangedCount == 0 && largestSide > maximumWordsPerSide {
            return []
        }

        return candidates
    }

    private static func tokens(in text: String) -> [Token] {
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return Token(text: String(text[range]))
        }
    }

    private static func diff(original: [Token], corrected: [Token]) -> [DiffOperation] {
        let originalCount = original.count
        let correctedCount = corrected.count
        var lengths = Array(
            repeating: Array(repeating: 0, count: correctedCount + 1),
            count: originalCount + 1
        )

        if originalCount > 0, correctedCount > 0 {
            for originalIndex in 1...originalCount {
                for correctedIndex in 1...correctedCount {
                    if original[originalIndex - 1] == corrected[correctedIndex - 1] {
                        lengths[originalIndex][correctedIndex] = lengths[originalIndex - 1][correctedIndex - 1] + 1
                    } else {
                        lengths[originalIndex][correctedIndex] = max(
                            lengths[originalIndex - 1][correctedIndex],
                            lengths[originalIndex][correctedIndex - 1]
                        )
                    }
                }
            }
        }

        var operations: [DiffOperation] = []
        var originalIndex = originalCount
        var correctedIndex = correctedCount

        while originalIndex > 0 || correctedIndex > 0 {
            if originalIndex > 0,
                correctedIndex > 0,
                original[originalIndex - 1] == corrected[correctedIndex - 1]
            {
                operations.append(.unchanged)
                originalIndex -= 1
                correctedIndex -= 1
            } else if correctedIndex > 0,
                (originalIndex == 0
                    || lengths[originalIndex][correctedIndex - 1] >= lengths[originalIndex - 1][correctedIndex])
            {
                operations.append(.added(corrected[correctedIndex - 1]))
                correctedIndex -= 1
            } else {
                operations.append(.removed(original[originalIndex - 1]))
                originalIndex -= 1
            }
        }

        return operations.reversed()
    }

    private static func isSafe(source: String, replacement: String) -> Bool {
        guard source != replacement,
            source.count <= 80,
            replacement.count <= 80,
            source.rangeOfCharacter(from: .alphanumerics) != nil,
            replacement.rangeOfCharacter(from: .alphanumerics) != nil
        else {
            return false
        }

        let sourceWords = source.split(whereSeparator: \.isWhitespace)
        if sourceWords.count == 1,
            riskySingleWords.contains(source.canonicalComparison),
            source.canonicalComparison != replacement.canonicalComparison
        {
            return false
        }

        return true
    }

    private static func isExpansionOfSource(_ source: [String], _ replacement: [String]) -> Bool {
        guard source.count < replacement.count else { return false }
        var sourceIndex = 0
        for token in replacement {
            guard sourceIndex < source.count else { break }
            if token == source[sourceIndex] {
                sourceIndex += 1
            }
        }
        return sourceIndex == source.count
    }
}
