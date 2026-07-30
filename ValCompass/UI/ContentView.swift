import SwiftUI

/// 总览：20 个标的按市场分组，缓存优先 + 下拉刷新。
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
              targets: TargetCatalog.all.filter { $0.market == .cn && $0.kind == .index }),
        MarketGroup(id: "cn-etf", title: "A股ETF",
              targets: TargetCatalog.all.filter { $0.market == .cn && $0.kind == .etf }),
        MarketGroup(id: "hk", title: "港股",
              targets: TargetCatalog.all.filter { $0.market == .hk }),
        MarketGroup(id: "us", title: "美股",
              targets: TargetCatalog.all.filter { $0.market == .us }),
    ]

    /// 无网络且无缓存：刷新结束后仍全部无数据
    private var isEmptyState: Bool {
        !repository.isRefreshing && repository.snapshots.allSatisfy { $0.status == .noData }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmptyState {
                    emptyState
                } else {
                    overviewList
                }
            }
            .background(Theme.background)
            .navigationTitle("估值罗盘")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("方法说明与免责声明")
                }
            }
            .sheet(isPresented: $showInfo) {
                MethodologyView()
            }
            .navigationDestination(for: MarketTarget.self) { target in
                TargetDetailView(target: target)
            }
        }
        .tint(Theme.accent)
    }

    // MARK: 列表

    private var overviewList: some View {
        List {
            timestampHeader
            ForEach(Self.groups) { group in
                Section {
                    ForEach(group.targets) { target in
                        NavigationLink(value: target) {
                            TargetRowView(
                                target: target,
                                snapshot: repository.snapshots.first { $0.id == target.id }
                                    ?? TargetSnapshot(id: target.id)
                            )
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .textCase(nil)
                        .padding(.bottom, 2)
                }
            }
            disclaimerFooter
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await repository.refreshAll() }
    }

    private var timestampHeader: some View {
        HStack(spacing: 6) {
            if repository.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                Text("正在刷新数据…")
            } else if let updated = repository.lastUpdatedAt {
                Text("数据更新于 \(Formatters.dateTime.string(from: updated))")
            } else {
                Text("数据尚未更新")
            }
        }
        .font(AppFont.caption)
        .foregroundStyle(Theme.textTertiary)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: Spacing.m, bottom: 0, trailing: Spacing.m))
    }

    private var disclaimerFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Divider().overlay(Theme.divider)
            Text("本应用仅为信息与研究工具，不构成投资建议，不保证任何收益。估值分数反映当前水平相对自身历史的位置：分数低不代表应当买入，分数高不代表应当卖出。")
                .font(AppFont.footnote)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.s)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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
