import AdaptiveDictionaryCore
import Foundation
import SwiftUI
import TypeWhisperPluginSDK
import os

private let logger = Logger(
    subsystem: "com.raysun.typewhisper.adaptive-dictionary",
    category: "AdaptiveDictionary"
)

@objc(AdaptiveDictionaryPlugin)
final class AdaptiveDictionaryPlugin: NSObject, PostProcessorPlugin, @unchecked Sendable {
    static let pluginId = "com.raysun.typewhisper.adaptive-dictionary"
    static let pluginName = "Adaptive Dictionary"

    let processorName = "Adaptive Dictionary"
    let priority = 220

    private struct RuntimeState: Sendable {
        let host: HostServices
        let store: CorrectionStore?
        let captureService: CorrectionCaptureService
        let model: AdaptiveDictionarySettingsModel
        let subscriptionID: UUID
    }

    private let stateLock = NSLock()
    private var runtimeState: RuntimeState?

    required override init() {
        super.init()
    }

    func activate(host: HostServices) {
        deactivate()

        let store: CorrectionStore?
        let initialError: String?
        do {
            store = try CorrectionStore(
                fileURL: host.pluginDataDirectory.appendingPathComponent("adaptive-corrections.json")
            )
            initialError = nil
        } catch {
            store = nil
            initialError = "Could not open the local corrections file: \(error.localizedDescription)"
            logger.error("Failed to initialize store: \(error.localizedDescription, privacy: .public)")
        }

        let captureService = CorrectionCaptureService(store: store) { [weak self] in
            self?.stateSnapshot()?.model.refresh()
        }
        let model = AdaptiveDictionarySettingsModel(
            host: host,
            store: store,
            initialError: initialError,
            onLearningChanged: { enabled in
                captureService.setEnabled(enabled)
            }
        )
        let subscriptionID = host.eventBus.subscribe { [weak self] event in
            await self?.handle(event)
        }

        stateLock.withLock {
            runtimeState = RuntimeState(
                host: host,
                store: store,
                captureService: captureService,
                model: model,
                subscriptionID: subscriptionID
            )
        }

        Task { @MainActor in
            model.start()
        }
        logger.info("Adaptive Dictionary activated")
    }

    func deactivate() {
        let oldState = stateLock.withLock {
            let state = runtimeState
            runtimeState = nil
            return state
        }
        guard let oldState else { return }
        oldState.host.eventBus.unsubscribe(id: oldState.subscriptionID)
        Task { @MainActor in
            oldState.captureService.stop()
        }
        logger.info("Adaptive Dictionary deactivated")
    }

    @MainActor
    var settingsView: AnyView? {
        guard let model = stateSnapshot()?.model else { return nil }
        return AnyView(AdaptiveDictionarySettingsView(model: model))
    }

    @MainActor
    func process(text: String, context: PostProcessingContext) async throws -> String {
        guard let state = stateSnapshot(), let store = state.store else { return text }
        let minimumConfirmations = state.host.userDefault(forKey: "minimumConfirmations") as? Int ?? 2
        let application = try await store.apply(
            to: text,
            minimumConfirmations: minimumConfirmations
        )
        if !application.appliedRuleIDs.isEmpty {
            state.model.refresh()
        }
        return application.text
    }

    private func handle(_ event: TypeWhisperEvent) async {
        guard let state = stateSnapshot() else { return }

        switch event {
        case .textInserted(let payload):
            await MainActor.run {
                state.captureService.beginInsertion(
                    text: payload.text,
                    bundleIdentifier: payload.bundleIdentifier,
                    timestamp: payload.timestamp
                )
            }

        default:
            break
        }
    }

    private func stateSnapshot() -> RuntimeState? {
        stateLock.withLock { runtimeState }
    }
}
