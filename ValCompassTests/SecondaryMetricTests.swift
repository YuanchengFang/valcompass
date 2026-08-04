import XCTest
@testable import ValCompass

/// 辅助估值指标测试：ERP 计算与 join 逻辑（含周末填充）、月度 ERP、
/// CAPE/股息率分位、方向标签、黄金ETF 自身法B 路径。
final class SecondaryMetricTests: XCTestCase {

    private func meta() -> SeriesMeta {
        SeriesMeta(source: .csindex, fetchedAt: Date(), currency: .cny, isMonthly: false, isDelayed: false)
    }

    // MARK: 日度 ERP：收益率周末缺失用前一交易日值填充

    func testERPDailyWeekendFill() {
        // 2026-07-24 周五、07-25/26 周末、07-27 周一。收益率只有周五（周末无发布），
        // 周一的 ERP 必须用周五的收益率。
        let pe = [PEPoint(date: "2026-07-24", pe: 10),   // 盈利收益率 10%
                  PEPoint(date: "2026-07-27", pe: 20)]   // 盈利收益率 5%
        let yields = [YieldPoint(date: "2026-07-24", cn10y: 2.0, us10y: nil),
                      YieldPoint(date: "2026-07-27", cn10y: nil, us10y: nil)] // 周一缺失
        let erp = ValuationEngine.erpSeriesDaily(pe: pe, yields: yields, yieldOf: \.cn10y)
        XCTAssertEqual(erp.count, 2)
        XCTAssertEqual(erp[0].erp, 10 - 2.0, accuracy: 1e-9)
        XCTAssertEqual(erp[1].erp, 5 - 2.0, accuracy: 1e-9, "周一应回填周五的收益率")
    }

    func testERPDailySkipsPEBeforeFirstYield() {
        let pe = [PEPoint(date: "2020-01-01", pe: 10), PEPoint(date: "2020-06-01", pe: 10)]
        let yields = [YieldPoint(date: "2020-03-01", cn10y: 3.0, us10y: nil)]
        let erp = ValuationEngine.erpSeriesDaily(pe: pe, yields: yields, yieldOf: \.cn10y)
        XCTAssertEqual(erp.count, 1, "PE 早于首个收益率点的日子应跳过")
        XCTAssertEqual(erp[0].date, "2020-06-01")
    }

    func testERPDailyIgnoresNonPositivePE() {
        let pe = [PEPoint(date: "2020-03-02", pe: -5), PEPoint(date: "2020-03-03", pe: 10)]
        let yields = [YieldPoint(date: "2020-03-02", cn10y: 3.0, us10y: nil)]
        let erp = ValuationEngine.erpSeriesDaily(pe: pe, yields: yields, yieldOf: \.cn10y)
        XCTAssertEqual(erp.count, 1)
        XCTAssertEqual(erp[0].date, "2020-03-03")
    }

    // MARK: 月度 ERP：配对该月最后一个收益率（月末口径）

    func testERPMonthlyUsesMonthEndYield() {
        let pe = [PEPoint(date: "2020-04-01", pe: 20), PEPoint(date: "2020-05-01", pe: 25)]
        let yields = [YieldPoint(date: "2020-04-15", cn10y: nil, us10y: 0.7),
                      YieldPoint(date: "2020-04-30", cn10y: nil, us10y: 0.6),  // 4 月末
                      YieldPoint(date: "2020-05-29", cn10y: nil, us10y: 0.65)] // 5 月末
        let erp = ValuationEngine.erpSeriesMonthly(pe: pe, yields: yields, yieldOf: \.us10y)
        XCTAssertEqual(erp.count, 2)
        XCTAssertEqual(erp[0].erp, 5 - 0.6, accuracy: 1e-9, "4 月 PE 应配 4 月末收益率")
        XCTAssertEqual(erp[1].erp, 4 - 0.65, accuracy: 1e-9)
    }

    // MARK: ERP 指标：方向与分位

    func testERPMetricDirectionAndPercentile() {
        // 10 个 ERP 点：1..9，当前 10 → 分位 90（9/10）
        let series = (1...10).map { (date: String(format: "2025-01-%02d", $0), erp: Double($0)) }
        let metric = ValuationEngine.erpMetric(erpSeries: series)
        XCTAssertNotNil(metric)
        XCTAssertEqual(metric?.direction, .higherCheaper, "ERP 分位越高越便宜")
        XCTAssertEqual(metric?.percentile ?? -1, 90, accuracy: 1e-9)
        XCTAssertEqual(metric?.valueText, "10.00%")
        XCTAssertEqual(metric?.asOf, "2025-01-10")
        XCTAssertEqual(metric?.confidence, .medium, "ERP 置信度标「中」")
        XCTAssertTrue(metric?.note.contains("相反") ?? false, "必须提示与主分数方向相反")
    }

