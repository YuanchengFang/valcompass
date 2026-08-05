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

/// 估值变化图的跨度（历史序列可能跨百年，比走势图的窗口更大）
enum ScoreChartRange: String, CaseIterable, Identifiable {
    case tenYears = "10年"
    case thirtyYears = "30年"
    case all = "全部"
    var id: String { rawValue }
    var years: Int? {
        switch self {
        case .tenYears: return 10
        case .thirtyYears: return 30
        case .all: return nil
        }
    }
}

extension View {
    /// 图表拖动游标：在 plot 区拖动时把 x 位置换算成日期写入 binding，松手清空。
    /// 两张图共用同一套手势语言。
    func chartDateCursor(_ selected: Binding<Date?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let x = value.location.x - geo[plotFrame].origin.x
                                guard x >= 0, x <= geo[plotFrame].width else { return }
                                if let date: Date = proxy.value(atX: x) {
                                    selected.wrappedValue = date
                                }
                            }
                            .onEnded { _ in selected.wrappedValue = nil }
                    )
            }
        }
    }
}

struct PriceChartView: View {
    let target: MarketTarget
    let priceSeries: PriceSeries
    let navSeries: FundNavSeries?   // 仅 ETF：叠加单位净值（虚线 + 图例）

    @State private var range: ChartRange = .threeYears
    @State private var selectedDate: Date?

