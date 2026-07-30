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

    /// 区间涨跌幅（仅陈述所选窗口内的价格变化，不含任何判断）
    private func rangeChange(_ pts: [Point]) -> Double? {
        let series = pts.filter { $0.series == priceLabel }
        guard let first = series.first?.value, let last = series.last?.value, first > 0 else { return nil }
        return last / first - 1
    }

    /// 显式 y 轴范围：AreaMark 的默认基线是 0，会把 y 轴一路拉到零点、
    /// 使曲线挤在顶部（`includesZero: false` 管不住它）。因此这里自己算上下界，
    /// 并让面积图以下界为基线。
    private func yBounds(_ pts: [Point]) -> (lower: Double, upper: Double)? {
        let values = pts.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        guard hi > lo else { return (lo * 0.98, hi * 1.02) }
        let pad = (hi - lo) * 0.08
        return (lo - pad, hi + pad)
    }

    var body: some View {
        let pts = points
        let bounds = yBounds(pts)
        return Card {
            HStack(alignment: .firstTextBaseline) {
                CardTitle(target.kind == .etf ? "市价走势" : "点位走势")
                Text(target.currency.rawValue)
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if let change = rangeChange(pts) {
                    Text("\(range.rawValue) \(Formatters.percent(change))")
                        .font(AppFont.number(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            SegmentedSelector(options: ChartRange.allCases, selection: $range) { $0.rawValue }

            Chart(pts) { p in
                if p.series == priceLabel, let bounds {
                    AreaMark(
                        x: .value("日期", p.date),
                        yStart: .value("下界", bounds.lower),
                        yEnd: .value(priceLabel, p.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.priceLine.opacity(0.16), Theme.priceLine.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.linear)
                }
                LineMark(
                    x: .value("日期", p.date),
                    y: .value(priceLabel, p.value)
                )
                .foregroundStyle(by: .value("系列", p.series))
                .lineStyle(StrokeStyle(lineWidth: p.series == Self.navLabel ? 1.1 : 1.5,
                                       lineCap: .round,
                                       dash: p.series == Self.navLabel ? [4, 3] : []))
                .interpolationMethod(.linear)
            }
            .chartForegroundStyleScale([
                priceLabel: Theme.priceLine,
                Self.navLabel: Theme.navLine,
            ])
            .chartLegend(hasNav ? .visible : .hidden)
            .chartLegend(position: .bottom, alignment: .leading, spacing: Spacing.s)
            .chartYScale(domain: bounds.map { $0.lower...$0.upper } ?? 0...1)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel(format: .dateTime.year(.twoDigits).month(.twoDigits))
                        .font(AppFont.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel()
                        .font(AppFont.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 208)
            .padding(.top, Spacing.xs)

            if hasNav {
                Disclaimer("虚线为单位净值，与市价分属不同口径；二者之差即溢折价。")
            }
        }
    }
}

// MARK: - 估值变化
// 对历史序列逐点以 asOf 口径重算评分（后台线程），画评分随时间的曲线。
// 背景铺五档参考带，与刻度尺同一套语义色：一眼看出历史上何时处在哪一档。

struct ScoreHistoryChartView: View {
    let target: MarketTarget
    @Environment(MarketRepository.self) private var repository
    @Environment(\.colorScheme) private var scheme
    @State private var history: [ScoreHistoryPoint]?
    @State private var usedMethod: ValuationMethod?

    /// 参考带在深色下需要更高不透明度才看得出色相
    private var bandOpacity: Double { scheme == .dark ? 0.14 : 0.07 }

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
        Card {
            HStack(alignment: .firstTextBaseline) {
                CardTitle("估值变化")
                Spacer()
                if let last = chartPoints.last {
                    Text("当前 \(Int(last.score.rounded()))")
                        .font(AppFont.number(12, weight: .medium))
                        .foregroundStyle(Theme.zone(forScore: last.score))
                }
            }
            if history != nil, !chartPoints.isEmpty {
                chart
                Disclaimer(captionText)
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

    private var chart: some View {
        Chart {
            // 五档参考带：与刻度尺共用语义色，极低透明度，不与曲线争夺注意力
            ForEach(Array(ValuationZone.allCases.enumerated()), id: \.element) { i, zone in
                RectangleMark(
                    yStart: .value("下界", i * 20),
                    yEnd: .value("上界", (i + 1) * 20)
                )
                .foregroundStyle(Theme.zone(zone).opacity(bandOpacity))
            }
            ForEach(chartPoints) { p in
                AreaMark(x: .value("日期", p.date), y: .value("评分", p.score))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.14), Theme.accent.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                LineMark(x: .value("日期", p.date), y: .value("评分", p.score))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = chartPoints.last {
                PointMark(x: .value("日期", last.date), y: .value("评分", last.score))
                    .symbolSize(46)
                    .foregroundStyle(Theme.zone(forScore: last.score))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.7))
                AxisValueLabel(format: .dateTime.year(.twoDigits))
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 20, 40, 60, 80, 100]) {
                AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.7))
                AxisValueLabel()
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: 186)
    }

    private var captionText: String {
        let method = usedMethod == .pricePosition ? "价格位置分位" : "PE 分位"
        return "每个采样点按当时可得的历史窗口重算评分（\(method)），曲线左端窗口较短、波动偏大属正常。背景色带为五档区间。评分只描述相对历史的位置。"
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
