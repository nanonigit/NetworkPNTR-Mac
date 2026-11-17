import AppKit
import NetworkPNTRCore
import SwiftUI

@MainActor struct TrafficView: View {
    let model: TrafficScreenModel
    @State private var lease: UUID?
    var body: some View {
        Group {
            if let lease { TrafficContent(model: model, lease: lease) }
            else { ProgressView() }
        }.task {
            guard let owned = model.begin() else { return }
            lease = owned
            defer { model.stop(owned) }
            do { while !Task.isCancelled { try await Task.sleep(for: .seconds(3600)) } } catch { }
        }
    }
}

@MainActor struct TrafficContent: View {
    let model: TrafficScreenModel
    let lease: UUID
    @Environment(\.locale) private var locale
    @State private var advanced = false
    @State private var showHosts = false
    @State private var countsDescending = true
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    private var owner: UUID { model.store.owner }
    private var recordActions: Bool { model.canUseRecords(lease: lease, owner: owner) && !model.store.catalog.isStale && !model.store.catalog.isLoading }
    var body: some View {
        let capturedOwner = owner, revision = model.previewRevision, selected = model.store.selectedExchange?.id ?? ""
        VStack(alignment: .leading, spacing: 12) {
            header
            filters
            notices
            actions
            flowActions
            trafficList
            pager
        }.padding(20).navigationTitle(s(.trafficUITitle))
        .sheet(isPresented: TrafficBindings.preview(model, lease: lease, owner: capturedOwner, revision: revision, id: selected)) {
            TrafficRawPreview(model: model, lease: lease, owner: capturedOwner, revision: revision, id: selected)
        }
        .sheet(item: TrafficBindings.confirmation(model, lease: lease, id: model.deletionDialog?.id, owner: capturedOwner)) { context in
            TrafficDeleteDialog(model: model, lease: lease, contextID: context.id)
        }
        .sheet(item: TrafficBindings.link(model, lease: lease, id: model.linkWorkspace?.id)) { workspace in
            TrafficLinkDialog(model: model, lease: lease, id: workspace.id)
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s(.trafficUITitle)).font(.largeTitle.bold()); Spacer()
                if model.store.isRefreshing { ProgressView().controlSize(.small) }
                Button(s(.trafficUIRefresh), systemImage: "arrow.clockwise") { _ = model.refresh(lease: lease) }
                    .keyboardShortcut("r", modifiers: .command).disabled(!model.controlsAvailable || model.store.isRefreshing)
            }
            Text(s(.trafficUISubtitle)).foregroundStyle(.secondary)
            HStack {
                if let page = model.store.catalog.value {
                    Label(s(page.enabled ? .trafficUICaptureOn : .trafficUICaptureOff), systemImage: page.enabled ? "record.circle" : "pause.circle")
                    if let total = page.count, let matched = page.total { Text(f(.trafficUITotal, ["matched": String(matched), "total": String(total)])) }
                    if let proxy = page.proxy, !proxy.isEmpty { Text(f(.trafficUIProxy, ["proxy": proxy])).textSelection(.enabled) }
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private var filters: some View {
        let capturedOwner = owner
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                field(.host, .trafficUIHost)
                VStack(alignment: .leading) {
                    Text(s(.trafficUIMethod)).font(.caption)
                    Picker(s(.trafficUIMethod), selection: TrafficBindings.method(model, lease: lease, owner: owner)) {
                        Text(s(.trafficUIAnyMethod)).tag("all")
                        ForEach(CapturedHTTPMethod.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }.labelsHidden().frame(width: 135)
                }
                field(.keyword, .trafficUIQuery)
            }
            DisclosureGroup(s(.trafficUIAdvanced), isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { field(.body, .trafficUIBody); field(.path, .trafficUIPath) }
                    HStack(alignment: .bottom) {
                        field(.responseMinimum, .trafficUIMinimum); field(.responseMaximum, .trafficUIMaximum)
                        VStack(alignment: .leading) {
                            Text(s(.trafficUIStatus)).font(.caption)
                            Picker(s(.trafficUIStatus), selection: TrafficBindings.status(model, lease: lease, owner: owner)) {
                                Text(s(.trafficUIAllStatuses)).tag("all")
                                ForEach(["2xx", "3xx", "4xx", "5xx"], id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().frame(width: 150)
                        }
                    }
                    Button(s(.trafficUIResetAdvanced)) { _ = model.resetAdvanced(lease: lease, owner: capturedOwner) }
                }.padding(.top, 8)
            }
        }.disabled(!model.controlsAvailable)
    }
    private func field(_ field: TrafficTextField, _ key: AppStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s(key)).font(.caption)
            TextField(s(key), text: TrafficBindings.text(model, field: field, lease: lease)).textFieldStyle(.roundedBorder).accessibilityLabel(s(key))
        }
    }
    private var notices: some View {
        VStack(alignment: .leading, spacing: 5) {
            let errors = [model.store.failure, model.store.catalog.failure, model.store.hosts.failure, model.store.settings.failure].compactMap { $0?.text(language: language) }
            ForEach(Array(Set(errors)).sorted(), id: \.self) { Text($0).foregroundStyle(.red).textSelection(.enabled) }
            if model.store.catalog.isStale, model.store.catalog.value != nil { Text(s(.findingUIStale)).font(.caption).foregroundStyle(.secondary) }
            if model.hasPendingText { Text(s(.trafficUIPendingInput)).font(.caption).foregroundStyle(.secondary) }
            if model.store.hasUnknownOutcome {
                let revision = model.store.unknownRevision, capturedOwner = owner
                Text(s(.trafficUIUnknown)).font(.callout)
                Button(s(.trafficUIAcknowledge)) { _ = model.acknowledge(lease: lease, owner: capturedOwner, revision: revision) }
                    .disabled(!model.controlsAvailable || !model.store.canAcknowledgeUnknown || model.hasPendingText)
            }
            if case .deleted(let receipt) = model.store.lastReceipt {
                Text(receipt.reclaimed.map { f(.trafficUIReclaimed, ["count": String(receipt.deleted), "bytes": String($0)]) } ?? f(.trafficUIDeleted, ["count": String(receipt.deleted)])).font(.caption)
            }
        }
    }
    private var actions: some View {
        let capturedOwner = owner
        return HStack {
            Button(s(.trafficUIHosts)) { showHosts.toggle() }.popover(isPresented: $showHosts) { hostsPanel }
                .disabled(!model.controlsAvailable)
            Text(f(.trafficUISelectedHosts, ["count": String(model.store.selectedHosts.count)])).font(.caption)
            Spacer()
            Button(s(.trafficUIDeleteMatching)) { _ = model.prepareDeletion(.matchingHost, lease: lease, owner: capturedOwner) }
                .disabled(model.store.query.host.isEmpty || !canDelete)
            Button(s(.trafficUIDeleteSelected)) { _ = model.prepareDeletion(.selectedHosts, lease: lease, owner: capturedOwner) }
                .disabled(model.store.selectedHosts.isEmpty || !canDelete || model.store.hosts.isStale)
            Button(s(.trafficUIPurge), role: .destructive) { _ = model.prepareDeletion(.purgeAll, lease: lease, owner: capturedOwner) }.disabled(!canDelete)
        }.controlSize(.small)
    }
    private var flowActions: some View {
        let capturedOwner = owner, revision = model.store.flowRevision
        let visible = model.store.catalog.value?.exchanges ?? []
        let all = !visible.isEmpty && visible.allSatisfy { row in model.store.selectedFlowIDs.contains { Data($0.utf8) == row.identity } }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(s(.trafficUISelectFlows), isOn: .init(get: { all }, set: { _ = model.selectVisibleFlows($0, lease: lease, owner: capturedOwner) }))
                    .toggleStyle(.checkbox).disabled(!recordActions)
                Text(f(.trafficUILinkCount, ["count": String(model.store.selectedFlowIDs.count)])).font(.caption)
                Spacer()
                Button(s(.trafficUIClearFlows)) { _ = model.clearFlows(lease: lease, owner: capturedOwner, revision: revision) }.disabled(!model.controlsAvailable || model.store.selectedFlowIDs.isEmpty)
                Button(s(.trafficUILink)) { _ = model.openLink(lease: lease, owner: capturedOwner, revision: revision) }
                    .disabled(!model.controlsAvailable || !model.canOpenLink || model.hasPendingText || model.store.selectedFlowIDs.isEmpty)
            }.controlSize(.small)
            if model.linkHasUnknown {
                Text(s(.trafficUILinkUnknown)).foregroundStyle(.orange)
                Button(s(.trafficUILinkRecovery)) { _ = model.openLinkRecovery(lease: lease) }.disabled(!model.controlsAvailable)
            }
            if let count = model.linkedCount { Text(f(.trafficUILinkDone, ["count": String(count)])) }
            if model.linkSelectionPreserved { Text(s(.trafficUILinkPreserved)).foregroundStyle(.secondary) }
        }
    }
    private var canDelete: Bool { recordActions && !model.linkHasUnknown && !model.store.isRefreshing && !model.store.hasUnknownOutcome && model.store.catalog.value?.isUnavailable == false }
    private var hostsPanel: some View {
        let capturedOwner = owner
        let hosts = (model.store.hosts.value?.hosts ?? []).sorted {
            if $0.count != $1.count { return countsDescending ? $0.count > $1.count : $0.count < $1.count }
            return $0.host.compare($1.host, locale: locale) == .orderedAscending
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(s(.trafficUIHosts)).font(.headline); Spacer()
                Button(s(countsDescending ? .trafficUIHostSortAscending : .trafficUIHostSortDescending), systemImage: "arrow.up.arrow.down") { countsDescending.toggle() }.labelStyle(.iconOnly)
            }
            FindingReadNotice(state: model.store.hosts)
            HStack {
                Button(s(.trafficUISelectAllHosts)) { _ = model.selectHosts(true, lease: lease, owner: capturedOwner) }
                Button(s(.trafficUIClearHosts)) { _ = model.selectHosts(false, lease: lease, owner: capturedOwner) }
            }
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(hosts, id: \.identity) { host in
                        Toggle(isOn: TrafficBindings.host(model, host: host.host, lease: lease, owner: capturedOwner)) {
                            HStack { Text(host.host).lineLimit(2); Spacer(); Text(String(host.count)).monospacedDigit() }
                        }.toggleStyle(.checkbox)
                    }
                }
            }.frame(maxHeight: 320)
        }.padding().frame(width: 380).disabled(!model.canUseRecords(lease: lease, owner: capturedOwner) || model.store.hosts.isStale || model.store.hosts.isLoading)
    }
    private var trafficList: some View {
        let capturedOwner = owner
        return ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    if model.store.catalog.value?.isUnavailable == true { Text(s(.trafficUIUnavailable)).padding() }
                    else if model.store.catalog.value?.exchanges.isEmpty == true { Text(s(.trafficUIEmpty)).padding() }
                    ForEach(model.store.catalog.value?.exchanges ?? [], id: \.identity) { row in
                        HStack(spacing: 12) {
                            Toggle(f(.trafficUISelectFlow, ["id": row.id]), isOn: TrafficBindings.flow(model, id: row.id, lease: lease, owner: capturedOwner))
                                .labelsHidden().toggleStyle(.checkbox).frame(width: 24).disabled(!recordActions)
                            Text(row.ts).frame(width: 180, alignment: .leading)
                            Text(row.host).frame(width: 150, alignment: .leading)
                            Text(row.method).frame(width: 70, alignment: .leading)
                            Button { Task { await model.selectDetail(row.id, lease: lease, owner: capturedOwner) } } label: { Text(row.url).lineLimit(1).frame(minWidth: 260, maxWidth: .infinity, alignment: .leading) }
                                .buttonStyle(.plain).help(s(.trafficUIOpen)).disabled(!recordActions)
                            Text(String(row.status)).frame(width: 80, alignment: .trailing)
                            Text(String(row.responseLength)).frame(width: 110, alignment: .trailing)
                        }.font(.system(.caption, design: .monospaced)).lineLimit(1).padding(.vertical, 9).padding(.horizontal, 8)
                        Divider()
                    }
                } header: {
                    HStack(spacing: 12) {
                        Color.clear.frame(width: 24, height: 1)
                        sort(.timestamp, .trafficUITime).frame(width: 180, alignment: .leading)
                        Text(s(.trafficUIHostColumn)).frame(width: 150, alignment: .leading)
                        Text(s(.trafficUIMethod)).frame(width: 70, alignment: .leading)
                        Text(s(.trafficUIURL)).frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
                        sort(.status, .trafficUIStatusColumn).frame(width: 80, alignment: .trailing)
                        sort(.responseLength, .trafficUILength).frame(width: 110, alignment: .trailing)
                    }.font(.caption.bold()).padding(8).background(.regularMaterial)
                }
            }.frame(minWidth: 980)
        }.background(.background).overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
    }
    private func sort(_ field: TrafficSort, _ label: AppStringKey) -> some View {
        let capturedOwner = owner, active = model.store.query.sort == field
        let ascending = active && model.store.query.order == .descending
        return Button {
            guard model.store.owner == capturedOwner else { return }; _ = model.control(.sort(field), lease: lease)
        } label: {
            HStack(spacing: 3) { Text(s(label)); if active { Image(systemName: model.store.query.order == .ascending ? "arrow.up" : "arrow.down") } }
        }.buttonStyle(.plain).accessibilityLabel(f(ascending ? .trafficUISortAscending : .trafficUISortDescending, ["field": s(label)])).disabled(!model.controlsAvailable)
    }
    private var pager: some View {
        let capturedOwner = owner
        let page = model.store.query.page, total = model.store.catalog.value?.total ?? 0
        let pages = total > 0 ? (total - 1) / Int64(model.store.query.size) + 1 : 1
        return HStack {
            Picker(s(.trafficUIPageSize), selection: TrafficBindings.size(model, lease: lease, owner: owner)) {
                ForEach([25, 50, 100, 200], id: \.self) { Text(String($0)).tag($0) }
            }.frame(width: 210).disabled(!model.controlsAvailable)
            Spacer()
            Text(f(.trafficUIPage, ["page": String(page + 1), "pages": String(pages)])).font(.caption).monospacedDigit()
            Button(s(.trafficUIPrevious)) { _ = model.page(-1, lease: lease, owner: capturedOwner) }.disabled(!model.controlsAvailable || !model.store.hasPrevious)
            Button(s(.trafficUINext)) { _ = model.page(1, lease: lease, owner: capturedOwner) }.disabled(!model.controlsAvailable || !model.store.hasNext)
        }.controlSize(.small)
    }
}

