import ArtexCore
import SwiftUI

@MainActor struct AgentCatalogView: View {
    private enum LoadState {
        case loading
        case loaded([AgentCatalogEntry])
        case failed(AppErrorMessage)
    }

    let session: AuthenticationSession
    @Environment(\.locale) private var locale
    @State private var state: LoadState = .loading
    @State private var reload = 0

    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(s(.agents)).font(.largeTitle.bold())
                    Text(s(.agentCatalogReadOnly)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(s(.agentCatalogRefresh), systemImage: "arrow.clockwise") { reload += 1 }
                    .labelStyle(.iconOnly)
                    .help(s(.agentCatalogRefresh))
                    .accessibilityIdentifier("agents-reload")
            }
            switch state {
            case .loading:
                ProgressView(s(.agentCatalogLoading))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(error):
                ContentUnavailableView(s(.agentCatalogLoadFailed), systemImage: "exclamationmark.triangle",
                                       description: Text(error.text(language: language)))
            case let .loaded(agents):
                catalog(agents)
            }
        }
        .padding()
        .navigationTitle(s(.agents))
        .task(id: reload) { await load() }
    }

    private func catalog(_ agents: [AgentCatalogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s(.agentCatalogListTitle)).font(.headline)
            Text(AppStrings.formatted(.agentCatalogCount, language: language,
                                      values: ["count": agents.count.formatted(.number.locale(locale))]))
                .foregroundStyle(.secondary)
            if agents.isEmpty {
                ContentUnavailableView(s(.agentCatalogEmpty), systemImage: "person.crop.rectangle.stack")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), alignment: .top)], spacing: 12) {
                        ForEach(agents) { agent in card(agent) }
                    }
                }
            }
        }
    }

    private func card(_ agent: AgentCatalogEntry) -> some View {
        let description = agent.displayDescription(language: language)
        return VStack(alignment: .leading, spacing: 8) {
            Label(agent.displayName(language: language), systemImage: "person.crop.square")
                .font(.headline)
            Text(agent.key).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack {
                badge(s(agent.builtin ? .agentCatalogBuiltin : .agentCatalogCustom))
                if !agent.enabled {
                    badge(s(.agentCatalogDisabled)).foregroundStyle(.red)
                }
            }
            Text(description.isEmpty ? s(.agentCatalogNoDescription) : description)
                .font(.callout)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { counts(agent) }
                VStack(alignment: .leading) { counts(agent) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-card-\(agent.key)")
    }

    @ViewBuilder private func counts(_ agent: AgentCatalogEntry) -> some View {
        badge("MCP \(agent.mcpCount.formatted(.number.locale(locale)))")
        badge("\(s(.agentCatalogSkill)) \(agent.skillCount.formatted(.number.locale(locale)))")
        badge("\(s(.agentCatalogTools)) \(agent.toolCount.formatted(.number.locale(locale)))")
    }

    private func badge(_ label: String) -> some View {
        Text(label).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: .rect(cornerRadius: 4))
    }

    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

    private func load() async {
        state = .loading
        do {
            let service = AgentCatalogService(client: AuthenticatedBackendClient(session: session))
            let agents = try await service.list()
            guard !Task.isCancelled else { return }
            state = .loaded(agents)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(AppErrorMessage(error))
        }
    }
}
