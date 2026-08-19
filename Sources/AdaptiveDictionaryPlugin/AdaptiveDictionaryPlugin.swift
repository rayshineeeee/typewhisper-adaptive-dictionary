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
    static let pluginName = "Adaptive Dictation"

    let processorName = "Adaptive Dictation"
    let priority = 220

    private struct RuntimeState: Sendable {
        let host: HostServices
        let store: CorrectionStore?
        let captureService: CorrectionCaptureService
        let model: AdaptiveDictionarySettingsModel
        let localModel: LocalGemmaRuntime
        let tracker: ProcessingSessionTracker
        let toastPresenter: LearningToastPresenter
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

        let localModel = LocalGemmaRuntime(host: host)
        let tracker = ProcessingSessionTracker()
        let toastPresenter = LearningToastPresenter()
        let captureService = CorrectionCaptureService(
            store: store,
            onRulesChanged: { [weak self] in
                self?.stateSnapshot()?.model.refresh()
            },
            onLearned: { [weak self] receipt in
                guard let state = self?.stateSnapshot(), let store = state.store else { return }
                state.toastPresenter.show(receipt: receipt) { [weak self] in
                    Task {
                        do {
                            try await store.undo(receipt)
                            await MainActor.run {
                                self?.stateSnapshot()?.model.refresh()
                            }
                        } catch {
                            logger.error(
                                "Failed to undo learned correction: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
            }
        )
        let model = AdaptiveDictionarySettingsModel(
            host: host,
            store: store,
            localModel: localModel,
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
                localModel: localModel,
                tracker: tracker,
                toastPresenter: toastPresenter,
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
            oldState.localModel.unload(clearPersistence: false)
            oldState.toastPresenter.dismiss()
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
        guard let state = stateSnapshot() else { return text }
        defer { state.localModel.finishDictationActivity() }
        let dictationContext = AccessibilityContextReader.context(from: context)
        let profile = DictationProfile.resolve(bundleIdentifier: context.bundleIdentifier)
        var correctedText = text
        let minimumConfirmations = state.host.userDefault(forKey: "minimumConfirmations") as? Int ?? 2
        var examples: [LearnedStyleExample] = []
        if let store = state.store {
            let application = try await store.apply(
                to: text,
                minimumConfirmations: minimumConfirmations
            )
            correctedText = application.text
            examples = await store.recentStyleExamples(profile: profile)
            if !application.appliedRuleIDs.isEmpty {
                state.model.refresh()
            }
        }
        let provider: (any SemanticRewriteProvider)? =
            state.localModel.canAttemptRewrite
            ? state.localModel
            : nil
        let result = await DictationPipeline.process(
            text: correctedText,
            profile: profile,
            context: dictationContext,
            learnedExamples: examples,
            semanticProvider: provider
        )
        state.tracker.recordProcessed(
            inputText: text,
            outputText: result.text,
            profile: profile,
            bundleIdentifier: context.bundleIdentifier
        )
        state.model.recordPipelineResult(result)
        state.host.setUserDefault(
            result.usedSemanticModel ? "semantic" : "deterministic",
            forKey: "lastCleanupMode"
        )
        state.host.setUserDefault(result.fallbackReason, forKey: "lastCleanupFallbackReason")
        return result.text
    }

    private func handle(_ event: TypeWhisperEvent) async {
        guard let state = stateSnapshot() else { return }

        switch event {
        case .recordingStarted:
            await MainActor.run {
                state.localModel.prepareForRecording()
            }

        case .recordingStopped:
            await MainActor.run {
                state.localModel.recordingDidStop()
            }

        case .textInserted(let payload):
            let learningEnabled = state.host.userDefault(forKey: "learningEnabled") as? Bool ?? true
            guard learningEnabled else { return }
            let snapshot = await MainActor.run {
                state.tracker.consumeInsertion(
                    text: payload.text,
                    bundleIdentifier: payload.bundleIdentifier
                )
            }
            let profile =
                snapshot?.profile
                ?? DictationProfile.resolve(bundleIdentifier: payload.bundleIdentifier)
            let rawTranscript = snapshot?.inputText ?? payload.text
            let recordID: UUID?
            do {
                recordID = try await state.store?.recordInsertion(
                    rawTranscript: rawTranscript,
                    pluginOutput: payload.text,
                    profile: profile,
                    now: payload.timestamp
                )
            } catch {
                recordID = nil
                logger.error(
                    "Failed to record local dictation history: \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run {
                if let recordID, let snapshot {
                    state.tracker.associate(recordID: recordID, with: snapshot)
                }
                state.captureService.beginInsertion(
                    text: payload.text,
                    recordID: recordID,
                    bundleIdentifier: payload.bundleIdentifier,
                    timestamp: payload.timestamp
                )
                state.model.refresh()
            }

        case .transcriptionCompleted(let payload):
            let recordID = await MainActor.run {
                state.tracker.consumeRecordID(
                    finalText: payload.finalText,
                    bundleIdentifier: payload.bundleIdentifier
                )
            }
            do {
                try await state.store?.updateRawTranscript(payload.rawText, recordID: recordID)
            } catch {
                logger.error("Failed to update raw transcript history: \(error.localizedDescription, privacy: .public)")
            }

        default:
            break
        }
    }

    private func stateSnapshot() -> RuntimeState? {
        stateLock.withLock { runtimeState }
    }
}
