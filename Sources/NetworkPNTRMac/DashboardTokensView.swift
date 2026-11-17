import NetworkPNTRCore
import Charts
import SwiftUI

struct DashboardTokensView: View {
    @Environment(\.locale) private var locale
    private var language: AppLanguage { AppLanguage.preferred(in: [locale.identifier]) }
    private func s(_ key: AppStringKey) -> String { AppStrings.text(key, language: language) }
    private func f(_ key: AppStringKey, _ values: [String: String]) -> String { AppStrings.formatted(key, language: language, values: values) }
    @Bindable var store: DashboardStore
    let metrics: DashboardMetrics
    @State private var selectedDay: String?
    @State private var hoveredDay: String?
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(s(.dashboardUITokenUsage), systemImage: "chart.bar").font(.headline)
                    Spacer()
                    Picker(s(.dashboardUISource), selection: $store.source) {
                        Text(s(.dashboardUILegacy)).tag(DashboardTokenSource.old)
                        Text(s(.dashboardUILedger)).tag(DashboardTokenSource.ledger)
                    }.pickerStyle(.segmented).frame(maxWidth: 240)
                    .help(s(.dashboardUISourceHelp))
                }
                ViewThatFits(in: .horizontal) {
                    HStack { profilePicker; Spacer(); daysPicker }
                    VStack(alignment: .leading) { profilePicker; daysPicker }
                }
                if store.tokensAvailable {
                    HStack(spacing: 24) {
                        token(s(.dashboardUIUncachedInput), metrics.uncachedInput)
                        token(s(.dashboardUICacheRead), metrics.tokens.cacheRead)
                        token(s(.dashboardUIOutput), metrics.tokens.output)
                        VStack(alignment: .leading) {
                            Text(s(.dashboardUICacheHit)).font(.caption).foregroundStyle(.secondary)
                            Text("\(DashboardFormat.number(metrics.cacheHitPercent))%").monospacedDigit().font(.headline)
                        }
                    }
                    Text(f(.dashboardUIUsageSummary, ["tasks": String(metrics.tokens.taskCount), "total": DashboardFormat.number(metrics.tokens.total)]))
                        .font(.callout).foregroundStyle(.secondary)
                    if metrics.daily.isEmpty {
                        Text(s(.dashboardUINoUsage)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        chart
                        HStack {
                            Picker(s(.dashboardUIInspectDay), selection: $selectedDay) {
                                Text(s(.dashboardUISelectDate)).tag(String?.none)
                                ForEach(metrics.daily) { day in Text(day.date).tag(Optional(day.date)) }
                            }.frame(maxWidth: 260)
                            if let day = metrics.daily.first(where: { $0.date == (selectedDay ?? hoveredDay) }) {
                                Text(f(.dashboardUIDaySummary, ["date": day.date, "input": DashboardFormat.number(day.input), "output": DashboardFormat.number(day.output), "cache": DashboardFormat.number(day.cacheRead)]))
                                    .font(.caption).monospacedDigit().textSelection(.enabled)
                            }
                        }
                        DisclosureGroup(s(.dashboardUIDailyTable)) {
                            Grid(alignment: .leading, horizontalSpacing: 24) {
                                GridRow { Text(s(.dashboardUIDate)); Text(s(.dashboardUIInput)); Text(s(.dashboardUIOutput)); Text(s(.dashboardUICache)) }.fontWeight(.semibold)
                                ForEach(metrics.daily) { day in
                                    GridRow {
                                        Text(day.date); Text(DashboardFormat.number(day.input))
                                        Text(DashboardFormat.number(day.output)); Text(DashboardFormat.number(day.cacheRead))
                                    }
                                }
                            }.font(.caption).monospacedDigit().textSelection(.enabled).padding(.top, 8)
                        }
                    }
                    Text(store.source == .old ? s(.dashboardUILegacyDailyHelp) : s(.dashboardUILedgerDailyHelp))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(s(.dashboardUIChartHelp))
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text(s(.dashboardUIUsageLoading)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160) }
            }.padding(12)
        }
        .onChange(of: store.source) { _, _ in resetDay() }
        .onChange(of: store.selection) { _, _ in resetDay() }
        .onChange(of: store.days) { _, _ in resetDay() }
    }
    private func resetDay() { selectedDay = nil; hoveredDay = nil }
    private var profilePicker: some View {
        Picker(s(.dashboardUIProfiles), selection: $store.selection) {
            Text(s(.dashboardUIAll)).tag(DashboardProfileSelection.all)
            ForEach(store.slow.value?.profiles ?? []) { profile in
                if let id = Int64(profile.id) { Text(profile.name + (profile.isDefault ? " ★" : "")).tag(DashboardProfileSelection.profile(id)) }
            }
            if store.slow.value?.profiles.contains(where: \.isDefault) == false {
                Text(s(.dashboardUIUnassigned)).tag(DashboardProfileSelection.profile(nil))
            }
        }.frame(maxWidth: 300)
    }
    private var daysPicker: some View {
        Picker(s(.dashboardUIPeriod), selection: $store.days) {
            ForEach(DashboardMetrics.dayRanges, id: \.self) { days in Text(f(.dashboardUIDays, ["days": String(days)])).tag(days) }
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
            BarMark(x: .value(s(.dashboardUIDate), day.date), y: .value(s(.dashboardUITokens), day.input)).foregroundStyle(by: .value(s(.dashboardUISeries), s(.dashboardUIInput)))
            BarMark(x: .value(s(.dashboardUIDate), day.date), y: .value(s(.dashboardUITokens), day.output)).foregroundStyle(by: .value(s(.dashboardUISeries), s(.dashboardUIOutput)))
            BarMark(x: .value(s(.dashboardUIDate), day.date), y: .value(s(.dashboardUITokens), day.cacheRead)).foregroundStyle(by: .value(s(.dashboardUISeries), s(.dashboardUICacheRead)))
        }
        .chartForegroundStyleScale([s(.dashboardUIInput): Color.blue, s(.dashboardUIOutput): Color.green, s(.dashboardUICacheRead): Color.purple])
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
        .accessibilityLabel(s(.dashboardUIChartAccessibility))
    }
}
