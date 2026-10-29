import ArtexCore
import SwiftUI

@MainActor struct TrafficLinkDialog: View {
    static func severityLabel(_ raw: String, language: AppLanguage) -> String {
        DashboardLabels.text(raw, domain: .severity, language: language)
    }
    static func candidateTitle(_ row: FindingRecord) -> String {
        "#" + (row.findingId ?? row.id) + " · " + (row.name.isEmpty ? row.vulnclass : row.name)
    }
    let model: TrafficScreenModel
    let lease: UUID
    let id: UUID
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    private var workspace: TrafficLinkWorkspace? {
        model.acceptsLink(id: id, lease: lease) ? model.linkWorkspace : nil
    }
    var body: some View {
        Group { if let workspace { content(workspace) } }
    }
    private func content(_ workspace: TrafficLinkWorkspace) -> some View {
        let owner = workspace.binding.owner, request = workspace.binding.requestID
        let revision = workspace.binding.unknownRevision
        return VStack(alignment: .leading, spacing: 14) {
            Text(s(workspace.recoveryOnly ? .trafficUILinkRecovery : .trafficUILink)).font(.title2.bold())
            if workspace.binding.hasUnknownOutcome {
                Text(s(.trafficUILinkUnknown)).foregroundStyle(.orange)
                if let summary = workspace.binding.summary, !workspace.binding.isStale {
                    Text(f(.trafficUILinkEvidence, ["id": summary.findingId, "count": String(summary.bindings.count)])).textSelection(.enabled)
                }
                HStack {
                    Button(s(.trafficUILinkReload)) { Task { await workspace.recover(owner: owner) } }
                        .disabled(workspace.binding.isMutating || workspace.binding.isLoading || workspace.isSubmitting)
                    Button(s(.trafficUILinkAcknowledge)) { _ = workspace.acknowledge(owner: owner, revision: revision) }
                        .disabled(!workspace.binding.canAcknowledgeUnknown || workspace.isSubmitting)
                }
            } else if !workspace.recoveryOnly {
                Text(f(.trafficUILinkCount, ["count": String(workspace.sourceIDs.count)]))
                candidates(workspace)
                if let target = workspace.selectedTarget {
                    Text(f(.trafficUILinkTarget, ["name": Self.candidateTitle(target)])).textSelection(.enabled)
                } else { Text(s(.trafficUILinkPrompt)).foregroundStyle(.secondary) }
            }
            if let failure = workspace.binding.failure { Text(failure.text(language: language)).foregroundStyle(.red) }
            if workspace.binding.isLoading || workspace.isSubmitting { ProgressView().controlSize(.small) }
            HStack {
                Spacer()
                Button(s(.trafficUIClose)) { _ = model.closeLink(id: id, lease: lease) }.keyboardShortcut(.cancelAction)
                    .disabled(workspace.isSubmitting || workspace.binding.isMutating)
                if !workspace.recoveryOnly {
                    Button(s(.trafficUILink)) { Task { _ = await workspace.submit(id: request, owner: owner) } }
                        .keyboardShortcut(.defaultAction).disabled(!workspace.canSubmit)
                }
            }
        }.padding(24).frame(minWidth: 540, idealWidth: 680, minHeight: 360)
            .interactiveDismissDisabled(workspace.isSubmitting || workspace.binding.isMutating)
    }
    private func candidates(_ workspace: TrafficLinkWorkspace) -> some View {
        let ticket = workspace.searchTicket
        let pages = workspace.candidates.map { $0.total > 0 ? ($0.total - 1) / 20 + 1 : 1 } ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Text(s(.trafficUILinkSearch)).font(.caption)
            TextField(s(.trafficUILinkSearch), text: .init(get: { workspace.searchDraft }, set: { _ = workspace.edit($0) }))
                .textFieldStyle(.roundedBorder).disabled(!workspace.editable)
            if let failure = workspace.failure {
                HStack {
                    Text(failure.text(language: language)).foregroundStyle(.red)
                    Button(s(.trafficUIRefresh)) { workspace.reloadCandidates(ticket: ticket) }.disabled(!workspace.editable)
                }
            }
            if workspace.isLoading { ProgressView().controlSize(.small) }
            if workspace.isStale { Text(s(.trafficUILinkStale)).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(workspace.candidates?.items ?? [], id: \.identity) { row in
                        Button { Task { _ = await workspace.choose(row.identity, ticket: ticket) } } label: {
                            HStack(alignment: .top) {
                                Image(systemName: workspace.selectedTarget?.identity == row.identity ? "largecircle.fill.circle" : "circle")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Self.candidateTitle(row)).font(.headline)
                                    Text(row.summary).font(.caption).lineLimit(3)
                                    if !row.canMutate { Text(s(.trafficUILinkReadOnly)).font(.caption) }
                                }
                                Spacer()
                                Text(Self.severityLabel(row.severity, language: language)).font(.caption)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        }.buttonStyle(.plain).disabled(!row.canMutate || !workspace.editable || workspace.isLoading || !workspace.pageIsCurrent)
                    }
                    if workspace.candidates?.items.isEmpty == true { Text(s(.trafficUILinkEmpty)).padding() }
                }
            }.frame(minHeight: 140, maxHeight: 360)
            HStack {
                Text(f(.trafficUIPage, ["page": String(workspace.pageNumber), "pages": String(pages)])).font(.caption)
                Spacer()
                Button(s(.trafficUIPrevious)) { _ = workspace.page(-1, ticket: ticket) }.disabled(!workspace.editable || !workspace.pageIsCurrent || workspace.pageNumber <= 1)
                Button(s(.trafficUINext)) { _ = workspace.page(1, ticket: ticket) }.disabled(!workspace.editable || !workspace.pageIsCurrent || workspace.pageNumber >= pages)
            }
        }
    }
}
