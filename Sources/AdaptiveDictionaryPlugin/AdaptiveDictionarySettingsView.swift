import AdaptiveDictionaryCore
import SwiftUI

struct AdaptiveDictionarySettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case cleanup = "Cleanup"
        case learning = "Learning"

        var id: Self { self }
    }

    @ObservedObject var model: AdaptiveDictionarySettingsModel
    @ObservedObject private var localModel: LocalGemmaRuntime
    @State private var page: Page = .cleanup
    @State private var showingClearRulesConfirmation = false
    @State private var showingClearHistoryConfirmation = false
    @State private var showingRemoveModelConfirmation = false

    init(model: AdaptiveDictionarySettingsModel) {
        self.model = model
        _localModel = ObservedObject(wrappedValue: model.localModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("Section", selection: $page) {
                ForEach(Page.allCases) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            .padding(.vertical, 12)
            Divider()

            switch page {
            case .cleanup:
                cleanupPage
            case .learning:
                learningPage
            }

            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 560)
        .alert("Delete all learned corrections?", isPresented: $showingClearRulesConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) { model.deleteAllRules() }
        } message: {
            Text("This removes every learned vocabulary rule from this Mac.")
        }
        .alert("Delete local dictation history?", isPresented: $showingClearHistoryConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete History", role: .destructive) { model.deleteHistory() }
        } message: {
            Text("This removes stored transcripts and style examples. Learned vocabulary rules remain.")
        }
        .alert("Remove the local model?", isPresented: $showingRemoveModelConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Model", role: .destructive) {
                Task { await localModel.removeSelectedModel() }
            }
        } message: {
            Text("You can download it again later. Learned corrections and history remain.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Adaptive Dictation")
                    .font(.title3.weight(.semibold))
                Text("Private cleanup that preserves your meaning and learns your vocabulary.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(model.lastPipelineStatus ?? "Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Casual + Clear")
                    .font(.caption.weight(.medium))
            }
        }
        .padding(20)
    }

    private var cleanupPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle(
                    "Standard cleanup",
                    detail:
                        "Obvious fillers, accidental stutters, punctuation, and structure. Questions remain questions."
                )

                VStack(spacing: 10) {
                    profileRow(
                        name: "Casual",
                        apps: "Messages and WeChat",
                        behavior: "lowercase opening · natural punctuation · no final period"
                    )
                    Divider()
                    profileRow(
                        name: "Clear",
                        apps: "Everywhere else",
                        behavior: "normal casing · clear punctuation · bullets only when useful"
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "Use local semantic cleanup when wording is ambiguous",
                        isOn: Binding(
                            get: { localModel.semanticCleanupEnabled },
                            set: { model.setSemanticCleanupEnabled($0) }
                        )
                    )
                    Text(
                        "Simple dictation stays deterministic. Self-corrections, ambiguous fillers, formatting commands, and long passages use the model when it is ready."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    modelControls

                    Toggle(
                        "Keep the model loaded between recordings",
                        isOn: Binding(
                            get: { localModel.keepLoaded },
                            set: { model.setKeepModelLoaded($0) }
                        )
                    )
                    .disabled(!localModel.isDownloaded(localModel.selectedModel))
                    Text(
                        localModel.keepLoaded
                            ? "Uses about 4.5 GB while TypeWhisper is open."
                            : "Loads when recording starts, then unloads after 10 idle minutes. A cold short dictation may use deterministic cleanup."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
        }
    }

    private var modelControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Local model")
                        .font(.subheadline.weight(.medium))
                    Text("One-time download from Hugging Face; inference never leaves this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                modelAction
            }

            Picker(
                "Model",
                selection: Binding(
                    get: { localModel.selectedModel.id },
                    set: { id in
                        if let selected = LocalGemmaModel.available.first(where: { $0.id == id }) {
                            localModel.selectModel(selected)
                        }
                    }
                )
            ) {
                ForEach(LocalGemmaModel.available) { option in
                    Text("\(option.displayName) · \(option.sizeDescription)").tag(option.id)
                }
            }
            .disabled(localModel.state.isBusy || localModel.isReady)

            HStack(spacing: 8) {
                modelStatusIcon
                Text(modelStatusText)
                    .font(.caption)
                    .foregroundStyle(modelStatusIsError ? .red : .secondary)
                Spacer()
                if case .ready = localModel.state,
                    let duration = localModel.lastInferenceDuration
                {
                    Text("Last rewrite \(duration, format: .number.precision(.fractionLength(2)))s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if case .downloading(let progress) = localModel.state {
                if progress >= 0.01 {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var modelAction: some View {
        switch localModel.state {
        case .notDownloaded:
            Button("Download & Load") { localModel.requestSetup() }
                .buttonStyle(.borderedProminent)
        case .downloaded:
            HStack {
                Button("Remove…", role: .destructive) { showingRemoveModelConfirmation = true }
                Button("Load") { localModel.loadSelectedModel() }
                    .buttonStyle(.borderedProminent)
            }
        case .downloading, .loading:
            Button("Cancel") { localModel.cancelLoad() }
        case .ready:
            HStack {
                Button("Remove…", role: .destructive) { showingRemoveModelConfirmation = true }
                Button("Unload") { localModel.unload(clearPersistence: false) }
            }
        case .error:
            HStack {
                Button("Remove Cache…", role: .destructive) { showingRemoveModelConfirmation = true }
                Button("Try Again") { localModel.requestSetup() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var modelStatusIcon: some View {
        switch localModel.state {
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .downloading, .loading:
            ProgressView().controlSize(.small)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .notDownloaded, .downloaded:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    private var modelStatusText: String {
        switch localModel.state {
        case .notDownloaded:
            "Not downloaded · \(localModel.selectedModel.sizeDescription)"
        case .downloaded:
            "Ready for the next recording · not loaded"
        case .downloading(let progress):
            progress >= 0.01 ? "Downloading · \(Int(progress * 100))%" : "Downloading model"
        case .loading:
            "Loading into memory"
        case .ready:
            localModel.keepLoaded
                ? "Loaded · \(localModel.selectedModel.ramDescription) recommended"
                : "Loaded · unloads after 10 idle minutes"
        case .error(let message):
            message
        }
    }

    private var modelStatusIsError: Bool {
        if case .error = localModel.state { true } else { false }
    }

    private var learningPage: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 13) {
                Toggle(
                    "Learn vocabulary and style from edits after dictation",
                    isOn: Binding(
                        get: { model.learningEnabled },
                        set: { model.setLearningEnabled($0) }
                    )
                )

                HStack {
                    Text("Confirm a non-casing correction")
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
                        .fill(captureStatusColor)
                        .frame(width: 7, height: 7)
                    Text(model.captureStatus.message)
                        .font(.caption)
                        .foregroundStyle(model.captureStatus.isActive ? .secondary : captureStatusColor)
                    Spacer()
                    Text("\(model.historyCount) local transcript\(model.historyCount == 1 ? "" : "s")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Clear History…", role: .destructive) {
                        showingClearHistoryConfirmation = true
                    }
                    .disabled(model.historyCount == 0)
                }

                Text(
                    "Vocabulary learns globally. Style examples are shared within Casual or Clear—not per app. Number and date edits never become automatic rules."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()
            rulesContent
        }
    }

    @ViewBuilder
    private var rulesContent: some View {
        if model.rules.isEmpty {
            ContentUnavailableView(
                "No learned corrections yet",
                systemImage: "text.badge.plus",
                description: Text("Correct dictated text and commit it with Return, Tab, or a focus change.")
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
                    Text(rule.replacement).fontWeight(.medium)
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
            Text("Local inference · private JSON · no telemetry")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if page == .learning {
                Text("\(model.activeRuleCount) active")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Delete Rules…", role: .destructive) {
                    showingClearRulesConfirmation = true
                }
                .disabled(model.rules.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func profileRow(name: String, apps: String, behavior: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).fontWeight(.medium).frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(apps)
                Text(behavior).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var captureStatusColor: Color {
        switch model.captureStatus {
        case .active: .green
        case .disabled: .secondary
        case .unavailable: .orange
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
        if rule.applicationCount > 0 { details.append("applied \(rule.applicationCount)×") }
        return details.joined(separator: " · ")
    }
}
