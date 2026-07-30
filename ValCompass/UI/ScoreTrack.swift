import SwiftUI

// MARK: - 评分刻度尺
// 五档区间以低饱和色段呈现，圆点标记当前分数。
// 总览行用迷你版（mini），详情页用完整版——这是本应用的标志性视觉元素。

struct ScoreTrackView: View {
    let score: Double
    var height: CGFloat = 6

    private let zones = ValuationZone.allCases

    var body: some View {
        GeometryReader { geo in
            let markerSize = height + 8
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(zones, id: \.self) { zone in
                        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                            .fill(Theme.zone(zone).opacity(0.22))
                    }
                }
                .frame(height: height)
                Circle()
                    .fill(Theme.zone(forScore: score))
                    .frame(width: markerSize, height: markerSize)
                    .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                    .offset(x: markerOffset(width: geo.size.width, markerSize: markerSize))
            }
        }
        .frame(height: height + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("估值评分")
        .accessibilityValue("\(Int(score.rounded())) 分，\(ValuationEngine.zone(for: score).rawValue)")
    }

    private func markerOffset(width: CGFloat, markerSize: CGFloat) -> CGFloat {
        let clamped = min(max(score, 0), 100) / 100
        return clamped * max(0, width - markerSize)
    }
}

/// 总览行内的迷你刻度：轨道 + 标记点，不配区间色段，保持克制。
struct MiniScoreTrack: View {
    let score: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surfaceMuted)
                Capsule()
                    .fill(Theme.zone(forScore: score).opacity(0.35))
                    .frame(width: max(6, geo.size.width * min(max(score, 0), 100) / 100))
                Circle()
                    .fill(Theme.zone(forScore: score))
                    .frame(width: 7, height: 7)
                    .offset(x: min(max(score, 0), 100) / 100 * max(0, geo.size.width - 7))
            }
        }
        .frame(width: 44, height: 7)
        .accessibilityHidden(true)
    }
}
