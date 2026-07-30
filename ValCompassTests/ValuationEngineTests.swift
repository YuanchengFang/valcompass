import XCTest
@testable import ValCompass

/// 估值引擎测试：分位数、区间映射、置信度、溢折价、过期判定、PE≤0 回退
final class ValuationEngineTests: XCTestCase {

    private func meta() -> SeriesMeta {
        SeriesMeta(source: .csindex, fetchedAt: Date(), currency: .cny, isMonthly: false, isDelayed: false)
    }

    // MARK: 分位数

    func testPercentileEmptySeries() {
        XCTAssertNil(ValuationEngine.percentileRank(of: 1, in: []))
    }

    func testPercentileSingleElement() {
        XCTAssertEqual(ValuationEngine.percentileRank(of: 5, in: [5]), 50)
    }

    func testPercentileNormal() {
        // [1,2,3,4,5] 中小于 3 的有 2 个 → 40
        XCTAssertEqual(ValuationEngine.percentileRank(of: 3, in: [1, 2, 3, 4, 5]) ?? -1, 40, accuracy: 1e-9)
    }

    func testPercentileMinAndMax() {
        XCTAssertEqual(ValuationEngine.percentileRank(of: 1, in: [1, 2, 3, 4, 5]) ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(ValuationEngine.percentileRank(of: 5, in: [1, 2, 3, 4, 5]) ?? -1, 80, accuracy: 1e-9)
    }

    func testPercentileOutOfRange() {
        XCTAssertEqual(ValuationEngine.percentileRank(of: 0.5, in: [1, 2, 3]) ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(ValuationEngine.percentileRank(of: 99, in: [1, 2, 3]) ?? -1, 100, accuracy: 1e-9)
    }

    // MARK: 区间映射（边界归属：20→偏低 40→合理 60→偏高 80→明显偏高）

    func testZoneBoundaries() {
        XCTAssertEqual(ValuationEngine.zone(for: 0), .veryLow)
        XCTAssertEqual(ValuationEngine.zone(for: 19.99), .veryLow)
        XCTAssertEqual(ValuationEngine.zone(for: 20), .low)
        XCTAssertEqual(ValuationEngine.zone(for: 39.99), .low)
        XCTAssertEqual(ValuationEngine.zone(for: 40), .fair)
        XCTAssertEqual(ValuationEngine.zone(for: 59.99), .fair)
        XCTAssertEqual(ValuationEngine.zone(for: 60), .high)
        XCTAssertEqual(ValuationEngine.zone(for: 79.99), .high)
        XCTAssertEqual(ValuationEngine.zone(for: 80), .veryHigh)
        XCTAssertEqual(ValuationEngine.zone(for: 100), .veryHigh)
    }

    // MARK: 置信度

    func testConfidenceBySpan() {
        XCTAssertEqual(ValuationEngine.confidence(dataYears: 10), .high)
        XCTAssertEqual(ValuationEngine.confidence(dataYears: 8), .high)
        XCTAssertEqual(ValuationEngine.confidence(dataYears: 7.9), .medium)
        XCTAssertEqual(ValuationEngine.confidence(dataYears: 3), .medium)
        XCTAssertEqual(ValuationEngine.confidence(dataYears: 2.9), .low)
    }

    // MARK: 法A 评估

    func testFundamentalsBasicScore() {
        // 约 10 年日度序列：PE 在 8/18 间交替，当前值 13 恰在中位 → score 50
        var points: [PEPoint] = []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = DateUtil.date("2015-01-05")!
        for i in 0..<3800 {
            let d = cal.date(byAdding: .day, value: i, to: start)!
            points.append(PEPoint(date: DateUtil.string(d), pe: i % 2 == 0 ? 8 : 18))
        }
        let lastD = cal.date(byAdding: .day, value: 3800, to: start)!
        points.append(PEPoint(date: DateUtil.string(lastD), pe: 13))
        let series = PESeries(meta: meta(), points: points)
        let result = ValuationEngine.evaluateFundamentals(peSeries: series)
        XCTAssertEqual(result?.score ?? -1, 50, accuracy: 0.5)
        XCTAssertEqual(result?.zone, .fair)
        XCTAssertEqual(result?.method, .fundamentals)
        XCTAssertEqual(result?.confidence, .high) // 约 10.4 年 → 高
    }

    func testFundamentalsRejectsNonPositivePE() {
        // PE≤0（亏损）→ 返回 nil，由调用方回退法B
        let points = [PEPoint(date: "2024-01-02", pe: 15), PEPoint(date: "2024-01-03", pe: -2)]
        let series = PESeries(meta: meta(), points: points)
        XCTAssertNil(ValuationEngine.evaluateFundamentals(peSeries: series))
    }

    func testFundamentalsLowConfidenceOnShortHistory() {
        let points = [PEPoint(date: "2024-01-02", pe: 10), PEPoint(date: "2024-06-03", pe: 20)]
        let series = PESeries(meta: meta(), points: points)
        let result = ValuationEngine.evaluateFundamentals(peSeries: series)
        XCTAssertEqual(result?.confidence, .low)
        XCTAssertTrue(result?.note.contains("不足3年") ?? false)
    }

    // MARK: 法B 评估

    func testPricePositionConfidenceCappedAtMedium() {
        var bars: [PriceBar] = []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = DateUtil.date("2014-01-02")!
        for i in 0..<3000 {
            let d = cal.date(byAdding: .day, value: i, to: start)!
            bars.append(PriceBar(date: DateUtil.string(d), open: 100, close: 100 + Double(i),
                                 high: 100, low: 100, volume: 1))
        }
        let series = PriceSeries(meta: meta(), bars: bars)
        let result = ValuationEngine.evaluatePricePosition(priceSeries: series)
        XCTAssertEqual(result?.confidence, .medium) // 约 8.2 年数据本来为高，但法B上限为中
        XCTAssertEqual(result?.method, .pricePosition)
        XCTAssertTrue(result?.note.contains("仅反映价格相对历史的位置") ?? false)
        XCTAssertEqual(result?.zone, .veryHigh) // 单调上升序列的最新值 → 最高分位
    }

    // MARK: 溢折价

    func testPremiumCalculation() {
        XCTAssertEqual(ValuationEngine.premium(price: 4.08, unitNav: 4.0) ?? 0, 0.02, accuracy: 1e-9)
        XCTAssertNil(ValuationEngine.premium(price: 4.0, unitNav: 0)) // 非法净值
    }

    func testPremiumTiers() {
        XCTAssertEqual(ValuationEngine.premiumTier(0), .normal)
        XCTAssertEqual(ValuationEngine.premiumTier(0.0029), .normal)
        XCTAssertEqual(ValuationEngine.premiumTier(-0.0029), .normal)
        XCTAssertEqual(ValuationEngine.premiumTier(0.003), .slight)
        XCTAssertEqual(ValuationEngine.premiumTier(0.0099), .slight)
        XCTAssertEqual(ValuationEngine.premiumTier(-0.0099), .slight)
        XCTAssertEqual(ValuationEngine.premiumTier(0.01), .significant)
        XCTAssertEqual(ValuationEngine.premiumTier(-0.02), .significant)
    }

    func testPremiumNotes() {
        XCTAssertTrue(ValuationEngine.premiumNote(0.02, isQDII: false).contains("追高风险"))
        XCTAssertTrue(ValuationEngine.premiumNote(-0.02, isQDII: false).contains("折价机会"))
        // QDII 必须提示净值滞后
        XCTAssertTrue(ValuationEngine.premiumNote(0.005, isQDII: true).contains("净值滞后"))
    }

    // MARK: 过期判定

    func testQuoteStaleness() {
        // 2026-07-22(三) → 2026-07-29(三)：5 个交易日，未过期
        let asOf = DateUtil.date("2026-07-22")!
        XCTAssertEqual(ValuationEngine.quoteFreshness(asOf: asOf, now: DateUtil.date("2026-07-29")!), .fresh)
        // → 2026-07-30(四)：6 个交易日，过期
        XCTAssertEqual(ValuationEngine.quoteFreshness(asOf: asOf, now: DateUtil.date("2026-07-30")!), .stale)
        // 跨越周末不算交易日：2026-07-24(五) → 2026-07-27(一) 只 1 个交易日
        XCTAssertEqual(ValuationEngine.quoteFreshness(asOf: DateUtil.date("2026-07-24")!,
                                                      now: DateUtil.date("2026-07-27")!), .fresh)
    }

    func testFundamentalStaleness() {
        let asOf = DateUtil.date("2026-07-19")!
        XCTAssertEqual(ValuationEngine.fundamentalFreshness(asOf: asOf, now: DateUtil.date("2026-07-29")!), .fresh) // 10 天
        XCTAssertEqual(ValuationEngine.fundamentalFreshness(asOf: asOf, now: DateUtil.date("2026-07-30")!), .stale) // 11 天
    }

    // MARK: QDII 净值日期标注

    func testQDIINavDateLabeling() {
        // 净值日期与市价日期不一致时，快照必须展示净值所属日期（T 日收盘后公布）
        let navPoint = FundNavPoint(date: "2026-07-27", unitNav: 1.85, accumulatedNav: 1.9)
        XCTAssertEqual(navPoint.date, "2026-07-27")
        // 溢折价用单位净值而非累计净值
        let p = ValuationEngine.premium(price: 1.9, unitNav: navPoint.unitNav) ?? 0
        XCTAssertEqual(p, 1.9 / 1.85 - 1, accuracy: 1e-9)
        XCTAssertNotEqual(p, 1.9 / (navPoint.accumulatedNav ?? 1) - 1, "不得用累计净值算溢价")
    }
}
