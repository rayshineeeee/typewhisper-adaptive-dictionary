import XCTest
@testable import AdaptiveDictionaryCore

final class DeterministicCleanupTests: XCTestCase {
    func testRemovesUnambiguousFillersAndAccidentalDuplicate() {
        let plan = DeterministicCleanup.plan(
            text: "Um, I I need this reviewed.",
            profile: .clear
        )

        XCTAssertEqual(plan.deterministicText, "I need this reviewed.")
        XCTAssertFalse(plan.needsSemanticRewrite)
    }

    func testPreservesIntentionalRepetition() {
        let plan = DeterministicCleanup.plan(
            text: "This is very, very important. No, no, no.",
            profile: .clear
        )

        XCTAssertEqual(plan.deterministicText, "This is very, very important. No, no, no.")
    }

    func testLeavesQuotedSpeechUntouched() {
        let plan = DeterministicCleanup.plan(
            text: "She said “um, I I disagree,” and uh left.",
            profile: .clear
        )

        XCTAssertEqual(plan.deterministicText, "She said “um, I I disagree,” and left.")
    }

    func testRepairsNumericOnOneHandIdiomOutsideQuotes() {
        XCTAssertEqual(
            DeterministicCleanup.plan(
                text: "Like on 1 hand, I know this role gives me more influence.",
                profile: .clear
            ).deterministicText,
            "Like on one hand, I know this role gives me more influence."
        )
        XCTAssertEqual(
            DeterministicCleanup.plan(
                text: "She said \"on 1 hand\" and stopped.",
                profile: .clear
            ).deterministicText,
            "She said \"on 1 hand\" and stopped."
        )
    }

    func testCasualProfileUsesLowercaseAndNoFinalPeriod() {
        let plan = DeterministicCleanup.plan(
            text: "I can send that now.",
            profile: .casual
        )

        XCTAssertEqual(plan.deterministicText, "i can send that now")
    }

    func testCasualProfilePreservesQuestionAndProperName() {
        XCTAssertEqual(
            DeterministicCleanup.plan(text: "Can Ray send that?", profile: .casual).deterministicText,
            "can Ray send that?"
        )
        XCTAssertEqual(
            DeterministicCleanup.plan(text: "Ray can send that.", profile: .casual).deterministicText,
            "Ray can send that"
        )
    }

    func testClearContinuationUsesLowercaseOpening() {
        let context = DictationContext(precedingText: "The main reason is ")
        let plan = DeterministicCleanup.plan(
            text: "That the state is stale.",
            profile: .clear,
            context: context
        )

        XCTAssertEqual(plan.deterministicText, "that the state is stale.")
    }

    func testRoutesAmbiguousCleanupToSemanticModel() {
        let plan = DeterministicCleanup.plan(
            text: "I think this is, like, the second problem.",
            profile: .clear
        )

        XCTAssertTrue(plan.semanticReasons.contains(.ambiguousFiller))
        XCTAssertFalse(plan.semanticReasons.contains(.structuredList))
    }

    func testSemanticLikeDoesNotTriggerModel() {
        let plan = DeterministicCleanup.plan(
            text: "This works like a compiler.",
            profile: .clear
        )

        XCTAssertFalse(plan.semanticReasons.contains(.ambiguousFiller))
    }

    func testPotentiallyGrammaticalRepetitionRemainsUntouched() {
        let plan = DeterministicCleanup.plan(
            text: "She had had enough.",
            profile: .clear
        )

        XCTAssertEqual(plan.deterministicText, "She had had enough.")
    }

    func testRoutesSelfCorrectionAndFormattingCommand() {
        let plan = DeterministicCleanup.plan(
            text: "Actually wait, scratch that. Put this in bullets: first speed, second safety.",
            profile: .clear
        )

        XCTAssertTrue(plan.semanticReasons.contains(.selfCorrection))
        XCTAssertTrue(plan.semanticReasons.contains(.spokenFormatting))
        XCTAssertTrue(plan.semanticReasons.contains(.structuredList))
    }

    func testProfileRoutingIsOnlyCasualForMessagesAndWeChat() {
        XCTAssertEqual(DictationProfile.resolve(bundleIdentifier: "com.apple.MobileSMS"), .casual)
        XCTAssertEqual(DictationProfile.resolve(bundleIdentifier: "com.tencent.xinWeChat"), .casual)
        XCTAssertEqual(DictationProfile.resolve(bundleIdentifier: "notion.id"), .clear)
        XCTAssertEqual(DictationProfile.resolve(bundleIdentifier: nil), .clear)
    }
}
