import Foundation
import NetworkPNTRCore
import SwiftUI

@MainActor struct GuestLogsView: View {
    @Environment(\.locale) private var locale
    @State private var store: GuestLogStore
    @State private var keyword = ""
    @State private var level: GuestLogLevel?
    @State private var historyRequest: UUID?
    @State private var visibleRow: GuestLogEntry.ID?
    @State private var historyAnchor: GuestLogEntry.ID?
    @State private var followingLatest = true

    init(session: AuthenticationSession) {
        let service = GuestLogService(client: AuthenticatedBackendClient(session: session))
        _store = State(initialValue: GuestLogStore(service: service))
    }

    var body: some View {
        let rows = store.filtered(keyword: keyword, level: level)
        VStack(alignment: .leading, spacing: 12) {
            Text(s(.logs)).font(.largeTitle.bold())
            HStack {
                TextField(s(.logsSearch), text: $keyword)
                Picker(s(.logsLevel), selection: $level) {
                    Text(s(.logsAll)).tag(nil as GuestLogLevel?)
                    ForEach(GuestLogLevel.allCases, id: \.self) { value in
                        Text(levelLabel(value)).tag(Optional(value))
                    }
                }.fixedSize()
                Button(s(store.paused ? .logsResume : .logsPause)) { store.paused.toggle() }
                Button(s(.logsClear)) { store.clear() }.disabled(store.rows.isEmpty)
            }
            HStack {
                Text(count(.logsTotalCount, store.rows.count))
                Text(count(.logsWarningCount, store.rows.count(where: { $0.level == "warn" })))
                Text(count(.logsErrorCount, store.rows.count(where: { $0.level == "error" })))
            }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let failure = store.recentFailure { error(failure) }
            if let failure = store.historyFailure { error(failure) }
            logList(rows)
        }
        .navigationTitle(s(.logs))
        .padding()
        .task {
            while !Task.isCancelled {
                await store.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .task(id: historyRequest) {
            guard historyRequest != nil else { return }
            await store.loadOlder()
            if let anchor = historyAnchor { visibleRow = anchor }
            historyAnchor = nil
        }
    }

    private func logList(_ rows: [GuestLogEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if store.canLoadOlder {
                        Button(s(.logsOlder)) {
                            historyAnchor = visibleRow
                            historyRequest = UUID()
                        }
                        .disabled(store.isLoadingHistory || store.isRefreshing)
                    }
                    if !store.hasLoaded && store.recentFailure == nil {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if rows.isEmpty {
                        Text(s(.logsEmpty)).foregroundStyle(.secondary).padding()
                    }
                    ForEach(rows) { entry in logRow(entry).id(entry.id) }
                }
                .scrollTargetLayout()
                .padding(12)
            }
            .scrollPosition(id: $visibleRow, anchor: .top)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
            } action: { _, value in
                followingLatest = value
            }
            .onChange(of: rows.last?.id) { _, last in
                if let last, followingLatest && !store.paused { proxy.scrollTo(last, anchor: .bottom) }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func logRow(_ entry: GuestLogEntry) -> some View {
        let severity = GuestLogLevel(rawValue: entry.level)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let date = try? Date.ISO8601FormatStyle().parse(entry.ts) {
                Text(date, format: .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second())
                    .foregroundStyle(.secondary).fixedSize()
            }
            Text(verbatim: severity.map(levelLabel) ?? entry.level).fixedSize()
                .foregroundStyle(severity == .error ? .red : severity == .warning ? .orange : .secondary)
            if !entry.tag.isEmpty {
                Text(verbatim: entry.tag).foregroundStyle(.secondary)
            }
            Text(verbatim: entry.message)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }

    private func error(_ failure: AppErrorMessage) -> some View {
        Label(failure.text(language: language), systemImage: "exclamationmark.triangle").foregroundStyle(.red)
    }

    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }

    private func count(_ key: AppStringKey, _ value: Int) -> String {
        AppStrings.formatted(key, language: language, values: ["count": value.formatted(.number.locale(locale))])
    }

    private func levelLabel(_ level: GuestLogLevel) -> String {
        switch level {
        case .info: s(.logsInfo)
        case .warning: s(.logsWarning)
        case .error: s(.logsError)
        }
    }
}
