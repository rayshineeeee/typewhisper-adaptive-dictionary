import AdaptiveDictionaryCore
import SwiftUI

struct AdaptiveDictionarySettingsView: View {
    @ObservedObject var model: AdaptiveDictionarySettingsModel
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            rulesContent
            Divider()
            footer
        }
        .frame(minWidth: 660, minHeight: 500)
        .alert("Delete all learned corrections?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                model.deleteAllRules()
            }
        } message: {
            Text("This removes the local rules file. The action cannot be undone.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "character.book.closed")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Adaptive Dictionary")
                    .font(.title3.weight(.semibold))
                Text("Learns small corrections you commit after dictation. Stored only on this Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(model.activeRuleCount) active")
                    .font(.headline.monospacedDigit())
                if model.pendingRuleCount > 0 {
                    Text("\(model.pendingRuleCount) pending")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(
                "Learn from edits committed after dictation",
                isOn: Binding(
                    get: { model.learningEnabled },
                    set: { model.setLearningEnabled($0) }
                )
            )

            HStack {
                Text("Confirm a correction")
                Spacer()
                Stepper(
                    value: Binding(
                        get: { model.minimumConfirmations },
                        set: { model.setMinimumConfirmations($0) }
                    ),
                    in: 1...5
                ) {
                    Text("\(model.minimumConfirmations)×")
                        .monospacedDigit()
                        .frame(minWidth: 24, alignment: .trailing)
                }
                .fixedSize()
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(model.captureStatus.message)
                    .font(.caption)
                    .foregroundStyle(model.captureStatus.isActive ? .secondary : statusColor)
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var rulesContent: some View {
        if model.rules.isEmpty {
            ContentUnavailableView(
                "No corrections yet",
                systemImage: "text.badge.plus",
                description: Text(
                    "Correct a dictated word or phrase, then press Return or Tab. Casing fixes activate immediately; other fixes wait for confirmation."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.rules) { rule in
                ruleRow(rule)
            }
            .listStyle(.inset)
        }
    }

    private func ruleRow(_ rule: LearnedCorrection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { model.setRuleEnabled($0, id: rule.id) }
                )
            )
            .labelsHidden()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(rule.source)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(rule.replacement)
                        .fontWeight(.medium)
                }
                .textSelection(.enabled)

                Text(ruleMetadata(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button(role: .destructive) {
                model.deleteRule(id: rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete correction")
        }
        .padding(.vertical, 5)
    }

    private var footer: some View {
        HStack {
            Text("Local JSON · no network access")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Delete All…", role: .destructive) {
                showingClearConfirmation = true
            }
            .disabled(model.rules.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var statusColor: Color {
        switch model.captureStatus {
        case .active:
            .green
        case .disabled:
            .secondary
        case .unavailable:
            .orange
        }
    }

    private func ruleMetadata(_ rule: LearnedCorrection) -> String {
        let state: String
        if !rule.isEnabled {
            state = "Disabled"
        } else if rule.isActive(minimumConfirmations: model.minimumConfirmations) {
            state = rule.isCasingOnly ? "Active · casing" : "Active · \(rule.observationCount) confirmations"
        } else {
            state = "Pending · \(rule.observationCount) of \(model.minimumConfirmations) confirmations"
        }

        var details = [state]
        if !rule.bundleIdentifiers.isEmpty {
            details.append("seen in \(rule.bundleIdentifiers.count) app\(rule.bundleIdentifiers.count == 1 ? "" : "s")")
        }
        if rule.applicationCount > 0 {
            details.append("applied \(rule.applicationCount)×")
        }
        return details.joined(separator: " · ")
    }
}