@MainActor struct TrafficDeleteDialog: View {
    let model: TrafficScreenModel
    let lease: UUID
    let contextID: UUID
    var context: TrafficConfirmation? {
        guard model.presentation == lease, let value = model.deletionDialog, value.id == contextID else { return nil }
        return value
    }
    @Environment(\.locale) private var locale
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    var body: some View {
        Group { if let context { content(context) } }
    }
    private func content(_ context: TrafficConfirmation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(s(.trafficUIConfirmTitle)).font(.title2.bold())
            switch context.change {
            case .deleteMatchingHost(let host):
                Text(s(.trafficUIScopeFilter)); Text(host).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            case .deleteHosts(let hosts):
                Text(s(.trafficUIScopeSelected)); ScrollView { Text(hosts.joined(separator: "\n")).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 220)
            case .purgeAll: Text(s(.trafficUIScopeAll))
            case .capture: EmptyView()
            }
            Text(s(.trafficUIScopeWarning)).foregroundStyle(.secondary)
            HStack {
                if model.store.isMutating { ProgressView().controlSize(.small) }
                Spacer()
                Button(s(.trafficUICancel)) { _ = model.cancelDeletion(id: context.id, lease: lease, owner: context.owner) }.keyboardShortcut(.cancelAction)
                Button(s(.trafficUIConfirmDelete), role: .destructive) { Task { _ = await model.confirmDeletion(id: context.id, lease: lease, owner: context.owner) } }
            }.disabled(model.store.isMutating || model.deletionDialog?.id != context.id || model.presentation != lease)
        }.padding(24).frame(minWidth: 480, idealWidth: 580).interactiveDismissDisabled(model.store.isMutating)
    }
}

