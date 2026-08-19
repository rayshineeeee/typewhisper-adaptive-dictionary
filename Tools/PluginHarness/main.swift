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
}

private final class HarnessHost: HostServices, @unchecked Sendable {
    private let pluginID = "com.raysun.typewhisper.adaptive-dictionary"
    private let defaults = UserDefaults(suiteName: "com.typewhisper.mac")!

    let eventBus: EventBusProtocol = HarnessEventBus()
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

    private func scoped(_ key: String) -> String { "plugin.\(pluginID).\(key)" }
}

private struct HarnessResult: Encodable {
    let input: String
    let output: String
    let bundleIdentifier: String
    let mode: String
    let fallbackReason: String?
    let elapsedSeconds: Double
}

@main
struct PluginHarness {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3, arguments[1] == "process" else {
            FileHandle.standardError.write(
                Data("Usage: AdaptiveDictationPluginHarness process <text> [bundle-id]\n".utf8)
            )
            Foundation.exit(64)
        }

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
        plugin.activate(host: host)
        try await waitForModel(host: host)

        let start = Date()
        let output = try await plugin.process(
            text: input,
            context: PostProcessingContext(
                appName: "Plugin Harness",
                bundleIdentifier: bundleIdentifier
            )
        )
        let result = HarnessResult(
            input: input,
            output: output,
            bundleIdentifier: bundleIdentifier,
            mode: host.userDefault(forKey: "lastCleanupMode") as? String ?? "unknown",
            fallbackReason: host.userDefault(forKey: "lastCleanupFallbackReason") as? String,
            elapsedSeconds: Date().timeIntervalSince(start)
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
