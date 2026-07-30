import Foundation

/// UI 层共享格式器（DateFormatter 创建成本高，复用静态实例）
enum Formatters {
    /// 时间戳：2026-07-28 15:04
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    /// 百分数：+0.85%
    static func percent(_ value: Double) -> String {
        String(format: "%+.2f%%", value * 100)
    }
}
