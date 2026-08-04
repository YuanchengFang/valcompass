import SwiftUI

/// 总览行：左侧名称 + 数据状态，右侧最新值 + 评分（刻度 / 档位 / 分数）。
/// 右侧整块固定宽度，且刻度与分数各自定宽，因此各行的指针与数字对齐成一列，可以竖着扫。
/// 评分文案只陈述「相对历史的位置」，不含任何买卖暗示。
struct TargetRowView: View {
    let target: MarketTarget
    let snapshot: TargetSnapshot

    private var isLoading: Bool { snapshot.status == .loading }

    // 右侧评分区固定尺寸：刻度 50 + 档位名 43 + 分数 36 + 两个 5pt 间距 = 139。
    // 定宽是为了让 20 行的指针与分数对齐成一列；同时尽量给左侧日期留出余量，
    // 否则 ETF 的「市价 X | 净值 Y」会被截断。
    // 分数宽度按三位数上限「100」设定（20pt 衬线等宽数字实测约 35.5pt），避免折行。
    private let trackWidth: CGFloat = 50
    private let zoneLabelWidth: CGFloat = 43
    private let scoreWidth: CGFloat = 36

    var body: some View {
        HStack(spacing: Spacing.s) {
            // 用 maxWidth: .infinity 撑满剩余宽度（而不是靠 Spacer 挤），
            // 这样状态行才能拿到确定的可用宽度，minimumScaleFactor 才会生效；
            // 否则宽度不定，SwiftUI 会直接截断。
            VStack(alignment: .leading, spacing: 3) {
                Text(target.name)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                statusLine
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                Text(snapshot.latestValueText.isEmpty ? "—" : snapshot.latestValueText)
                    .font(AppFont.number(14.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                scoreLine
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary.opacity(0.55))
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 11)
        .contentShape(.rect)
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
            // ETF 的 asOfText 含市价与净值两个日期，靠 minimumScaleFactor 缩字即可放进一行。
            // 只有 QDII 会再追加「（QDII 滞后）」，一行装不下——那是最该让人看见的提示，
            // 不能截掉，因此单独允许它折成两行（其余 19 行仍是等高单行；
            // 注意 lineLimit(2) 会让 SwiftUI 优先折行而不再缩字，所以必须按标的区分）。
            Text(snapshot.asOfText.isEmpty ? target.kind.displayName : snapshot.asOfText)
                .font(AppFont.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(target.isQDII ? 2 : 1)
                .minimumScaleFactor(0.82)
        case .stale:
            statusLabel(snapshot.statusDetail.isEmpty ? "数据已过期" : snapshot.statusDetail,
                        icon: "clock.badge.exclamationmark", tint: Theme.statusWarning)
        case .refreshFailed:
            statusLabel("刷新失败，显示缓存",
                        icon: "arrow.triangle.2.circlepath", tint: Theme.statusWarning)
        case .noData:
            statusLabel(snapshot.statusDetail.isEmpty ? "暂无数据" : snapshot.statusDetail,
                        icon: "wifi.exclamationmark", tint: Theme.statusError)
        }
    }

    private func statusLabel(_ text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 3.5) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .lineLimit(1)
        }
        .font(AppFont.caption)
        .foregroundStyle(tint)
    }

    // MARK: 右下：评分（刻度 · 档位 · 分数，定宽对齐）

    @ViewBuilder
    private var scoreLine: some View {
        if let result = snapshot.result, let score = result.score, let zone = result.zone {
            HStack(spacing: 5) {
                RowScoreTrack(score: score, width: trackWidth)
                Text(zone.rawValue)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(width: zoneLabelWidth, alignment: .trailing)
                Text("\(Int(score.rounded()))")
                    .font(AppFont.scoreRow)
                    .foregroundStyle(Theme.zone(zone))
                    .lineLimit(1)
                    .frame(width: scoreWidth, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("估值评分")
            .accessibilityValue("\(Int(score.rounded())) 分，\(zone.rawValue)")
        } else {
            Text(snapshot.status == .loading ? "计算中" : "暂无评分")
                .font(AppFont.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(height: 26)
        }
    }
}
