import AdaptiveDictionaryCore
import AppKit
import SwiftUI

final class LearningToastPresenter: @unchecked Sendable {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    @MainActor func show(
        receipt: LearningReceipt,
        undo: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let first = receipt.learnedRules.first else { return }
        dismiss()

        let message: String
        if receipt.learnedRules.count == 1 {
            message = "Learned “\(first.source)” → “\(first.replacement)”"
        } else {
            message = "Learned \(receipt.learnedRules.count) corrections"
        }
        let content = LearningToastView(
            message: message,
            undo: { [weak self] in
                undo()
                self?.dismiss()
            }
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 390, height: 54)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = false

        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(
                NSPoint(
                    x: frame.maxX - hostingView.frame.width - 18,
                    y: frame.maxY - hostingView.frame.height - 18
                )
            )
        }
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    @MainActor func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct LearningToastView: View {
    let message: String
    let undo: @MainActor @Sendable () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo", action: undo)
                .buttonStyle(.borderless)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 14)
        .frame(width: 390, height: 54)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.1))
        }
    }
}
