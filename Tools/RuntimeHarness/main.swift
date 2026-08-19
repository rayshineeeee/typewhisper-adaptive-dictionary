import AppKit
import Foundation

@MainActor
final class HarnessAppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
    private var window: NSWindow?
    private var timer: Timer?
    private var lastTextVersion = -1
    private var lastFocusVersion = -1
    private var lastCommitVersion = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 18)
        textView.textContainerInset = NSSize(width: 16, height: 16)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Adaptive Dictionary Runtime Verification"
        window.contentView = scrollView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        defaults.set(ProcessInfo.processInfo.processIdentifier, forKey: "pid")
        defaults.set("", forKey: "currentText")
        defaults.synchronize()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollCommands()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        defaults.removeObject(forKey: "pid")
        defaults.synchronize()
    }

    private func pollCommands() {
        let textVersion = defaults.integer(forKey: "textVersion")
        if textVersion != lastTextVersion {
            lastTextVersion = textVersion
            textView.string = defaults.string(forKey: "commandText") ?? ""
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }

        let focusVersion = defaults.integer(forKey: "focusVersion")
        if focusVersion != lastFocusVersion {
            lastFocusVersion = focusVersion
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(textView)
            NSApp.activate(ignoringOtherApps: true)
        }

        let commitVersion = defaults.integer(forKey: "commitVersion")
        if commitVersion != lastCommitVersion {
            lastCommitVersion = commitVersion
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
                .first?
                .activate(options: [.activateAllWindows])
        }

        defaults.set(textView.string, forKey: "currentText")
        defaults.synchronize()
    }
}

@main
@MainActor
struct RuntimeHarness {
    static func main() {
        let app = NSApplication.shared
        let delegate = HarnessAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
