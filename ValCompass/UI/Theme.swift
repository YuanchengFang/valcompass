import SwiftUI

// MARK: - 设计令牌
// 视觉语言：安静、低饱和、编辑感。暖白底 + 单一赭石灰调 accent；
// 估值五档用「钢蓝 → 暖灰 → 赭石 → 赤陶」的低饱和色阶，刻意避开涨跌红绿。

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
    }
}

enum Theme {
    // 中性色（暖调）
    static let background = Color(light: "FAFAF8", dark: "1B1B19")
    static let surface = Color(light: "FFFFFF", dark: "262521")
    static let surfaceMuted = Color(light: "F3F1EC", dark: "302E29")
    static let textPrimary = Color(light: "1F1D1A", dark: "F0EDE6")
    static let textSecondary = Color(light: "6E6A62", dark: "9C978C")
    static let textTertiary = Color(light: "9B968C", dark: "6B6760")
    static let divider = Color(light: "E8E5DE", dark: "3A3833")

    // 单一 accent：赭石
    static let accent = Color(light: "9A6B2F", dark: "D9A45B")

    // 状态色（与估值色阶区分：仅用于数据状态，不表达贵贱）
    static let statusWarning = Color(light: "9A6B2F", dark: "D9A45B")   // 过期/缓存
    static let statusError = Color(light: "8C4A3B", dark: "C98A70")     // 刷新失败/无数据

    /// 估值五档语义色：分数低=钢蓝（冷、低），分数高=赤陶（暖、高），中间暖灰。
    /// 刻意不用红绿，避免与涨跌/买卖暗示混淆。
    static func zone(_ zone: ValuationZone) -> Color {
        switch zone {
        case .veryLow:  return Color(light: "35617E", dark: "7BA7C4")
        case .low:      return Color(light: "5E84A0", dark: "93B4C9")
        case .fair:     return Color(light: "8A8478", dark: "A8A294")
        case .high:     return Color(light: "A97F3C", dark: "CDA45E")
        case .veryHigh: return Color(light: "9E5A41", dark: "C98A70")
        }
    }

    static func zone(forScore score: Double) -> Color {
        zone(ValuationEngine.zone(for: score))
    }

    // 图表
    static let priceLine = Color(light: "4A4640", dark: "D8D4CA")
    static let navLine = accent
}

enum AppFont {
    static let display = Font.system(size: 32, weight: .bold, design: .serif)
    static let scoreBig = Font.system(size: 44, weight: .semibold, design: .serif)
    static let sectionTitle = Font.system(size: 19, weight: .semibold, design: .serif)
    static let heading = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15)
    static let caption = Font.system(size: 12)
    static let footnote = Font.system(size: 11)
    /// 数字统一用等宽数字，避免列表跳动
    static func number(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - 文案映射（UI 层统一口径）

extension DataSourceKind {
    var displayName: String {
        switch self {
        case .tencent: return "腾讯行情"
        case .sina: return "新浪美股"
        case .csindex: return "中证指数"
        case .eastmoney: return "天天基金"
        case .multpl: return "multpl.com"
        }
    }
}

extension Market {
    var displayName: String {
        switch self {
        case .cn: return "A股"
        case .hk: return "港股"
        case .us: return "美股"
        }
    }
}

extension AssetKind {
    var displayName: String {
        switch self {
        case .index: return "指数"
        case .etf: return "ETF"
        }
    }
}

extension ValuationMethod {
    var displayName: String {
        switch self {
        case .fundamentals: return "基本面分位（PE）"
        case .pricePosition: return "价格位置分位"
        }
    }
}
