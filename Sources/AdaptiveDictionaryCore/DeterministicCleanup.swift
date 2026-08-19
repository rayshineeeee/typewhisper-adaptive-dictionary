import Foundation

public enum SemanticRewriteReason: String, Codable, CaseIterable, Sendable {
    case ambiguousFiller
    case selfCorrection
    case spokenFormatting
    case structuredList
    case repeatedPhrase
    case convolutedPassage
}

public struct CleanupPlan: Sendable, Equatable {
    public let originalText: String
    public let deterministicText: String
    public let profile: DictationProfile
    public let semanticReasons: Set<SemanticRewriteReason>

    public init(
        originalText: String,
        deterministicText: String,
        profile: DictationProfile,
        semanticReasons: Set<SemanticRewriteReason>
    ) {
        self.originalText = originalText
        self.deterministicText = deterministicText
        self.profile = profile
        self.semanticReasons = semanticReasons
    }

    public var needsSemanticRewrite: Bool { !semanticReasons.isEmpty }
}

public enum DeterministicCleanup {
    private static let fillerPattern = #"(?i)(?<![\p{L}\p{N}_])(?:uh+|um+|erm+|ehm+)(?![\p{L}\p{N}_])[,;:]?[ \t]*"#
    private static let duplicateWordPattern =
        #"(?i)(?<![\p{L}\p{N}_])([\p{L}][\p{L}\p{M}'’-]*)([ \t]*,[ \t]*|[ \t]+)(\1)(?![\p{L}\p{N}_])"#
    private static let emphaticRepetitions: Set<String> = [
        "absolutely", "definitely", "no", "never", "really", "so", "very", "way", "yes",
    ]
    private static let potentiallyGrammaticalRepetitions: Set<String> = [
        "do", "had", "is", "that", "was", "were",
    ]
    private static let safeSentenceStarts: Set<String> = [
        "a", "actually", "also", "and", "are", "but", "can", "could", "did", "do", "does",
        "for", "here", "how", "i", "if", "in", "is", "it", "let", "maybe", "my", "please",
        "so", "that", "the", "then", "there", "these", "this", "those", "to", "we", "what",
        "when", "where", "which", "who", "why", "will", "would", "you",
    ]

    public static func plan(
        text: String,
        profile: DictationProfile,
        context: DictationContext = DictationContext()
    ) -> CleanupPlan {
        guard !text.isEmpty else {
            return CleanupPlan(
                originalText: text,
                deterministicText: text,
                profile: profile,
                semanticReasons: []
            )
        }

        let reasons = semanticReasons(in: text)
        var cleaned = transformOutsideQuotes(text) { segment in
            normalizeSegment(
                normalizeCommonDictationIdioms(
                    removeDuplicateWords(from: removeFillers(from: segment))
                )
            )
        }
        cleaned = applySurfaceStyle(cleaned, profile: profile, context: context)

        return CleanupPlan(
            originalText: text,
            deterministicText: cleaned,
            profile: profile,
            semanticReasons: reasons
        )
    }

