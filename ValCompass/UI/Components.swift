import SwiftUI

// MARK: - 卡片
// 全应用统一的承载容器：纸面上的一张卡，浅色下带极轻投影，深色下靠表面色差与描边区分。

struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Theme.divider.opacity(scheme == .dark ? 0.9 : 0.55), lineWidth: 0.5)
            )
            .shadow(
                color: .black.opacity(scheme == .dark ? 0 : 0.045),
                radius: 10, x: 0, y: 3
            )
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}

/// 带内边距的标准卡片
struct Card<Content: View>: View {
    var padding: CGFloat = Spacing.m
    var spacing: CGFloat = Spacing.m
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

// MARK: - 标题与文字块

/// 分组标题（衬线，用于卡片之上）
struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(AppFont.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            if let trailing {
                Spacer()
                Text(trailing)
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// 卡片内标题（衬线小号）
struct CardTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(AppFont.cardTitle)
            .foregroundStyle(Theme.textPrimary)
    }
}

/// 眉题：卡片顶部的说明性小标签
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.textTertiary
    init(_ text: String, color: Color = Theme.textTertiary) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text)
            .font(AppFont.eyebrow)
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

/// 空态/说明性小段文字
struct ContentNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 免责/局限说明：比正文更轻，带左侧细线以示注解性质
struct Disclaimer: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Rectangle()
                .fill(Theme.divider)
                .frame(width: 2)
            Text(text)
                .font(AppFont.footnote)
                .lineSpacing(3)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 标签

/// 小标签（市场 / 类型 / 币种 / 数据标记）
struct Tag: View {
    let text: String
    var tint: Color? = nil
    init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }
    var body: some View {
        Text(text)
            .font(AppFont.footnote)
            .foregroundStyle(tint ?? Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                (tint ?? Theme.textSecondary).opacity(tint == nil ? 0 : 0.10),
                in: .capsule
            )
            .background(tint == nil ? Theme.surfaceMuted : Color.clear, in: .capsule)
    }
}

/// 置信度胶囊：低饱和描边，不与估值色阶争夺注意力
struct ConfidencePill: View {
    let confidence: Confidence

    var body: some View {
        HStack(spacing: 4) {
            Text("置信度")
                .foregroundStyle(Theme.textTertiary)
            Text(confidence.rawValue)
                .foregroundStyle(Theme.textSecondary)
        }
        .font(AppFont.footnote)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 0.5))
    }
}

// MARK: - 状态提示

/// 数据状态横幅（过期 / 刷新失败 / 无数据，诚实标注，不静默）
struct StatusBanner: View {
    let icon: String
    let text: String
    var tint: Color = Theme.statusWarning

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 12.5))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(AppFont.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, 12)
        .background(tint.opacity(0.07), in: .rect(cornerRadius: Radius.inner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 0.5)
        )
    }
}

// MARK: - 行

/// 卡片内的键值行
struct KeyValueRow: View {
    let label: String
    let value: String
    var note: String? = nil
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: Spacing.s)
            Text(value)
                .font(AppFont.number(14, weight: .medium))
                .foregroundStyle(valueColor)
            if let note {
                Text(note)
                    .font(AppFont.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// 卡片内分隔线（左侧留白，视觉上归属于列表）
struct CardDivider: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

// MARK: - 交互

/// 卡片内可点击行：按下时整行浅底高亮，替代 List 的默认选中态
struct CardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.surfaceMuted : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 自定义分段选择器：替换系统 segmented control，与卡片语言一致
struct SegmentedSelector<T: Hashable & Identifiable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .background(Theme.surfaceMuted, in: .rect(cornerRadius: 10.5, style: .continuous))
    }
}