@MainActor struct TrafficRawPreview: View {
    let model: TrafficScreenModel
    let lease: UUID, owner: UUID, revision: UUID
    let id: String
    @Environment(\.locale) private var locale
    @State private var response = false
    @State private var wrap = false
    @State private var presenter = EvidenceSavePanelPresenter()
    var ownedExport: TrafficBodyExportModel? {
        guard model.bodyExportSupported, let export = model.bodyExport,
              export.scope.presentation == lease, export.scope.storeOwner == owner,
              export.scope.detailRevision == revision, Data(export.scope.trafficID.utf8) == Data(id.utf8),
              model.presentation == lease, model.store.owner == owner, model.previewRevision == revision else { return nil }
        return export
    }
    private var side: FindingEvidenceSide { response ? .response : .request }
    private var sideBinding: Binding<Bool> {
        Binding(get: { response }, set: { value in
            guard ownedExport?.isExporting != true else { return }
            ownedExport?.cancel(); response = value
        })
    }
    private var language: AppLanguage { .preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private var packet: String {
        guard model.presentation == lease, model.previewRevision == revision, model.store.selectedExchange?.identity == Data(id.utf8),
              let detail = model.store.detail.value, let exchange = model.store.selectedExchange else { return "" }
        return response ? detail.response : TrafficPresentation.request(detail.request, url: exchange.url, host: exchange.host)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(s(.trafficUIOpen), selection: sideBinding) { Text(s(.trafficUIRequest)).tag(false); Text(s(.trafficUIResponse)).tag(true) }.pickerStyle(.segmented).frame(width: 240).disabled(ownedExport?.isExporting == true)
                Spacer()
                Toggle(s(.trafficUIWrap), isOn: $wrap).toggleStyle(.checkbox)
                Button(s(.trafficUICopy)) {
                    let value = packet
                    guard !value.isEmpty, !model.store.detail.isStale, !model.store.detail.isLoading else { return }
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
                }.disabled(packet.isEmpty || model.store.detail.isStale || model.store.detail.isLoading)
                if let export = ownedExport {
                    Button(s(.evidenceUIDownload), systemImage: "square.and.arrow.down") {
                        presenter.language = language
                        _ = export.start(side, owner: export.id, chooser: presenter)
                    }.disabled(!export.canStart(side))
                }
                Button(s(.trafficUIClose)) { model.closeDetail(id, lease: lease, owner: owner, revision: revision) }.keyboardShortcut(.cancelAction)
            }
            FindingReadNotice(state: model.store.detail)
            if let export = ownedExport {
                if export.isExporting {
                    HStack { ProgressView().controlSize(.small); Text(s(.evidenceUIExporting)); Button(s(.findingUICancel)) { export.cancel() } }
                }
                if let failure = export.failure { Text(failure.text(language: language)).foregroundStyle(.red) }
                if let file = export.saved {
                    Text(AppStrings.formatted(.evidenceUISaved, language: language, values: ["name": file.url.lastPathComponent, "bytes": String(file.byteCount)])).textSelection(.enabled)
                    Text(verbatim: "SHA-256: " + file.sha256).font(.caption.monospaced()).textSelection(.enabled)
                    if !file.stagingCleanupComplete || !file.directorySynced { Text(s(.evidenceUISavedWarning)).foregroundStyle(.orange) }
                }
            }
            ScrollView(wrap ? [.vertical] : [.horizontal, .vertical]) {
                Text(packet).font(.system(.body, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: !wrap, vertical: true).frame(maxWidth: wrap ? .infinity : nil, alignment: .leading).padding(12)
            }.background(.background)
        }.background(EvidenceWindowAnchor(presenter: presenter).frame(width: 0, height: 0))
        .onDisappear { ownedExport?.cancel() }
        .padding(20).frame(minWidth: 700, idealWidth: 1000, minHeight: 500, idealHeight: 700)
    }
}
