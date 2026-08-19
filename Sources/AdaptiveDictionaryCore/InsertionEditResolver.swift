import Foundation

public enum InsertionEditResolver {
    public static func locateInsertedRange(
        text: String,
        in baseline: String,
        selectedRange: NSRange?
    ) -> NSRange? {
        let baselineString = baseline as NSString
        let textLength = (text as NSString).length
        guard textLength > 0, baselineString.length >= textLength else { return nil }

        if let selectedRange {
            let candidate = NSRange(
                location: selectedRange.location - textLength,
                length: textLength
            )
            if candidate.location >= 0,
                NSMaxRange(candidate) <= baselineString.length,
                baselineString.substring(with: candidate) == text
            {
                return candidate
            }
        }

        var searchRange = NSRange(location: 0, length: baselineString.length)
        var matches: [NSRange] = []
        while searchRange.length > 0 {
            let match = baselineString.range(of: text, options: [], range: searchRange)
            guard match.location != NSNotFound else { break }
            matches.append(match)
            let nextLocation = NSMaxRange(match)
            searchRange = NSRange(location: nextLocation, length: baselineString.length - nextLocation)
        }

        guard !matches.isEmpty else { return nil }
        let cursor = selectedRange?.location ?? baselineString.length
        return matches.min { abs(NSMaxRange($0) - cursor) < abs(NSMaxRange($1) - cursor) }
    }

    public static func correctedInsertedText(
        baselineText: String,
        editedText: String,
        insertedRange: NSRange
    ) -> String? {
        guard baselineText != editedText else { return nil }
        let baseline = Array(baselineText.utf16)
        let edited = Array(editedText.utf16)

        var prefixLength = 0
        while prefixLength < baseline.count,
            prefixLength < edited.count,
            baseline[prefixLength] == edited[prefixLength]
        {
            prefixLength += 1
        }

        var suffixLength = 0
        while suffixLength < baseline.count - prefixLength,
            suffixLength < edited.count - prefixLength,
            baseline[baseline.count - 1 - suffixLength] == edited[edited.count - 1 - suffixLength]
        {
            suffixLength += 1
        }

        let baselineChange = NSRange(
            location: prefixLength,
            length: baseline.count - prefixLength - suffixLength
        )
        let editedChange = NSRange(
            location: prefixLength,
            length: edited.count - prefixLength - suffixLength
        )
        guard baselineChange.location >= insertedRange.location,
            NSMaxRange(baselineChange) <= NSMaxRange(insertedRange)
        else {
            return nil
        }

        let baselineString = baselineText as NSString
        let editedString = editedText as NSString
        let beforeRange = NSRange(
            location: insertedRange.location,
            length: baselineChange.location - insertedRange.location
        )
        let afterRange = NSRange(
            location: NSMaxRange(baselineChange),
            length: NSMaxRange(insertedRange) - NSMaxRange(baselineChange)
        )
        let corrected =
            baselineString.substring(with: beforeRange)
            + editedString.substring(with: editedChange)
            + baselineString.substring(with: afterRange)
        let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
