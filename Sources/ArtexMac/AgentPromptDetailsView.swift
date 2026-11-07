import ArtexCore
import SwiftUI

@MainActor struct AgentPromptDetailsView: View {
    private enum Panel: Hashable {
        case prompt, wrapUp, mcp, skill, tools

        var visibilityKind: AgentVisibilityKind? {
            switch self {
            case .mcp: .mcp
            case .skill: .skill
            case .prompt, .wrapUp, .tools: nil
            }
        }
    }

    let agent: AgentCatalogEntry
    let onVisibilityChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var panel = Panel.prompt
    @State private var editor: AgentPromptEditor
    @State private var visibility: AgentVisibilityEditor
    @State private var toolBindings: AgentToolBindingEditor
    @State private var inspection: AgentPromptInspectionView.Inspection?
    @State private var confirmDiscard = false
    @State private var confirmRestore = false
    @State private var restoreSection: AgentWrapUpSection?
    @State private var replacementDraft: String?

    init(agent: AgentCatalogEntry, service: AgentCatalogService, onVisibilityChange: @escaping () -> Void) {
        self.agent = agent
        self.onVisibilityChange = onVisibilityChange
        _visibility = State(initialValue: AgentVisibilityEditor(key: agent.key, service: service))
        _toolBindings = State(initialValue: AgentToolBindingEditor(key: agent.key, service: service))
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
                    .disabled((editor.isBusy && editor.details != nil) || visibility.isBusy || toolBindings.isBusy)
            }
            if let details = editor.details {
                saveStatus
                Picker(s(.agentDetailsSection), selection: $panel) {
                    Text(s(.agentDetailsPrompt)).tag(Panel.prompt)
                    Text(s(.agentDetailsWrapUp)).tag(Panel.wrapUp)
                    Text(verbatim: "MCP").tag(Panel.mcp)
                    Text(s(.agentCatalogSkill)).tag(Panel.skill)
                    Text(s(.agentCatalogTools)).tag(Panel.tools)
                }
                .pickerStyle(.segmented)
                .disabled(editor.isBusy || visibility.isBusy || toolBindings.isBusy)
                .accessibilityIdentifier("agent-detail-section")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch panel {
                        case .prompt: promptPanel(details)
                        case .mcp: visibilityPanel(.mcp, agentID: details.backendID)
                        case .skill: visibilityPanel(.skill, agentID: details.backendID)
                        case .tools: toolBindingPanel
                        case .wrapUp:
                            wrapUpPanel(details.wrapUp, section: .normal, title: .agentDetailsWrapUp)
                            if let task = details.taskTimeout {
                                Divider()
                                wrapUpPanel(task, section: .taskTimeout, title: .agentDetailsTaskTimeout)
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
        .task {
            await editor.refresh()
            await editor.loadWebSearchAvailability()
        }
        .task(id: panel) {
            if let kind = panel.visibilityKind { await visibility.load(kind) }
            if panel == .tools { await toolBindings.load() }
        }
        .interactiveDismissDisabled(editor.isBusy || editor.hasUnsavedChanges || visibility.isBusy || toolBindings.isBusy)
        .sheet(item: $inspection) { selection in
            AgentPromptInspectionView(inspection: selection, editor: editor)
                .environment(\.locale, locale)
        }
        .alert(s(restoreSection == nil ? .agentDetailsRestoreQuestion : .agentWrapUpRestoreQuestion), isPresented: $confirmRestore) {
            Button(s(.agentDetailsRestore), role: .destructive) {
                let section = restoreSection
                Task {
                    if let section { await editor.restoreWrapUp(section) }
                    else { await editor.restoreDefault() }
                }
            }
            Button(s(.chatCancel), role: .cancel) {}
        } message: {
            if let restoreSection {
                Text(s(restoreSection == .normal ? .agentWrapUpRestoreNormal : .agentWrapUpRestoreTimeout))
            } else {
                Text(s(editor.hasUnsavedPrompt ? .agentDetailsRestoreDraft : .agentDetailsRestoreHistory))
            }
        }
        .confirmationDialog(s(.agentDetailsDiscardQuestion), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(s(.agentDetailsDiscard), role: .destructive) {
                if let replacementDraft { editor.edit(replacementDraft) } else { dismiss() }
            }
            Button(s(.chatCancel), role: .cancel) {}
        }
    }

    @ViewBuilder private func promptPanel(_ details: AgentPromptDetails) -> some View {
        executionPanel(details)
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
        HStack {
            Button(s(.agentInspectPreview), systemImage: "eye") { inspection = .preview(editor.draft) }
                .disabled(editor.isBusy)
                .accessibilityIdentifier("agent-prompt-preview")
            Button(s(.agentDetailsSave), systemImage: "square.and.arrow.down") {
                Task { await editor.save() }
            }
            .disabled(!editor.canSave)
            .accessibilityIdentifier("agent-prompt-save")
            if agent.builtin {
                Button(s(.agentDetailsRestore), systemImage: "arrow.counterclockwise") {
                    restoreSection = nil
                    confirmRestore = true
                }
                    .disabled(!editor.canEdit)
                    .accessibilityIdentifier("agent-prompt-restore")
            }
        }
        Divider()
        Text(s(.agentDetailsVersions)).font(.headline)
        if details.versions.isEmpty {
            Text(s(.agentDetailsNoVersions)).foregroundStyle(.secondary)
        }
        ForEach(details.versions) { version in
            DisclosureGroup {
                literal(version.templateText)
                if let current = details.versions.first, current.id != version.id {
                    Button(s(.agentInspectCompare), systemImage: "arrow.left.arrow.right") {
                        inspection = .comparison(version, current)
                    }
                }
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

    @ViewBuilder private func visibilityPanel(_ kind: AgentVisibilityKind, agentID: String?) -> some View {
        Text(s(kind == .mcp ? .agentVisibilityMCP : .agentVisibilitySkills))
            .foregroundStyle(.secondary)
        if let failure = visibility.failure {
            Text(failure.text(language: language)).foregroundStyle(.red)
            Button(s(.authRetry)) { Task { await visibility.load(kind) } }
        }
        if visibility.isBusy { ProgressView().controlSize(.small) }
        if visibility.kind == kind {
            if visibility.canEdit && visibility.resources.isEmpty {
                Text(s(kind == .mcp ? .agentVisibilityNoMCP : .agentVisibilityNoSkills))
                    .foregroundStyle(.secondary)
            }
            ForEach(visibility.resources) { resource in
                Toggle(isOn: Binding(
                    get: { visibility.contains(resource.id) },
                    set: { value in
                        guard let agentID else { return }
                        Task {
                            await visibility.set(resource.id, visible: value, agentID: agentID)
                            onVisibilityChange()
                        }
                    }
                )) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: resource.name)
                        Spacer()
                        if let detail = resource.displayDetail(language: language), !detail.isEmpty {
                            Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!visibility.canEdit || agentID == nil)
            }
        }
    }

    @ViewBuilder private var toolBindingPanel: some View {
        Text(s(.agentToolBindingHelp)).foregroundStyle(.secondary)
        if let failure = toolBindings.failure {
            Text(failure.text(language: language)).foregroundStyle(.red)
            Button(s(.authRetry)) { Task { await toolBindings.load() } }
        }
        if toolBindings.isBusy { ProgressView().controlSize(.small) }
        if toolBindings.hasLoaded && toolBindings.tools.isEmpty {
            Text(s(.agentToolBindingEmpty)).foregroundStyle(.secondary)
        }
        ForEach(toolBindings.tools) { tool in
            Toggle(isOn: Binding(
                get: { toolBindings.contains(tool) },
                set: { value in
                    Task {
                        await toolBindings.set(tool.id, bound: value)
                        onVisibilityChange()
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: tool.key).font(.body.monospaced())
                    if toolBindings.trafficGated(tool) {
                        Text(s(.agentToolBindingNeedsCapture)).font(.caption).foregroundStyle(.secondary)
                    }
                    if !tool.enabled {
                        Text(s(.agentToolBindingDisabled)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!toolBindings.canSet(tool))
            .accessibilityIdentifier("agent-tool-binding-\(tool.key)")
        }
    }

    @ViewBuilder private func executionPanel(_ details: AgentPromptDetails) -> some View {
        if let draft = editor.executionDraft {
            GroupBox(s(.agentExecutionTitle)) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(s(.agentExecutionModel), selection: executionBinding(\.profileID, fallback: draft.profileID)) {
                        Text(s(.agentExecutionInherit)).tag(Optional<Int64>.none)
                        ForEach(details.modelOptions) { profile in
                            let suffix = profile.isDefault ? s(.agentExecutionDefaultSuffix) : ""
                            Text(verbatim: "\(profile.name) (\(profile.model))\(suffix)").tag(Optional(profile.id))
                        }
                        if let id = draft.profileID, !details.modelOptions.contains(where: { $0.id == id }) {
                            Text(AppStrings.formatted(.agentExecutionMissing, language: language,
                                                      values: ["id": String(id)])).tag(Optional(id))
                        }
                    }
                    .accessibilityIdentifier("agent-execution-model")
                    if details.showsExecutionLimits {
                        LabeledContent(s(.agentExecutionTurns)) {
                            TextField(s(.agentExecutionTurns), text: executionBinding(\.maxTurns, fallback: draft.maxTurns))
                                .labelsHidden()
                                .accessibilityIdentifier("agent-execution-turns")
                        }
                        LabeledContent(s(.agentExecutionSeconds)) {
                            TextField(s(.agentExecutionSeconds), text: executionBinding(\.runSeconds, fallback: draft.runSeconds))
                                .labelsHidden()
                                .accessibilityIdentifier("agent-execution-seconds")
                        }
                        if !validExecutionLimit(draft.maxTurns) || !validExecutionLimit(draft.runSeconds) {
                            Text(s(.agentWrapUpInvalidRounds)).foregroundStyle(.red)
                        }
                    }
                    if details.showsExecutionTools {
                        Divider()
                        Toggle(s(.agentExecutionWebSearch),
                               isOn: executionBinding(\.webSearch, fallback: draft.webSearch))
                            .toggleStyle(.switch)
                            .disabled(editor.webSearchEnabled != true)
                            .accessibilityIdentifier("agent-execution-web-search")
                        Text(s(webSearchHint)).font(.caption).foregroundStyle(.secondary)
                        Toggle(s(.agentExecutionShell),
                               isOn: executionBinding(\.interactiveShell, fallback: draft.interactiveShell))
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("agent-execution-shell")
                        Text(s(.agentExecutionShellHint)).font(.caption).foregroundStyle(.secondary)
                    }
                    Button(s(.agentExecutionSave), systemImage: "square.and.arrow.down") {
                        Task { await editor.saveExecution() }
                    }
                    .disabled(!editor.canSaveExecution)
                    .accessibilityIdentifier("agent-execution-save")
                }
                .padding(.vertical, 4)
                .disabled(!editor.canEdit)
            }
        }
    }

    private var webSearchHint: AppStringKey {
        switch editor.webSearchEnabled {
        case .some(true): .agentExecutionWebOn
        case .some(false): .agentExecutionWebOff
        case nil: .agentExecutionWebUnavailable
        }
    }

    private func validExecutionLimit(_ raw: String) -> Bool {
        guard let value = Int32(raw) else { return false }
        return value >= 0
    }

    private func executionBinding<Value>(_ keyPath: WritableKeyPath<AgentExecutionDraft, Value>,
                                         fallback: Value) -> Binding<Value> {
        Binding(
            get: { editor.executionDraft?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard var draft = editor.executionDraft else { return }
                draft[keyPath: keyPath] = value
                editor.editExecution(draft)
            }
        )
    }

    @ViewBuilder private func wrapUpPanel(_ wrap: AgentPromptDetails.WrapUp,
                                         section: AgentWrapUpSection, title: AppStringKey) -> some View {
        Text(s(title)).font(.headline)
        if let draft = editor.wrapUpDraft(section) {
            TextEditor(text: Binding(
                get: { editor.wrapUpDraft(section)?.prompt ?? draft.prompt },
                set: { value in
                    guard var latest = editor.wrapUpDraft(section) else { return }
                    latest.prompt = value
                    editor.editWrapUp(section, draft: latest)
                }
            ))
            .font(.callout.monospaced())
            .frame(minHeight: 140)
            .disabled(!editor.canEdit)
            .accessibilityLabel(s(title))
            .accessibilityIdentifier("agent-wrapup-prompt-\(section.rawValue)")

            let roundsLabel = AppStrings.formatted(.agentWrapUpRounds, language: language,
                                                   values: ["count": wrap.defaultRounds.formatted(.number.locale(locale))])
            Text(roundsLabel).font(.callout)
            TextField(roundsLabel, text: Binding(
                get: { editor.wrapUpDraft(section)?.rounds ?? draft.rounds },
                set: { value in
                    guard var latest = editor.wrapUpDraft(section) else { return }
                    latest.rounds = value
                    editor.editWrapUp(section, draft: latest)
                }
            ))
            .disabled(!editor.canEdit)
            .accessibilityIdentifier("agent-wrapup-rounds-\(section.rawValue)")
            if draft.validRounds == nil {
                Text(s(.agentWrapUpInvalidRounds)).foregroundStyle(.red)
            }
            HStack {
                Button(s(.agentWrapUpSave), systemImage: "square.and.arrow.down") {
                    Task { await editor.saveWrapUp(section) }
                }
                .disabled(!editor.canSaveWrapUp(section))
                .accessibilityIdentifier("agent-wrapup-save-\(section.rawValue)")
                Button(s(.agentDetailsRestore), systemImage: "arrow.counterclockwise") {
                    restoreSection = section
                    confirmRestore = true
                }
                .disabled(!editor.canEdit)
                .accessibilityIdentifier("agent-wrapup-restore-\(section.rawValue)")
            }
        }
        LabeledContent(s(.agentDetailsRounds), value: wrap.effectiveRounds.formatted(.number.locale(locale)))
        if !wrap.builtIn.isEmpty {
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
        if editor.executionSaved {
            Text(s(.agentExecutionSaved)).foregroundStyle(.secondary)
        }
        if editor.wrapUpSaved {
            Text(s(.agentWrapUpSaved)).foregroundStyle(.secondary)
        }
        if let version = editor.savedVersion {
            Text(AppStrings.formatted(editor.restoredDefault ? .agentDetailsRestored : .agentDetailsSaved,
                                      language: language,
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
        if editor.hasUnsavedPrompt && !editor.draft.utf8.elementsEqual(text.utf8) {
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
