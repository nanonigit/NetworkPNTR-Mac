import NetworkPNTRCore
import SwiftUI

enum CompanyEditorAction: Identifiable {
    case create
    case append(AssetCatalogCompany)
    case replace(AssetCatalogCompany)
    case delete(AssetCatalogCompany)

    var id: String {
        switch self {
        case .create: "create"
        case .append(let company): "append-\(company.id)"
        case .replace(let company): "replace-\(company.id)"
        case .delete(let company): "delete-\(company.id)"
        }
    }

    var title: AppStringKey {
        switch self {
        case .create: .companyAdd
        case .append: .companyAppend
        case .replace: .companyReplace
        case .delete: .companyDelete
        }
    }
}

enum CompanyEditorFailure: Equatable {
    case duplicate, rejected, missing, unconfirmed

    init(_ error: any Error, action: CompanyEditorAction) {
        switch (error, action) {
        case (BackendAPIError.status(409), .create):
            self = .duplicate
        case (BackendAPIError.status(404), .append),
             (BackendAPIError.status(404), .replace),
             (BackendAPIError.status(404), .delete):
            self = .missing
        case (BackendAPIError.status(400), _), (AssetCatalogQueryError.invalidQuery, _):
            self = .rejected
        default:
            self = .unconfirmed
        }
    }

    var message: AppStringKey {
        switch self {
        case .duplicate: .companyDuplicate
        case .rejected: .companyRejected
        case .missing: .companyMissing
        case .unconfirmed: .companyUnconfirmed
        }
    }

    var requiresRefresh: Bool { self == .missing || self == .unconfirmed }
}

struct CompanyEditorResult {
    let message: AppStringKey
    var added: Int = 0
    var invalid: Int = 0
    var skipped: Int = 0
    var assets: Int64 = 0
    var warnings: [String] = []
}

@MainActor struct CompanyEditor: View {
    @Environment(\.dismiss) private var dismiss
    let action: CompanyEditorAction
    let locale: Locale
    let service: AssetCatalogService
    let refresh: () -> Void
    let completed: (CompanyEditorResult) -> Void

    @State private var name = ""
    @State private var scope: String
    @State private var reason = ""
    @State private var deleteAssets = false
    @State private var busy = false
    @State private var failure: CompanyEditorFailure?

    init(action: CompanyEditorAction, locale: Locale, service: AssetCatalogService, refresh: @escaping () -> Void,
         completed: @escaping (CompanyEditorResult) -> Void) {
        self.action = action
        self.locale = locale
        self.service = service
        self.refresh = refresh
        self.completed = completed
        let existing = Self.savedRules(action).map { $0.raw.trimmingCharacters(in: .whitespacesAndNewlines) }
        _scope = State(initialValue: existing.joined(separator: "\n"))
    }

    var body: some View {
        let parsed = CompanyScopeText(scope, preserving: Self.savedRules(action))
        VStack(alignment: .leading, spacing: 12) {
            Text(s(action.title)).font(.title2.bold())
            switch action {
            case .delete(let company):
                Text(verbatim: company.name).font(.headline)
                Text(s(.companyDeleteHelp))
                Toggle(s(.companyDeleteAssets), isOn: $deleteAssets)
            case .create:
                TextField(s(.companyName), text: $name)
                scopeEditor(parsed)
            case .append(let company), .replace(let company):
                Text(verbatim: company.name).font(.headline)
                if case .replace = action { Text(s(.companyReplaceHelp)).foregroundStyle(.secondary) }
                scopeEditor(parsed)
                TextField(s(.companyReason), text: $reason)
            }
            if let failure { Text(s(failure.message)).foregroundStyle(.red) }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(s(.findingUICancel), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(busy)
                if case .delete = action {
                    Button(s(.companyDelete), role: .destructive) { submit(parsed.rules) }
                        .disabled(busy || failure?.requiresRefresh == true)
                } else {
                    Button(s(.companySave)) { submit(parsed.rules) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy || failure?.requiresRefresh == true || !canSave(parsed))
                }
            }
        }
        .padding(22)
        .frame(width: 510)
        .interactiveDismissDisabled(busy)
    }

    private func scopeEditor(_ parsed: CompanyScopeText) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s(.assetCatalogScope)).font(.headline)
            Text(s(.companyScopeHelp)).foregroundStyle(.secondary)
            TextEditor(text: $scope)
                .font(.body.monospaced())
                .frame(minHeight: 120, idealHeight: 160)
                .border(.quaternary)
                .accessibilityLabel(s(.assetCatalogScope))
            if !parsed.invalidLines.isEmpty {
                let lines = parsed.invalidLines.map { $0.formatted(.number.locale(locale)) }.joined(separator: ", ")
                Text(s(.companyInvalidLines).replacingOccurrences(of: "{lines}", with: lines))
                    .foregroundStyle(.red)
            }
        }
        .disabled(busy)
    }

    private func canSave(_ parsed: CompanyScopeText) -> Bool {
        guard parsed.invalidLines.isEmpty else { return false }
        switch action {
        case .create: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .append: return !parsed.rules.isEmpty
        case .replace, .delete: return true
        }
    }

    private func submit(_ rules: [CompanyScopeInput]) {
        guard !busy, failure?.requiresRefresh != true else { return }
        busy = true
        failure = nil
        let requestedName = name
        let requestedReason = reason
        let requestedDeletion = deleteAssets
        Task {
            defer { busy = false }
            do {
                let result: CompanyEditorResult
                switch action {
                case .create:
                    let receipt = try await service.createCompany(name: requestedName, scope: rules)
                    result = .init(message: .companyCreated, added: receipt.scopeAdded,
                                   invalid: receipt.scopeInvalid, skipped: receipt.scopeSkipped)
                case .append(let company), .replace(let company):
                    let replace: Bool
                    if case .replace = action { replace = true } else { replace = false }
                    let receipt = try await service.writeCompanyScope(id: company.id, scope: rules,
                                                                     reason: requestedReason, replace: replace)
                    result = .init(message: .companyScopeSaved, added: receipt.added,
                                   invalid: receipt.invalid, skipped: receipt.skipped, warnings: receipt.warnings ?? [])
                case .delete(let company):
                    let count = try await service.deleteCompany(id: company.id, deleteAssets: requestedDeletion)
                    result = .init(message: .companyDeleted, assets: count)
                }
                refresh()
                completed(result)
                dismiss()
            } catch {
                let result = CompanyEditorFailure(error, action: action)
                failure = result
                if result.requiresRefresh { refresh() }
            }
        }
    }

    private static func savedRules(_ action: CompanyEditorAction) -> [AssetCatalogCompany.ScopeRule] {
        if case .replace(let company) = action { return company.scope ?? [] }
        return []
    }

    private func s(_ key: AppStringKey) -> String {
        AppStrings.text(key, language: .preferred(in: [locale.identifier]))
    }
}
