import ArtexCore
import SwiftUI

struct RuntimeView: View {
    let runtime: VMController
    private var guestDirectory: URL { Bundle.main.resourceURL!.appendingPathComponent("Guest") }
    private var logDirectory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("artex-mac-proof", isDirectory: true) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("専用Linux実行環境").font(.largeTitle.bold())
                    Text("Phase 1 · Macアプリが管理する仮想マシンの技術実証").foregroundStyle(.secondary)
                }
                GroupBox {
                    HStack(spacing: 16) {
                        Image(systemName: runtime.guestReady ? "checkmark.shield.fill" : "shield.lefthalf.filled").font(.system(size: 32)).foregroundStyle(runtime.guestReady ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(runtime.guestReady ? "Linuxの起動を確認しました" : runtime.state == .running ? "Linuxを起動しています" : "状態：" + runtime.state.rawValue).font(.headline)
                            Text("Docker不要 · ホスト共有なし · ネットワークなし").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if runtime.state == .starting || runtime.state == .stopping { ProgressView().controlSize(.small) }
                    }.padding(12)
                }
                HStack {
                    Button("隔離Linuxを起動", systemImage: "play.fill") {
                        Task { do { try await runtime.start(artifacts: guestDirectory, logs: logDirectory) } catch { /* VMController presents the failure. */ } }
                    }.buttonStyle(.borderedProminent).disabled(!runtime.mayStart).keyboardShortcut("r", modifiers: [.command, .shift])
                    Button("停止", systemImage: "stop.fill") {
                        Task { do { try await runtime.stop() } catch { /* VMController presents the failure. */ } }
                    }.disabled(!runtime.state.canStop)
                    if runtime.state == .failed && runtime.hasMachine {
                        Button("強制停止", role: .destructive) { Task { do { try await runtime.forceStop() } catch { /* Visible in runtime.lastError. */ } } }
                    }
                }
                if let error = runtime.lastError { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled) }
                GroupBox("このフェーズで確認すること") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AppleのVirtualization.frameworkで実際のLinuxを実行", systemImage: "cpu")
                        Label("起動前にカーネルと初期RAMディスクのSHA-256を照合", systemImage: "checkmark.seal")
                        Label("ゲスト起動と停止を実ログで確認", systemImage: "terminal")
                        Text("ARTEX本体・DB・AIタスクの接続は次のフェーズです。サイドバーのブラウザ版機能は現在、移植待ちです。")
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
