import ArtexCore
import SwiftUI

@MainActor struct LLMRotationView: View {
    let store: LLMStore
    @Environment(\.dismiss) private var dismiss
    private var busy: Bool { store.isLoading || store.isMutating }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ローテーション設定").font(.title2.bold())
            Text("有効な設定を最初に使い、接続障害時は優先順位に従って別の設定へ切り替えます。")
                .foregroundStyle(.secondary)
            if store.pool == nil { ProgressView("設定を取得しています") }
            Toggle("ローテーションを有効にする", isOn: Binding(get: { store.pool?.enabled ?? false }, set: { enabled in Task { await store.setRotation(enabled: enabled) } }))
                .disabled(busy || store.pool == nil)
            if let pool = store.pool, pool.enabled {
                Toggle("個別指定したモデルでも代替を許可", isOn: Binding(get: { store.pool?.bindFallback ?? false }, set: { fallback in Task { await store.setRotation(bindFallback: fallback) } })).disabled(busy)
                Text("個別指定のモデルが利用できない場合にもローテーションを使います。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("実際の試行順").font(.headline)
                    Spacer()
                    Button("すべて復旧") { Task { await store.resetPool() } }.disabled(busy)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(pool.chain.enumerated()), id: \.element.id) { position, member in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(member.excluded && !member.active ? "対象外" : "\(pool.chain.prefix(position + 1).filter { $0.active || !$0.excluded }.count)")
                                        Text(member.name).font(.headline)
                                        if member.active { Text("有効").font(.caption).foregroundStyle(.orange) }
                                        Spacer()
                                        Text(member.state == "tripped" ? "待機 \(member.cooldownSecs)秒" : member.state == "degraded" ? "連続失敗 \(member.fails)" : "正常").font(.caption)
                                    }
                                    Text("\(member.model) · 優先順位 \(member.priority)").font(.caption).foregroundStyle(.secondary)
                                    if let error = member.lastError, !error.isEmpty { Text(error).font(.caption).textSelection(.enabled) }
                                    if member.state != "ok" { Button("この設定を復旧") { Task { await store.resetPool(id: member.profileId) } }.disabled(busy) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                            }
                        }
                        if pool.chain.isEmpty { ContentUnavailableView("モデル設定がありません", systemImage: "brain") }
                    }
                }
            } else { Spacer() }
            if let error = store.error { Text(error).foregroundStyle(.red) }
            HStack { if busy { ProgressView().controlSize(.small) }; Spacer(); Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 630, height: 680)
        .task {
            await store.refreshPool()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                if let pool = store.pool, pool.enabled, pool.chain.contains(where: { $0.state != "ok" }) { await store.refreshPool() }
            }
        }
    }
}
