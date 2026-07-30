import SwiftUI
import Charts

// MARK: - 走势图
// 指数画点位、ETF 画市价；ETF 可叠加单位净值线，图例明确区分，绝不混画。

enum ChartRange: String, CaseIterable, Identifiable {
    case oneYear = "1年"
    case threeYears = "3年"
    case tenYears = "10年"
    var id: String { rawValue }
    var years: Int {
        switch self {
        case .oneYear: return 1
        case .threeYears: return 3
        case .tenYears: return 10
        }
    }
}

struct PriceChartView: View {
    let target: MarketTarget
    let priceSeries: PriceSeries
    let navSeries: FundNavSeries?   // 仅 ETF：叠加单位净值（虚线 + 图例）

    @State private var range: ChartRange = .threeYears

    private struct Point: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let series: String
    }

    private var priceLabel: String { target.kind == .etf ? "市价" : "点位" }
    private static let navLabel = "单位净值"

    private var points: [Point] {
        let all = priceSeries.bars
        guard let lastDate = all.last.flatMap({ DateUtil.date($0.date) }) else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let cutoff = cal.date(byAdding: .year, value: -range.years, to: lastDate) ?? .distantPast

        let filtered = all.filter { DateUtil.date($0.date).map { $0 >= cutoff } ?? false }
        // 抽样上限约 600 点，避免一次性渲染过多 LineMark
        let stride = max(1, filtered.count / 600)
        var out: [Point] = []
        for (i, bar) in filtered.enumerated() where i % stride == 0 || i == filtered.count - 1 {
            if let d = DateUtil.date(bar.date) {
                out.append(Point(id: "p-\(bar.date)", date: d, value: bar.close, series: priceLabel))
            }
        }
        if target.kind == .etf, let navSeries {
            let navFiltered = navSeries.points.filter { DateUtil.date($0.date).map { $0 >= cutoff } ?? false }
            let navStride = max(1, navFiltered.count / 600)
            for (i, p) in navFiltered.enumerated() where i % navStride == 0 || i == navFiltered.count - 1 {
                if let d = DateUtil.date(p.date) {
                    out.append(Point(id: "n-\(p.date)", date: d, value: p.unitNav, series: Self.navLabel))
                }
            }
        }
        return out
    }

    private var hasNav: Bool { target.kind == .etf && navSeries != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                SectionTitle(target.kind == .etf ? "市价走势（\(target.currency.rawValue)）" : "点位走势")
                Spacer()
            }
            Picker("时间范围", selection: $range) {
                ForEach(ChartRange.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Chart(points) { p in
                LineMark(
                    x: .value("日期", p.date),
                    y: .value(priceLabel, p.value)
                )
                .foregroundStyle(by: .value("系列", p.series))
                .lineStyle(StrokeStyle(lineWidth: p.series == Self.navLabel ? 1.2 : 1.6,
                                       dash: p.series == Self.navLabel ? [5, 3] : []))
                .interpolationMethod(.linear)
            }
            .chartForegroundStyleScale([
                priceLabel: Theme.priceLine,
                Self.navLabel: Theme.navLine,
            ])
            .chartLegend(hasNav ? .visible : .hidden)
            .chartLegend(position: .bottom, alignment: .leading, spacing: Spacing.m)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine().foregroundStyle(Theme.divider)
                    AxisValueLabel(format: .dateTime.year(.twoDigits).month(.twoDigits))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(Theme.divider)
                    AxisValueLabel().foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 220)

            if hasNav {
                Text("虚线为单位净值，与市价分属不同口径；二者之差即溢折价。")
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

// MARK: - 估值变化
// 对历史序列逐点以 asOf 口径重算评分（后台线程），画评分随时间的曲线。

struct ScoreHistoryChartView: View {
    let target: MarketTarget
    @Environment(MarketRepository.self) private var repository
    @State private var history: [ScoreHistoryPoint]?
    @State private var usedMethod: ValuationMethod?

    /// ETF 的评分序列来自底层标的
    private var sourceID: String { target.underlyingTargetID ?? target.id }

    /// 数据到达/更新后触发重算
    private var dataToken: String {
        let pe = repository.peSeries(for: sourceID)?.asOfDate ?? ""
        let price = repository.priceSeries(for: sourceID)?.asOfDate ?? ""
        return "\(target.id)|\(pe)|\(price)"
    }

    private struct Point: Identifiable {
        let id: String
        let date: Date
        let score: Double
    }

    private var chartPoints: [Point] {
        (history ?? []).compactMap { p in
            DateUtil.date(p.date).map { Point(id: p.date, date: $0, score: p.score) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionTitle("估值变化")
            if history != nil, !chartPoints.isEmpty {
                Chart(chartPoints) { p in
                    AreaMark(x: .value("日期", p.date), y: .value("评分", p.score))
                        .foregroundStyle(Theme.accent.opacity(0.07))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("日期", p.date), y: .value("评分", p.score))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.6))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(Theme.divider)
                        AxisValueLabel(format: .dateTime.year(.twoDigits))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 20, 40, 60, 80, 100]) {
                        AxisGridLine().foregroundStyle(Theme.divider)
                        AxisValueLabel().foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 180)
                Text(captionText)
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if history != nil {
                ContentNote(text: "历史数据不足，无法绘制评分曲线。")
            } else {
                HStack(spacing: Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text("正在后台计算历史评分…")
                        .font(AppFont.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.l)
            }
        }
        .task(id: dataToken) {
            await compute()
        }
    }

    private var captionText: String {
        let method = usedMethod == .pricePosition ? "价格位置分位" : "PE 分位"
        return "每个采样点按当时可得的历史窗口重算评分（\(method)），曲线左端窗口较短、波动偏大属正常。评分只描述相对历史的位置。"
    }

    private func compute() async {
        let pe = repository.peSeries(for: sourceID)
        let price = repository.priceSeries(for: sourceID)
        let method = target.method
        let computed: ([ScoreHistoryPoint], ValuationMethod?) = await Task.detached(priority: .userInitiated) {
            switch method {
            case .fundamentals:
                if let pe { return (ValuationEngine.scoreHistory(peSeries: pe), .fundamentals) }
                if let price { return (ValuationEngine.scoreHistory(priceSeries: price), .pricePosition) }
                return ([], nil)
            case .pricePosition:
                if let price { return (ValuationEngine.scoreHistory(priceSeries: price), .pricePosition) }
                return ([], nil)
            }
        }.value
        history = computed.0
        usedMethod = computed.1
    }
}

// MARK: - 小组件

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(AppFont.sectionTitle)
            .foregroundStyle(Theme.textPrimary)
    }
}

/// 空态/说明性小段文字
struct ContentNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.s)
    }
}
