import Foundation

// MARK: - 基础数据模型
// 注意：指数点位、ETF 市价、基金单位净值、累计净值是不同概念，分开表示，严禁混用。

enum Currency: String, Codable {
    case cny = "CNY"
    case hkd = "HKD"
    case usd = "USD"
}

enum DataSourceKind: String, Codable {
    case tencent    // 腾讯日线行情
    case sina       // 新浪美股日线
    case csindex    // 中证指数官网市盈率
    case eastmoney  // 天天基金净值
    case multpl     // multpl.com 标普500市盈率/股息率（月度）
    case eastmoneyYield // 东方财富数据中心：中/美 10 年期国债收益率
}

/// 日线行情（指数点位或 ETF 市价）
struct PriceBar: Codable, Equatable {
    var date: String   // yyyy-MM-dd
    var open: Double
    var close: Double
    var high: Double
    var low: Double
    var volume: Double
}

/// 市盈率数据点（中证为日度，multpl 为月度）
struct PEPoint: Codable, Equatable {
    var date: String   // yyyy-MM-dd
    var pe: Double     // 来源字段名为 peg（中证官网口径），每日收盘后发布
}

/// 基金净值（单位净值与累计净值分开保存）
struct FundNavPoint: Codable, Equatable {
    var date: String        // yyyy-MM-dd，净值所属日期（T 日收盘后公布，QDII 可能滞后 1-2 个交易日）
    var unitNav: Double     // 单位净值：用于溢折价计算
    var accumulatedNav: Double? // 累计净值：用于长期收益对比
}

/// 序列元信息：每个数据点可溯源
struct SeriesMeta: Codable, Equatable {
    var source: DataSourceKind
    var fetchedAt: Date     // 抓取时间
    var currency: Currency
    var isMonthly: Bool     // 月度数据（精度有限）
    var isDelayed: Bool     // 延迟数据（如 QDII 净值滞后）
}

struct PriceSeries: Codable, Equatable {
    var meta: SeriesMeta
    var bars: [PriceBar]
    var asOfDate: String? { bars.last?.date }
}

struct PESeries: Codable, Equatable {
    var meta: SeriesMeta
    var points: [PEPoint]
    var asOfDate: String? { points.last?.date }
}

struct FundNavSeries: Codable, Equatable {
    var meta: SeriesMeta
    var fundName: String
    var points: [FundNavPoint]
    var asOfDate: String? { points.last?.date }
}

/// 10 年期国债收益率（东方财富数据中心，日度；周末/假日无值，由计算层向前填充）
struct YieldPoint: Codable, Equatable {
    var date: String        // yyyy-MM-dd
    var cn10y: Double?      // 中国 10Y，百分数（如 1.72 表示 1.72%）
    var us10y: Double?      // 美国 10Y；部分日期缺失（美方假日/发布滞后）
}

struct YieldSeries: Codable, Equatable {
    var meta: SeriesMeta
    var points: [YieldPoint]    // 升序
    var asOfDate: String? { points.last?.date }
}

// MARK: - 辅助估值指标（「其他视角」，不并入主分数）

/// 指标方向：决定「百分位越高」意味着什么，展示时必须与主分数方向区分清楚
enum MetricDirection: String, Codable, Equatable {
    case higherCheaper = "越高越便宜"   // ERP、股息率：与主分数方向相反
    case higherExpensive = "越高越贵"   // CAPE 分位：与主分数同向
}

/// 一条辅助估值指标：名称/当前值/百分位/方向/数据截至/一句方法说明
struct SecondaryMetric: Equatable, Sendable {
    var name: String
    var valueText: String          // 当前值展示文本，如 "5.20%"
    var percentile: Double         // 0–100，近 10 年（不足则全部）序列中的分位
    var direction: MetricDirection
    var asOf: String               // 数据截至日期
    var note: String               // 一句方法说明（含方向提示与局限）
    var confidence: Confidence     // 辅助指标一律偏保守
}

// MARK: - 日期工具

enum DateUtil {
    static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 「抓取于 07-28 15:04」展示用。与 `ymd` 同理：创建后只读，可跨线程共享。
    static let monthDayTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    /// 解析缓存：评分历史采样会对同一批日期字符串反复解析，
    /// DateFormatter 解析成本高，用线程安全的 NSCache 去重（语义不变）。
    private static let dateCache = NSCache<NSString, NSDate>()

    static func date(_ ymdString: String) -> Date? {
        let key = ymdString as NSString
        if let cached = dateCache.object(forKey: key) { return cached as Date }
        guard let parsed = ymd.date(from: ymdString) else { return nil }
        dateCache.setObject(parsed as NSDate, forKey: key)
        return parsed
    }

    static func string(_ date: Date) -> String {
        ymd.string(from: date)
    }

    /// 两个日期之间的交易日数（近似：只剔除周末，不剔节假日）
    static func tradingDaysBetween(_ from: Date, _ to: Date) -> Int {
        guard to > from else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var count = 0
        var day = cal.startOfDay(for: from)
        let end = cal.startOfDay(for: to)
        while day < end {
            day = cal.date(byAdding: .day, value: 1, to: day)!
            let wd = cal.component(.weekday, from: day)
            if wd != 1 && wd != 7 { count += 1 }
        }
        return count
    }
}
