import ArtexCore
import SwiftUI
struct ParityView: View {
    let catalog: FeatureCatalog
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ブラウザ版との機能比較").font(.largeTitle.bold())
            Text("基準：" + String(catalog.baseline.prefix(12)) + " · 21主要機能 / 27画面 / 243 APIハンドラー").foregroundStyle(.secondary)
            Text("移植後は同じデータ・操作・エラー・保存状態を比較します。現在はVM技術実証のため、下記機能はすべて未実装です。")
            Table(catalog.features) {
                TableColumn("機能", value: \.title)
                TableColumn("ブラウザ版の画面", value: \.browserPath)
                TableColumn("予定") { feature in Text("フェーズ\(feature.phase)・未移植") }
            }
        }.padding(28).navigationTitle("機能の比較状況")
    }
}
