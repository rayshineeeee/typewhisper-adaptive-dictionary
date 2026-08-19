import XCTest
@testable import AdaptiveDictionaryCore

final class SemanticRewriteTests: XCTestCase {
    @MainActor
    private final class StubProvider: SemanticRewriteProvider, @unchecked Sendable {
        let output: String

        init(output: String) {
            self.output = output
        }

        func rewrite(_ request: SemanticRewriteRequest) async throws -> String {
            output
        }
    }

    @MainActor
    private final class SlowProvider: SemanticRewriteProvider, @unchecked Sendable {
        func rewrite(_ request: SemanticRewriteRequest) async throws -> String {
            try await Task.sleep(for: .seconds(2))
            return request.deterministicText
        }
    }

    func testPromptForbidsAnsweringAndIncludesContext() {
        let request = SemanticRewriteRequest(
            originalText: "Can you inspect useState?",
            deterministicText: "Can you inspect useState?",
            profile: .clear,
            context: DictationContext(
                appName: "Cursor",
                selectedText: "const [value, setValue] = useState(0)",
                precedingText: "Please review this component. "
            ),
            reasons: [.convolutedPassage]
        )

        let prompt = SemanticPromptBuilder.userPrompt(for: request)
        XCTAssertTrue(SemanticPromptBuilder.systemPrompt.contains("Never answer a question"))
        XCTAssertTrue(prompt.contains("Cursor"))
        XCTAssertTrue(prompt.contains("useState"))
        XCTAssertTrue(prompt.contains("Please review this component"))
    }

    func testValidatorAcceptsConservativePromptCleanup() {
        let request = SemanticRewriteRequest(
            originalText: "Can you look at this React component focus on useState and give me fixes",
            deterministicText: "Can you look at this React component focus on useState and give me fixes",
            profile: .clear,
            context: DictationContext(),
            reasons: [.convolutedPassage]
        )

        XCTAssertEqual(
            SemanticRewriteValidator.validatedCandidate(
                "Can you look at this React component? Focus on useState and give me fixes.",
                for: request
            ),
            "Can you look at this React component? Focus on useState and give me fixes."
        )
    }

    func testValidatorRejectsAssistantAnswer() {
        let request = SemanticRewriteRequest(
            originalText: "What are the problems with useState?",
            deterministicText: "What are the problems with useState?",
            profile: .clear,
            context: DictationContext(),
            reasons: [.ambiguousFiller]
        )

        XCTAssertNil(
            SemanticRewriteValidator.validatedCandidate(
                "Sure, here are the problems with useState: stale closures and extra renders.",
                for: request
            )
        )
    }

    func testValidatorPreservesNumbersUrlsIdentifiersAndQuotes() {
        let request = SemanticRewriteRequest(
            originalText: "Send 42 to https://example.com using user_id and say “um, leave this.”",
            deterministicText: "Send 42 to https://example.com using user_id and say “um, leave this.”",
            profile: .clear,
            context: DictationContext(),
            reasons: [.convolutedPassage]
        )

        XCTAssertNil(
            SemanticRewriteValidator.validatedCandidate(
                "Send 43 to example.com using userId and say leave this.",
                for: request
            )
        )
    }

    func testValidatorRejectsNewNumericLiteralForNumberWord() {
        let request = SemanticRewriteRequest(
            originalText: "On one hand, I think this role gives me more influence.",
            deterministicText: "On one hand, I think this role gives me more influence.",
            profile: .clear,
            context: DictationContext(),
            reasons: [.ambiguousFiller]
        )

        XCTAssertNil(
            SemanticRewriteValidator.validatedCandidate(
                "On 1 hand, I think this role gives me more influence.",
                for: request
            )
        )
    }

    @MainActor
    func testPipelineUsesModelOnlyForSemanticCase() async {
        let provider = StubProvider(output: "Can you inspect this component? Focus on state management.")
        let semantic = await DictationPipeline.process(
            text: "Can you inspect this component I think focus on state management",
            profile: .clear,
            context: DictationContext(),
            semanticProvider: provider
        )
        let deterministic = await DictationPipeline.process(
            text: "Um, I I can send it now.",
            profile: .clear,
            context: DictationContext(),
            semanticProvider: provider
        )

        XCTAssertTrue(semantic.usedSemanticModel)
        XCTAssertEqual(semantic.text, "Can you inspect this component? Focus on state management.")
        XCTAssertFalse(deterministic.usedSemanticModel)
        XCTAssertEqual(deterministic.text, "I can send it now.")
    }

    @MainActor
    func testPipelineRejectsAssistantBehavior() async {
        let provider = StubProvider(output: "Sure, here are the answers: use an actor.")
        let result = await DictationPipeline.process(
            text: "Can you review this code I think and tell me the problems?",
            profile: .clear,
            context: DictationContext(),
            semanticProvider: provider
        )

        XCTAssertFalse(result.usedSemanticModel)
        XCTAssertEqual(result.fallbackReason, "Local rewrite failed safety checks")
    }

    @MainActor
    func testTimeoutReturnsWithoutWaitingForProviderCancellation() async {
        let start = ContinuousClock.now
        let result = await DictationPipeline.process(
            text: "Can you inspect this component I think focus on state management",
            profile: .clear,
            context: DictationContext(),
            semanticProvider: SlowProvider(),
            shortTimeout: .milliseconds(50)
        )

        XCTAssertFalse(result.usedSemanticModel)
        XCTAssertEqual(result.fallbackReason, "Local rewrite timed out")
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(250))
    }
}
