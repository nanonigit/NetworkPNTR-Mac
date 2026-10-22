import ArtexCore
import SwiftUI

struct RuntimeView: View {
    let environment: DesktopRuntime
    private var runtime: VMController { environment.controller }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("専用Linux実行環境").font(.largeTitle.bold())
                    Text("専用VM内でARTEXとPostgreSQLを実行").foregroundStyle(.secondary)
                }
                GroupBox {
                    HStack(spacing: 16) {
                        Image(systemName: runtime.guestReady ? "checkmark.shield.fill" : "shield.lefthalf.filled").font(.system(size: 32)).foregroundStyle(runtime.guestReady ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(runtime.guestReady ? "ARTEXとDBの起動を確認しました" : runtime.state == .running ? "ARTEXを起動しています" : "状態：" + runtime.state.rawValue).font(.headline)
                            Text("Docker不要 · ホスト共有なし · ネットワークなし").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if runtime.state == .starting || runtime.state == .stopping { ProgressView().controlSize(.small) }
                    }.padding(12)
                }
                HStack {
                    Button("隔離Linuxを起動", systemImage: "play.fill") {
                        Task { await environment.start() }
                    }.buttonStyle(.borderedProminent).disabled(environment.isStarting || !runtime.mayStart).keyboardShortcut("r", modifiers: [.command, .shift])
                    Button("停止", systemImage: "stop.fill") {
                        Task { do { try await environment.stop() } catch { /* VMController presents the failure. */ } }
                    }.disabled(!runtime.state.canStop)
                    if runtime.hasMachine && (runtime.state == .failed || runtime.state == .stopping) {
                        Button("強制停止", role: .destructive) { Task { do { try await environment.forceStop() } catch { /* Visible in runtime.lastError. */ } } }
                    }
                }
                if let error = environment.error ?? runtime.lastError { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled) }
                GroupBox("専用実行環境") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AppleのVirtualization.frameworkで実際のLinuxを実行", systemImage: "cpu")
                        Label("起動前にカーネル・初期RAM・OSディスクのSHA-256を照合", systemImage: "checkmark.seal")
                        Label("設定と認証情報を専用ディスクに保持", systemImage: "terminal")
                        Text("認証はアカウント画面から操作できます。クラウドAPI向け通信は現在オフです。サイドバーの各機能は、比較検証を経て順に接続します。")
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                if !runtime.guestLog.isEmpty {
                    GroupBox("ゲスト起動ログ") {
                        Text(runtime.guestLog).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
            }.padding(32).frame(maxWidth: 940, alignment: .leading)
        }
        .groupBoxStyle(RuntimePanelStyle())
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("実行環境")
    }
}

private struct RuntimePanelStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label.font(.headline)
            configuration.content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}
