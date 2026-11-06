import ArtexCore
import SwiftUI

@MainActor struct AgentPromptDetailsView: View {
    private enum Panel: Hashable { case prompt, wrapUp }

    let agent: AgentCatalogEntry

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var panel = Panel.prompt
    @State private var editor: AgentPromptEditor
    @State private var confirmDiscard = false
    @State private var replacementDraft: String?

    init(agent: AgentCatalogEntry, service: AgentCatalogService) {
        self.agent = agent
        _editor = State(initialValue: AgentPromptEditor(key: agent.key, service: service))
    }

    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.displayName(language: language)).font(.title2.bold())
                    Text(agent.key).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Button(s(.close), action: close)
                    .keyboardShortcut(.cancelAction)
                    .disabled(editor.isBusy && editor.details != nil)
            }
            if let details = editor.details {
                saveStatus
                Picker(s(.agentDetailsSection), selection: $panel) {
                    Text(s(.agentDetailsPrompt)).tag(Panel.prompt)
                    Text(s(.agentDetailsWrapUp)).tag(Panel.wrapUp)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("agent-detail-section")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch panel {
                        case .prompt: promptPanel(details)
                        case .wrapUp:
                            wrapUpPanel(details.wrapUp, title: .agentDetailsWrapUp)
                            if let task = details.taskTimeout {
                                Divider()
                                wrapUpPanel(task, title: .agentDetailsTaskTimeout)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            } else if let failure = editor.failure {
                ContentUnavailableView {
                    Label(s(.agentDetailsFailed), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure.text(language: language))
                } actions: {
                    Button(s(.authRetry)) { Task { await editor.refresh() } }
                }
            } else {
                ProgressView(s(.agentDetailsLoading)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(minWidth: 540, idealWidth: 670, minHeight: 460, idealHeight: 640)
        .task { await editor.refresh() }
        .interactiveDismissDisabled(editor.isBusy || editor.hasUnsavedChanges)
        .confirmationDialog(s(.agentDetailsDiscardQuestion), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(s(.agentDetailsDiscard), role: .destructive) {
                if let replacementDraft { editor.edit(replacementDraft) } else { dismiss() }
            }
            Button(s(.chatCancel), role: .cancel) {}
        }
    }

    @ViewBuilder private func promptPanel(_ details: AgentPromptDetails) -> some View {
        Text(s(.agentDetailsVariables)).font(.headline)
        if details.variables.isEmpty {
            Text(s(.agentDetailsNoVariables)).foregroundStyle(.secondary)
        } else {
            ForEach(details.variables.indices, id: \.self) { index in
                let variable = details.variables[index]
                let description = variable.displayDescription(agent: agent, language: language)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "{{.\(variable.name)}}").font(.callout.monospaced())
                    if !description.isEmpty {
                        Text(verbatim: description).font(.caption).foregroundStyle(.secondary)
                    }
                    if !variable.example.isEmpty {
                        Text(AppStrings.formatted(.agentDetailsExample, language: language,
                                                  values: ["example": variable.example]))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Text(s(.agentDetailsPrompt)).font(.headline)
        TextEditor(text: Binding(get: { editor.draft }, set: editor.edit))
            .font(.callout.monospaced())
            .frame(minHeight: 220)
            .disabled(!editor.canEdit)
            .accessibilityLabel(s(.agentDetailsPrompt))
            .accessibilityIdentifier("agent-prompt-editor")
        Button(s(.agentDetailsSave), systemImage: "square.and.arrow.down") {
            Task { await editor.save() }
        }
        .disabled(!editor.canSave)
        .accessibilityIdentifier("agent-prompt-save")
        Divider()
        Text(s(.agentDetailsVersions)).font(.headline)
        if details.versions.isEmpty {
            Text(s(.agentDetailsNoVersions)).foregroundStyle(.secondary)
        }
        ForEach(details.versions) { version in
            DisclosureGroup {
                literal(version.templateText)
                Button(s(.agentDetailsLoadVersion)) { useAsDraft(version.templateText) }
                    .disabled(!editor.canEdit)
                    .accessibilityIdentifier("agent-prompt-load-version-\(version.id)")
            } label: {
                HStack {
                    Text(verbatim: "v\(version.version)").font(.body.monospacedDigit())
                    if version.id == details.versions.first?.id {
                        Text(s(.agentDetailsCurrent)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = version.note {
                        Text(verbatim: note).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let timestamp = version.ts {
                        Text(verbatim: dateLabel(timestamp)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("agent-prompt-version-\(version.id)")
        }
    }

    @ViewBuilder private func wrapUpPanel(_ wrap: AgentPromptDetails.WrapUp, title: AppStringKey) -> some View {
        Text(s(title)).font(.headline)
        if wrap.usesDefault {
            Text(s(.agentDetailsUsesDefault)).foregroundStyle(.secondary)
        }
        literal(wrap.effectivePrompt)
        LabeledContent(s(.agentDetailsRounds), value: wrap.effectiveRounds.formatted(.number.locale(locale)))
        if !wrap.usesDefault, !wrap.builtIn.isEmpty {
            DisclosureGroup(s(.agentDetailsBuiltIn)) { literal(wrap.builtIn) }
        }
    }

    private func literal(_ value: String) -> some View {
        Text(verbatim: value.isEmpty ? s(.agentDetailsEmpty) : value)
            .font(.callout.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary, in: .rect(cornerRadius: 6))
    }

    private func dateLabel(_ timestamp: String) -> String {
        let date = (try? Date(timestamp, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(timestamp, strategy: .iso8601))
        return date?.formatted(.dateTime.month().day().hour().minute().locale(locale)) ?? timestamp
    }

    @ViewBuilder private var saveStatus: some View {
        if let version = editor.savedVersion {
            Text(AppStrings.formatted(.agentDetailsSaved, language: language,
                                      values: ["version": String(version)]))
                .foregroundStyle(.secondary)
        }
        if editor.isBusy {
            ProgressView().controlSize(.small)
        }
        if let failure = editor.failure {
            Text(failure.text(language: language)).foregroundStyle(.red)
        }
        if editor.requiresRefresh {
            Text(s(.agentDetailsUncertain)).font(.callout)
            Button(s(.agentDetailsRefreshHistory)) { Task { await editor.refresh() } }
        }
    }

    private func useAsDraft(_ text: String) {
        if editor.hasUnsavedChanges && !editor.draft.utf8.elementsEqual(text.utf8) {
            replacementDraft = text
            confirmDiscard = true
        } else {
            editor.edit(text)
        }
    }

    private func close() {
        if editor.hasUnsavedChanges {
            replacementDraft = nil
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
}
