import XCTest
@testable import ValCompass

/// 摘要缓存与快照重算测试。
///
/// 这批函数在启动优化里从实例方法改成了 `nonisolated static` 纯函数（为了能整批搬到
/// 后台线程），副产物是可以脱开 app 直接测。覆盖两件事：
/// 1. 新鲜度改为「只落盘 asOf、恢复时按当下时间重算」之后判据是否仍然正确；
/// 2. 摘要缓存的编解码与版本失配处理——它决定首帧能不能点亮。
final class SnapshotCacheTests: XCTestCase {

    private func meta(fetchedAt: Date = Date()) -> SeriesMeta {
        SeriesMeta(source: .tencent, fetchedAt: fetchedAt, currency: .cny, isMonthly: false, isDelayed: false)
    }

    private func day(_ s: String) -> Date { DateUtil.date(s)! }

    private func fairResult(asOf: String) -> ValuationResult {
        ValuationResult(score: 50, zone: .fair, method: .fundamentals,
                        confidence: .high, asOfDate: asOf, note: "测试")
    }

    // MARK: 新鲜度重算

    /// PE/净值：超过 10 个自然日未更新即过期
    func testIndexFundamentalStalePast10NaturalDays() {
        var snap = TargetSnapshot(id: "sh000300")
        snap.status = .ok
        snap.fundamentalAsOf = "2026-07-01"
        MarketRepository.applyFreshness(to: &snap, kind: .index, now: day("2026-08-04"))
        XCTAssertEqual(snap.freshness, .stale)
        XCTAssertEqual(snap.status, .stale)
        XCTAssertEqual(snap.statusDetail, "数据已过期")
    }

    func testIndexFundamentalFreshWithinWindow() {
        var snap = TargetSnapshot(id: "sh000300")
        snap.status = .ok
        snap.fundamentalAsOf = "2026-08-01"
        MarketRepository.applyFreshness(to: &snap, kind: .index, now: day("2026-08-04"))
        XCTAssertEqual(snap.freshness, .fresh)
        XCTAssertEqual(snap.status, .ok)
        XCTAssertEqual(snap.statusDetail, "")
    }

    /// 法A 标的抓 PE 失败时才退到行情判定（交易日口径）
    func testIndexFallsBackToQuoteWhenFundamentalMissing() {
        var snap = TargetSnapshot(id: "sh000300")
        snap.status = .ok
        snap.quoteAsOf = "2026-08-03"
        MarketRepository.applyFreshness(to: &snap, kind: .index, now: day("2026-08-04"))
        XCTAssertEqual(snap.freshness, .fresh)
    }

    /// 两个日期都在时以 PE 为准：法A 标的的过期与否由基本面数据决定，不看行情
    func testIndexPrefersFundamentalOverQuote() {
        var snap = TargetSnapshot(id: "sh000300")
        snap.status = .ok
        snap.fundamentalAsOf = "2026-08-01"   // 新
        snap.quoteAsOf = "2026-01-01"         // 旧到该判过期
        MarketRepository.applyFreshness(to: &snap, kind: .index, now: day("2026-08-04"))
        XCTAssertEqual(snap.freshness, .fresh)
        XCTAssertEqual(snap.status, .ok)
    }

    /// ETF 有意不写 freshness：无评分时要落到「暂无数据」，
    /// freshness 非空会让 applyCacheStatus 把它当成有数据。
    func testETFLeavesFreshnessNilByDesign() {
        var snap = TargetSnapshot(id: "sh513100")
        snap.status = .ok
        snap.quoteAsOf = "2026-08-03"
        snap.fundamentalAsOf = "2026-08-03"
        MarketRepository.applyFreshness(to: &snap, kind: .etf, now: day("2026-08-04"))
        XCTAssertNil(snap.freshness)
        XCTAssertEqual(snap.status, .ok)
    }

    func testETFStaleQuoteIsReported() {
        var snap = TargetSnapshot(id: "sh513100")
        snap.status = .ok
        snap.quoteAsOf = "2026-07-01"        // 远超 5 个交易日
        snap.fundamentalAsOf = "2026-08-03"  // 净值是新的
        MarketRepository.applyFreshness(to: &snap, kind: .etf, now: day("2026-08-04"))
        XCTAssertEqual(snap.status, .stale)
        XCTAssertEqual(snap.statusDetail, "行情已过期")
        XCTAssertNil(snap.freshness)
    }

    /// 行情与净值都过期时以净值文案为准（净值判定放在后面，有意覆盖）
    func testETFStaleNavOverridesQuoteMessage() {
        var snap = TargetSnapshot(id: "sh513100")
        snap.status = .ok
        snap.quoteAsOf = "2026-07-01"
        snap.fundamentalAsOf = "2026-07-01"
        MarketRepository.applyFreshness(to: &snap, kind: .etf, now: day("2026-08-04"))
        XCTAssertEqual(snap.status, .stale)
        XCTAssertEqual(snap.statusDetail, "净值已过期")
    }

