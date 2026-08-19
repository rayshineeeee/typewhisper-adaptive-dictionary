import AdaptiveDictionaryCore
import AppKit
import ApplicationServices
import Foundation
import os

private let captureLogger = Logger(
    subsystem: "com.raysun.typewhisper.adaptive-dictionary",
    category: "CorrectionCapture"
)

final class CorrectionCaptureService: @unchecked Sendable {
    private struct FocusedTextSnapshot {
        let element: AXUIElement
        let value: String
        let selectedRange: NSRange?
    }

    private struct CaptureSession {
        let originalText: String
        let bundleIdentifier: String?
        let baselineText: String
        let insertedRange: NSRange
        let element: AXUIElement
        let startedAt: Date
        var latestCorrectedText: String?
    }

    private let store: CorrectionStore?
    private let onRulesChanged: @MainActor @Sendable () -> Void
    private var isEnabled = false
    private var session: CaptureSession?
    private var pollTask: Task<Void, Never>?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?

    init(store: CorrectionStore?, onRulesChanged: @escaping @MainActor @Sendable () -> Void) {
        self.store = store
        self.onRulesChanged = onRulesChanged
    }

    @MainActor
    func setEnabled(_ enabled: Bool) -> CaptureStatus {
        isEnabled = enabled
        guard enabled else {
            stopMonitoring()
            return .disabled
        }

        guard AXIsProcessTrusted() else {
            stopMonitoring()
            return .unavailable("Learning needs TypeWhisper's Accessibility permission.")
        }

        installCommitMonitorsIfNeeded()
        return .active
    }

    @MainActor
    func beginInsertion(text: String, bundleIdentifier: String?, timestamp: Date) {
        guard isEnabled, !text.isEmpty else { return }
        commitCurrentSession()

        guard let snapshot = focusedTextSnapshot(),
            let insertedRange = InsertionEditResolver.locateInsertedRange(
                text: text,
                in: snapshot.value,
                selectedRange: snapshot.selectedRange
            )
        else {
            captureLogger.info("Skipped insertion: focused text snapshot unavailable")
            return
        }

        session = CaptureSession(
            originalText: text,
            bundleIdentifier: bundleIdentifier,
            baselineText: snapshot.value,
            insertedRange: insertedRange,
            element: snapshot.element,
            startedAt: timestamp,
            latestCorrectedText: nil
        )
        startPolling()
    }

    @MainActor
    func stop() {
        isEnabled = false
        stopMonitoring()
    }

    @MainActor
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled else { return }
                if !self.pollCurrentSession() {
                    return
                }
            }
        }
    }

    @MainActor
    @discardableResult
    private func pollCurrentSession() -> Bool {
        guard var session else { return false }
        guard Date().timeIntervalSince(session.startedAt) <= 30 else {
            clearSession()
            return false
        }

        guard let focused = focusedTextSnapshot() else {
            commitCurrentSession()
            return false
        }
        guard focused.element == session.element else {
            commitCurrentSession()
            return false
        }

        if let corrected = InsertionEditResolver.correctedInsertedText(
            baselineText: session.baselineText,
            editedText: focused.value,
            insertedRange: session.insertedRange
        ), corrected != session.originalText {
            session.latestCorrectedText = corrected
            self.session = session
        }
        return true
    }

    @MainActor
    private func commitCurrentSession() {
        _ = pollCurrentSessionWithoutFocusTransition()
        guard let completedSession = session else { return }
        clearSession()

        guard let correctedText = completedSession.latestCorrectedText,
            correctedText != completedSession.originalText,
            let store
        else {
            return
        }

        Task {
            do {
                let learned = try await store.observe(
                    original: completedSession.originalText,
                    corrected: correctedText,
                    bundleIdentifier: completedSession.bundleIdentifier
                )
                if !learned.isEmpty {
                    await onRulesChanged()
                    captureLogger.info("Learned \(learned.count, privacy: .public) local correction candidate(s)")
                }
            } catch {
                captureLogger.error("Failed to persist correction: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @MainActor
    private func pollCurrentSessionWithoutFocusTransition() -> Bool {
        guard var session,
            let value = stringAttribute(kAXValueAttribute as CFString, from: session.element)
        else {
            return false
        }
        if let corrected = InsertionEditResolver.correctedInsertedText(
            baselineText: session.baselineText,
            editedText: value,
            insertedRange: session.insertedRange
        ), corrected != session.originalText {
            session.latestCorrectedText = corrected
            self.session = session
        }
        return true
    }

    @MainActor
    private func clearSession() {
        pollTask?.cancel()
        pollTask = nil
        session = nil
    }

    @MainActor
    private func stopMonitoring() {
        clearSession()
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    @MainActor
    private func installCommitMonitorsIfNeeded() {
        guard globalKeyMonitor == nil, localKeyMonitor == nil, appActivationObserver == nil else { return }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isCommitKey(event.keyCode) else { return }
            Task { @MainActor in
                self?.commitCurrentSession()
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isCommitKey(event.keyCode) {
                self?.commitCurrentSession()
            }
            return event
        }
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.commitCurrentSession()
            }
        }
    }

    @MainActor
    private func focusedTextSnapshot() -> FocusedTextSnapshot? {
        guard AXIsProcessTrusted() else { return nil }
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
        else {
            return nil
        }

        let element = focusedValue as! AXUIElement
        guard let value = stringAttribute(kAXValueAttribute as CFString, from: element) else {
            return nil
        }
        return FocusedTextSnapshot(
            element: element,
            value: value,
            selectedRange: selectedRangeAttribute(from: element)
        )
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private func selectedRangeAttribute(from element: AXUIElement) -> NSRange? {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func isCommitKey(_ keyCode: UInt16) -> Bool {
        keyCode == 0x24 || keyCode == 0x4C || keyCode == 0x30
    }

}
