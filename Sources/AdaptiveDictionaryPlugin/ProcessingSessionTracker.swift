import AdaptiveDictionaryCore
import Foundation

final class ProcessingSessionTracker: @unchecked Sendable {
    struct Snapshot: Sendable {
        let inputText: String
        let outputText: String
        let profile: DictationProfile
        let bundleIdentifier: String?
        let createdAt: Date
    }

    private struct PendingRecord {
        let id: UUID
        let outputText: String
        let bundleIdentifier: String?
        let createdAt: Date
    }

    private var latestSnapshot: Snapshot?
    private var pendingRecord: PendingRecord?

    @MainActor func recordProcessed(
        inputText: String,
        outputText: String,
        profile: DictationProfile,
        bundleIdentifier: String?
    ) {
        latestSnapshot = Snapshot(
            inputText: inputText,
            outputText: outputText,
            profile: profile,
            bundleIdentifier: bundleIdentifier,
            createdAt: Date()
        )
    }

    @MainActor func consumeInsertion(text: String, bundleIdentifier: String?) -> Snapshot? {
        guard let snapshot = latestSnapshot,
            Date().timeIntervalSince(snapshot.createdAt) < 20,
            bundleIdentifier == snapshot.bundleIdentifier,
            equivalent(text, snapshot.outputText)
        else { return nil }
        latestSnapshot = nil
        return snapshot
    }

    @MainActor func associate(recordID: UUID, with snapshot: Snapshot) {
        pendingRecord = PendingRecord(
            id: recordID,
            outputText: snapshot.outputText,
            bundleIdentifier: snapshot.bundleIdentifier,
            createdAt: Date()
        )
    }

    @MainActor func consumeRecordID(finalText: String, bundleIdentifier: String?) -> UUID? {
        guard let pendingRecord,
            Date().timeIntervalSince(pendingRecord.createdAt) < 20,
            bundleIdentifier == pendingRecord.bundleIdentifier,
            equivalent(finalText, pendingRecord.outputText)
        else { return nil }
        self.pendingRecord = nil
        return pendingRecord.id
    }

    private func equivalent(_ left: String, _ right: String) -> Bool {
        left.trimmingCharacters(in: .whitespacesAndNewlines)
            == right.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
