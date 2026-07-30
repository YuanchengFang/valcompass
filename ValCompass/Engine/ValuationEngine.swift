import Foundation

// MARK: - 估值引擎（纯函数，可复现）

enum ValuationZone: String, CaseIterable {
    case veryLow = "明显偏低"   // 0–20 便宜
    case low = "偏低"           // 20–40
    case fair = "合理"          // 40–60
    case high = "偏高"          // 60–80
    case veryHigh = "明显偏高"  // 80–100 昂贵
}

enum Confidence: String, Comparable {
    case low = "低"
    case medium = "中"
    case high = "高"
    private var rank: Int { switch self { case .low: 0; case .medium: 1; case .high: 2 } }
    static func < (l: Confidence, r: Confidence) -> Bool { l.rank < r.rank }
}

enum PremiumTier: String {
    case normal = "正常"          // |p| < 0.3%
    case slight = "轻微"          // 0.3%–1%
    case significant = "显著"     // >1%
}

enum Freshness: String {
    case fresh = "最新"
    case stale = "已过期"
}

struct ValuationResult: Equatable {
    var score: Double?           // 0–100 百分位；nil 表示数据不足
    var zone: ValuationZone?
    var method: ValuationMethod
    var confidence: Confidence
    var asOfDate: String?        // 评分所用当前值的数据日期
    var note: String             // 中文说明（口径/局限）
}

/// 评分历史采样点：某一历史日期按当时可得窗口算出的评分
struct ScoreHistoryPoint: Equatable, Sendable {
    var date: String   // yyyy-MM-dd
    var score: Double  // 0–100
}

enum ValuationEngine {

    // MARK: 分位数

    /// 当前值在序列中的百分位（0–100）：序列中小于当前值的比例。
    /// 空序列返回 nil；单元素返回 50（数据不足，按中性处理）。
    static func percentileRank(of current: Double, in values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        guard values.count > 1 else { return 50 }
        let below = values.filter { $0 < current }.count
        return 100.0 * Double(below) / Double(values.count)
    }

    // MARK: 区间映射

    /// 0–20 明显偏低 / 20–40 偏低 / 40–60 合理 / 60–80 偏高 / 80–100 明显偏高
    /// 边界归属：恰好 20 归「偏低」，恰好 40 归「合理」，恰好 60 归「偏高」，恰好 80 归「明显偏高」。
    static func zone(for score: Double) -> ValuationZone {
        switch score {
        case ..<20: return .veryLow
        case ..<40: return .low
        case ..<60: return .fair
        case ..<80: return .high
        default: return .veryHigh
        }
    }

    // MARK: 置信度

    /// 法A：≥8年=高，3–8年=中，<3年=低
    static func confidence(dataYears: Double) -> Confidence {
        if dataYears >= 8 { return .high }
        if dataYears >= 3 { return .medium }
        return .low
    }

    // MARK: 新鲜度

    /// 行情：超过 5 个交易日未更新 → 过期
    static func quoteFreshness(asOf: Date, now: Date) -> Freshness {
        DateUtil.tradingDaysBetween(asOf, now) > 5 ? .stale : .fresh
    }

