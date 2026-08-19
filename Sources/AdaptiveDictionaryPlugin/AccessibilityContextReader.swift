import AdaptiveDictionaryCore
import ApplicationServices
import Foundation
import TypeWhisperPluginSDK

@MainActor
enum AccessibilityContextReader {
    private static let maximumContextLength = 1_000

    static func context(from hostContext: PostProcessingContext) -> DictationContext {
        let base = DictationContext(
            appName: hostContext.appName,
            bundleIdentifier: hostContext.bundleIdentifier,
            url: hostContext.url,
            selectedText: limited(hostContext.selectedText)
        )
        guard AXIsProcessTrusted(), let snapshot = focusedTextSnapshot(), !snapshot.isSecure else {
            return base
        }

        let value = snapshot.value as NSString
        let selection = sanitized(snapshot.selectedRange, maximumLocation: value.length)
        let beforeStart = max(0, selection.location - maximumContextLength)
        let beforeRange = NSRange(location: beforeStart, length: selection.location - beforeStart)
        let afterStart = min(value.length, NSMaxRange(selection))
        let afterLength = min(maximumContextLength, value.length - afterStart)

        return DictationContext(
            appName: hostContext.appName,
            bundleIdentifier: hostContext.bundleIdentifier,
            url: hostContext.url,
            selectedText: limited(hostContext.selectedText)
                ?? (selection.length > 0 ? value.substring(with: selection) : nil),
            precedingText: value.substring(with: beforeRange),
            followingText: value.substring(with: NSRange(location: afterStart, length: afterLength))
        )
    }

    private struct FocusedSnapshot {
        let value: String
        let selectedRange: NSRange?
        let isSecure: Bool
    }

    private static func focusedTextSnapshot() -> FocusedSnapshot? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focusedValue
            ) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedValue as! AXUIElement
        guard let value = stringAttribute(kAXValueAttribute as CFString, from: element) else {
            return nil
        }
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element)
        return FocusedSnapshot(
            value: value,
            selectedRange: selectedRange(from: element),
            isSecure: subrole == "AXSecureTextField"
        )
    }

    private static func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private static func selectedRange(from element: AXUIElement) -> NSRange? {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func sanitized(_ range: NSRange?, maximumLocation: Int) -> NSRange {
        guard let range, range.location >= 0, range.length >= 0 else {
            return NSRange(location: maximumLocation, length: 0)
        }
        let location = min(range.location, maximumLocation)
        let length = min(range.length, maximumLocation - location)
        return NSRange(location: location, length: length)
    }

    private static func limited(_ text: String?) -> String? {
        guard let text else { return nil }
        return text.count <= maximumContextLength ? text : String(text.suffix(maximumContextLength))
    }
}