    /// 无法解析的 asOf 不参与判定，也不能崩
    func testUnparsableAsOfIsIgnored() {
        var snap = TargetSnapshot(id: "sh000300")
        snap.status = .ok
        snap.fundamentalAsOf = "不是日期"
        MarketRepository.applyFreshness(to: &snap, kind: .index, now: day("2026-08-04"))
        XCTAssertNil(snap.freshness)
        XCTAssertEqual(snap.status, .ok)
    }

    // MARK: 收尾状态

    func testNoDataWhenNoResultAndNoFreshness() {
        var snap = TargetSnapshot(id: "sh000300")
        snap.status = .ok
        MarketRepository.applyCacheStatus(to: &snap, fromCache: true)
        XCTAssertEqual(snap.status, .noData)
        XCTAssertEqual(snap.statusDetail, "暂无数据")
    }

    /// 缓存文案会盖掉过期文案，但 status 必须仍是 .stale——详情页的过期横幅看的是 status
    func testCacheDetailDoesNotClearStaleStatus() {
        var snap = TargetSnapshot(id: "sh000300")
        snap.status = .stale
        snap.statusDetail = "数据已过期"
        snap.freshness = .stale
        snap.fetchedAt = day("2026-08-04")
        MarketRepository.applyCacheStatus(to: &snap, fromCache: true)
        XCTAssertEqual(snap.status, .stale)
        XCTAssertTrue(snap.statusDetail.hasPrefix("缓存数据，抓取于"),
                      "实际为 \(snap.statusDetail)")
    }

    // MARK: 摘要缓存

    /// 本次改动的核心不变式：同一份摘要在不同的「现在」下恢复，状态必须跟着变。
    /// 若把 status 也落盘，昨天存下的「最新」明天读出来还是「最新」，
    /// 就成了静默沿用过期数据。
    func testSameSummaryGoesStaleAsTimePasses() {
        var snap = TargetSnapshot(id: "sh000300")
        snap.result = fairResult(asOf: "2026-08-01")
        snap.fundamentalAsOf = "2026-08-01"
        let summary = SnapshotSummary(snap)

        var soon = summary.snapshot()
        MarketRepository.applyFreshness(to: &soon, kind: .index, now: day("2026-08-04"))
        XCTAssertEqual(soon.status, .ok)

        var later = summary.snapshot()
        MarketRepository.applyFreshness(to: &later, kind: .index, now: day("2026-09-04"))
        XCTAssertEqual(later.status, .stale)
    }

    func testSummaryRoundTripPreservesDisplayFields() throws {
        var snap = TargetSnapshot(id: "sh000300")
        snap.result = ValuationResult(score: 42.5, zone: .fair, method: .fundamentals,
                                      confidence: .high, asOfDate: "2026-08-01", note: "说明")
        snap.latestValueText = "3800.00 点"
        snap.asOfText = "PE 截至 2026-08-01"
        snap.premium = -0.0042
        snap.premiumText = "折价 0.42%"
        snap.quoteAsOf = "2026-08-02"
        snap.fundamentalAsOf = "2026-08-01"
        snap.fetchedAt = day("2026-08-04")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode([SnapshotSummary(snap)])
        let restored = try XCTUnwrap(decoder.decode([SnapshotSummary].self, from: data).first).snapshot()

        XCTAssertEqual(restored.result, snap.result)
        XCTAssertEqual(restored.latestValueText, snap.latestValueText)
        XCTAssertEqual(restored.asOfText, snap.asOfText)
        XCTAssertEqual(restored.premium, snap.premium)
        XCTAssertEqual(restored.premiumText, snap.premiumText)
        XCTAssertEqual(restored.quoteAsOf, snap.quoteAsOf)
        XCTAssertEqual(restored.fundamentalAsOf, snap.fundamentalAsOf)
        XCTAssertEqual(restored.fetchedAt, snap.fetchedAt)
        // 有意不落盘的三项：状态与新鲜度交给调用方按当下时间重算，
        // 辅助指标等后台把序列读完自然补上。
        XCTAssertEqual(restored.status, .ok)
        XCTAssertNil(restored.freshness)
        XCTAssertTrue(restored.secondaryMetrics.isEmpty)
    }

