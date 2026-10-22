import ArtexCore
import SwiftUI
struct ParityView: View {
    let catalog: FeatureCatalog
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ブラウザ版との機能比較").font(.largeTitle.bold())
            Text("基準：" + String(catalog.baseline.prefix(12)) + " · 21主要機能 / 27画面 / 243 APIハンドラー").foregroundStyle(.secondary)
            Text("同じデータ・操作・エラー・保存状態を比較します。LLM設定は実装・検証中です。全機能の受け入れ条件を満たすまで移植完了にはしません。")
            Table(catalog.features) {
                TableColumn("機能", value: \.title)
                TableColumn("ブラウザ版の画面", value: \.browserPath)
                TableColumn("状態") { feature in Text(feature.nativeStatus == "in_progress" ? "実装・検証中" : "フェーズ\(feature.phase)・移植待ち") }
            }
        }.padding(28).navigationTitle("機能の比較状況")
    }
}