    private static func removeFillers(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: fillerPattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func removeDuplicateWords(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: duplicateWordPattern) else { return text }
        var result = text

        while true {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, range: range)
            var changed = false

            for match in matches.reversed() {
                guard let wordRange = Range(match.range(at: 1), in: result),
                    let matchRange = Range(match.range, in: result)
                else { continue }
                let word = String(result[wordRange]).lowercased()
                guard !emphaticRepetitions.contains(word),
                    !potentiallyGrammaticalRepetitions.contains(word)
                else { continue }
                let repeatedRange = match.range(at: 3)
                guard let repeatedSwiftRange = Range(repeatedRange, in: result) else { continue }
                result.replaceSubrange(matchRange, with: String(result[repeatedSwiftRange]))
                changed = true
            }

            if !changed { return result }
        }
    }

    private static func normalizeSegment(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            (#"[ \t]{2,}"#, " "),
            (#"[ \t]+([,.;:!?])"#, "$1"),
            (#"([,;:])[ \t]*([,;:])"#, "$2"),
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return result
    }

    private static func normalizeCommonDictationIdioms(_ text: String) -> String {
        let replacements: [(String, String)] = [
            (#"\bOn the 1 hand\b"#, "On the one hand"),
            (#"\bon the 1 hand\b"#, "on the one hand"),
            (#"\bOn 1 hand\b"#, "On one hand"),
            (#"\bon 1 hand\b"#, "on one hand"),
        ]
        return replacements.reduce(text) { result, replacement in
            result.replacingOccurrences(
                of: replacement.0,
                with: replacement.1,
                options: .regularExpression
            )
        }
    }

    private static func applySurfaceStyle(
        _ text: String,
        profile: DictationProfile,
        context: DictationContext
    ) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        let continuesSentence =
            context.precedingText.map { preceding in
                guard let last = preceding.last(where: { !$0.isWhitespace }) else { return false }
                return !".!?\n".contains(last)
            } ?? false

        switch profile {
        case .casual:
            result = changeFirstWordCase(in: result, uppercase: false)
            if result.hasSuffix("."), !result.hasSuffix("...") {
                result.removeLast()
            }
        case .clear:
            result = changeFirstWordCase(in: result, uppercase: !continuesSentence)
            if continuesSentence {
                result = changeFirstWordCase(in: result, uppercase: false)
            }
        }
        return result
    }

    private static func changeFirstWordCase(in text: String, uppercase: Bool) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^([\"“‘'\(\[\{]*)([\p{L}][\p{L}\p{M}'’-]*)"#),
            let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
            ),
            let wordRange = Range(match.range(at: 2), in: text)
        else { return text }

        let word = String(text[wordRange])
        guard safeSentenceStarts.contains(word.lowercased()), let first = word.first else { return text }
        let transformedFirst = uppercase ? String(first).uppercased() : String(first).lowercased()
        var result = text
        result.replaceSubrange(wordRange, with: transformedFirst + word.dropFirst())
        return result
    }

    private static func semanticReasons(in text: String) -> Set<SemanticRewriteReason> {
        var reasons: Set<SemanticRewriteReason> = []
        let lowercased = text.lowercased()

        if contains(pattern: #"\bi think\b"#, in: lowercased)
            || contains(pattern: #"\blike\s*,|,\s*like\b"#, in: lowercased)
            || contains(
                pattern: #"\b(?:this|that|it|i|we|you)\s+like\s+(?:is|are|was|were|think|want|need)\b"#,
                in: lowercased
            )
        {
            reasons.insert(.ambiguousFiller)
        }
        if contains(
            pattern:
                #"\b(?:never mind|nevermind|actually wait|wait actually|scratch that|correction|i mean|no,? sorry)\b"#,
            in: lowercased
        ) {
            reasons.insert(.selfCorrection)
        }
        if contains(
            pattern:
                #"\b(?:put (?:that|this) in (?:bullet points|bullets)|make (?:that|this) a (?:list|bullet list)|new paragraph|new bullet)\b"#,
            in: lowercased
        ) {
            reasons.insert(.spokenFormatting)
        }
        let ordinalCount = matches(
            pattern: #"\b(?:first(?:ly)?|second(?:ly)?|third(?:ly)?)\b"#,
            in: lowercased
        )
        if ordinalCount >= 2
            || contains(
                pattern: #"\b(?:three (?:problems|issues|reasons|steps|things)|the following)\b"#,
                in: lowercased
            )
        {
            reasons.insert(.structuredList)
        }
        if hasRepeatedPhrase(in: lowercased) {
            reasons.insert(.repeatedPhrase)
        }

        let wordCount = lowercased.split(whereSeparator: { $0.isWhitespace }).count
        let clauseCount = lowercased.filter { ",;—".contains($0) }.count
        if wordCount >= 65 || (wordCount >= 35 && clauseCount >= 5) {
            reasons.insert(.convolutedPassage)
        }
        return reasons
    }

    private static func hasRepeatedPhrase(in text: String) -> Bool {
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard words.count >= 6 else { return false }
        for phraseLength in 2...3 where words.count >= phraseLength * 2 {
            for index in 0...(words.count - phraseLength * 2) {
                let first = words[index..<(index + phraseLength)]
                let second = words[(index + phraseLength)..<(index + phraseLength * 2)]
                if first.elementsEqual(second) { return true }
            }
        }
        return false
    }

    private static func contains(pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func matches(pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
    }

    private static func transformOutsideQuotes(
        _ text: String,
        transform: (String) -> String
    ) -> String {
        var result = ""
        var segment = ""
        var closingQuote: Character?

        func flush(transformed: Bool) {
            result += transformed ? transform(segment) : segment
            segment.removeAll(keepingCapacity: true)
        }

        for character in text {
            if let expectedClosingQuote = closingQuote {
                segment.append(character)
                if character == expectedClosingQuote {
                    flush(transformed: false)
                    closingQuote = nil
                }
            } else if character == "\"" {
                flush(transformed: true)
                segment.append(character)
                closingQuote = "\""
            } else if character == "“" {
                flush(transformed: true)
                segment.append(character)
                closingQuote = "”"
            } else {
                segment.append(character)
            }
        }
        flush(transformed: closingQuote == nil)
        return result
    }
}
