import XCTest
@testable import ValCompass

/// 已知历史锚点合理性验证（客观证据，全部离线 fixture）
final class AnchorTests: XCTestCase {

    private func csindexSeries() throws -> PESeries {
        let points = try CSIndexParser.parse(try Fixtures.data("csindex_000300.json"))
        return PESeries(meta: SeriesMeta(source: .csindex, fetchedAt: Date(), currency: .cny,
                                         isMonthly: false, isDelayed: false), points: points)
    }

    private func spxSeries() throws -> PriceSeries {
        let bars = try SinaUSParser.parse(try Fixtures.data("sina_INX.jsonp"))
        return PriceSeries(meta: SeriesMeta(source: .sina, fetchedAt: Date(), currency: .usd,
                                            isMonthly: false, isDelayed: false), bars: bars)
    }

    // 沪深300 2018-12-28 熊市底部（PE≈10.7）应判偏低
    func testCSI300At2018BottomScoresLow() throws {
        let series = try csindexSeries()
        let asOf = DateUtil.date("2018-12-28")!
        let result = ValuationEngine.evaluateFundamentals(peSeries: series, asOf: asOf)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result?.score ?? 100, 30)
        XCTAssertEqual(result?.zone, .veryLow)
        // 历史约 3.5 年 → 置信度中
        XCTAssertEqual(result?.confidence, .medium)
    }

    // 沪深300 2021-02-10 牛市顶部（PE≈19.1）应判偏高
    func testCSI300At2021TopScoresHigh() throws {
        let series = try csindexSeries()
        let asOf = DateUtil.date("2021-02-10")!
        let result = ValuationEngine.evaluateFundamentals(peSeries: series, asOf: asOf)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result?.score ?? 0, 70)
        XCTAssertEqual(result?.zone, .veryHigh)
    }

    // 标普500 价格位置：2020-03 疫情底应显著低于 2021 年高点
    func testSPXCovidBottomVsBullTop() throws {
        let series = try spxSeries()
        let bottom = ValuationEngine.evaluatePricePosition(priceSeries: series,
                                                           asOf: DateUtil.date("2020-03-23")!)
        let top = ValuationEngine.evaluatePricePosition(priceSeries: series,
                                                        asOf: DateUtil.date("2021-12-27")!)
        XCTAssertNotNil(bottom); XCTAssertNotNil(top)
        XCTAssertGreaterThan(top?.score ?? 0, 80)
        XCTAssertLessThan(bottom?.score ?? 100, top?.score ?? 0)
        XCTAssertGreaterThan((top?.score ?? 0) - (bottom?.score ?? 100), 25, "疫情底应显著低于牛市高点")
        // 法B 置信度上限为中
        XCTAssertEqual(bottom?.confidence, .medium)
        XCTAssertEqual(top?.confidence, .medium)
    }
}