    func testERPMetricEmptyReturnsNil() {
        XCTAssertNil(ValuationEngine.erpMetric(erpSeries: []))
    }

    // MARK: CAPE / 股息率分位：方向标签

    func testDirectionLabels() {
        XCTAssertEqual(MetricDirection.higherCheaper.rawValue, "越高越便宜")
        XCTAssertEqual(MetricDirection.higherExpensive.rawValue, "越高越贵")
    }

    func testPercentileMetricDirections() {
        let points = (1...10).map { PEPoint(date: String(format: "2025-01-%02d", $0), pe: Double($0)) }
        let series = PESeries(meta: meta(), points: points)
        let cape = ValuationEngine.percentileMetric(name: "Shiller CAPE 分位", series: series,
                                                    unit: "", direction: .higherExpensive, note: "n")
        XCTAssertEqual(cape?.direction, .higherExpensive, "CAPE 分位越高越贵，与主分数同向")
        XCTAssertEqual(cape?.valueText, "10.00")
        let div = ValuationEngine.percentileMetric(name: "股息率分位", series: series,
                                                   unit: "%", direction: .higherCheaper, note: "n")
        XCTAssertEqual(div?.direction, .higherCheaper, "股息率分位越高越便宜")
        XCTAssertEqual(div?.valueText, "10.00%")
    }

    // MARK: 黄金ETF 自身法B 路径

    // 引擎测试用合成标的，不依赖目录（目录增删不应让引擎测试崩溃）；
    // 目录本身的形态由 testGoldETFCatalogShape 单独校验。
    private func goldETF() -> MarketTarget {
        MarketTarget(id: "testGold", name: "黄金ETF", kind: .etf, market: .cn, currency: .cny,
                     method: .pricePosition, rationale: "黄金无盈利，PE 不适用",
                     tencentSymbol: "sh518880", fundCode: "518880")
    }

    private func risingPriceSeries() -> PriceSeries {
        let bars = (0..<100).map {
            PriceBar(date: String(format: "2026-04-%02d", $0 % 28 + 1),
                     open: 1, close: Double($0), high: 1, low: 1, volume: 1)
        }
        return PriceSeries(meta: meta(), bars: bars)
    }

    func testETFScorePrefersUnderlying() throws {
        let underlying = ValuationResult(score: 42, zone: .fair, method: .fundamentals,
                                         confidence: .high, asOfDate: "2026-07-29", note: "底层")
        let etf = try XCTUnwrap(TargetCatalog.target(id: "sh510880"), "红利ETF 必须在目录中")
        let result = ValuationEngine.etfScore(target: etf, underlying: underlying, ownPrice: risingPriceSeries())
        XCTAssertEqual(result?.score ?? -1, 42, "有底层评分时必须用底层，不得用自身价格")
    }

    func testGoldETFScoresOnOwnPrice() {
        let result = ValuationEngine.etfScore(target: goldETF(), underlying: nil, ownPrice: risingPriceSeries())
        XCTAssertNotNil(result, "黄金ETF 无底层，必须用自身市价跑法B")
        XCTAssertEqual(result?.method, .pricePosition)
        // 单调上升序列的最新价 → 最高分位
        XCTAssertEqual(result?.zone, .veryHigh)
    }

    func testGoldETFWithoutPriceReturnsNil() {
        XCTAssertNil(ValuationEngine.etfScore(target: goldETF(), underlying: nil, ownPrice: nil))
    }

    func testFundamentalsETFWithoutUnderlyingNeverFallsBackToOwnPrice() throws {
        // 法A ETF 底层缺失时宁可无分，也不能用自身价格冒充基本面评分
        var etf = try XCTUnwrap(TargetCatalog.target(id: "sh510880"), "红利ETF 必须在目录中")
        etf.underlyingTargetID = nil
        XCTAssertNil(ValuationEngine.etfScore(target: etf, underlying: nil, ownPrice: risingPriceSeries()))
    }

    // MARK: 目录中的黄金ETF 定义

    func testGoldETFCatalogShape() throws {
        let gold = try XCTUnwrap(TargetCatalog.target(id: "sh518880"), "黄金ETF 必须在目录中")
        XCTAssertNil(gold.underlyingTargetID)
        XCTAssertEqual(gold.method, .pricePosition)
        XCTAssertEqual(gold.kind, .etf)
        XCTAssertNotNil(gold.tencentSymbol)
        XCTAssertNotNil(gold.fundCode)
        XCTAssertTrue(gold.rationale.contains("PE 不适用"), "rationale 必须写明黄金无盈利、PE 不适用")
    }
}
