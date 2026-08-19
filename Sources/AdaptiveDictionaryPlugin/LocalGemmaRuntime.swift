import AdaptiveDictionaryCore
import Foundation
import HuggingFace
import Hub
import MLX
import MLXLMCommon
import MLXVLM
import SwiftUI
import Tokenizers
import TypeWhisperPluginSDK

// Model loading and tokenization are adapted from TypeWhisper's GPL-3.0 Gemma4Plugin v1.5.1.
// The rewrite policy, lifecycle, storage, and UI in this plugin are independent.

private struct AdaptiveGemmaDownloader: Downloader {
    let client: HubClient
    let modelsDirectory: URL

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest _: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repositoryID = Repo.ID(rawValue: id) else {
            throw LocalGemmaError.invalidRepository(id)
        }
        let destination = modelsDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try await client.downloadSnapshot(
            of: repositoryID,
            to: destination,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in
                progressHandler(progress)
            }
        )
    }
}

private struct AdaptiveGemmaTokenizer: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

private struct AdaptiveGemmaTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return AdaptiveGemmaTokenizer(upstream: tokenizer)
    }
}

struct LocalGemmaModel: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    let repositoryID: String
    let sizeDescription: String
    let ramDescription: String

    static let e2b = LocalGemmaModel(
        id: "gemma-4-e2b-it-4bit",
        displayName: "Gemma 4 E2B (4-bit)",
        repositoryID: "mlx-community/gemma-4-e2b-it-4bit",
        sizeDescription: "~3.6 GB",
        ramDescription: "8 GB+"
    )
    static let e4b = LocalGemmaModel(
        id: "gemma-4-e4b-it-4bit",
        displayName: "Gemma 4 E4B (4-bit)",
        repositoryID: "mlx-community/gemma-4-e4b-it-4bit",
        sizeDescription: "~5.2 GB",
        ramDescription: "16 GB+"
    )
    static let available = [e4b, e2b]
}

enum LocalGemmaState: Equatable, Sendable {
    case notDownloaded
    case downloaded
    case downloading(Double)
    case loading
    case ready
    case error(String)

    var isBusy: Bool {
        switch self {
        case .downloading, .loading: true
        default: false
        }
    }
}

enum LocalGemmaError: LocalizedError {
    case invalidRepository(String)
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .invalidRepository(let repository):
            "Invalid Hugging Face repository: \(repository)"
        case .modelNotLoaded:
            "The local cleanup model is not loaded."
        }
    }
}

final class LocalGemmaRuntime: ObservableObject, SemanticRewriteProvider, @unchecked Sendable {
    static let defaultIdleUnloadSeconds = 600
    static let selectedModelKey = "selectedSemanticModel"
    static let semanticEnabledKey = "semanticCleanupEnabled"
    static let keepLoadedKey = "keepSemanticModelLoaded"
    static let setupRequestedKey = "semanticModelSetupRequested"
    static let runtimeStateKey = "semanticModelRuntimeState"
    static let downloadProgressKey = "semanticModelDownloadProgress"
    static let idleUnloadSecondsKey = "semanticModelIdleUnloadSeconds"

    @Published private(set) var state: LocalGemmaState {
        didSet { persistState() }
    }
    @Published private(set) var selectedModel: LocalGemmaModel
    @Published private(set) var lastInferenceDuration: TimeInterval?

    private let host: HostServices
    private var modelContainer: ModelContainer?
    private var loadTask: Task<Void, Never>?
    private var idleUnloadTask: Task<Void, Never>?
    private var recordingInProgress = false
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(host: HostServices) {
        self.host = host
        let storedID = host.userDefault(forKey: Self.selectedModelKey) as? String
        selectedModel = Self.model(withID: storedID) ?? .e4b
        state = .notDownloaded
        state = isDownloaded(selectedModel) ? .downloaded : .notDownloaded
        installMemoryPressureHandler()

        if host.userDefault(forKey: Self.semanticEnabledKey) == nil {
            host.setUserDefault(true, forKey: Self.semanticEnabledKey)
        }
        if host.userDefault(forKey: Self.keepLoadedKey) == nil {
            host.setUserDefault(false, forKey: Self.keepLoadedKey)
        }
    }

    deinit {
        idleUnloadTask?.cancel()
        memoryPressureSource?.cancel()
    }

    @MainActor var isReady: Bool { modelContainer != nil && state == .ready }
    @MainActor var semanticCleanupEnabled: Bool {
        host.userDefault(forKey: Self.semanticEnabledKey) as? Bool ?? true
    }
    @MainActor var keepLoaded: Bool {
        host.userDefault(forKey: Self.keepLoadedKey) as? Bool ?? false
    }
    @MainActor var canAttemptRewrite: Bool {
        semanticCleanupEnabled && (isReady || state == .loading)
    }

    @MainActor func start() {
        persistState()
        let setupRequested = host.userDefault(forKey: Self.setupRequestedKey) as? Bool ?? false
        if setupRequested {
            loadSelectedModel()
        } else if keepLoaded, isDownloaded(selectedModel) {
            loadSelectedModel()
        }
    }

