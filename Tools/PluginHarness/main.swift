import Foundation
import TypeWhisperPluginSDK

private final class HarnessEventBus: EventBusProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [UUID: @Sendable (TypeWhisperEvent) async -> Void] = [:]

    func subscribe(handler: @escaping @Sendable (TypeWhisperEvent) async -> Void) -> UUID {
        let id = UUID()
        lock.withLock { handlers[id] = handler }
        return id
    }

    func unsubscribe(id: UUID) {
        _ = lock.withLock { handlers.removeValue(forKey: id) }
    }

    func emit(_ event: TypeWhisperEvent) async {
        let currentHandlers = lock.withLock { Array(handlers.values) }
        for handler in currentHandlers {
            await handler(event)
        }
    }
}

private final class HarnessHost: HostServices, @unchecked Sendable {
    private let pluginID = "com.raysun.typewhisper.adaptive-dictionary"
    private let defaults = UserDefaults(suiteName: "com.typewhisper.mac")!

    private let harnessEventBus = HarnessEventBus()
    var eventBus: EventBusProtocol { harnessEventBus }
    let activeAppBundleId: String? = nil
    let activeAppName: String? = nil
    let availableRuleNames: [String] = []
    let availableWorkflows: [PluginWorkflowInfo] = []

    var pluginDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TypeWhisper/PluginData")
            .appendingPathComponent(pluginID, isDirectory: true)
    }

    func storeSecret(key: String, value: String) throws {}
    func loadSecret(key: String) -> String? { nil }
    func userDefault(forKey key: String) -> Any? { defaults.object(forKey: scoped(key)) }
    func setUserDefault(_ value: Any?, forKey key: String) { defaults.set(value, forKey: scoped(key)) }
    func notifyCapabilitiesChanged() {}
    func setStreamingDisplayActive(_ active: Bool) {}

    func emit(_ event: TypeWhisperEvent) async {
        await harnessEventBus.emit(event)
    }

    private func scoped(_ key: String) -> String { "plugin.\(pluginID).\(key)" }
}

private struct HarnessResult: Encodable {
    let input: String
    let output: String
    let bundleIdentifier: String
    let mode: String
    let fallbackReason: String?
    let modelStateBeforeRecording: String
    let recordingTriggeredLoadSeconds: Double
    let modelStateDuringRecordingAfterIdleWindow: String?
    let modelStateAfterIdle: String?
    let idleUnloadSeconds: Double?
    let elapsedSeconds: Double
}

