import SwiftUI

// MARK: - 设计令牌
// 视觉语言：安静、低饱和、编辑感。暖纸底 + 单一赭石 accent + 衬线数字；
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
        self.init(uiColor: .dynamic(light: light, dark: dark))
    }
}

extension UIColor {
    /// 随外观切换的动态色。UIKit 在绘制时按当时的 traitCollection 求值，
    /// 因此可以在 App.init() 阶段（尚无 trait 环境）安全构造。
    /// 注意：不要用 UIColor(SwiftUI.Color) 转换动态色——那会当场求值，
    /// 在没有 trait 环境时可能取到错误的一侧（导航栏标题曾因此变成纸面色而不可见）。
    static func dynamic(light: String, dark: String) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        }
    }
}

enum Theme {
    // 纸面与墨色（暖调中性）
    // 这两色导航栏也要用，hex 只写一处，SwiftUI 与 UIKit 各自派生。
    private static let paperHex = (light: "FAF8F3", dark: "161512")
    private static let inkHex = (light: "1A1815", dark: "F2EEE6")

    static let background = Color(light: paperHex.light, dark: paperHex.dark)
    static let textPrimary = Color(light: inkHex.light, dark: inkHex.dark)
    static var uiBackground: UIColor { .dynamic(light: paperHex.light, dark: paperHex.dark) }
    static var uiTextPrimary: UIColor { .dynamic(light: inkHex.light, dark: inkHex.dark) }

    static let surface = Color(light: "FFFFFF", dark: "211F1B")
    static let surfaceMuted = Color(light: "F1EDE3", dark: "2C2924")
    static let textSecondary = Color(light: "6B655B", dark: "A29C90")
    static let textTertiary = Color(light: "9B9488", dark: "716C63")
    static let divider = Color(light: "E7E2D7", dark: "35322C")
    /// 卡片内分隔线：比 divider 更轻
    static let hairline = Color(light: "EFEBE1", dark: "2D2A24")

    // 单一 accent：赭石
    static let accent = Color(light: "8C5F22", dark: "D9A45B")

    // 状态色（与估值色阶区分：仅用于数据状态，不表达贵贱）
    static let statusWarning = Color(light: "8C5F22", dark: "D9A45B")   // 过期/缓存
    static let statusError = Color(light: "8B4A38", dark: "C98A70")     // 刷新失败/无数据

    /// 估值五档语义色：分数低=钢蓝（冷、低），分数高=赤陶（暖、高），中间暖灰。
    /// 刻意不用红绿，避免与涨跌/买卖暗示混淆。
    static func zone(_ zone: ValuationZone) -> Color {
        switch zone {
        case .veryLow:  return Color(light: "2F5C7A", dark: "82ADC8")
        case .low:      return Color(light: "5B839F", dark: "9CBBCE")
        case .fair:     return Color(light: "857F72", dark: "ABA598")
        case .high:     return Color(light: "A87C38", dark: "CFA55F")
        case .veryHigh: return Color(light: "9B5539", dark: "CB8869")
        }
    }

    static func zone(forScore score: Double) -> Color {
        zone(ValuationEngine.zone(for: score))
    }

    /// 0–100 五档色阶（硬边界渐变）：刻度尺与图表参考带共用同一套语义色
    static func zoneBands(opacity: Double) -> LinearGradient {
        var stops: [Gradient.Stop] = []
        for (i, z) in ValuationZone.allCases.enumerated() {
            let c = zone(z).opacity(opacity)
            stops.append(.init(color: c, location: Double(i) / 5))
            stops.append(.init(color: c, location: Double(i + 1) / 5))
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    // 图表
    static let priceLine = Color(light: "43403A", dark: "D8D4CA")
    static let navLine = accent
}

enum AppFont {
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// 衬线数字（估值分数专用，等宽数字避免跳动）
    static func serifNumber(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        serif(size, weight).monospacedDigit()
    }

    static let display = serif(28, .semibold)      // 详情页标的名
    static let scoreHero = serifNumber(52)         // 详情页主分数
    static let scoreRow = serifNumber(20)          // 列表行分数
    static let sectionTitle = serif(20, .semibold) // 分组标题
    static let cardTitle = serif(17, .semibold)    // 卡片内标题
    static let rowTitle = Font.system(size: 16.5, weight: .semibold)
    static let heading = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15)
    static let caption = Font.system(size: 12.5)
    static let footnote = Font.system(size: 11)
    /// 小标签（眉题）：字重高 + 字距，用于卡片顶部的说明性标签
    static let eyebrow = Font.system(size: 10.5, weight: .semibold)
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

enum Radius {
    static let card: CGFloat = 18
    static let inner: CGFloat = 12
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