    /// PE/净值：超过 10 个自然日未更新 → 过期
    static func fundamentalFreshness(asOf: Date, now: Date) -> Freshness {
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: asOf, to: now).day ?? 0
        return days > 10 ? .stale : .fresh
    }

    // MARK: 窗口

    /// 取截至 asOf 的最近 10 年窗口（不足则用全部可用历史）
    static func window<T>(_ items: [T], asOf: Date, dateOf: (T) -> Date?, years: Int = 10) -> [T] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let cutoff = cal.date(byAdding: .year, value: -years, to: asOf) ?? .distantPast
        return items.filter { item in
            guard let d = dateOf(item) else { return false }
            return d >= cutoff && d <= asOf
        }
    }

    // MARK: 法A：基本面（PE）分位

    /// - peSeries: 升序 PE 序列；asOf 默认取序列最后一点。
    /// - PE ≤ 0（亏损）时指标不适用，返回 nil 由调用方回退法B。
    static func evaluateFundamentals(peSeries: PESeries, asOf explicitAsOf: Date? = nil) -> ValuationResult? {
        guard let latest = peSeries.points.last,
              let asOf = explicitAsOf ?? DateUtil.date(latest.date),
              let current = pointValue(at: asOf, in: peSeries.points) else { return nil }
        guard current > 0 else { return nil } // PE≤0：不适用，回退法B
        let win = window(peSeries.points, asOf: asOf) { DateUtil.date($0.date) }
        let values = win.map(\.pe).filter { $0 > 0 }
        guard let firstDate = win.first.flatMap({ DateUtil.date($0.date) }) else { return nil }
        let years = asOf.timeIntervalSince(firstDate) / (365.25 * 86400)
        let score = percentileRank(of: current, in: values)
        var note = "当前 PE \(String(format: "%.1f", current))，处于近\(max(1, Int(years.rounded())))年分位"
        if peSeries.meta.isMonthly { note += "（月度数据，精度有限）" }
        if years < 3 { note += "；历史不足3年，置信度低" }
        return ValuationResult(score: score,
                               zone: score.map(zone(for:)),
                               method: .fundamentals,
                               confidence: confidence(dataYears: years),
                               asOfDate: DateUtil.string(asOf),
                               note: note)
    }

    // MARK: 法B：价格位置分位

    /// 当前收盘价在近 10 年日线中的百分位。置信度上限为「中」。
    static func evaluatePricePosition(priceSeries: PriceSeries, asOf explicitAsOf: Date? = nil) -> ValuationResult? {
        guard let latest = priceSeries.bars.last,
              let asOf = explicitAsOf ?? DateUtil.date(latest.date),
              let current = barClose(at: asOf, in: priceSeries.bars) else { return nil }
        let win = window(priceSeries.bars, asOf: asOf) { DateUtil.date($0.date) }
        guard let firstDate = win.first.flatMap({ DateUtil.date($0.date) }) else { return nil }
        let years = asOf.timeIntervalSince(firstDate) / (365.25 * 86400)
        let score = percentileRank(of: current, in: win.map(\.close))
        var note = "收盘价处于近\(max(1, Int(years.rounded())))年分位；仅反映价格相对历史的位置，不含盈利/净资产等基本面"
        if years < 3 { note += "；历史不足3年" }
        let base = confidence(dataYears: years)
        return ValuationResult(score: score,
                               zone: score.map(zone(for:)),
                               method: .pricePosition,
                               confidence: min(base, .medium),
                               asOfDate: DateUtil.string(asOf),
                               note: note)
    }

    /// PE ≤ 0 回退说明
    static let peNotApplicableNote = "当前 PE≤0（成分股整体亏损），市盈率指标不适用，已回退价格位置法"

    // MARK: 评分历史采样

    /// 评分历史（法A）：对 PE 序列自适应采样，逐点以显式 asOf 重算评分。
    /// 纯函数、无状态，可在后台线程调用。早期采样点历史窗口短，评分波动大属正常。
    static func scoreHistory(peSeries: PESeries, maxSamples: Int = 120) -> [ScoreHistoryPoint] {
        sample(dates: peSeries.points.map(\.date), maxSamples: maxSamples) { asOf in
            evaluateFundamentals(peSeries: peSeries, asOf: asOf)
        }
    }

    /// 评分历史（法B）：对收盘价序列自适应采样，逐点以显式 asOf 重算评分。
    static func scoreHistory(priceSeries: PriceSeries, maxSamples: Int = 120) -> [ScoreHistoryPoint] {
        sample(dates: priceSeries.bars.map(\.date), maxSamples: maxSamples) { asOf in
            evaluatePricePosition(priceSeries: priceSeries, asOf: asOf)
        }
    }

    /// 按自适应步长采样（上限 maxSamples 个点），并始终包含序列末点。
    private static func sample(dates: [String], maxSamples: Int, evaluate: (Date) -> ValuationResult?) -> [ScoreHistoryPoint] {
        guard dates.count > 1 else { return [] }
        let stride = max(1, Int(ceil(Double(dates.count) / Double(max(1, maxSamples)))))
        var out: [ScoreHistoryPoint] = []
        var i = 0
        while i < dates.count - 1 {
            if let d = DateUtil.date(dates[i]), let score = evaluate(d)?.score {
                out.append(ScoreHistoryPoint(date: dates[i], score: score))
            }
            i += stride
        }
        if let last = dates.last, let d = DateUtil.date(last), let score = evaluate(d)?.score {
            out.append(ScoreHistoryPoint(date: last, score: score))
        }
        return out
    }

    // MARK: 溢折价

    /// premium = 市价 / 单位净值 − 1（必须用单位净值，不得用累计净值）
    static func premium(price: Double, unitNav: Double) -> Double? {
        guard unitNav > 0 else { return nil }
        return price / unitNav - 1
    }

    static func premiumTier(_ premium: Double) -> PremiumTier {
        let a = abs(premium)
        if a < 0.003 { return .normal }
        if a < 0.01 { return .slight }
        return .significant
    }

    static func premiumNote(_ premium: Double, isQDII: Bool) -> String {
        let pct = String(format: "%.2f%%", premium * 100)
        var note: String
        switch premiumTier(premium) {
        case .normal: note = "溢折价 \(pct)，正常范围"
        case .slight: note = "溢折价 \(pct)，轻微偏离"
        case .significant:
            note = premium > 0 ? "溢价 \(pct)，显著偏高，注意追高风险" : "折价 \(pct)，显著偏低，可能存在折价机会"
        }
        if isQDII { note += "（QDII 净值滞后 1-2 个交易日，溢折价仅供参考）" }
        return note
    }

    // MARK: 内部

    private static func pointValue(at date: Date, in points: [PEPoint]) -> Double? {
        points.last { DateUtil.date($0.date).map { $0 <= date } ?? false }?.pe
    }

    private static func barClose(at date: Date, in bars: [PriceBar]) -> Double? {
        bars.last { DateUtil.date($0.date).map { $0 <= date } ?? false }?.close
    }
}