@main
struct PluginHarness {
    static func main() async throws {
        let arguments = CommandLine.arguments
        let supportedCommands = ["process", "process-immediately", "verify-idle"]
        guard arguments.count >= 3, supportedCommands.contains(arguments[1]) else {
            FileHandle.standardError.write(
                Data(
                    "Usage: AdaptiveDictationPluginHarness <process|process-immediately|verify-idle> <text> [bundle-id]\n"
                        .utf8
                )
            )
            Foundation.exit(64)
        }

        let command = arguments[1]
        let input = arguments[2]
        let bundleIdentifier =
            arguments.count >= 4
            ? arguments[3]
            : "com.todesktop.230313mzl4w4u92"
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let bundleURL =
            executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("AdaptiveDictionaryPlugin.bundle")
        guard let bundle = Bundle(url: bundleURL), bundle.load(),
            let principalType = bundle.principalClass as? NSObject.Type,
            let plugin = principalType.init() as? any PostProcessorPlugin
        else {
            throw HarnessError.pluginLoadFailed(bundleURL.path)
        }

        let host = HarnessHost()
        let previousIdleSeconds = host.userDefault(forKey: "semanticModelIdleUnloadSeconds")
        if command == "verify-idle" {
            host.setUserDefault(1, forKey: "semanticModelIdleUnloadSeconds")
        }
        defer {
            if command == "verify-idle" {
                host.setUserDefault(previousIdleSeconds, forKey: "semanticModelIdleUnloadSeconds")
            }
        }
        plugin.activate(host: host)
        try await Task.sleep(for: .milliseconds(100))
        let stateBeforeRecording =
            host.userDefault(forKey: "semanticModelRuntimeState") as? String ?? "unknown"
        let loadStart = Date()
        await host.emit(
            .recordingStarted(
                RecordingStartedPayload(
                    appName: "Plugin Harness",
                    bundleIdentifier: bundleIdentifier
                )
            )
        )
        var recordingTriggeredLoadSeconds: Double?
        if command != "process-immediately" {
            try await waitForModel(host: host)
            recordingTriggeredLoadSeconds = Date().timeIntervalSince(loadStart)
        }

        var modelStateDuringRecordingAfterIdleWindow: String?
        if command == "verify-idle" {
            try await Task.sleep(for: .milliseconds(1_250))
            modelStateDuringRecordingAfterIdleWindow =
                host.userDefault(forKey: "semanticModelRuntimeState") as? String
            guard modelStateDuringRecordingAfterIdleWindow == "ready" else {
                throw HarnessError.modelFailed("model unloaded while recording was still active")
            }
        }
        await host.emit(.recordingStopped(RecordingStoppedPayload(durationSeconds: 1)))

        let start = Date()
        let output = try await plugin.process(
            text: input,
            context: PostProcessingContext(
                appName: "Plugin Harness",
                bundleIdentifier: bundleIdentifier
            )
        )
        let processElapsed = Date().timeIntervalSince(start)
        try await waitForModel(host: host)
        if recordingTriggeredLoadSeconds == nil {
            recordingTriggeredLoadSeconds = Date().timeIntervalSince(loadStart)
        }

        var modelStateAfterIdle: String?
        var idleUnloadSeconds: Double?
        if command == "verify-idle" {
            let idleStart = Date()
            try await waitForState("downloaded", host: host, timeout: 10)
            idleUnloadSeconds = Date().timeIntervalSince(idleStart)
            modelStateAfterIdle =
                host.userDefault(forKey: "semanticModelRuntimeState") as? String
            host.setUserDefault(previousIdleSeconds, forKey: "semanticModelIdleUnloadSeconds")
        }
        let result = HarnessResult(
            input: input,
            output: output,
            bundleIdentifier: bundleIdentifier,
            mode: host.userDefault(forKey: "lastCleanupMode") as? String ?? "unknown",
            fallbackReason: host.userDefault(forKey: "lastCleanupFallbackReason") as? String,
            modelStateBeforeRecording: stateBeforeRecording,
            recordingTriggeredLoadSeconds: recordingTriggeredLoadSeconds ?? 0,
            modelStateDuringRecordingAfterIdleWindow: modelStateDuringRecordingAfterIdleWindow,
            modelStateAfterIdle: modelStateAfterIdle,
            idleUnloadSeconds: idleUnloadSeconds,
            elapsedSeconds: processElapsed
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(result))
        FileHandle.standardOutput.write(Data("\n".utf8))
        // The production host owns a plugin for the lifetime of its process. Exit the
        // one-shot harness without unloading its dynamically loaded MLX module during
        // Swift runtime teardown, which is not a supported host lifecycle.
        Foundation.exit(EXIT_SUCCESS)
    }

    private static func waitForModel(host: HarnessHost) async throws {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            let state = host.userDefault(forKey: "semanticModelRuntimeState") as? String
            if state == "ready" { return }
            if state?.hasPrefix("error:") == true {
                throw HarnessError.modelFailed(state ?? "unknown error")
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw HarnessError.modelFailed("timed out while loading")
    }

    private static func waitForState(
        _ expectedState: String,
        host: HarnessHost,
        timeout: TimeInterval
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = host.userDefault(forKey: "semanticModelRuntimeState") as? String
            if state == expectedState { return }
            if state?.hasPrefix("error:") == true {
                throw HarnessError.modelFailed(state ?? "unknown error")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw HarnessError.modelFailed("timed out waiting for \(expectedState)")
    }
}

private enum HarnessError: LocalizedError {
    case pluginLoadFailed(String)
    case modelFailed(String)

    var errorDescription: String? {
        switch self {
        case .pluginLoadFailed(let path): "Could not load plugin bundle at \(path)"
        case .modelFailed(let message): "Local model failed: \(message)"
        }
    }
}
