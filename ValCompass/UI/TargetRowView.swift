import SwiftUI

/// 总览行：名称 + 数据状态 / 最新值 + 评分刻度与区间结论。
/// 评分文案只陈述「相对历史的位置」，不含任何买卖暗示。
struct TargetRowView: View {
    let target: MarketTarget
    let snapshot: TargetSnapshot

    private var isLoading: Bool { snapshot.status == .loading }

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.name)
                    .font(AppFont.heading)
                    .foregroundStyle(Theme.textPrimary)
                statusLine
            }
            Spacer(minLength: Spacing.s)
            VStack(alignment: .trailing, spacing: 4) {
                Text(snapshot.latestValueText.isEmpty ? "—" : snapshot.latestValueText)
                    .font(AppFont.number(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                scoreLine
            }
        }
        .padding(.vertical, 6)
        .redacted(reason: isLoading ? .placeholder : [])
    }

    // MARK: 左下：数据状态（诚实标注，不静默）

    @ViewBuilder
    private var statusLine: some View {
        switch snapshot.status {
        case .loading:
            Text("加载中…")
                .font(AppFont.caption)
                .foregroundStyle(Theme.textTertiary)
        case .ok:
            Text(snapshot.asOfText.isEmpty ? target.kind.displayName : snapshot.asOfText)
                .font(AppFont.caption)
                .foregroundStyle(Theme.textSecondary)
        case .stale:
            Label(snapshot.statusDetail.isEmpty ? "数据已过期" : snapshot.statusDetail, systemImage: "clock.exclamationmark")
                .font(AppFont.caption)
                .foregroundStyle(Theme.statusWarning)
        case .refreshFailed:
            Label("刷新失败，显示缓存", systemImage: "arrow.triangle.2.circlepath.circle")
                .font(AppFont.caption)
                .foregroundStyle(Theme.statusWarning)
        case .noData:
            Label(snapshot.statusDetail.isEmpty ? "暂无数据" : snapshot.statusDetail, systemImage: "wifi.exclamationmark")
                .font(AppFont.caption)
                .foregroundStyle(Theme.statusError)
        }
    }

    // MARK: 右下：评分（区间结论 · 分数 + 迷你刻度）

    @ViewBuilder
    private var scoreLine: some View {
        if let result = snapshot.result, let score = result.score, let zone = result.zone {
            HStack(spacing: 6) {
                MiniScoreTrack(score: score)
                Text("\(zone.rawValue) · \(Int(score.rounded()))")
                    .font(AppFont.caption)
                    .foregroundStyle(Theme.zone(zone))
            }
        } else {
            Text(snapshot.status == .loading ? "计算中" : "暂无评分")
                .font(AppFont.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}
