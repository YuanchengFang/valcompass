import SwiftUI

/// 详情页：估值卡片 / 走势 / 估值变化 / 数据溯源 / 选择理由。
/// 历史序列缺失（如首次安装无网络）时，每个区块显示自己的空态，不造假数据。
struct TargetDetailView: View {
    let target: MarketTarget
    @Environment(MarketRepository.self) private var repository
    @State private var showMethodology = false

    private var snapshot: TargetSnapshot? {
        repository.snapshots.first { $0.id == target.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                if let banner = statusBanner {
                    banner
                }
                valuationCard
                priceSection
                ScoreHistoryChartView(target: target)
                provenanceSection
                rationaleSection
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.xl)
        }
        .background(Theme.background)
        #if DEBUG
        // 调试：-debugBottom 直接滚到底部，便于截图验证下方区块
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-debugBottom") ? .bottom : .top)
        #endif
        .navigationTitle(target.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMethodology = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("方法说明")
            }
        }
        .sheet(isPresented: $showMethodology) {
            MethodologyView()
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(target.name)
                .font(AppFont.display)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: Spacing.s) {
                Tag(target.market.displayName)
                Tag(target.kind.displayName)
                Tag(target.currency.rawValue)
                if target.isQDII { Tag("QDII") }
            }
            if let snap = snapshot {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.latestValueText.isEmpty ? "—" : snap.latestValueText)
                        .font(AppFont.number(26, weight: .semibold))
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
    }

    // MARK: 状态横幅（过期 / 刷新失败 / 无数据，诚实标注）

    private var statusBanner: AnyView? {
        guard let snap = snapshot else { return nil }
        let (icon, text): (String, String)
        switch snap.status {
        case .ok, .loading:
            return nil
        case .stale:
            (icon, text) = ("clock.exclamationmark", "数据已过期：\(snap.statusDetail)。显示的是最近一次可用数据。")
        case .refreshFailed:
            (icon, text) = ("arrow.triangle.2.circlepath.circle", "本次刷新失败，当前显示缓存数据。")
        case .noData:
            (icon, text) = ("wifi.exclamationmark", snap.statusDetail.isEmpty ? "暂无数据。" : "\(snap.statusDetail)。")
        }
        return AnyView(
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: icon)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(AppFont.caption)
            .foregroundStyle(Theme.statusWarning)
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.statusWarning.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
        )
    }

    // MARK: 估值卡片

    private var valuationCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let result = snapshot?.result, let score = result.score, let zone = result.zone {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(score.rounded()))")
                        .font(AppFont.scoreBig)
                        .foregroundStyle(Theme.zone(zone))
                    Text(zone.rawValue)
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(Theme.zone(zone))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("置信度 \(result.confidence.rawValue)")
                        Text(result.method.displayName)
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                ScoreTrackView(score: score)
                HStack {
                    zoneTick("低")
                    Spacer()
                    zoneTick("合理")
                    Spacer()
                    zoneTick("高")
                }
                Text(result.note)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("分数衡量当前水平相对自身近10年历史的位置；分数低不代表应当买入，分数高不代表应当卖出。")
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if target.kind == .etf {
                    premiumBlock
                }
            } else {
                Text("暂无评分")
                    .font(AppFont.heading)
                    .foregroundStyle(Theme.textSecondary)
                Text(snapshot?.status == .loading
                     ? "数据加载中…"
                     : "数据不足，无法计算估值分数。应用不会用假设数据代替。")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.m)
        .background(Theme.surface, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 0.5)
        )
    }

    private func zoneTick(_ text: String) -> some View {
        Text(text)
            .font(AppFont.footnote)
            .foregroundStyle(Theme.textTertiary)
    }

    /// ETF 溢折价：市价 vs 单位净值（各自日期），QDII 滞后提示在 premiumText 内
    @ViewBuilder
    private var premiumBlock: some View {
        if let snap = snapshot, !snap.premiumText.isEmpty {
            Divider().overlay(Theme.divider)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("溢折价")
                    .font(AppFont.heading)
                    .foregroundStyle(Theme.textPrimary)
                if let priceS = repository.priceSeries(for: target.id)?.bars.last {
                    premiumRow("市价", value: String(format: "%.3f", priceS.close), date: priceS.date)
                }
                if let nav = repository.navSeries(for: target.id)?.points.last {
                    premiumRow("单位净值", value: String(format: "%.4f", nav.unitNav), date: nav.date)
                }
                if let premium = snap.premium {
                    HStack {
                        Text("溢折价率")
                            .font(AppFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(Formatters.percent(premium))
                            .font(AppFont.number(13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                Text(snap.premiumText)
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("ETF 溢折价反映交易价格相对净值的偏离，与底层资产的估值分数是两个不同维度。")
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func premiumRow(_ label: String, value: String, date: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("\(value) \(target.currency.rawValue)")
                .font(AppFont.number(13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(date)
                .font(AppFont.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: 走势图（含空态）

    @ViewBuilder
    private var priceSection: some View {
        if let priceS = repository.priceSeries(for: target.id), !priceS.bars.isEmpty {
            PriceChartView(target: target, priceSeries: priceS, navSeries: repository.navSeries(for: target.id))
        } else {
            VStack(alignment: .leading, spacing: Spacing.m) {
                SectionTitle(target.kind == .etf ? "市价走势" : "点位走势")
                ContentNote(text: "暂无行情历史数据。首次使用且无网络时，历史数据不可用；联网刷新后自动出现。")
            }
        }
    }

    // MARK: 数据溯源

    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionTitle("数据溯源")
            VStack(spacing: 0) {
                if let priceS = repository.priceSeries(for: target.id) {
                    provenanceRow(
                        title: target.kind == .etf ? "市价（日线）" : "点位（日线）",
                        meta: priceS.meta,
                        asOf: priceS.asOfDate
                    )
                }
                if let peS = repository.peSeries(for: target.underlyingTargetID ?? target.id) {
                    provenanceRow(title: "市盈率（PE）", meta: peS.meta, asOf: peS.asOfDate)
                }
                if let navS = repository.navSeries(for: target.id) {
                    provenanceRow(title: "基金单位净值", meta: navS.meta, asOf: navS.asOfDate)
                }
                if repository.priceSeries(for: target.id) == nil,
                   repository.peSeries(for: target.underlyingTargetID ?? target.id) == nil,
                   repository.navSeries(for: target.id) == nil {
                    ContentNote(text: "暂无已抓取的数据源记录。")
                }
            }
        }
    }

    private func provenanceRow(title: String, meta: SeriesMeta, asOf: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(AppFont.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(meta.source.displayName)
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: Spacing.s) {
                Text("数据截至 \(asOf ?? "未知")")
                Text("·")
                Text("抓取于 \(Formatters.dateTime.string(from: meta.fetchedAt))")
            }
            .font(AppFont.footnote)
            .foregroundStyle(Theme.textTertiary)
            if meta.isMonthly || meta.isDelayed {
                HStack(spacing: Spacing.s) {
                    if meta.isMonthly { Tag("月度数据") }
                    if meta.isDelayed { Tag("延迟数据") }
                }
            }
            Divider().overlay(Theme.divider).padding(.top, Spacing.s)
        }
        .padding(.vertical, Spacing.s)
    }

    // MARK: 选择理由

    private var rationaleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionTitle("为什么跟踪它")
            Text(target.rationale)
                .font(AppFont.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showMethodology = true
            } label: {
                Label("名单选择标准与方法说明", systemImage: "book")
                    .font(AppFont.caption)
            }
            .tint(Theme.accent)
        }
    }
}

/// 小标签（市场 / 类型 / 币种 / 数据标记）
struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(AppFont.footnote)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.surfaceMuted, in: .capsule)
    }
}
