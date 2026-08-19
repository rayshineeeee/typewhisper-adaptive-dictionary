import XCTest
@testable import AdaptiveDictionaryCore

final class CorrectionExtractorTests: XCTestCase {
    func testExtractsSingleWordCasingCorrection() {
        let candidates = CorrectionExtractor.extract(
            original: "I opened linear today",
            corrected: "I opened Linear today"
        )

        XCTAssertEqual(candidates, [CorrectionCandidate(source: "linear", replacement: "Linear")])
    }

    func testExtractsMultiwordToSingleWordCorrection() {
        let candidates = CorrectionExtractor.extract(
            original: "Please open git hub issues",
            corrected: "Please open GitHub issues"
        )

        XCTAssertEqual(candidates, [CorrectionCandidate(source: "git hub", replacement: "GitHub")])
    }

    func testExtractsTwoIndependentCorrections() {
        let candidates = CorrectionExtractor.extract(
            original: "Use type whisper with convex",
            corrected: "Use TypeWhisper with Convex"
        )

        XCTAssertEqual(
            candidates,
            [
                CorrectionCandidate(source: "type whisper", replacement: "TypeWhisper"),
                CorrectionCandidate(source: "convex", replacement: "Convex"),
            ])
    }

    func testIgnoresPunctuationOnlyEdit() {
        XCTAssertEqual(
            CorrectionExtractor.extract(original: "hello world", corrected: "hello, world!"),
            []
        )
    }

    func testIgnoresInsertionWithoutReplacement() {
        XCTAssertEqual(
            CorrectionExtractor.extract(original: "ship today", corrected: "please ship today"),
            []
        )
    }

    func testRejectsCorrectionMixedWithContinuedTyping() {
        XCTAssertEqual(
            CorrectionExtractor.extract(
                original: "open linear",
                corrected: "open Linear and check issues"
            ),
            []
        )
    }

    func testRejectsRiskyFunctionWordReplacement() {
        XCTAssertEqual(
            CorrectionExtractor.extract(original: "send it to Ray", corrected: "send it for Ray"),
            []
        )
    }

    func testRejectsLargeRewrite() {
        XCTAssertEqual(
            CorrectionExtractor.extract(
                original: "one two three four five six seven",
                corrected: "alpha beta gamma delta epsilon zeta eta"
            ),
            []
        )
    }
}
