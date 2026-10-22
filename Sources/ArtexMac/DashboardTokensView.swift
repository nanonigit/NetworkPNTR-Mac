import ArtexCore
import Charts
import SwiftUI

struct DashboardTokensView: View {
    @Bindable var store: DashboardStore
    let metrics: DashboardMetrics
    @State private var selectedDay: String?
    @State private var hoveredDay: String?
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("トークン使用量", systemImage: "chart.bar").font(.headline)
                    Spacer()
                    Picker("集計元", selection: $store.source) {
                        Text("旧集計").tag(DashboardTokenSource.old)
                        Text("使用量台帳").tag(DashboardTokenSource.ledger)
                    }.pickerStyle(.segmented).frame(maxWidth: 240)
                    .help("旧集計はタスク・会話の活動履歴に基づく概算です。使用量台帳は呼び出し単位で記録し、中断した処理の使用量も含みます。台帳導入前の消費は含みません。")
                }
                ViewThatFits(in: .horizontal) {
                    HStack { profilePicker; Spacer(); daysPicker }
                    VStack(alignment: .leading) { profilePicker; daysPicker }
                }
                if store.tokensAvailable {
                    HStack(spacing: 24) {
                        token("入力（キャッシュ除外）", metrics.uncachedInput)
                        token("キャッシュ読込", metrics.tokens.cacheRead)
                        token("出力", metrics.tokens.output)
                        VStack(alignment: .leading) {
                            Text("キャッシュヒット").font(.caption).foregroundStyle(.secondary)
                            Text("\(DashboardFormat.number(metrics.cacheHitPercent))%").monospacedDigit().font(.headline)
                        }
                    }
                    Text("\(metrics.tokens.taskCount) タスク · 合計 \(DashboardFormat.number(metrics.tokens.total)) tokens")
                        .font(.callout).foregroundStyle(.secondary)
                    if metrics.daily.isEmpty {
                        Text("この期間の使用量はありません。").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        chart
                        HStack {
                            Picker("日別の値を確認", selection: $selectedDay) {
                                Text("日付を選択").tag(String?.none)
                                ForEach(metrics.daily) { day in Text(day.date).tag(Optional(day.date)) }
                            }.frame(maxWidth: 260)
                            if let day = metrics.daily.first(where: { $0.date == (selectedDay ?? hoveredDay) }) {
                                Text("\(day.date) · 入力 \(DashboardFormat.number(day.input)) · 出力 \(DashboardFormat.number(day.output)) · キャッシュ \(DashboardFormat.number(day.cacheRead))")
                                    .font(.caption).monospacedDigit().textSelection(.enabled)
                            }
                        }
                        DisclosureGroup("日別データを表で確認") {
                            Grid(alignment: .leading, horizontalSpacing: 24) {
                                GridRow { Text("日付"); Text("入力"); Text("出力"); Text("キャッシュ") }.fontWeight(.semibold)
                                ForEach(metrics.daily) { day in
                                    GridRow {
                                        Text(day.date); Text(DashboardFormat.number(day.input))
                                        Text(DashboardFormat.number(day.output)); Text(DashboardFormat.number(day.cacheRead))
                                    }
                                }
                            }.font(.caption).monospacedDigit().textSelection(.enabled).padding(.top, 8)
                        }
                    }
                    Text(store.source == .old ? "旧集計の日別表示はタスク・会話の作成日に基づく概算です。" : "使用量台帳の日別表示はUTCの記録日を使います。合計は全記録、日別データは最大365日分です。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("ブラウザ版と同じ3系列を表示します。入力にはキャッシュ読込を含むため、積み上げた高さは総トークン数とは異なります。")
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text("使用量の集計に必要なデータを取得しています。").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160) }
            }.padding(12)
        }
        .onChange(of: store.source) { _, _ in resetDay() }
        .onChange(of: store.selection) { _, _ in resetDay() }
        .onChange(of: store.days) { _, _ in resetDay() }
    }
    private func resetDay() { selectedDay = nil; hoveredDay = nil }
    private var profilePicker: some View {
        Picker("モデル設定", selection: $store.selection) {
            Text("すべて").tag(DashboardProfileSelection.all)
            ForEach(store.slow.value?.profiles ?? []) { profile in
                if let id = Int64(profile.id) { Text(profile.name + (profile.isDefault ? " ★" : "")).tag(DashboardProfileSelection.profile(id)) }
            }
            if store.slow.value?.profiles.contains(where: \.isDefault) == false {
                Text("未割当").tag(DashboardProfileSelection.profile(nil))
            }
        }.frame(maxWidth: 300)
    }
    private var daysPicker: some View {
        Picker("期間", selection: $store.days) {
            ForEach(DashboardMetrics.dayRanges, id: \.self) { days in Text("\(days)日").tag(days) }
        }.frame(maxWidth: 160)
    }
    private func token(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(DashboardFormat.number(value)).font(.headline).monospacedDigit()
        }
    }
    private var chart: some View {
        Chart(metrics.daily) { day in
            BarMark(x: .value("日付", day.date), y: .value("トークン", day.input)).foregroundStyle(by: .value("系列", "入力"))
            BarMark(x: .value("日付", day.date), y: .value("トークン", day.output)).foregroundStyle(by: .value("系列", "出力"))
            BarMark(x: .value("日付", day.date), y: .value("トークン", day.cacheRead)).foregroundStyle(by: .value("系列", "キャッシュ読込"))
        }
        .chartForegroundStyleScale(["入力": Color.blue, "出力": Color.green, "キャッシュ読込": Color.purple])
        .chartXSelection(value: $hoveredDay)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) { value in
            AxisGridLine(); AxisTick()
            AxisValueLabel { if let date = value.as(String.self) { Text(String(date.suffix(5))) } }
        } }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                    guard let frame = proxy.plotFrame else { return }
                    switch phase {
                    case .active(let point): hoveredDay = proxy.value(atX: point.x - geometry[frame].origin.x)
                    case .ended: hoveredDay = nil
                    }
                }
            }
        }
        .frame(height: 220)
        .accessibilityLabel("日別トークン使用量。正確な値は日付選択または日別データの表で確認できます。")
    }
}