    @MainActor func setSemanticCleanupEnabled(_ enabled: Bool) {
        host.setUserDefault(enabled, forKey: Self.semanticEnabledKey)
        if enabled, keepLoaded, isDownloaded(selectedModel) {
            loadSelectedModel()
        } else if !enabled {
            unload(clearPersistence: false)
        }
    }

    @MainActor func setKeepLoaded(_ enabled: Bool) {
        host.setUserDefault(enabled, forKey: Self.keepLoadedKey)
        if enabled {
            cancelIdleUnload()
            if !isReady, isDownloaded(selectedModel) {
                loadSelectedModel()
            }
        } else {
            scheduleIdleUnloadIfNeeded()
        }
    }

    @MainActor func prepareForRecording() {
        recordingInProgress = true
        guard semanticCleanupEnabled, isDownloaded(selectedModel) else { return }
        cancelIdleUnload()
        if !isReady, !state.isBusy {
            loadSelectedModel()
        }
    }

    @MainActor func recordingDidStop() {
        recordingInProgress = false
        scheduleIdleUnloadIfNeeded()
    }

    @MainActor func finishDictationActivity() {
        recordingInProgress = false
        scheduleIdleUnloadIfNeeded()
    }

    @MainActor func selectModel(_ model: LocalGemmaModel) {
        guard !state.isBusy, model != selectedModel else { return }
        unload(clearPersistence: false)
        selectedModel = model
        host.setUserDefault(model.id, forKey: Self.selectedModelKey)
        state = isDownloaded(model) ? .downloaded : .notDownloaded
    }

    @MainActor func requestSetup() {
        host.setUserDefault(true, forKey: Self.setupRequestedKey)
        loadSelectedModel()
    }

