import SwiftUI

/// 总览：可见标的按市场分组成卡片，缓存优先 + 下拉刷新。
/// 顶部分布条既是「当前各档有几个标的」的事实陈述，也是五档色阶的图例。
/// 克制呈现估值：分数只表示「相对自身历史的位置」，不代表买卖建议。
struct ContentView: View {
    @Environment(MarketRepository.self) private var repository
    #if DEBUG
    // 调试入口：-debugInfo 启动时直接展开方法说明 sheet（用于模拟器截图验证）
    @State private var showInfo = ProcessInfo.processInfo.arguments.contains("-debugInfo")
    #else
    @State private var showInfo = false
    #endif

    private struct MarketGroup: Identifiable {
        let id: String
        let title: String
        let targets: [MarketTarget]
    }

    private static let groups: [MarketGroup] = [
        MarketGroup(id: "cn-index", title: "A股指数",
              targets: TargetCatalog.visible.filter { $0.market == .cn && $0.kind == .index }),
        MarketGroup(id: "cn-etf", title: "A股ETF",
              targets: TargetCatalog.visible.filter { $0.market == .cn && $0.kind == .etf }),
        MarketGroup(id: "hk", title: "港股",
              targets: TargetCatalog.visible.filter { $0.market == .hk }),
        MarketGroup(id: "us", title: "美股",
              targets: TargetCatalog.visible.filter { $0.market == .us }),
    ]

    /// 无网络且无缓存：刷新结束后仍全部无数据
    private var isEmptyState: Bool {
        !repository.isRefreshing && repository.snapshots.allSatisfy { $0.status == .noData }
    }

    /// 已评分标的在五档中的分布（只统计可见标的；隐藏底层指数不计入）
    private var zoneCounts: [ValuationZone: Int] {
        let visibleIDs = Set(TargetCatalog.visible.map(\.id))
        var counts: [ValuationZone: Int] = [:]
        for snap in repository.snapshots where visibleIDs.contains(snap.id) {
            if let zone = snap.result?.zone {
                counts[zone, default: 0] += 1
            }
        }
        return counts
    }

    #if DEBUG
    /// 调试：-debugDetail <targetID> 以该标的详情页为根（用于模拟器截图验证）
    private static var debugTarget: MarketTarget? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-debugDetail"), args.indices.contains(i + 1) else { return nil }
        return TargetCatalog.target(id: args[i + 1])
    }
    #endif

    var body: some View {
        NavigationStack {
            #if DEBUG
            if let target = Self.debugTarget {
                TargetDetailView(target: target)
            } else {
                rootContent
            }
            #else
            rootContent
            #endif
        }
        .tint(Theme.accent)
    }

    private var rootContent: some View {
        Group {
            if isEmptyState {
                VStack(spacing: 0) {
                    brandHeader
                        .padding(.horizontal, Spacing.m + Spacing.xs)
                        .padding(.top, Spacing.s)
                    emptyState
                }
            } else {
                overview
            }
        }
        .background(Theme.background)
        // 品牌标题由内容自行绘制（衬线大标题 + 副标题），因此隐藏系统导航栏，
        // 既统一了字体，也省下大标题区约 60pt 的空白。
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showInfo) {
            MethodologyView()
        }
        .navigationDestination(for: MarketTarget.self) { target in
            TargetDetailView(target: target)
        }
    }

    // MARK: 品牌头部

    private var brandHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("估值罗盘")
                    .font(AppFont.serif(31, .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(TargetCatalog.visible.count) 个标的相对自身近 10 年历史的估值分位")
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: Spacing.s)
            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("方法说明与免责声明")
            .padding(.top, 4)
        }
    }

    // MARK: 主体

    private var overview: some View {
        ScrollView {
            // Lazy：直接子节点是「头部 + 概览卡 + 4 个分组卡 + 页脚」，非惰性时首屏之外的
            // 分组卡（连同其中全部行）也要在首帧前布局并栅格化，实测拖长启动白屏。
            // 推迟的是首屏之下那 1–2 个分组，不是行级惰性。
            LazyVStack(alignment: .leading, spacing: Spacing.l) {
                brandHeader
                    .padding(.horizontal, Spacing.xs)
                    .padding(.bottom, -Spacing.s)
                summaryCard
                ForEach(Self.groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(group.title, trailing: "\(group.targets.count) 个")
                            .padding(.horizontal, Spacing.xs)
                        groupCard(group)
                    }
                }
                disclaimerFooter
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xl)
        }
        #if DEBUG
        // 调试：-debugBottom 直接滚到底部，便于截图验证下方分组与页脚
        .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-debugBottom") ? .bottom : .top)
        #endif
        .refreshable { await repository.refreshAll() }
    }

    private func groupCard(_ group: MarketGroup) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(group.targets.enumerated()), id: \.element.id) { index, target in
                NavigationLink(value: target) {
                    TargetRowView(
                        target: target,
                        snapshot: repository.snapshots.first { $0.id == target.id }
                            ?? TargetSnapshot(id: target.id)
                    )
                }
                .buttonStyle(CardRowButtonStyle())
                if index < group.targets.count - 1 {
                    CardDivider(inset: Spacing.m)
                }
            }
        }
        .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
        .cardBackground()
    }

    // MARK: 顶部概览（时间戳 + 五档分布）

    private var summaryCard: some View {
        Card(padding: Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("估值分位分布")
                Spacer()
                timestampLabel
            }
            if zoneCounts.isEmpty {
                ContentNote(text: repository.isRefreshing
                            ? "正在计算各标的估值分位…"
                            : "暂无可用评分，分布不可用。")
            } else {
                ZoneDistributionBar(counts: zoneCounts)
                Text("当前 \(zoneCounts.values.reduce(0, +)) 个标的按分位落在各档的数量。分布只描述各标的相对自身历史的位置，不是对市场整体的判断。")
                    .font(AppFont.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var timestampLabel: some View {
        HStack(spacing: 5) {
            if repository.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                Text("正在刷新")
            } else if let updated = repository.lastUpdatedAt {
                Text("更新于 \(Formatters.dateTime.string(from: updated))")
            } else {
                Text("数据尚未更新")
            }
        }
        .font(AppFont.footnote)
        .foregroundStyle(Theme.textTertiary)
    }

    // MARK: 页脚免责声明

    private var disclaimerFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Rectangle()
                .fill(Theme.divider)
                .frame(width: 28, height: 1)
            Text("本应用仅为信息与研究工具，不构成投资建议，不保证任何收益。估值分数反映当前水平相对自身历史的位置：分数低不代表应当买入，分数高不代表应当卖出。")
                .font(AppFont.footnote)
                .lineSpacing(3)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.xs)
        .padding(.horizontal, Spacing.xs)
    }

    // MARK: 空态（无网络 + 无缓存）

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无数据", systemImage: "wifi.exclamationmark")
        } description: {
            Text("无法连接网络，且本机暂无缓存数据。\n请检查网络连接后重试。")
        } actions: {
            Button("重试") {
                Task { await repository.refreshAll() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
    }
}

#Preview {
    ContentView()
        .environment(MarketRepository())
}
