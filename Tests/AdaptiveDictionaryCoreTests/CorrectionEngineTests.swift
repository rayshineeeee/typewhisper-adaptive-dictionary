import Foundation
import XCTest
@testable import AdaptiveDictionaryCore

final class CorrectionEngineTests: XCTestCase {
    func testCasingRuleActivatesImmediately() {
        let rule = LearnedCorrection(source: "linear", replacement: "Linear")

        let result = CorrectionEngine.apply(
            to: "open linear",
            rules: [rule],
            minimumConfirmations: 2
        )

        XCTAssertEqual(result.text, "open Linear")
        XCTAssertEqual(result.appliedRuleIDs, [rule.id])
    }

    func testNonCasingRuleWaitsForConfirmationThreshold() {
        let pending = LearnedCorrection(source: "lemma labs", replacement: "Lemma")
        var confirmed = pending
        confirmed.observationCount = 2

        XCTAssertEqual(
            CorrectionEngine.apply(to: "ask lemma labs", rules: [pending], minimumConfirmations: 2).text,
            "ask lemma labs"
        )
        XCTAssertEqual(
            CorrectionEngine.apply(to: "ask lemma labs", rules: [confirmed], minimumConfirmations: 2).text,
            "ask Lemma"
        )
    }

    func testMatchesOnlyWholeBoundaries() {
        let rule = LearnedCorrection(source: "ray", replacement: "Ray", observationCount: 2)

        let result = CorrectionEngine.apply(
            to: "ray uses array and xray",
            rules: [rule],
            minimumConfirmations: 2
        )

        XCTAssertEqual(result.text, "Ray uses array and xray")
    }

    func testUsesLongestNonOverlappingRule() {
        let short = LearnedCorrection(source: "type whisper", replacement: "TypeWhisper", observationCount: 5)
        let long = LearnedCorrection(
            source: "type whisper plugin",
            replacement: "Adaptive Dictionary",
            observationCount: 2
        )

        let result = CorrectionEngine.apply(
            to: "the type whisper plugin works",
            rules: [short, long],
            minimumConfirmations: 2
        )

        XCTAssertEqual(result.text, "the Adaptive Dictionary works")
        XCTAssertEqual(result.appliedRuleIDs, [long.id])
    }

    func testDoesNotCascadeReplacements() {
        let first = LearnedCorrection(source: "alpha", replacement: "beta", observationCount: 2)
        let second = LearnedCorrection(source: "beta", replacement: "gamma", observationCount: 2)

        let result = CorrectionEngine.apply(
            to: "alpha",
            rules: [first, second],
            minimumConfirmations: 2
        )

        XCTAssertEqual(result.text, "beta")
        XCTAssertEqual(result.appliedRuleIDs, [first.id])
    }

    func testPrefersMoreObservedConflictingRule() {
        let older = Date(timeIntervalSince1970: 100)
        let lessObserved = LearnedCorrection(
            source: "codex",
            replacement: "Code X",
            observationCount: 2,
            updatedAt: older
        )
        let moreObserved = LearnedCorrection(
            source: "codex",
            replacement: "Codex",
            observationCount: 4,
            updatedAt: older
        )

        let result = CorrectionEngine.apply(
            to: "open codex",
            rules: [lessObserved, moreObserved],
            minimumConfirmations: 2
        )

        XCTAssertEqual(result.text, "open Codex")
        XCTAssertEqual(result.appliedRuleIDs, [moreObserved.id])
    }
}