    @MainActor func loadSelectedModel() {
        guard !state.isBusy, !isReady else { return }
        cancelIdleUnload()
        let model = selectedModel
        state = isDownloaded(model) ? .loading : .downloading(0)
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.load(model)
                self.host.setUserDefault(false, forKey: Self.setupRequestedKey)
            } catch is CancellationError {
                self.state = self.isDownloaded(model) ? .downloaded : .notDownloaded
            } catch {
                self.modelContainer = nil
                self.state = .error(Self.userFacingMessage(for: error))
            }
            self.loadTask = nil
            self.scheduleIdleUnloadIfNeeded()
        }
    }

    @MainActor func cancelLoad() {
        cancelIdleUnload()
        loadTask?.cancel()
        loadTask = nil
        state = isDownloaded(selectedModel) ? .downloaded : .notDownloaded
    }

    @MainActor func unload(clearPersistence: Bool = false) {
        cancelIdleUnload()
        loadTask?.cancel()
        loadTask = nil
        modelContainer = nil
        state = isDownloaded(selectedModel) ? .downloaded : .notDownloaded
        if clearPersistence {
            host.setUserDefault(false, forKey: Self.keepLoadedKey)
        }
        Task {
            try? await PluginLocalInferenceGate.shared.withLock {
                Memory.clearCache()
            }
        }
    }

    @MainActor func removeSelectedModel() async {
        unload(clearPersistence: false)
        for directory in modelCacheDirectories(for: selectedModel) {
            try? FileManager.default.removeItem(at: directory)
        }
        state = .notDownloaded
    }

    @MainActor func rewrite(_ request: SemanticRewriteRequest) async throws -> String {
        defer { scheduleIdleUnloadIfNeeded() }
        let modelContainer = try await waitForModelContainer()
        let start = Date()
        let sourceWordCount = request.deterministicText.split(whereSeparator: { $0.isWhitespace }).count
        let maximumTokens = min(256, max(48, sourceWordCount * 2 + 24))
        let output = try await PluginLocalInferenceGate.shared.withLock {
            let prompt = """
                Follow these instructions exactly:
                \(SemanticPromptBuilder.systemPrompt)

                \(SemanticPromptBuilder.userPrompt(for: request))
                """
            let input = try await modelContainer.prepare(
                input: UserInput(chat: [.user(prompt)])
            )
            let stream = try await modelContainer.generate(
                input: input,
                parameters: GenerateParameters(
                    maxTokens: maximumTokens,
                    temperature: 0,
                    prefillStepSize: selectedModel == .e2b ? 256 : 128
                )
            )
            var result = ""
            for await generation in stream {
                try Task.checkCancellation()
                if case .chunk(let text) = generation {
                    result += text
                }
            }
            Memory.clearCache()
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        lastInferenceDuration = Date().timeIntervalSince(start)
        return output
    }

    @MainActor private func waitForModelContainer() async throws -> ModelContainer {
        while true {
            try Task.checkCancellation()
            if let modelContainer { return modelContainer }
            guard state == .loading else { throw LocalGemmaError.modelNotLoaded }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    func isDownloaded(_ model: LocalGemmaModel) -> Bool {
        let directory = localModelDirectory(for: model)
        let required = ["config.json", "tokenizer.json"]
        guard
            required.allSatisfy({
                FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
            })
        else { return false }
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else { return false }
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "safetensors" {
            return true
        }
        return false
    }

    @MainActor private func load(_ model: LocalGemmaModel) async throws {
        try Task.checkCancellation()
        let downloaded = isDownloaded(model)
        if !downloaded {
            removeIncompleteCache(for: model)
        }
        let modelsDirectory = modelsDirectory()
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let hubClient = HubClient(
            host: HubClient.defaultHost,
            cache: HubCache(cacheDirectory: modelsDirectory)
        )
        let downloader = AdaptiveGemmaDownloader(
            client: hubClient,
            modelsDirectory: modelsDirectory
        )
        let configuration =
            downloaded
            ? ModelConfiguration(
                directory: localModelDirectory(for: model),
                extraEOSTokens: ["<turn|>"]
            )
            : ModelConfiguration(id: model.repositoryID, extraEOSTokens: ["<turn|>"])

        let container = try await VLMModelFactory.shared.loadContainer(
            from: downloader,
            using: AdaptiveGemmaTokenizerLoader(),
            configuration: configuration
        ) { [weak self] progress in
            guard !downloaded else { return }
            let fraction = max(0, min(progress.fractionCompleted, 1))
            Task { @MainActor in
                guard let self, self.selectedModel == model else { return }
                self.state = .downloading(fraction)
            }
        }
        try Task.checkCancellation()
        guard selectedModel == model else { return }
        state = .loading
        try await warmUp(container, model: model)
        try Task.checkCancellation()
        guard selectedModel == model else { return }
        modelContainer = container
        state = .ready
    }

    @MainActor private func scheduleIdleUnloadIfNeeded() {
        cancelIdleUnload()
        guard !keepLoaded, !recordingInProgress, modelContainer != nil || state == .loading else {
            return
        }
        let idleSeconds = configuredIdleUnloadSeconds
        idleUnloadTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(idleSeconds))
            } catch {
                return
            }
            guard let self, !self.keepLoaded else { return }
            self.unload(clearPersistence: false)
        }
    }

    @MainActor private func cancelIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    private var configuredIdleUnloadSeconds: Int {
        let stored = host.userDefault(forKey: Self.idleUnloadSecondsKey) as? Int
        return min(max(stored ?? Self.defaultIdleUnloadSeconds, 1), 3_600)
    }

    private func warmUp(_ container: ModelContainer, model: LocalGemmaModel) async throws {
        try await PluginLocalInferenceGate.shared.withLock {
            let input = try await container.prepare(
                input: UserInput(chat: [.user("Return only: OK")])
            )
            let stream = try await container.generate(
                input: input,
                parameters: GenerateParameters(
                    maxTokens: 1,
                    temperature: 0,
                    prefillStepSize: model == .e2b ? 256 : 128
                )
            )
            for await _ in stream {
                try Task.checkCancellation()
            }
            Memory.clearCache()
        }
    }

    private func modelsDirectory() -> URL {
        host.pluginDataDirectory.appendingPathComponent("models", isDirectory: true)
    }

    private func localModelDirectory(for model: LocalGemmaModel) -> URL {
        modelsDirectory().appendingPathComponent(model.repositoryID, isDirectory: true)
    }

    private func hubCacheDirectory(for model: LocalGemmaModel) -> URL {
        let cacheName = "models--" + model.repositoryID.replacingOccurrences(of: "/", with: "--")
        return modelsDirectory().appendingPathComponent(cacheName, isDirectory: true)
    }

    private func modelCacheDirectories(for model: LocalGemmaModel) -> [URL] {
        [localModelDirectory(for: model), hubCacheDirectory(for: model)]
    }

    private func removeIncompleteCache(for model: LocalGemmaModel) {
        guard
            modelCacheDirectories(for: model).contains(where: {
                FileManager.default.fileExists(atPath: $0.path)
            })
        else { return }
        for directory in modelCacheDirectories(for: model) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func installMemoryPressureHandler() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.unload(clearPersistence: false)
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    private static func model(withID id: String?) -> LocalGemmaModel? {
        LocalGemmaModel.available.first { $0.id == id }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "Model download needs an internet connection once. Inference remains local."
            case .timedOut:
                return "The model download timed out. Try again."
            default:
                break
            }
        }
        let raw = String(describing: error).lowercased()
        if raw.contains("missing") || raw.contains("shape mismatch") || raw.contains("key ") {
            return "The model cache is incomplete. Remove it and download again."
        }
        return error.localizedDescription
    }

    private func persistState() {
        let stateName: String
        let progress: Double?
        switch state {
        case .notDownloaded:
            stateName = "notDownloaded"
            progress = nil
        case .downloaded:
            stateName = "downloaded"
            progress = nil
        case .downloading(let fraction):
            stateName = "downloading"
            progress = fraction
        case .loading:
            stateName = "loading"
            progress = nil
        case .ready:
            stateName = "ready"
            progress = nil
        case .error(let message):
            stateName = "error: \(message)"
            progress = nil
        }
        host.setUserDefault(stateName, forKey: Self.runtimeStateKey)
        host.setUserDefault(progress, forKey: Self.downloadProgressKey)
    }
}
