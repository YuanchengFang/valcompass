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

    // MARK: 辅助指标 · 股债性价比（ERP）

    /// ERP = 1/PE × 100 − 10Y 国债收益率（百分数口径，如 5.2 表示 5.2%）。
    /// 日度：PE 按交易日，收益率周末/假日缺失时用此前最近一个交易日的值填充。
    /// 返回升序 (date, erp) 序列；任一输入缺失的日子跳过。
    static func erpSeriesDaily(pe pePoints: [PEPoint], yields: [YieldPoint],
                               yieldOf keyPath: KeyPath<YieldPoint, Double?>) -> [(date: String, erp: Double)] {
        // 先构建 日期→收益率 的前向填充序列（收益率序列本身升序）
        var filled: [(date: String, y: Double)] = []
        var last: Double?
        for p in yields {
            if let y = p[keyPath: keyPath] { last = y }
            if let last { filled.append((p.date, last)) }
        }
        guard !filled.isEmpty else { return [] }
        var out: [(date: String, erp: Double)] = []
        var yi = 0
        for pe in pePoints where pe.pe > 0 {
            // 推进到不超过 pe.date 的最后一个收益率点（字符串日期同格式可直接比较）
            while yi + 1 < filled.count && filled[yi + 1].date <= pe.date { yi += 1 }
            guard filled[yi].date <= pe.date else { continue } // PE 早于首个收益率点
            out.append((pe.date, 100.0 / pe.pe - filled[yi].y))
        }
        return out
    }

    /// 月度 ERP（spx）：每月 PE 点配对该月最后一个可得收益率（月末口径）。
    static func erpSeriesMonthly(pe pePoints: [PEPoint], yields: [YieldPoint],
                                 yieldOf keyPath: KeyPath<YieldPoint, Double?>) -> [(date: String, erp: Double)] {
        var filled: [(date: String, y: Double)] = []
        var last: Double?
        for p in yields {
            if let y = p[keyPath: keyPath] { last = y }
            if let last { filled.append((p.date, last)) }
        }
        guard !filled.isEmpty else { return [] }
        var out: [(date: String, erp: Double)] = []
        var yi = 0
        for pe in pePoints where pe.pe > 0 {
            let month = String(pe.date.prefix(7)) // yyyy-MM
            // 月末：该月内最后一个有值的收益率点；该月无数据则取此前最近一个
            while yi + 1 < filled.count && String(filled[yi + 1].date.prefix(7)) <= month { yi += 1 }
            guard String(filled[yi].date.prefix(7)) <= month else { continue }
            out.append((pe.date, 100.0 / pe.pe - filled[yi].y))
        }
        return out
    }

    /// 由 ERP 序列生成辅助指标：当前 ERP 在近 10 年（不足则全部）序列中的分位。
    /// 方向：ERP 越高 = 股票相对债券越便宜（与主分数方向相反）。
    static func erpMetric(erpSeries: [(date: String, erp: Double)]) -> SecondaryMetric? {
        guard let latest = erpSeries.last, let asOf = DateUtil.date(latest.date) else { return nil }
        let win = window(erpSeries, asOf: asOf) { DateUtil.date($0.date) }
        guard let percentile = percentileRank(of: latest.erp, in: win.map(\.erp)) else { return nil }
        return SecondaryMetric(
            name: "股债性价比（ERP）",
            valueText: String(format: "%.2f%%", latest.erp),
            percentile: percentile,
            direction: .higherCheaper,
            asOf: latest.date,
            note: "ERP = 盈利收益率（1/PE）− 10年期国债收益率；百分位越高，股票相对债券越便宜（与主分数方向相反）。",
            confidence: .medium)
    }

    // MARK: 辅助指标 · CAPE / 股息率分位（spx）

    /// 当前值在近 10 年月度序列中的分位，包装为辅助指标。
    /// - direction: CAPE 越高越贵（与主分数同向）；股息率越高越便宜（相反）。
    static func percentileMetric(name: String, series: PESeries, unit: String,
                                 direction: MetricDirection, note: String) -> SecondaryMetric? {
        guard let latest = series.points.last, let asOf = DateUtil.date(latest.date) else { return nil }
        let win = window(series.points, asOf: asOf) { DateUtil.date($0.date) }
        guard let percentile = percentileRank(of: latest.pe, in: win.map(\.pe)) else { return nil }
        return SecondaryMetric(
            name: name,
            valueText: String(format: "%.2f%@", latest.pe, unit),
            percentile: percentile,
            direction: direction,
            asOf: latest.date,
            note: note,
            confidence: .medium)
    }

    // MARK: ETF 评分来源

    /// ETF 评分 = 底层指数评分；无底层且方法为法B（如黄金ETF）时，用自身市价序列跑价格位置。
    static func etfScore(target: MarketTarget, underlying: ValuationResult?, ownPrice: PriceSeries?) -> ValuationResult? {
        if let underlying { return underlying }
        guard target.underlyingTargetID == nil, target.method == .pricePosition,
              let ownPrice else { return nil }
        return evaluatePricePosition(priceSeries: ownPrice)
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
