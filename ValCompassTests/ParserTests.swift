import XCTest
@testable import ValCompass

/// 各数据源解析器测试（全部离线，fixture 为真实抓取响应）
final class ParserTests: XCTestCase {

    // 腾讯 A股指数（day 键）
    func testTencentAShareIndex() throws {
        let bars = try TencentKlineParser.parse(try Fixtures.data("tencent_sh000300.json"), symbol: "sh000300")
        XCTAssertEqual(bars.count, 39)
        XCTAssertEqual(bars.first?.date, "2025-06-03")
        XCTAssertEqual(bars.last?.date, "2025-07-25")
        XCTAssertEqual(bars.first?.open ?? 0, 3833.46, accuracy: 1e-6)
        XCTAssertEqual(bars.first?.close ?? 0, 3852.01, accuracy: 1e-6)
        XCTAssertEqual(bars.last?.close ?? 0, 4127.16, accuracy: 1e-6)
        XCTAssertEqual(bars.last?.volume ?? 0, 273594963, accuracy: 1)
    }

    // 腾讯港股指数（day 键，HKD 大成交量）
    func testTencentHKIndex() throws {
        let bars = try TencentKlineParser.parse(try Fixtures.data("tencent_hkHSI.json"), symbol: "hkHSI")
        XCTAssertEqual(bars.count, 39)
        XCTAssertEqual(bars.first?.date, "2025-06-02")
        XCTAssertEqual(bars.last?.date, "2025-07-25")
        XCTAssertEqual(bars.first?.close ?? 0, 23157.97, accuracy: 1e-6)
        XCTAssertEqual(bars.last?.close ?? 0, 25388.35, accuracy: 1e-6)
    }

    // 腾讯 ETF（qfqday 键）
    func testTencentETFUsesQfqdayKey() throws {
        let bars = try TencentKlineParser.parse(try Fixtures.data("tencent_sh510300.json"), symbol: "sh510300")
        XCTAssertEqual(bars.count, 39)
        XCTAssertEqual(bars.first?.date, "2025-06-03")
        XCTAssertEqual(bars.last?.date, "2025-07-25")
        XCTAssertEqual(bars.first?.close ?? 0, 3.746, accuracy: 1e-6)
        XCTAssertEqual(bars.last?.close ?? 0, 4.08, accuracy: 1e-6)
    }

