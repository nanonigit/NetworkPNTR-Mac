import ArtexCore
import SwiftUI

struct RootView: View {
    let environment: DesktopRuntime
    private var runtime: VMController { environment.controller }
    @State private var selection: String? = "runtime"
    @State private var catalog: FeatureCatalog?
    @State private var catalogError: String?
    @State private var taskDetailID: String?
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Mac") {
                    Label("実行環境", systemImage: "desktopcomputer").tag("runtime")
                    Label("アカウント", systemImage: "person.crop.circle").tag("auth")
                    Label("機能の比較状況", systemImage: "checklist").tag("parity")
                }
                if let catalog {
                    Section("Features") { ForEach(Array(catalog.features.prefix(10))) { feature in featureRow(feature) } }
                    Section("System") { ForEach(Array(catalog.features.dropFirst(10))) { feature in featureRow(feature) } }
                }
            }
            .navigationTitle("ARTEX")
            .navigationSplitViewColumnWidth(min: 200, ideal: 228, max: 300)
            .safeAreaInset(edge: .bottom) {
                Label(runtime.guestReady ? "隔離Linux：起動確認済み" : "隔離Linux：" + runtime.state.rawValue, systemImage: "shield.lefthalf.filled")
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
        } detail: {
            if let catalogError { ContentUnavailableView("機能一覧を読み込めません", systemImage: "exclamationmark.triangle", description: Text(catalogError)) }
            else if selection == "runtime" { RuntimeView(environment: environment) }
            else if selection == "auth", let session = environment.authentication { AuthenticationView(session: session) }
            else if selection == "auth" { ContentUnavailableView("ARTEXを起動してください", systemImage: "power", description: Text("実行環境の準備が完了すると認証画面を開きます。")) }
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
                ContentUnavailableView("ログインが必要です", systemImage: "person.crop.circle", description: Text("アカウント画面でログインしてからダッシュボードを開いてください。"))
            }
            else if selection == "chat", let session = environment.authentication, session.phase == .authenticated {
                ChatView(session: session).id(ObjectIdentifier(session))
            }
            else if selection == "chat" {
                ContentUnavailableView("ログインが必要です", systemImage: "person.crop.circle", description: Text("アカウント画面でログインしてからチャットを開いてください。"))
            }
            else if selection == "llm", let session = environment.authentication, session.phase == .authenticated {
                LLMSettingsView(session: session).id(ObjectIdentifier(session))
            }
            else if selection == "llm" {
                ContentUnavailableView("ログインが必要です", systemImage: "person.crop.circle", description: Text("アカウント画面でログインしてからLLM設定を開いてください。"))
            }
            else if let feature = catalog?.features.first(where: { $0.id == selection }) {
                ContentUnavailableView {
                    Label(feature.title, systemImage: "hammer")
                } description: {
                    Text("フェーズ\(feature.phase)で移植予定です。ブラウザ版の \(feature.browserPath) と機能・UI/UXを比較して実装します。現在は操作できません。")
                }
                .navigationTitle(feature.title)
            }
        }
        .sheet(isPresented: Binding(get: { taskDetailID != nil }, set: { if !$0 { taskDetailID = nil } })) {
            VStack(alignment: .leading, spacing: 16) {
                Label("タスク詳細は移植中です", systemImage: "hammer").font(.title2.bold())
                Text("選択したタスク：" + (taskDetailID ?? "")).textSelection(.enabled)
                Text("ブラウザ版の詳細画面と比較して実装する予定です。")
                Button("閉じる") { taskDetailID = nil }.keyboardShortcut(.cancelAction)
            }.padding(28).frame(minWidth: 440)
        }
        .task {
            do { catalog = try FeatureCatalog.load() } catch { catalogError = error.localizedDescription }
            await environment.start()
        }
        .onChange(of: environment.authentication?.phase) { _, phase in
            if phase == .needsSetup || phase == .needsLogin || phase == .unavailable { selection = "auth" }
        }
    }
    private func featureRow(_ feature: BrowserFeature) -> some View {
        Label(feature.title, systemImage: feature.id == "chat" ? "bubble.left.and.bubble.right" : feature.id == "llm" ? "brain" : feature.id == "tasks" ? "checklist" : feature.id == "settings" ? "gearshape" : "square.grid.2x2")
            .tag(feature.id)
    }
}
