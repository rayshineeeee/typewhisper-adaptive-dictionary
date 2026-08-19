import Foundation
import XCTest
@testable import AdaptiveDictionaryCore

final class CorrectionStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testObservationsAccumulateAndRetainAppContext() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("corrections.json")
        let store = try CorrectionStore(fileURL: fileURL)

        _ = try await store.observe(
            original: "open lemma labs",
            corrected: "open Lemma",
            bundleIdentifier: "com.apple.Notes"
        )
        _ = try await store.observe(
            original: "ask lemma labs",
            corrected: "ask Lemma",
            bundleIdentifier: "com.tinyspeck.slackmacgap"
        )

        let rules = await store.snapshot()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].observationCount, 2)
        XCTAssertEqual(
            rules[0].bundleIdentifiers,
            [
                "com.apple.Notes",
                "com.tinyspeck.slackmacgap",
            ])
    }

    func testPersistsRulesAndApplicationCounts() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("corrections.json")
        let writer = try CorrectionStore(fileURL: fileURL)
        _ = try await writer.observe(
            original: "use type whisper",
            corrected: "use TypeWhisper",
            bundleIdentifier: nil
        )
        _ = try await writer.observe(
            original: "open type whisper",
            corrected: "open TypeWhisper",
            bundleIdentifier: nil
        )
        let application = try await writer.apply(to: "open type whisper", minimumConfirmations: 2)
        XCTAssertEqual(application.text, "open TypeWhisper")

        let reader = try CorrectionStore(fileURL: fileURL)
        let rules = await reader.snapshot()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].applicationCount, 1)
    }

    func testCanDisableAndDeleteRule() async throws {
        let fileURL = temporaryDirectory.appendingPathComponent("corrections.json")
        let store = try CorrectionStore(fileURL: fileURL)
        let observed = try await store.observe(
            original: "use convex",
            corrected: "use Convex",
            bundleIdentifier: nil
        )
        let id = try XCTUnwrap(observed.first?.id)

        try await store.setEnabled(false, id: id)
        let disabledApplication = try await store.apply(to: "use convex", minimumConfirmations: 1)
        XCTAssertEqual(disabledApplication.text, "use convex")

        try await store.delete(id: id)
        let remainingRules = await store.snapshot()
        XCTAssertEqual(remainingRules, [])
    }
}
