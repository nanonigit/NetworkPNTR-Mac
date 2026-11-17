import NetworkPNTRCore
import SwiftUI

struct RootView: View {
    let environment: DesktopRuntime
    let language: AppLanguagePreferences
    let trafficRetirements: TrafficBodyExportRetirement
    private var runtime: VMController { environment.controller }
    @State private var selection: String? = "runtime"
    @State private var catalog: FeatureCatalog?
    @State private var catalogError: String?
    @State private var taskDetailID: String?
    @State private var taskScreen: TaskScreenModel?
    @State private var taskOwner: ObjectIdentifier?
    @State private var llmWorkspace = LLMWorkspace()
    @State private var findingScreen: FindingScreenModel?
    @State private var findingOwner: ObjectIdentifier?
    @State private var trafficScreen: TrafficScreenModel?
    @State private var trafficOwner: ObjectIdentifier?
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Mac") {
                    Label(s(.runtime), systemImage: "desktopcomputer").tag("runtime")
                    Label(s(.account), systemImage: "person.crop.circle").tag("auth")
                    Label(s(.mcpClientsTitle), systemImage: "link").tag("mcp-clients")
                    Label(s(.parity), systemImage: "checklist").tag("parity")
                }
                if let catalog {
                    Section(s(.features)) { ForEach(Array(catalog.features.prefix(10))) { feature in featureRow(feature) } }
                    Section(s(.system)) { ForEach(Array(catalog.features.dropFirst(10))) { feature in featureRow(feature) } }
                }
            }
            .navigationTitle(s(.productName))
            .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 300)
            .safeAreaInset(edge: .bottom) {
                Label(runtime.guestReady ? s(.guestReady) : s(.guestPrefix) + RuntimeLabels.state(runtime.state, language: language.language), systemImage: "shield.lefthalf.filled")
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
        } detail: {
            if let catalogError { ContentUnavailableView(s(.catalogUnavailable), systemImage: "exclamationmark.triangle", description: Text(catalogError)) }
            else if selection == "runtime" { RuntimeView(environment: environment) }
            else if selection == "mcp-clients" { MCPConnectionsView(environment: environment) }
            else if selection == "auth", let session = environment.authentication { AuthenticationView(session: session) }
            else if selection == "auth" { ContentUnavailableView(s(.startRequired), systemImage: "power", description: Text(s(.authPreparation))) }
            else if selection == "parity", let catalog { ParityView(catalog: catalog) }
            else if selection == "dashboard", let session = environment.authentication, session.phase == .authenticated {
                DashboardView(session: session) { destination in
                    switch destination {
                    case .feature(let id): selection = id
                    case .task(let id): taskDetailID = id; selection = "tasks"
                    }
                }.id(ObjectIdentifier(session))
            }
            else if selection == "dashboard" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle", description: Text(s(.dashboardLogin)))
            }
            else if selection == "tasks", let session = environment.authentication, session.phase == .authenticated {
                taskContent(session)
            }
            else if selection == "tasks" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle", description: Text(s(.taskUILogin)))
            }
            else if selection == "chat", let session = environment.authentication, session.phase == .authenticated {
                ChatView(session: session).id(ObjectIdentifier(session))
            }
            else if selection == "commands", let session = environment.authentication, session.phase == .authenticated {
                ToolRunView(session: session).id(ObjectIdentifier(session))
            }
            else if selection == "commands" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle",
                                       description: Text(s(.toolRunLogin)))
            }
            else if selection == "llm-records", let session = environment.authentication, session.phase == .authenticated {
                LLMRecordView(session: session).id(ObjectIdentifier(session))
            }
            else if selection == "llm-records" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle",
                                       description: Text(s(.llmRecordLogin)))
            }
            else if selection == "assets", let session = environment.authentication, session.phase == .authenticated {
                AssetCatalogView(session: session).id(ObjectIdentifier(session))
            }
            else if selection == "assets" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle",
                                       description: Text(s(.assetCatalogLogin)))
            }
            else if selection == "traffic", let session = environment.authentication, session.phase == .authenticated {
                trafficContent(session)
            }
            else if selection == "traffic" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle", description: Text(s(.taskUILogin)))
            }
            else if selection == "findings", let session = environment.authentication, session.phase == .authenticated {
                findingContent(session)
            }
            else if selection == "findings" {
                ContentUnavailableView(s(.loginRequired),systemImage:"person.crop.circle",description:Text(s(.taskUILogin)))
            }
            else if selection == "chat" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle", description: Text(s(.chatLogin)))
            }
            else if selection == "llm", let session = environment.authentication, session.phase == .authenticated {
                llmContent(session)
            }
            else if selection == "llm" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle", description: Text(s(.llmLogin)))
            }
            else if selection == "agents", let session = environment.authentication, session.phase == .authenticated {
                AgentCatalogView(session: session).id(ObjectIdentifier(session))
            }
            else if selection == "agents" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle",
                                       description: Text(s(.agentCatalogLogin)))
            }
            else if let feature = catalog?.features.first(where: { $0.id == selection }) {
                ContentUnavailableView {
                    Label(title(feature), systemImage: "hammer")
                } description: {
                    Text(AppStrings.plannedFeature(phase: feature.phase, path: feature.browserPath, language: language.language))
                }
                .navigationTitle(title(feature))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !trafficRetirements.notices.isEmpty {
                VStack(alignment: .leading) {
                    ForEach(trafficRetirements.notices) { notice in
                        HStack {
                            Text(notice.message.text(language: language.language)).foregroundStyle(.red)
                            Spacer()
                            Button(s(.trafficUIClose)) { trafficRetirements.dismiss(notice.id) }
                        }
                    }
                }.padding().background(.background)
            }
        }
        .environment(\.locale, language.language.locale)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker(s(.language), selection: Binding(get: { language.language }, set: { language.select($0) })) {
                    ForEach(AppLanguage.allCases) { value in Text(value.nativeName).tag(value) }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(s(.language))
                .help(s(.languageHelp))
            }
        }
        .task {
            do { catalog = try FeatureCatalog.load() } catch { catalogError = error.localizedDescription }
            // Diagnostic startup belongs to its validated plan, not this UI task.
            if RuntimeFactory.diagnosticsDirectory == nil { await environment.start() }
        }
        .onChange(of: runtime.trafficBlobExportGeneration) { _, _ in
            trafficScreen?.reset(); trafficOwner = nil
        }
        .onChange(of: environment.authentication?.exportSessionGeneration) { _, _ in
            trafficScreen?.reset(); trafficOwner = nil
        }
        .onChange(of: environment.authentication?.phase) { _, phase in
            if phase != .authenticated { llmWorkspace.reset(); taskScreen?.reset(); findingScreen?.reset(); trafficScreen?.reset(); taskDetailID = nil }
            if phase == .needsSetup || phase == .needsLogin || phase == .unavailable { selection = "auth" }
        }
    }
    @ViewBuilder private func llmContent(_ session: AuthenticationSession) -> some View {
        if llmWorkspace.belongs(to: session), let store = llmWorkspace.store {
            LLMSettingsView(store: store).id(ObjectIdentifier(session))
        } else {
            ProgressView().task {
                guard !Task.isCancelled, session.phase == .authenticated else { return }
                llmWorkspace.attach(owner: session) {
                    LLMStore(service: LLMService(client: AuthenticatedBackendClient(session: session)))
                }
            }
        }
    }
    @ViewBuilder private func trafficContent(_ session: AuthenticationSession) -> some View {
        if trafficOwner == ObjectIdentifier(session), let trafficScreen {
            TrafficView(model: trafficScreen).id(ObjectIdentifier(session))
        } else {
            ProgressView().task {
                guard !Task.isCancelled, session.phase == .authenticated else { return }
                trafficScreen?.reset()
                let client = AuthenticatedBackendClient(session: session)
                let runtime = environment.controller
                let generation = runtime.trafficBlobExportGeneration
                let authenticationGeneration = session.exportSessionGeneration
                let metadata = TrafficService(client: client)
                trafficScreen = TrafficScreenModel(store: TrafficStore(service: metadata), findings: FindingService(client: client), binding: FindingTrafficService(client: client), bodyMetadata: metadata.blobDownload, bodyExporter: session.authenticatedTrafficBlobExport, bodyAvailable: { [weak runtime, weak session] in
                    guard let runtime, let session, generation != nil, authenticationGeneration != nil else { return false }
                    return runtime.trafficBlobExportGeneration == generation && session.exportSessionGeneration == authenticationGeneration
                }, bodyRetirement: trafficRetirements, preferences: .standard)
                trafficOwner = ObjectIdentifier(session)
            }
        }
    }
    @ViewBuilder private func findingContent(_ session: AuthenticationSession) -> some View {
        if findingOwner == ObjectIdentifier(session), let findingScreen {
            FindingsView(model:findingScreen) { id in taskDetailID = id; selection = "tasks" }
        } else {
            ProgressView().task {
                guard !Task.isCancelled, session.phase == .authenticated else { return }
                findingScreen?.reset()
                let client = AuthenticatedBackendClient(session:session)
                findingScreen = FindingScreenModel(store:FindingStore(service:FindingService(client:client)),preferences:.standard,trafficService:FindingTrafficService(client:client),capturedTrafficService:CapturedTrafficService(client:client),evidenceExporter:{ [weak evidenceSession = session] manifest,destination in
                    guard let evidenceSession else { throw CancellationError() }; return try await evidenceSession.authenticatedEvidenceExport(manifest,destination:destination)
                })
                findingOwner = ObjectIdentifier(session)
            }
        }
    }
    @ViewBuilder private func taskContent(_ session: AuthenticationSession) -> some View {
        if taskOwner == ObjectIdentifier(session), let taskScreen {
            TasksView(model: taskScreen, requestedID: $taskDetailID)
        } else {
            ProgressView().task {
                guard !Task.isCancelled, session.phase == .authenticated else { return }
                taskScreen?.reset()
                let client = AuthenticatedBackendClient(session: session)
                taskScreen = TaskScreenModel(store: TaskStore(service: TaskService(client: client)), creationService: TaskCreationService(client: client), stagingUploader: client, templateService: TaskTemplateService(client: client), categoryService: TaskCategoryService(client: client), bulkService: TaskService(client: client), archiveService: TaskArchiveService(client: client))
                taskOwner = ObjectIdentifier(session)
            }
        }
    }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language.language) }
    private func title(_ feature: BrowserFeature) -> String { AppStrings.featureTitle(feature.id, fallback: feature.title, language: language.language) }
    private func featureRow(_ feature: BrowserFeature) -> some View {
        Label(title(feature), systemImage: feature.id == "chat" ? "bubble.left.and.bubble.right" : feature.id == "llm" ? "brain" : feature.id == "tasks" ? "checklist" : feature.id == "settings" ? "gearshape" : "square.grid.2x2")
            .tag(feature.id)
    }
}
