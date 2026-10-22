import ArtexCore
import SwiftUI

struct AuthenticationView: View {
    let session: AuthenticationSession
    @State private var password = ""
    @State private var confirmation = ""
    @State private var agreed = false
    @State private var showTerms = false
    @FocusState private var focused: Field?
    private enum Field { case password, confirmation }
    private var setup: Bool { session.phase == .needsSetup }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("ARTEX Mac", systemImage: "shield.lefthalf.filled").font(.title.bold())
                if session.phase == .checking {
                    ProgressView("認証状態を確認しています")
                } else if session.phase == .unavailable {
                    Text("認証状態を確認できません").font(.title2.bold())
                    Text("データベースまたは通信の復旧後に再試行してください。").foregroundStyle(.secondary)
                    if let error = session.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    Button("再試行") { Task { await session.refresh() } }.buttonStyle(.borderedProminent)
                } else if session.phase == .authenticated {
                    Label("ログイン済み", systemImage: "checkmark.shield.fill").font(.title2).foregroundStyle(.green)
                    Text("専用VMのARTEXに接続しています。各機能は比較テストを通したものから順に移植します。").foregroundStyle(.secondary)
                    Button("ログアウト") { session.logout(); agreed = false }
                    if let error = session.error { Text(error).foregroundStyle(.red) }
                } else {
                    Text(setup ? "管理者パスワードを設定" : "ログイン").font(.title2.bold())
                    Text(setup ? "このMacの専用ARTEX環境にパスワードを設定します。初期設定トークンはアプリが安全に受け渡します。" : "ユーザー名はARTEXです。設定したパスワードを入力してください。")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 16) {
                        if !setup { LabeledContent("ユーザー名", value: "ARTEX") }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(setup ? "新しいパスワード" : "パスワード")
                            SecureField(setup ? "8文字以上、UTF-8で72バイト以内" : "パスワード", text: $password)
                                .focused($focused, equals: .password).textContentType(setup ? .newPassword : .password)
                                .onSubmit { if setup { focused = .confirmation } else { submit() } }
                        }
                        if setup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("パスワードを確認")
                                SecureField("もう一度入力", text: $confirmation).focused($focused, equals: .confirmation).onSubmit(submit)
                            }
                        } else {
                            HStack {
                                Toggle("利用条件に同意する", isOn: $agreed).toggleStyle(.checkbox)
                                Button("利用条件を読む") { showTerms = true }
                            }
                        }
                        if let error = session.error { Text(error).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("auth-error") }
                        HStack {
                            Button(setup ? "パスワードを設定" : "ログイン", action: submit)
                                .buttonStyle(.borderedProminent)
                                .disabled(session.isBusy || password.isEmpty || (setup ? confirmation.isEmpty : !agreed))
                            if session.isBusy { ProgressView().controlSize(.small) }
                        }
                    }.textFieldStyle(.roundedBorder)
                }
            }.padding(40).frame(maxWidth: 540, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("アカウント")
        .sheet(isPresented: $showTerms) { TermsView(agreed: $agreed) }
        .onAppear { focused = session.phase == .needsSetup || session.phase == .needsLogin ? .password : nil }
        .onChange(of: session.phase) { _, phase in
            password = ""; confirmation = ""
            focused = phase == .needsSetup || phase == .needsLogin ? .password : nil
        }
        .onDisappear { password = ""; confirmation = ""; focused = nil }
    }
    private func submit() {
        let value = password; let repeated = confirmation
        Task {
            if setup { await session.setup(password: value, confirmation: repeated) }
            else { await session.login(password: value, agreed: agreed) }
        }
    }
}

private struct TermsView: View {
    @Binding var agreed: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var terms: [String: String] = [:]
    @State private var error: String?
    @State private var readToEnd = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(terms["title"] ?? "利用条件").font(.title2.bold())
            Text(terms["meta"] ?? "").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text((terms["intro"] ?? "") + " " + (terms["introEmphasis"] ?? ""))
                    ForEach(1...8, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(terms["a\(index)Title"] ?? "").font(.headline)
                            if index == 3 {
                                ForEach(1...5, id: \.self) { item in Text("\(item). " + (terms["a3Item\(item)"] ?? "")) }
                            } else { Text((terms["a\(index)Body"] ?? "") + " " + (terms["a\(index)Emphasis"] ?? "")) }
                        }
                    }

                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 8
            } action: { _, atEnd in if atEnd { readToEnd = true } }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("閉じる") { dismiss() }
                Spacer()
                Text(readToEnd ? (terms["footerRead"] ?? "") : (terms["footerNotRead"] ?? "")).font(.caption).foregroundStyle(.secondary)
                Button(terms["agreeButton"] ?? "同意する") { agreed = true; dismiss() }.disabled(!readToEnd || terms.isEmpty).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 620, height: 600)
        .task { do { terms = try AuthTerms.load() } catch { self.error = error.localizedDescription } }
    }
}
