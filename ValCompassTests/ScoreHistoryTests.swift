import XCTest
@testable import ValCompass

/// 评分历史采样：自适应步长、包含末点、分数范围、逐点 asOf 口径
final class ScoreHistoryTests: XCTestCase {

    private func meta() -> SeriesMeta {
        SeriesMeta(source: .csindex, fetchedAt: Date(), currency: .cny, isMonthly: false, isDelayed: false)
    }

    /// 造一段多年日度序列：日期从 start 起逐日递增，值按 given 闭包生成
    private func makeDates(count: Int) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let start = cal.date(from: DateComponents(year: 2015, month: 1, day: 5))!
        return (0..<count).map { DateUtil.string(cal.date(byAdding: .day, value: $0, to: start)!) }
    }

    func testPriceHistoryContainsLastAndAscending() {
        let dates = makeDates(count: 500)
        let bars = dates.enumerated().map { i, d in
            PriceBar(date: d, open: 0, close: Double(100 + i % 50), high: 0, low: 0, volume: 0)
        }
        let series = PriceSeries(meta: meta(), bars: bars)
        let history = ValuationEngine.scoreHistory(priceSeries: series)
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.last?.date, dates.last)
        XCTAssertLessThanOrEqual(history.count, 120)
        // 日期升序
        for (a, b) in zip(history, history.dropFirst()) {
            XCTAssertLessThan(a.date, b.date)
        }
        // 分数在 0–100
        for p in history {
            XCTAssertGreaterThanOrEqual(p.score, 0)
            XCTAssertLessThanOrEqual(p.score, 100)
        }
    }

    func testPEHistoryScoresMatchAsOfSemantics() {
        // PE 单调上升：越靠后的采样点百分位应越高
        let dates = makeDates(count: 400)
        let points = dates.enumerated().map { i, d in PEPoint(date: d, pe: 10 + Double(i) * 0.05) }
        let series = PESeries(meta: meta(), points: points)
        let history = ValuationEngine.scoreHistory(peSeries: series, maxSamples: 50)
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.last?.date, dates.last)
        // 末点 PE 是序列最大值 → 评分应明显高于中位
        XCTAssertGreaterThan(history.last!.score, 90)
        XCTAssertLessThan(history.first!.score, history.last!.score)
    }

    func testHistoryTooShortReturnsEmpty() {
        let dates = makeDates(count: 1)
        let series = PriceSeries(meta: meta(), bars: [PriceBar(date: dates[0], open: 0, close: 1, high: 0, low: 0, volume: 0)])
        XCTAssertTrue(ValuationEngine.scoreHistory(priceSeries: series).isEmpty)
        let pe = PESeries(meta: meta(), points: [PEPoint(date: dates[0], pe: 12)])
        XCTAssertTrue(ValuationEngine.scoreHistory(peSeries: pe).isEmpty)
    }

    func testHistorySkipsNonPositivePE() {
        // 前段 PE≤0 不适用，采样点应被跳过而不是造假分数
        let dates = makeDates(count: 200)
        let points = dates.enumerated().map { i, d in PEPoint(date: d, pe: i < 100 ? -1 : 10 + Double(i)) }
        let series = PESeries(meta: meta(), points: points)
        let history = ValuationEngine.scoreHistory(peSeries: series, maxSamples: 400)
        XCTAssertFalse(history.isEmpty)
        XCTAssertTrue(history.allSatisfy { $0.date >= dates[100] })
    }
}
