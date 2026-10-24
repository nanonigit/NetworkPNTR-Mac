import ArtexCore
import SwiftUI

struct AuthenticationView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
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
                    ProgressView(s(.authChecking))
                } else if session.phase == .unavailable {
                    Text(s(.authUnavailable)).font(.title2.bold())
                    Text(s(.authRecovery)).foregroundStyle(.secondary)
                    if let error = session.failure?.text(language: language) { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                    Button(s(.authRetry)) { Task { await session.refresh() } }.buttonStyle(.borderedProminent)
                } else if session.phase == .authenticated {
                    Label(s(.authLoggedIn), systemImage: "checkmark.shield.fill").font(.title2).foregroundStyle(.green)
                    Text(s(.authConnected)).foregroundStyle(.secondary)
                    Button(s(.authLogout)) { session.logout(); agreed = false }
                    if let error = session.failure?.text(language: language) { Text(error).foregroundStyle(.red) }
                } else {
                    Text(setup ? s(.authSetupTitle) : s(.authLogin)).font(.title2.bold())
                    Text(setup ? s(.authSetupHelp) : s(.authLoginHelp))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 16) {
                        if !setup { LabeledContent(s(.authUsername), value: "ARTEX") }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(setup ? s(.authNewPassword) : s(.authPassword))
                            SecureField(setup ? s(.authPasswordHint) : s(.authPassword), text: $password)
                                .focused($focused, equals: .password).textContentType(setup ? .newPassword : .password)
                                .onSubmit { if setup { focused = .confirmation } else { submit() } }
                        }
                        if setup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(s(.authConfirm))
                                SecureField(s(.authRepeat), text: $confirmation).focused($focused, equals: .confirmation).onSubmit(submit)
                            }
                        } else {
                            HStack {
                                Toggle(s(.authAgree), isOn: $agreed).toggleStyle(.checkbox)
                                Button(s(.authReadTerms)) { showTerms = true }
                            }
                        }
                        if let error = session.failure?.text(language: language) { Text(error).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("auth-error") }
                        HStack {
                            Button(setup ? s(.authSetPassword) : s(.authLogin), action: submit)
                                .buttonStyle(.borderedProminent)
                                .disabled(session.isBusy || password.isEmpty || (setup ? confirmation.isEmpty : !agreed))
                            if session.isBusy { ProgressView().controlSize(.small) }
                        }
                    }.textFieldStyle(.roundedBorder)
                }
            }.padding(40).frame(maxWidth: 540, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(s(.account))
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
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    @Binding var agreed: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var documents: [AppLanguage: [String: String]] = [:]
    private var terms: [String: String] { documents[language] ?? [:] }
    @State private var error: AppErrorMessage?
    @State private var readToEnd = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(terms["title"] ?? s(.authTermsTitle)).font(.title2.bold())
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
            if let error { Text(error.text(language: language)).foregroundStyle(.red) }
            HStack {
                Button(s(.close)) { dismiss() }
                Spacer()
                Text(readToEnd ? (terms["footerRead"] ?? "") : (terms["footerNotRead"] ?? "")).font(.caption).foregroundStyle(.secondary)
                Button(terms["agreeButton"] ?? s(.authAcceptTerms)) { agreed = true; dismiss() }.disabled(!readToEnd || terms.isEmpty).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 620, height: 600)
        .task { do { documents = try AuthTerms.loadAll() } catch { self.error = AppErrorMessage(key: .authTermsUnavailable) } }
    }
}
