import Foundation

public enum CorrectionEngine {
    private struct MatchProposal {
        let range: NSRange
        let replacement: String
        let rule: LearnedCorrection
    }

    public static func apply(
        to text: String,
        rules: [LearnedCorrection],
        minimumConfirmations: Int
    ) -> CorrectionApplication {
        guard !text.isEmpty else {
            return CorrectionApplication(text: text, appliedRuleIDs: [])
        }

        let activeRules = rules.filter { $0.isActive(minimumConfirmations: minimumConfirmations) }
        guard !activeRules.isEmpty else {
            return CorrectionApplication(text: text, appliedRuleIDs: [])
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var proposals: [MatchProposal] = []

        for rule in activeRules {
            guard let regex = regex(for: rule.source) else { continue }
            for match in regex.matches(in: text, range: fullRange) {
                guard let matchRange = Range(match.range, in: text),
                    String(text[matchRange]) != rule.replacement
                else {
                    continue
                }
                proposals.append(
                    MatchProposal(
                        range: match.range,
                        replacement: rule.replacement,
                        rule: rule
                    ))
            }
        }

        proposals.sort { left, right in
            if left.range.location != right.range.location {
                return left.range.location < right.range.location
            }
            if left.range.length != right.range.length {
                return left.range.length > right.range.length
            }
            if left.rule.observationCount != right.rule.observationCount {
                return left.rule.observationCount > right.rule.observationCount
            }
            return left.rule.updatedAt > right.rule.updatedAt
        }

        var selected: [MatchProposal] = []
        for proposal in proposals
        where !selected.contains(where: { NSIntersectionRange($0.range, proposal.range).length > 0 }) {
            selected.append(proposal)
        }

        guard !selected.isEmpty else {
            return CorrectionApplication(text: text, appliedRuleIDs: [])
        }

        var result = text
        for proposal in selected.sorted(by: { $0.range.location > $1.range.location }) {
            guard let replacementRange = Range(proposal.range, in: result) else { continue }
            result.replaceSubrange(replacementRange, with: proposal.replacement)
        }

        return CorrectionApplication(
            text: result,
            appliedRuleIDs: Set(selected.map(\.rule.id))
        )
    }

    private static func regex(for source: String) -> NSRegularExpression? {
        let tokens = source.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }
        let phrase =
            tokens
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: #"\s+"#)
        let pattern = #"(?<![\p{L}\p{M}\p{N}_])(?:"# + phrase + #")(?![\p{L}\p{M}\p{N}_])"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