    private func tempCache() -> CacheStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vc-test-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return CacheStore(directory: dir)
    }

    func testSummaryRoundTripThroughCacheStore() throws {
        let cache = tempCache()
        var snap = TargetSnapshot(id: "ndx")
        snap.latestValueText = "20000.00 点"
        cache.saveSummary([SnapshotSummary(snap)])

        let loaded = try XCTUnwrap(cache.loadSummary())
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.latestValueText, "20000.00 点")
    }

    /// 版本失配必须当作「没有缓存」：`ValuationZone` 的 rawValue 就是中文展示文案，
    /// 改一次档位措辞旧文件就解不出来，宁可丢弃重建也不半信半疑地用。
    func testSummaryVersionMismatchIsDiscarded() {
        let cache = tempCache()
        var snap = TargetSnapshot(id: "ndx")
        snap.latestValueText = "20000.00 点"
        cache.save(SummaryFile(version: SummaryFile.currentVersion + 1,
                               items: [SnapshotSummary(snap)]),
                   key: CacheStore.summaryKey())
        XCTAssertNil(cache.loadSummary())
    }

    /// 内容对不上时同样只是「没有缓存」，不能抛也不能崩
    func testSummaryUndecodableFileIsDiscarded() {
        let cache = tempCache()
        cache.save(["这不是摘要文件"], key: CacheStore.summaryKey())
        XCTAssertNil(cache.loadSummary())
    }

    func testMissingSummaryReturnsNil() {
        XCTAssertNil(tempCache().loadSummary())
    }

    // MARK: 全量重算

    /// 生成连续自然日的日线。分位只看 close 的相对位置，不需要真实交易日历。
    private func priceSeries(endingAt endDate: String, days: Int,
                             start: Double, step: Double) -> PriceSeries {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let end = day(endDate)
        var bars: [PriceBar] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            let date = cal.date(byAdding: .day, value: -i, to: end)!
            let close = start + Double(days - 1 - i) * step
            bars.append(PriceBar(date: DateUtil.string(date), open: close, close: close,
                                 high: close, low: close, volume: 1))
        }
        return PriceSeries(meta: meta(), bars: bars)
    }

    /// ETF 的评分复用底层指数结果，因此必须「先指数后 ETF」。这个顺序由
    /// buildAllSnapshots 保证；一旦被改成单趟遍历，ETF 会拿不到底层结果而静默变成无评分。
    func testBuildAllSnapshotsFeedsETFFromUnderlyingIndex() throws {
        var store = SeriesStore()
        // 单调递增，因此最后一根收在最高位，分位 = 100 * 799/800
        store.price["ndx"] = priceSeries(endingAt: "2026-08-03", days: 800, start: 15000, step: 5)
        store.price["sh513100"] = PriceSeries(meta: meta(), bars: [
            PriceBar(date: "2026-08-03", open: 1.5, close: 1.53, high: 1.55, low: 1.49, volume: 1)
        ])
        store.nav["sh513100"] = FundNavSeries(meta: meta(), fundName: "纳指ETF", points: [
            FundNavPoint(date: "2026-08-03", unitNav: 1.5, accumulatedNav: nil)
        ])

        let built = MarketRepository.buildAllSnapshots(series: store,
                                                      now: day("2026-08-04"),
                                                      fromCache: true)
        let byID = Dictionary(uniqueKeysWithValues: built.snapshots.map { ($0.id, $0) })

        let underlying = try XCTUnwrap(byID["ndx"]?.result)
        XCTAssertEqual(try XCTUnwrap(underlying.score), 99.875, accuracy: 0.01)
        XCTAssertEqual(underlying.method, .pricePosition)
        XCTAssertEqual(built.context.underlyingResults["ndx"], underlying)

        // ETF 评分逐字段等于底层指数评分
        XCTAssertEqual(byID["sh513100"]?.result, underlying)
        // 溢折价用单位净值算：1.53 / 1.50 − 1 = 2%
        XCTAssertEqual(try XCTUnwrap(byID["sh513100"]?.premium), 0.02, accuracy: 1e-9)

        // 目录里每个标的都要有一条快照，否则列表会缺行
        XCTAssertEqual(built.snapshots.count, TargetCatalog.all.count)
        XCTAssertEqual(Set(byID.keys), Set(TargetCatalog.all.map(\.id)))
    }

    /// 无任何缓存时全部落到「暂无数据」，且不产生评分
    func testBuildAllSnapshotsWithEmptyStoreYieldsNoData() {
        let built = MarketRepository.buildAllSnapshots(series: SeriesStore(),
                                                      now: day("2026-08-04"),
                                                      fromCache: true)
        XCTAssertEqual(built.snapshots.count, TargetCatalog.all.count)
        XCTAssertTrue(built.snapshots.allSatisfy { $0.status == .noData })
        XCTAssertTrue(built.snapshots.allSatisfy { $0.result == nil })
    }

    /// 「抓取于」按 PE → 行情 → 净值 取第一个可用的，与各标的主数据源一致
    func testFetchedAtPrefersPEOverPrice() throws {
        let peTime = day("2026-08-04")
        let priceTime = day("2026-08-02")
        var store = SeriesStore()
        store.pe["sh000300"] = PESeries(meta: meta(fetchedAt: peTime),
                                        points: [PEPoint(date: "2026-08-03", pe: 12.5)])
        store.price["sh000300"] = PriceSeries(meta: meta(fetchedAt: priceTime), bars: [
            PriceBar(date: "2026-08-03", open: 3800, close: 3810, high: 3820, low: 3790, volume: 1)
        ])

        var context = SnapshotContext()
        let snap = try XCTUnwrap(MarketRepository.buildSnapshot(
            id: "sh000300", series: store, now: day("2026-08-04"),
            fromCache: true, context: &context))
        XCTAssertEqual(snap.fetchedAt, peTime)
    }
}
