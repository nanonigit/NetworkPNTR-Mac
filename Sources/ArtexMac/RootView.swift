import ArtexCore
import SwiftUI

struct RootView: View {
    let environment: DesktopRuntime
    let language: AppLanguagePreferences
    private var runtime: VMController { environment.controller }
    @State private var selection: String? = "runtime"
    @State private var catalog: FeatureCatalog?
    @State private var catalogError: String?
    @State private var taskDetailID: String?
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Mac") {
                    Label(s(.runtime), systemImage: "desktopcomputer").tag("runtime")
                    Label(s(.account), systemImage: "person.crop.circle").tag("auth")
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
                Label(runtime.guestReady ? s(.guestReady) : s(.guestPrefix) + runtime.state.rawValue, systemImage: "shield.lefthalf.filled")
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
        } detail: {
            if let catalogError { ContentUnavailableView(s(.catalogUnavailable), systemImage: "exclamationmark.triangle", description: Text(catalogError)) }
            else if selection == "runtime" { RuntimeView(environment: environment) }
            else if selection == "auth", let session = environment.authentication { AuthenticationView(session: session) }
            else if selection == "auth" { ContentUnavailableView(s(.startRequired), systemImage: "power", description: Text(s(.authPreparation))) }
            else if selection == "parity", let catalog { ParityView(catalog: catalog) }
            else if selection == "dashboard", let session = environment.authentication, session.phase == .authenticated {
                DashboardView(session: session) { destination in
                    switch destination {
                    case .feature(let id): selection = id
                    case .task(let id): taskDetailID = id
                    }
                }.id(ObjectIdentifier(session))
            }
            else if selection == "dashboard" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle", description: Text(s(.dashboardLogin)))
            }
            else if selection == "chat", let session = environment.authentication, session.phase == .authenticated {
                ChatView(session: session).id(ObjectIdentifier(session))
            }
            else if selection == "chat" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle", description: Text(s(.chatLogin)))
            }
            else if selection == "llm", let session = environment.authentication, session.phase == .authenticated {
                LLMSettingsView(session: session).id(ObjectIdentifier(session))
            }
            else if selection == "llm" {
                ContentUnavailableView(s(.loginRequired), systemImage: "person.crop.circle", description: Text(s(.llmLogin)))
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
        .sheet(isPresented: Binding(get: { taskDetailID != nil }, set: { if !$0 { taskDetailID = nil } })) {
            VStack(alignment: .leading, spacing: 16) {
                Label(s(.taskPending), systemImage: "hammer").font(.title2.bold())
                Text(s(.selectedTask) + (taskDetailID ?? "")).textSelection(.enabled)
                Text(s(.taskComparison))
                Button(s(.close)) { taskDetailID = nil }.keyboardShortcut(.cancelAction)
            }.padding(28).frame(minWidth: 440)
        }
        .task {
            do { catalog = try FeatureCatalog.load() } catch { catalogError = error.localizedDescription }
            // Diagnostic startup belongs to its validated plan, not this UI task.
            if RuntimeFactory.diagnosticsDirectory == nil { await environment.start() }
        }
        .onChange(of: environment.authentication?.phase) { _, phase in
            if phase == .needsSetup || phase == .needsLogin || phase == .unavailable { selection = "auth" }
        }
    }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language.language) }
    private func title(_ feature: BrowserFeature) -> String { AppStrings.featureTitle(feature.id, fallback: feature.title, language: language.language) }
    private func featureRow(_ feature: BrowserFeature) -> some View {
        Label(title(feature), systemImage: feature.id == "chat" ? "bubble.left.and.bubble.right" : feature.id == "llm" ? "brain" : feature.id == "tasks" ? "checklist" : feature.id == "settings" ? "gearshape" : "square.grid.2x2")
            .tag(feature.id)
    }
}
