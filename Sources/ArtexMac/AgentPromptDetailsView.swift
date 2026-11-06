import ArtexCore
import SwiftUI

@MainActor struct AgentPromptDetailsView: View {
    private enum Panel: Hashable { case prompt, wrapUp }

    let agent: AgentCatalogEntry
    let service: AgentCatalogService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var panel = Panel.prompt
    @State private var details: AgentPromptDetails?
    @State private var failure: AppErrorMessage?
    @State private var attempt = 0

    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.displayName(language: language)).font(.title2.bold())
                    Text(agent.key).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Button(s(.close)) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(s(.agentDetailsReadOnly)).font(.callout).foregroundStyle(.secondary)
            if let details {
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
            } else if let failure {
                ContentUnavailableView {
                    Label(s(.agentDetailsFailed), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure.text(language: language))
                } actions: {
                    Button(s(.authRetry)) { attempt += 1 }
                }
            } else {
                ProgressView(s(.agentDetailsLoading)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(minWidth: 540, idealWidth: 670, minHeight: 460, idealHeight: 640)
        .task(id: attempt) { await load() }
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
        literal(details.prompt)
        Divider()
        Text(s(.agentDetailsVersions)).font(.headline)
        if details.versions.isEmpty {
            Text(s(.agentDetailsNoVersions)).foregroundStyle(.secondary)
        }
        ForEach(details.versions) { version in
            DisclosureGroup {
                literal(version.templateText)
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

    private func load() async {
        failure = nil
        do {
            let result = try await service.promptDetails(key: agent.key)
            guard !Task.isCancelled else { return }
            details = result
        } catch {
            guard !Task.isCancelled else { return }
            failure = AppErrorMessage(error)
        }
    }

    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
}