    // 腾讯异常响应
    func testTencentBadResponse() {
        XCTAssertThrowsError(try TencentKlineParser.parse(Data("{}".utf8), symbol: "sh000300"))
        XCTAssertThrowsError(try TencentKlineParser.parse(Data(#"{"data":{"sh000300":{"day":[]}}}"#.utf8), symbol: "sh000300"))
    }

    // 新浪 JSONP（剥前缀与 x() 后缀）
    func testSinaJSONP() throws {
        let bars = try SinaUSParser.parse(try Fixtures.data("sina_INX.jsonp"))
        XCTAssertEqual(bars.count, 5680)
        XCTAssertEqual(bars.first?.date, "2004-01-02")
        XCTAssertEqual(bars.first?.close ?? 0, 1108.48, accuracy: 1e-6)
        XCTAssertEqual(bars.last?.date, "2026-07-28")
        XCTAssertEqual(bars.last?.close ?? 0, 7428.78, accuracy: 1e-6)
        // 抽样中间点
        let covid = bars.first { $0.date == "2020-03-23" }
        XCTAssertEqual(covid?.close ?? 0, 2237.4, accuracy: 1e-6)
    }

    // 中证 PE（peg 字段即官方市盈率）
    func testCSIndexPE() throws {
        let points = try CSIndexParser.parse(try Fixtures.data("csindex_000300.json"))
        XCTAssertEqual(points.count, 2692)
        XCTAssertEqual(points.first?.date, "2015-07-01")
        XCTAssertEqual(points.last?.date, "2026-07-29")
        let bottom = points.first { $0.date == "2018-12-28" }
        XCTAssertEqual(bottom?.pe ?? 0, 10.71, accuracy: 1e-6)
        let top = points.first { $0.date == "2021-02-10" }
        XCTAssertEqual(top?.pe ?? 0, 19.09, accuracy: 1e-6)
    }

    // 天天基金净值 JS（BOM + 两个数组）
    func testEastmoneyFund() throws {
        let fund = try EastmoneyFundParser.parse(try Fixtures.data("eastmoney_510300.js"))
        XCTAssertEqual(fund.fundName, "沪深300ETF华泰柏瑞")
        XCTAssertEqual(fund.points.count, 3460)
        XCTAssertEqual(fund.points.first?.date, "2012-05-04")
        XCTAssertEqual(fund.points.first?.unitNav ?? 0, 1.007, accuracy: 1e-6)
        XCTAssertEqual(fund.points.first?.accumulatedNav ?? 0, 1.007, accuracy: 1e-6)
        XCTAssertEqual(fund.points.last?.date, "2026-07-29")
        XCTAssertEqual(fund.points.last?.unitNav ?? 0, 4.6568, accuracy: 1e-6)
        XCTAssertEqual(fund.points.last?.accumulatedNav ?? 0, 2.0539, accuracy: 1e-6)
    }

    // multpl 标普500 PE（HTML 表格，值单元格含 &#x2002; 与换行）
    func testMultplSPXPE() throws {
        let points = try MultplParser.parse(try Fixtures.data("multpl_spx_pe.html"))
        XCTAssertGreaterThan(points.count, 1000) // 自 1871 年起的月度数据
        XCTAssertEqual(points.first?.date, "1871-01-01")
        // 升序：最后一条最新
        XCTAssertEqual(points.last?.date, "2026-07-28")
        let jul2025 = points.first { $0.date == "2025-07-01" }
        XCTAssertEqual(jul2025?.pe ?? 0, 27.81, accuracy: 1e-6)
        // 近 10 年月度窗口约 120 个点
        let recent = points.filter { $0.date >= "2016-07-01" }
        XCTAssertGreaterThanOrEqual(recent.count, 120)
    }

    func testMultplShillerPE() throws {
        let points = try MultplParser.parse(try Fixtures.data("multpl_shiller_pe.html"))
        XCTAssertGreaterThan(points.count, 1000)
        XCTAssertEqual(points.first?.date, "1871-02-01")
    }

    // multpl 标普500 股息率（结构与 PE 表相同，值带 % 号；日期为月末）
    // 注意：页面顶部除了当月正式行还有一个当日估计行（†），翻转后估计行在最后，
    // 因此序列大体升序但当月有两行——与 PE 表现状一致，消费方取 last 即最新值。
    func testMultplDividendYield() throws {
        let points = try MultplParser.parse(try Fixtures.data("multpl_spx_dividend_yield.html"))
        XCTAssertGreaterThan(points.count, 1000)
        XCTAssertEqual(points.first?.date, "1871-01-31")
        XCTAssertEqual(points.first?.pe ?? 0, 5.86, accuracy: 1e-6) // 值字段即股息率百分数
        XCTAssertEqual(points.last?.date, "2026-07-29")
        XCTAssertEqual(points.last?.pe ?? 0, 1.10, accuracy: 1e-6)  // % 号已剥离
        // 历史锚点：2020-04 疫情期股息率冲高
        let apr2020 = points.first { $0.date == "2020-04-30" }
        XCTAssertEqual(apr2020?.pe ?? 0, 2.16, accuracy: 1e-6)
    }

    // 东方财富 10 年期国债收益率（字段锚点已用历史值验证）
    func testTreasuryYield() throws {
        let page = try TreasuryYieldParser.parse(try Fixtures.data("eastmoney_treasury_yield.json"))
        XCTAssertEqual(page.points.count, 4000) // fixture 合并了第 1–8 页真实数据
        XCTAssertGreaterThan(page.pages, 1)     // 服务端 pageSize 上限 500，必须翻页
        // 升序
        XCTAssertEqual(page.points.map(\.date), page.points.map(\.date).sorted())
        // 历史锚点：EMM00166466=中国10Y、EMG00001310=美国10Y
        let jan2018 = page.points.first { $0.date == "2018-01-02" }
        XCTAssertEqual(jan2018?.cn10y ?? 0, 3.9, accuracy: 0.15)
        let apr2020 = page.points.first { $0.date == "2020-04-01" }
        XCTAssertEqual(apr2020?.cn10y ?? 0, 2.51, accuracy: 0.1)
        XCTAssertEqual(apr2020?.us10y ?? 0, 0.75, accuracy: 0.2)
        let dec2024 = page.points.first { $0.date == "2024-12-02" }
        XCTAssertEqual(dec2024?.cn10y ?? 0, 1.98, accuracy: 0.15)
        XCTAssertEqual(dec2024?.us10y ?? 0, 4.55, accuracy: 0.4)
        // 美国收益率允许为 null（美方假日/发布滞后），解析不得丢行
        XCTAssertTrue(page.points.contains { $0.us10y == nil && $0.cn10y != nil })
    }

    func testTreasuryYieldBadResponse() {
        XCTAssertThrowsError(try TreasuryYieldParser.parse(Data("{}".utf8)))
        XCTAssertThrowsError(try TreasuryYieldParser.parse(
            Data(#"{"success":true,"result":{"pages":1,"data":[]}}"#.utf8)))
    }
}
