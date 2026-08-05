import SwiftUI

/// 详情页：估值卡片 / 溢折价 / 走势 / 估值变化 / 数据溯源 / 选择理由。
/// 每个维度一张卡：估值分数与 ETF 溢折价是两件事，因此分开成两张卡，不混在一起。
/// 历史序列缺失（如首次安装无网络）时，每个区块显示自己的空态，不造假数据。
struct TargetDetailView: View {
    let target: MarketTarget
    @Environment(MarketRepository.self) private var repository
    @State private var showMethodology = false

    private var snapshot: TargetSnapshot? {
        repository.snapshots.first { $0.id == target.id }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    header
                        .padding(.bottom, Spacing.xs)
                    if let snap = snapshot, let banner = statusBanner(for: snap) {
                        banner
                    }
                    valuationCard
                    secondaryMetricsCard
                    if target.kind == .etf {
                        premiumCard
                    }
                    priceSection
                    ScoreHistoryChartView(target: target)
                        .id("scoreChart")
                    provenanceCard
                    rationaleCard
                }
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.xl)
            }
            #if DEBUG
            // 调试：-debugCharts 滚动到估值变化图，便于截图验证
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-debugCharts") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        proxy.scrollTo("scoreChart", anchor: .top)
                    }
                }
            }
            #endif
        }
        .background(Theme.background)
        #if DEBUG
        // 调试：-debugBottom 直接滚到底部，便于截图验证下方区块
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-debugBottom") ? .bottom : .top)
        #endif
        .navigationTitle(target.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar {
            // 标题用衬线，与应用内其它标题统一（系统标题字体无法直接换 design）
            ToolbarItem(placement: .principal) {
                Text(target.name)
                    .font(AppFont.serif(17, .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMethodology = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("方法说明")
            }
        }
        .sheet(isPresented: $showMethodology) {
            MethodologyView()
        }
    }

    // MARK: 头部（纸面上，不入卡）

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(target.name)
                .font(AppFont.display)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                Tag(target.market.displayName)
                Tag(target.kind.displayName)
                Tag(target.currency.rawValue)
                if target.isQDII { Tag("QDII", tint: Theme.statusWarning) }
            }
            if let snap = snapshot {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snap.latestValueText.isEmpty ? "—" : snap.latestValueText)
                        .font(AppFont.number(27, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if !snap.asOfText.isEmpty {
                        Text(snap.asOfText)
                            .font(AppFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.xs)
    }

    // MARK: 状态横幅（过期 / 刷新失败 / 无数据，诚实标注）

    private func statusBanner(for snap: TargetSnapshot) -> AnyView? {
        switch snap.status {
        case .ok, .loading:
            return nil
        case .stale:
            return AnyView(StatusBanner(
                icon: "clock.badge.exclamationmark",
                text: "数据已过期：\(snap.statusDetail)。显示的是最近一次可用数据。"))
        case .refreshFailed:
            return AnyView(StatusBanner(
                icon: "arrow.triangle.2.circlepath",
                text: "本次刷新失败，当前显示缓存数据。"))
        case .noData:
            return AnyView(StatusBanner(
                icon: "wifi.exclamationmark",
                text: snap.statusDetail.isEmpty ? "暂无数据。" : "\(snap.statusDetail)。",
                tint: Theme.statusError))
        }
    }

    // MARK: 估值卡片

    private var valuationCard: some View {
        Card(spacing: 13) {
            if let result = snapshot?.result, let score = result.score, let zone = result.zone {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("估值分位")
                    Spacer()
                    ConfidencePill(confidence: result.confidence)
                }
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Text("\(Int(score.rounded()))")
                        .font(AppFont.scoreHero)
                        .foregroundStyle(Theme.zone(zone))
                    Text(zone.rawValue)
                        .font(AppFont.serif(21, .semibold))
                        .foregroundStyle(Theme.zone(zone))
                    Spacer()
                    Text("/ 100")
                        .font(AppFont.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.top, -Spacing.xs)
                ScoreScaleView(score: score)
                    .padding(.top, Spacing.xs)
                CardDivider()
                Text(result.note)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("评分方法")
                        .foregroundStyle(Theme.textTertiary)
                    Text(result.method.displayName)
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(AppFont.footnote)
                Disclaimer("分数衡量当前水平相对自身近 10 年历史的位置；分数低不代表应当买入，分数高不代表应当卖出。")
            } else {
                Eyebrow("估值分位")
                Text("暂无评分")
                    .font(AppFont.serif(24, .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(snapshot?.status == .loading
                     ? "数据加载中…"
                     : "数据不足，无法计算估值分数。应用不会用假设数据代替。")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 其他视角（辅助指标：ERP / CAPE / 股息率，不并入主分数）

    @ViewBuilder
    private var secondaryMetricsCard: some View {
        if let metrics = snapshot?.secondaryMetrics, !metrics.isEmpty {
            Card(spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("其他视角")
                    Spacer()
                    Text("不并入主分数")
                        .font(AppFont.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                    if index > 0 { CardDivider() }
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(metric.name)
                                .font(AppFont.body)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(metric.valueText)
                                .font(AppFont.serifNumber(19))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        HStack(spacing: 6) {
                            Text("分位 \(Int(metric.percentile.rounded())) / 100")
                                .foregroundStyle(Theme.textSecondary)
                            Text("·")
                                .foregroundStyle(Theme.textTertiary)
                            Text("百分位\(metric.direction.rawValue)")
                                .foregroundStyle(metric.direction == .higherCheaper
                                                 ? Theme.zone(.low) : Theme.zone(.high))
                            Spacer()
                            Text("截至 \(metric.asOf)")
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .font(AppFont.footnote)
                        Text(metric.note)
                            .font(AppFont.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Disclaimer("辅助指标从不同角度观察估值，方向可能与主分数相反（如 ERP、股息率是分位越高越便宜）；均不构成买卖信号。")
            }
        }
    }

    // MARK: 溢折价（ETF 独立成卡：与底层估值是两个维度）

    @ViewBuilder
    private var premiumCard: some View {
        if let snap = snapshot, !snap.premiumText.isEmpty {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    CardTitle("溢折价")
                    Spacer()
                    if let premium = snap.premium {
                        Text(Formatters.percent(premium))
                            .font(AppFont.serifNumber(22))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                VStack(spacing: 9) {
                    if let bar = repository.priceSeries(for: target.id)?.bars.last {
                        KeyValueRow(label: "市价",
                                    value: "\(String(format: "%.3f", bar.close)) \(target.currency.rawValue)",
                                    note: bar.date)
                    }
                    if let nav = repository.navSeries(for: target.id)?.points.last {
                        KeyValueRow(label: "单位净值",
                                    value: "\(String(format: "%.4f", nav.unitNav)) \(target.currency.rawValue)",
                                    note: nav.date)
                    }
                }
                Text(snap.premiumText)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Disclaimer("ETF 溢折价反映交易价格相对净值的偏离，与底层资产的估值分数是两个不同维度。")
            }
        }
    }

    // MARK: 走势图（含空态）

    @ViewBuilder
    private var priceSection: some View {
        if let priceS = repository.priceSeries(for: target.id), !priceS.bars.isEmpty {
            PriceChartView(target: target,
                           priceSeries: priceS,
                           navSeries: repository.navSeries(for: target.id))
        } else if !repository.hasLoadedSeries {
            // 序列还在后台读盘（列表由摘要缓存点亮，因此这里可能比数据先到）。
            // 此时不能说「暂无数据」——那是一句几百毫秒后就被推翻的话。
            Card {
                CardTitle(target.kind == .etf ? "市价走势" : "点位走势")
                LoadingNote(text: "正在读取历史数据…")
            }
        } else {
            Card {
                CardTitle(target.kind == .etf ? "市价走势" : "点位走势")
                ContentNote(text: "暂无行情历史数据。首次使用且无网络时，历史数据不可用；联网刷新后自动出现。")
            }
        }
    }

    // MARK: 数据溯源

    /// 逐条收集数据源记录（辅助数据源只在有辅助指标时出现），卡片内统一渲染
    private var provenanceRows: [(title: String, meta: SeriesMeta, asOf: String?)] {
        var rows: [(title: String, meta: SeriesMeta, asOf: String?)] = []
        if let priceS = repository.priceSeries(for: target.id) {
            rows.append((target.kind == .etf ? "市价（日线）" : "点位（日线）", priceS.meta, priceS.asOfDate))
        }
        if let peS = repository.peSeries(for: target.underlyingTargetID ?? target.id) {
            rows.append(("市盈率（PE）", peS.meta, peS.asOfDate))
        }
        if let navS = repository.navSeries(for: target.id) {
            rows.append(("基金单位净值", navS.meta, navS.asOfDate))
        }
        let metrics = snapshot?.secondaryMetrics ?? []
        if metrics.contains(where: { $0.name.contains("ERP") }), let yields = repository.yieldSeries() {
            let which = target.market == .us || target.underlyingTargetID == "spx" ? "美国" : "中国"
            rows.append(("10年期国债收益率（\(which)）", yields.meta, yields.asOfDate))
        }
        if metrics.contains(where: { $0.name.contains("CAPE") }), let shiller = repository.spxShillerPE() {
            rows.append(("Shiller PE", shiller.meta, shiller.asOfDate))
        }
        if metrics.contains(where: { $0.name.contains("股息率") }), let div = repository.spxDividendYield() {
            rows.append(("标普500 股息率", div.meta, div.asOfDate))
        }
        return rows
    }

    private var provenanceCard: some View {
        Card {
            CardTitle("数据溯源")
            let rows = provenanceRows
            if rows.isEmpty, !repository.hasLoadedSeries {
                LoadingNote(text: "正在读取数据源记录…")
            } else if rows.isEmpty {
                ContentNote(text: "暂无已抓取的数据源记录。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        provenanceRow(title: row.title, meta: row.meta, asOf: row.asOf,
                                      isLast: index == rows.count - 1)
                    }
                }
            }
        }
    }

    private func provenanceRow(title: String, meta: SeriesMeta, asOf: String?, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(meta.source.displayName)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.accent)
            }
            Text("数据截至 \(asOf ?? "未知") · 抓取于 \(Formatters.dateTime.string(from: meta.fetchedAt))")
                .font(AppFont.footnote)
                .foregroundStyle(Theme.textTertiary)
            if meta.isMonthly || meta.isDelayed {
                HStack(spacing: 6) {
                    if meta.isMonthly { Tag("月度数据") }
                    if meta.isDelayed { Tag("延迟数据") }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !isLast { CardDivider() }
        }
    }

    // MARK: 选择理由

    private var rationaleCard: some View {
        Card {
            CardTitle("为什么跟踪它")
            Text(target.rationale)
                .font(AppFont.body)
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            CardDivider()
            Button {
                showMethodology = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book")
                        .font(.system(size: 11))
                    Text("名单选择标准与方法说明")
                        .font(AppFont.caption)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }
}