    private struct Point: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let series: String
    }

    /// 游标命中：取该系列中离触摸日期最近的点
    private func nearest(to date: Date, series: String, in pts: [Point]) -> Point? {
        pts.filter { $0.series == series }
            .min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    /// 读数数值格式：ETF 市价/净值需要 3 位小数，指数点位 1 位足够
    private func formatValue(_ v: Double) -> String {
        v < 20 ? String(format: "%.3f", v) : String(format: "%.1f", v)
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

    /// 游标读数行：选中时显示「日期 · 市价 X · 净值 Y」，未选中时给手势提示。
    /// 固定高度，避免拖动时卡片上下跳动。
    private func readoutRow(selPrice: Point?, selNav: Point?) -> some View {
        Group {
            if let selPrice {
                HStack(spacing: 6) {
                    Text(selPrice.date.formatted(.dateTime.year().month().day()))
                    Text("\(priceLabel) \(formatValue(selPrice.value))")
                        .foregroundStyle(Theme.textPrimary)
                    if let selNav {
                        Text("· \(Self.navLabel) \(formatValue(selNav.value))")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            } else {
                Text("拖动图表查看任一时点数值")
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .font(AppFont.footnote)
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 15)
    }

    var body: some View {
        let pts = points
        let bounds = yBounds(pts)
        let selPrice = selectedDate.flatMap { nearest(to: $0, series: priceLabel, in: pts) }
        let selNav = selectedDate.flatMap { nearest(to: $0, series: Self.navLabel, in: pts) }
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
            readoutRow(selPrice: selPrice, selNav: selNav)

            Chart {
                ForEach(pts) { p in
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
                // 游标：细竖线 + 命中点高亮（不进入系列色标，避免污染图例）
                if let selPrice {
                    RuleMark(x: .value("选中", selPrice.date))
                        .foregroundStyle(Theme.divider)
                        .lineStyle(StrokeStyle(lineWidth: 0.5))
                    PointMark(x: .value("选中", selPrice.date), y: .value("选中值", selPrice.value))
                        .symbolSize(40)
                        .foregroundStyle(Theme.priceLine)
                    if let selNav {
                        PointMark(x: .value("选中", selNav.date), y: .value("选中净值", selNav.value))
                            .symbolSize(40)
                            .foregroundStyle(Theme.navLine)
                    }
                }
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
            .chartDateCursor($selectedDate)
            .sensoryFeedback(.selection, trigger: selPrice?.id)
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
    @State private var range: ScoreChartRange = .tenYears
    @State private var selectedDate: Date?

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

    /// 游标命中：离触摸日期最近的采样点
    private var selectedPoint: Point? {
        guard let selectedDate else { return nil }
        return chartPoints.min(by: {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        })
    }

    // MARK: 跨度选择

    /// 评分来源序列的完整跨度（年）。与 compute() 的取数顺序一致：法A 优先 PE，回退价格。
    private var fullSpanYears: Int? {
        let dates: [String]
        if target.method == .fundamentals, let pe = repository.peSeries(for: sourceID) {
            dates = pe.points.map(\.date)
        } else if let price = repository.priceSeries(for: sourceID) {
            dates = price.bars.map(\.date)
        } else if let pe = repository.peSeries(for: sourceID) {
            dates = pe.points.map(\.date)
        } else {
            return nil
        }
        guard let first = dates.first.flatMap(DateUtil.date),
              let last = dates.last.flatMap(DateUtil.date) else { return nil }
        return Calendar.current.dateComponents([.year], from: first, to: last).year
    }

    /// 可选跨度按数据跨度自适应；只有一档时不显示选择器（不制造无用 UI）
    private var availableRanges: [ScoreChartRange] {
        guard let span = fullSpanYears else { return [.all] }
        if span > 30 { return ScoreChartRange.allCases }
        if span > 10 { return [.tenYears, .all] }
        return [.all]
    }

    /// 兜底：数据跨度装不下所选窗口时回退「全部」
    private var effectiveRange: ScoreChartRange {
        availableRanges.contains(range) ? range : .all
    }

    /// 横轴年份格式随当前窗口切换：≤3 年带月份；>90 年（如标普500「全部」档，
    /// PE 自 19 世纪起）两位年份会撞名（1890 与 1990 都是「90年」），用四位年份。
    private var xAxisYearFormat: Date.FormatStyle {
        guard let first = chartPoints.first?.date, let last = chartPoints.last?.date,
              let span = Calendar.current.dateComponents([.year], from: first, to: last).year else {
            return .dateTime.year(.twoDigits)
        }
        if span > 90 { return .dateTime.year() }
        if span <= 3 { return .dateTime.year(.twoDigits).month(.twoDigits) }
        return .dateTime.year(.twoDigits)
    }

    /// 读数日期格式：PE 月度数据到月，价格位置日度数据到日
    private var readoutDateFormat: Date.FormatStyle {
        usedMethod == .pricePosition ? .dateTime.year().month().day() : .dateTime.year().month()
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
            if availableRanges.count > 1 {
                SegmentedSelector(options: availableRanges, selection: $range) { $0.rawValue }
            }
            if history != nil, !chartPoints.isEmpty {
                readoutRow
                chart
                Disclaimer(captionText)
            } else if history != nil, repository.hasLoadedSeries {
                // 只有序列确实读完了、算出来还是空，才能说「数据不足」。
                // 少了 hasLoadedSeries 这个条件，读盘那几百毫秒里 compute() 拿到
                // 空序列会把 history 置成 []，于是断言一件随后就被推翻的事。
                ContentNote(text: "历史数据不足，无法绘制评分曲线。")
            } else {
                LoadingNote(text: repository.hasLoadedSeries ? "正在后台计算历史评分…" : "正在读取历史数据…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.l)
            }
        }
        .task(id: "\(dataToken)|\(effectiveRange.rawValue)") {
            await compute()
        }
        .onChange(of: range) { selectedDate = nil }
    }

    /// 游标读数行：选中时显示「日期 · 分数 档位」，未选中时给所选窗口的极值摘要。
    /// 固定高度，避免拖动时卡片上下跳动。
    @ViewBuilder
    private var readoutRow: some View {
        Group {
            if let sel = selectedPoint {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(sel.date.formatted(readoutDateFormat))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(Int(sel.score.rounded()))")
                        .font(AppFont.serifNumber(13))
                        .foregroundStyle(Theme.zone(forScore: sel.score))
                    Text(ValuationEngine.zone(for: sel.score).rawValue)
                        .foregroundStyle(Theme.zone(forScore: sel.score))
                }
            } else if let hi = chartPoints.max(by: { $0.score < $1.score }),
                      let lo = chartPoints.min(by: { $0.score < $1.score }) {
                Text("区间内 最高 \(Int(hi.score.rounded()))（\(hi.date.formatted(.dateTime.year()))）· 最低 \(Int(lo.score.rounded()))（\(lo.date.formatted(.dateTime.year()))）")
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .font(AppFont.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 15)
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
            // 游标：细竖线 + 命中点高亮
            if let sel = selectedPoint {
                RuleMark(x: .value("选中", sel.date))
                    .foregroundStyle(Theme.divider)
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                PointMark(x: .value("选中", sel.date), y: .value("选中评分", sel.score))
                    .symbolSize(46)
                    .foregroundStyle(Theme.zone(forScore: sel.score))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.7))
                AxisValueLabel(format: xAxisYearFormat)
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
        .chartDateCursor($selectedDate)
        .sensoryFeedback(.selection, trigger: selectedPoint?.id)
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
        let years = effectiveRange.years
        // 以序列末点为基准回推窗口起点；评估仍基于全量序列，分数与「全部」档一致
        func since(_ lastDateString: String?) -> Date? {
            guard let years, let lastDateString, let end = DateUtil.date(lastDateString) else { return nil }
            return Calendar.current.date(byAdding: .year, value: -years, to: end)
        }
        let computed: ([ScoreHistoryPoint], ValuationMethod?) = await Task.detached(priority: .userInitiated) {
            switch method {
            case .fundamentals:
                if let pe { return (ValuationEngine.scoreHistory(peSeries: pe, since: since(pe.points.last?.date)), .fundamentals) }
                if let price { return (ValuationEngine.scoreHistory(priceSeries: price, since: since(price.bars.last?.date)), .pricePosition) }
                return ([], nil)
            case .pricePosition:
                if let price { return (ValuationEngine.scoreHistory(priceSeries: price, since: since(price.bars.last?.date)), .pricePosition) }
                return ([], nil)
            }
        }.value
        history = computed.0
        usedMethod = computed.1
    }
}
