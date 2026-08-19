import Foundation

public enum DictationProfile: String, Codable, CaseIterable, Sendable {
    case casual
    case clear

    public static func resolve(bundleIdentifier: String?) -> Self {
        guard let bundleIdentifier else { return .clear }
        return casualBundleIdentifiers.contains(bundleIdentifier) ? .casual : .clear
    }

    public var displayName: String {
        switch self {
        case .casual: "Casual"
        case .clear: "Clear"
        }
    }

    private static let casualBundleIdentifiers: Set<String> = [
        "com.apple.MobileSMS",
        "com.tencent.xinWeChat",
    ]
}

public struct DictationContext: Sendable, Equatable {
    public let appName: String?
    public let bundleIdentifier: String?
    public let url: String?
    public let selectedText: String?
    public let precedingText: String?
    public let followingText: String?

    public init(
        appName: String? = nil,
        bundleIdentifier: String? = nil,
        url: String? = nil,
        selectedText: String? = nil,
        precedingText: String? = nil,
        followingText: String? = nil
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.url = url
        self.selectedText = selectedText
        self.precedingText = precedingText
        self.followingText = followingText
    }
}
