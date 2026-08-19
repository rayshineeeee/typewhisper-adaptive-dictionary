import AdaptiveDictionaryCore
import Foundation
import TypeWhisperPluginSDK

final class AdaptiveDictionarySettingsModel: ObservableObject, @unchecked Sendable {
    private static let learningEnabledKey = "learningEnabled"
    private static let minimumConfirmationsKey = "minimumConfirmations"

    private let host: HostServices
    private let store: CorrectionStore?
    private let onLearningChanged: @MainActor @Sendable (Bool) -> CaptureStatus

    @Published private(set) var rules: [LearnedCorrection] = []
    @Published private(set) var learningEnabled: Bool
    @Published private(set) var minimumConfirmations: Int
    @Published private(set) var captureStatus: CaptureStatus = .disabled
    @Published private(set) var errorMessage: String?

    init(
        host: HostServices,
        store: CorrectionStore?,
        initialError: String?,
        onLearningChanged: @escaping @MainActor @Sendable (Bool) -> CaptureStatus
    ) {
        self.host = host
        self.store = store
        self.onLearningChanged = onLearningChanged

        if let stored = host.userDefault(forKey: Self.learningEnabledKey) as? Bool {
            learningEnabled = stored
        } else {
            learningEnabled = true
            host.setUserDefault(true, forKey: Self.learningEnabledKey)
        }

        if let stored = host.userDefault(forKey: Self.minimumConfirmationsKey) as? Int {
            minimumConfirmations = Self.clampedConfirmations(stored)
        } else {
            minimumConfirmations = 2
            host.setUserDefault(2, forKey: Self.minimumConfirmationsKey)
        }

        errorMessage = initialError
    }

    var activeRuleCount: Int {
        rules.count { $0.isActive(minimumConfirmations: minimumConfirmations) }
    }

    var pendingRuleCount: Int {
        rules.count { $0.isEnabled && !$0.isActive(minimumConfirmations: minimumConfirmations) }
    }

    @MainActor
    func start() {
        captureStatus = onLearningChanged(learningEnabled)
        refresh()
    }

    @MainActor
    func setLearningEnabled(_ enabled: Bool) {
        learningEnabled = enabled
        host.setUserDefault(enabled, forKey: Self.learningEnabledKey)
        captureStatus = onLearningChanged(enabled)
    }

    @MainActor
    func setMinimumConfirmations(_ value: Int) {
        let clamped = Self.clampedConfirmations(value)
        minimumConfirmations = clamped
        host.setUserDefault(clamped, forKey: Self.minimumConfirmationsKey)
    }

    @MainActor
    func refresh() {
        guard let store else { return }
        Task { [weak self] in
            let snapshot = await store.snapshot()
            await MainActor.run {
                self?.rules = snapshot
            }
        }
    }

    @MainActor
    func updateCaptureStatus(_ status: CaptureStatus) {
        captureStatus = status
    }

    @MainActor
    func setRuleEnabled(_ enabled: Bool, id: UUID) {
        guard let store else { return }
        Task { [weak self] in
            do {
                try await store.setEnabled(enabled, id: id)
                let snapshot = await store.snapshot()
                await MainActor.run {
                    self?.rules = snapshot
                    self?.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    func deleteRule(id: UUID) {
        guard let store else { return }
        Task { [weak self] in
            do {
                try await store.delete(id: id)
                let snapshot = await store.snapshot()
                await MainActor.run {
                    self?.rules = snapshot
                    self?.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    func deleteAllRules() {
        guard let store else { return }
        Task { [weak self] in
            do {
                try await store.deleteAll()
                await MainActor.run {
                    self?.rules = []
                    self?.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private static func clampedConfirmations(_ value: Int) -> Int {
        min(max(value, 1), 5)
    }
}
