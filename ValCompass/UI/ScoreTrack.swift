import SwiftUI

// MARK: - 评分刻度尺
// 本应用的标志性视觉元素：一条连续的 0–100 色阶，五档以硬边界分色，
// 指针（needle）标出当前分数。详情页用完整版（带档位名），列表行用窄版。
// 列表行的窄版固定宽度、右对齐，20 行的指针因此对齐成一列，可以竖着扫。

struct ScoreScaleView: View {
    let score: Double
    var height: CGFloat = 11
    var showsZoneLabels: Bool = true
    /// 图例场景（方法说明页）只展示色阶本身，不画指针，避免读成「当前分数」
    var showsNeedle: Bool = true
    @Environment(\.colorScheme) private var scheme

    private var clamped: Double { min(max(score, 0), 100) }
    /// 深色下低透明度会把五个色相压成同一种褐灰，需要更高的不透明度才分得开
    private var bandOpacity: Double { scheme == .dark ? 0.46 : 0.30 }

    var body: some View {
        VStack(spacing: Spacing.s) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    // 五档色阶
                    Capsule()
                        .fill(Theme.zoneBands(opacity: bandOpacity))
                    // 档位边界（20/40/60/80）
                    ForEach(1..<5, id: \.self) { i in
                        Rectangle()
                            .fill(Theme.background.opacity(0.6))
                            .frame(width: 1, height: height)
                            .offset(x: w * CGFloat(i) / 5)
                    }
                    if showsNeedle {
                        needle
                            .offset(x: clamped / 100 * max(0, w - needleWidth))
                    }
                }
                .frame(height: height)
            }
            .frame(height: height)

            if showsZoneLabels {
                HStack(spacing: 0) {
                    ForEach(ValuationZone.allCases, id: \.self) { zone in
                        Text(zone.rawValue)
                            .font(AppFont.footnote)
                            .foregroundStyle(
                                ValuationEngine.zone(for: clamped) == zone
                                    ? Theme.zone(zone)
                                    : Theme.textTertiary
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("估值评分")
        .accessibilityValue("\(Int(clamped.rounded())) 分，\(ValuationEngine.zone(for: clamped).rawValue)")
    }

    private var needleWidth: CGFloat { 8 }

    /// 指针：卡面色底衬在下、语义色在上。描边会向内吃掉宽度，
    /// 因此用「大一圈的底 + 小一圈的芯」而不是 strokeBorder。
    private var needle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: needleWidth / 2, style: .continuous)
                .fill(Theme.surface)
                .frame(width: needleWidth, height: height + 12)
                .shadow(color: .black.opacity(0.16), radius: 2, y: 0.5)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Theme.zone(forScore: clamped))
                .frame(width: 4.5, height: height + 7)
        }
    }
}

/// 列表行内的窄刻度：同一套五档色阶（更淡）+ 指针，固定尺寸以便跨行对齐。
struct RowScoreTrack: View {
    let score: Double
    var width: CGFloat = 56
    var height: CGFloat = 5
    @Environment(\.colorScheme) private var scheme

    private var clamped: Double { min(max(score, 0), 100) }
    private var bandOpacity: Double { scheme == .dark ? 0.42 : 0.26 }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.zoneBands(opacity: bandOpacity))
            // 指针：同详情页刻度，卡面色底衬 + 语义色芯，避免描边吃掉宽度
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.surface)
                    .frame(width: 6, height: height + 8)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.zone(forScore: clamped))
                    .frame(width: 3, height: height + 5)
            }
            .offset(x: clamped / 100 * max(0, width - 6))
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - 五档分布条
// 总览页顶部：可见标的当前落在各档的数量，按比例分段。
// 只陈述分布事实，不做整体判断；同时充当五档色阶的图例。

struct ZoneDistributionBar: View {
    /// 各档数量，顺序与 ValuationZone.allCases 一致
    let counts: [ValuationZone: Int]
    @Environment(\.colorScheme) private var scheme

    private var total: Int { counts.values.reduce(0, +) }
    private var segmentOpacity: Double { scheme == .dark ? 0.72 : 0.55 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            GeometryReader { geo in
                let gaps = CGFloat(max(0, nonEmpty.count - 1)) * 2
                let usable = max(0, geo.size.width - gaps)
                HStack(spacing: 2) {
                    ForEach(nonEmpty, id: \.self) { zone in
                        let n = counts[zone] ?? 0
                        let w = usable * CGFloat(n) / CGFloat(max(total, 1))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.zone(zone).opacity(segmentOpacity))
                            .frame(width: w)
                            .overlay {
                                if w >= 20 {
                                    Text("\(n)")
                                        .font(AppFont.number(10, weight: .semibold))
                                        .foregroundStyle(Theme.surface)
                                }
                            }
                    }
                }
            }
            .frame(height: 18)

            HStack {
                Text(ValuationZone.veryLow.rawValue)
                Spacer()
                Text(ValuationZone.veryHigh.rawValue)
            }
            .font(AppFont.footnote)
            .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("估值分布")
        .accessibilityValue(
            ValuationZone.allCases
                .map { "\($0.rawValue) \(counts[$0] ?? 0) 个" }
                .joined(separator: "，")
        )
    }

    private var nonEmpty: [ValuationZone] {
        ValuationZone.allCases.filter { (counts[$0] ?? 0) > 0 }
    }
}
