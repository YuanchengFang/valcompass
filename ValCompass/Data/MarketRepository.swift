import Foundation
import SwiftUI

// MARK: - 单个标的的快照（调试 UI 直接消费）

enum SnapshotStatus: Equatable, Sendable {
    case loading
    case ok
    case stale          // 数据过期（显式状态，不静默沿用）
    case refreshFailed  // 刷新失败，展示缓存
    case noData         // 无缓存且无网络
}

struct TargetSnapshot: Identifiable, Equatable, Sendable {
    var id: String
    var status: SnapshotStatus = .loading
    var statusDetail: String = ""
    var result: ValuationResult?
    var latestValueText: String = ""   // 最新点位/市价
    var asOfText: String = ""          // 数据所属日期
    var freshness: Freshness?
    var premium: Double?               // ETF 溢折价率
    var premiumText: String = ""
    var secondaryMetrics: [SecondaryMetric] = []  // 其他视角（不并入主分数）

    // 数据溯源（不直接展示，用于重算新鲜度与「抓取于 X」文案）。
    // 摘要缓存只落盘这三项，状态与新鲜度一律按当下时间重算，
    // 否则昨天存下的「最新」明天读出来还是「最新」，等于静默沿用过期数据。
    var quoteAsOf: String?             // 行情/市价数据日期（按交易日判过期）
    var fundamentalAsOf: String?       // PE/净值数据日期（按自然日判过期）
    var fetchedAt: Date?               // 原始数据抓取时间
}

// MARK: - 原始序列集合

/// 内存中的全部原始序列。值类型，因此可以整份搬到后台线程算快照。
struct SeriesStore: Sendable {
    var price: [String: PriceSeries] = [:]
    var pe: [String: PESeries] = [:]
    var nav: [String: FundNavSeries] = [:]
    var yields: YieldSeries?           // 中/美 10Y 国债收益率（ERP 用）
}

/// 快照计算的中间产物：ETF 的评分与「其他视角」都复用底层指数的结果，
/// 因此必须按「先指数、后 ETF」的顺序算，并把中间结果带在上下文里。
struct SnapshotContext: Sendable {
    var underlyingResults: [String: ValuationResult] = [:]
    var secondaryByTarget: [String: [SecondaryMetric]] = [:]
}

// MARK: - 列表摘要缓存

/// 点亮总览列表所需的最小信息（37 条约几 KB）。
/// 启动时同步解这一个文件，首帧就能显示分数，不必等十几 MB 原始序列解码完。
/// 有意不落盘的两项：
/// - status / freshness：与「当前时间」相关，必须按 asOf 日期在恢复时重算。
/// - secondaryMetrics：依赖完整序列，后台把序列读完会自然补上。
struct SnapshotSummary: Codable, Sendable {
    var id: String
    var result: ValuationResult?
    var latestValueText: String
    var asOfText: String
    var premium: Double?
    var premiumText: String
    var quoteAsOf: String?
    var fundamentalAsOf: String?
    var fetchedAt: Date?

    init(_ snap: TargetSnapshot) {
        id = snap.id
        result = snap.result
        latestValueText = snap.latestValueText
        asOfText = snap.asOfText
        premium = snap.premium
        premiumText = snap.premiumText
        quoteAsOf = snap.quoteAsOf
        fundamentalAsOf = snap.fundamentalAsOf
        fetchedAt = snap.fetchedAt
    }

    /// 还原成快照。状态与新鲜度不取缓存值，交给调用方按当下时间重算。
    func snapshot() -> TargetSnapshot {
        var snap = TargetSnapshot(id: id)
        snap.status = .ok
        snap.result = result
        snap.latestValueText = latestValueText
        snap.asOfText = asOfText
        snap.premium = premium
        snap.premiumText = premiumText
        snap.quoteAsOf = quoteAsOf
        snap.fundamentalAsOf = fundamentalAsOf
        snap.fetchedAt = fetchedAt
        return snap
    }
}

// MARK: - 仓库：缓存优先，后台刷新

@Observable
@MainActor
final class MarketRepository {
    private(set) var snapshots: [TargetSnapshot]
    private(set) var isRefreshing = false

    private let fetcher: MarketDataFetcher
    private let cache: CacheStore

    /// 内存中的原始序列（ETF 需要取底层指数评分）
    private var series = SeriesStore()
    /// 底层指数结果与辅助指标，供 ETF 复用
    private var context = SnapshotContext()

    init(fetcher: MarketDataFetcher = MarketDataFetcher(client: HTTPClient()), cache: CacheStore = CacheStore()) {
        self.fetcher = fetcher
        self.cache = cache
        self.snapshots = TargetCatalog.all.map { TargetSnapshot(id: $0.id) }
    }

    /// 启动：先用摘要缓存点亮列表（同步，只解几 KB），再后台读原始序列，最后联网刷新。
    ///
    /// 后两段都不能压在首帧之前：`.task` 在首帧提交前执行，任何同步重活都会把系统启动屏
    /// 一直挂住——十几 MB 原始序列的解码加 37 个标的的全量分位计算实测约 0.6s（模拟器），
    /// 真机更久，正是启动白屏的主因。
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        restoreFromSummary()
        // 启动即置刷新中：首次安装时后台读缓存会把全部标的判成「暂无数据」，
        // 若此刻 isRefreshing 还是 false，空态（无网络提示）会在联网刷新开始前闪一下。
        isRefreshing = true
        Task { await loadSeriesThenRefresh() }
    }

    private func loadSeriesThenRefresh() async {
        await loadAllFromCache()
        await refreshAll()
    }

    // MARK: 详情页只读访问（原始序列）

    func priceSeries(for id: String) -> PriceSeries? { series.price[id] }
    func peSeries(for id: String) -> PESeries? { series.pe[id] }
    func navSeries(for id: String) -> FundNavSeries? { series.nav[id] }
    func yieldSeries() -> YieldSeries? { series.yields }
    /// 标普500 Shiller PE / 股息率（月度，仅 spx 详情页溯源用）
    func spxShillerPE() -> PESeries? { series.pe[CacheStore.spxShillerPEKey()] }
    func spxDividendYield() -> PESeries? { series.pe[CacheStore.spxDividendYieldKey()] }

    /// 全库最近一次抓取时间（取各序列 meta.fetchedAt 的最大值）。
    /// 原始序列尚未读完时退回摘要里的抓取时间，免得顶部时间戳先空一下再跳出来。
    var lastUpdatedAt: Date? {
        var dates = series.price.values.map(\.meta.fetchedAt)
        dates += series.pe.values.map(\.meta.fetchedAt)
        dates += series.nav.values.map(\.meta.fetchedAt)
        if let y = series.yields { dates.append(y.meta.fetchedAt) }
        if dates.isEmpty { return snapshots.compactMap(\.fetchedAt).max() }
        return dates.max()
    }

    private var hasStarted = false

    // MARK: 缓存

    /// 摘要缓存 → 列表。同步执行（几 KB，约 1ms），因此首帧就有分数可看。
    private func restoreFromSummary() {
        guard let summaries = cache.loadSummary() else { return }
        let now = Date()
        for summary in summaries {
            guard let target = TargetCatalog.target(id: summary.id) else { continue }
            var snap = summary.snapshot()
            Self.applyFreshness(to: &snap, kind: target.kind, now: now)
            Self.applyCacheStatus(to: &snap, fromCache: true)
            update(summary.id) { $0 = snap }
        }
    }

    /// 后台读全部原始序列并整批重算快照，算完一次性回主线程赋值。
    private func loadAllFromCache() async {
        let cache = self.cache
        let now = Date()
        let loaded = await Task.detached(priority: .userInitiated) {
            let series = cache.loadAllSeries(targets: TargetCatalog.all)
            return (series, Self.buildAllSnapshots(series: series, now: now, fromCache: true))
        }.value
        series = loaded.0
        context = loaded.1.context
        for snap in loaded.1.snapshots {
            update(snap.id) { $0 = snap }
        }
        saveSummary()
    }

    // MARK: 刷新

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let targets = TargetCatalog.all
        // 先刷非 ETF（含 ETF 的底层标的），ETF 依赖其结果
        let nonETF = targets.filter { $0.kind == .index }
        let etfs = targets.filter { $0.kind == .etf }
        await withTaskGroup(of: Void.self) { group in
            for t in nonETF {
                group.addTask { await self.refreshIndex(t) }
            }
            // 辅助数据独立抓取：失败只影响「其他视角」，不拖垮任何标的评分
            group.addTask { await self.refreshAuxiliaryData() }
        }
        await withTaskGroup(of: Void.self) { group in
            for t in etfs {
                group.addTask { await self.refreshETF(t) }
            }
        }
        saveSummary()
    }

    private func refreshIndex(_ target: MarketTarget) async {
        // 行情与估值数据解耦抓取：单一源失败只降级对应部分，不拖垮整个标的
        var peS: PESeries?
        var priceS: PriceSeries?
        var peFailed = false
        var priceFailed = false

        switch (target.market, target.method) {
        case (.cn, .fundamentals):
            do { peS = try await fetcher.fetchCSIndexPE(indexCode: target.csindexCode!) }
            catch { peFailed = true }
            // 部分中证指数（如半导体 H30184）腾讯无报价：只取 PE，属预期降级
            if let symbol = target.tencentSymbol {
                do { priceS = try await fetcher.fetchTencentDaily(symbol: symbol, currency: target.currency) }
                catch { priceFailed = true }
            }
        case (.us, .fundamentals):
            // 标普500：multpl 提供 PE（月度），新浪提供日线点位（走势图用）
            do { peS = try await fetcher.fetchMultplPE() }
            catch { peFailed = true }
            do { priceS = try await fetcher.fetchSinaDaily(symbol: target.sinaSymbol!) }
            catch { priceFailed = true }
        case (.us, .pricePosition):
            do { priceS = try await fetcher.fetchSinaDaily(symbol: target.sinaSymbol!) }
            catch { priceFailed = true }
        case (.hk, _), (.cn, .pricePosition):
            do { priceS = try await fetcher.fetchTencentDaily(symbol: target.tencentSymbol!, currency: target.currency) }
            catch { priceFailed = true }
        }

        store(target: target, pe: peS, price: priceS)
        let needsPE = target.method == .fundamentals
        let coreFailed = (needsPE && peFailed && series.pe[target.id] == nil) || (!needsPE && priceFailed && series.price[target.id] == nil)
        let allFailed = (needsPE ? peFailed : true) && priceFailed
        if allFailed || (peS == nil && priceS == nil && series.pe[target.id] == nil && series.price[target.id] == nil) {
            markFailed(target.id, error: FetchError.httpStatus(0))
        } else {
            markRefreshed(target.id)
            if coreFailed || peFailed || priceFailed {
                let what = peFailed ? "估值数据" : "行情"
                update(target.id) { $0.statusDetail = "\(what)刷新失败，显示已有数据" }
            }
        }
    }

    private func refreshETF(_ target: MarketTarget) async {
        do {
            async let price = fetcher.fetchTencentDaily(symbol: target.tencentSymbol!, currency: target.currency)
            async let nav = fetcher.fetchFundNav(fundCode: target.fundCode!, isQDII: target.isQDII)
            let (priceS, navS) = try await (price, nav)
            storeETF(target: target, price: priceS, nav: navS)
            markRefreshed(target.id)
        } catch {
            markFailed(target.id, error: error)
        }
    }

    // MARK: 辅助数据（国债收益率 / 标普500 Shiller PE / 股息率）

    /// 只服务「其他视角」；失败静默降级（辅助指标不显示），保留缓存。
    private func refreshAuxiliaryData() async {
        do {
            let yields = try await fetcher.fetchTreasuryYields()
            series.yields = yields
            persist(yields, key: CacheStore.yieldKey())
        } catch { /* 辅助源失败：沿用缓存或隐藏辅助指标 */ }
        do {
            let shiller = try await fetcher.fetchMultplPE(shiller: true)
            series.pe[CacheStore.spxShillerPEKey()] = shiller
            persist(shiller, key: CacheStore.spxShillerPEKey())
        } catch { }
        do {
            let div = try await fetcher.fetchMultplDividendYield()
            series.pe[CacheStore.spxDividendYieldKey()] = div
            persist(div, key: CacheStore.spxDividendYieldKey())
        } catch { }
    }

    // MARK: 状态更新（主线程）

    // (类整体 @MainActor)
    private func store(target: MarketTarget, pe: PESeries?, price: PriceSeries?) {
        if let pe { series.pe[target.id] = pe; persist(pe, key: CacheStore.peKey(target.id)) }
        if let price { series.price[target.id] = price; persist(price, key: CacheStore.priceKey(target.id)) }
    }

    // (类整体 @MainActor)
    private func storeETF(target: MarketTarget, price: PriceSeries, nav: FundNavSeries) {
        series.price[target.id] = price; persist(price, key: CacheStore.priceKey(target.id))
        series.nav[target.id] = nav; persist(nav, key: CacheStore.navKey(target.id))
    }

    /// 落盘一律走后台：单条五千点序列编码加写盘约 5–10ms，37 个标的叠在主线程上会卡出顿挫。
    /// 缓存是尽力而为的，进程结束时没写完的那几条下次刷新会补上。
    private func persist<T: Encodable & Sendable>(_ value: T, key: String) {
        let cache = self.cache
        Task.detached(priority: .utility) { cache.save(value, key: key) }
    }

    /// 摘要缓存：整份重写（几 KB），缓存重算后与刷新收尾各存一次。
    private func saveSummary() {
        let summaries = snapshots.map(SnapshotSummary.init)
        let cache = self.cache
        Task.detached(priority: .utility) { cache.saveSummary(summaries) }
    }

    // (类整体 @MainActor)
    private func markRefreshed(_ id: String) {
        rebuildSnapshot(id: id, fromCache: false)
    }

    // (类整体 @MainActor)
    private func markFailed(_ id: String, error: Error) {
        let hasCache = series.price[id] != nil || series.pe[id] != nil || series.nav[id] != nil
        if hasCache {
            rebuildSnapshot(id: id, fromCache: true)
            update(id) { $0.status = .refreshFailed; $0.statusDetail = "刷新失败，展示缓存数据" }
        } else {
            update(id) { $0.status = .noData; $0.statusDetail = "暂无数据：网络请求失败" }
        }
    }

    // MARK: 快照计算

    private func rebuildSnapshot(id: String, fromCache: Bool) {
        guard let snap = Self.buildSnapshot(id: id, series: series, now: Date(),
                                            fromCache: fromCache, context: &context) else { return }
        update(id) { $0 = snap }
    }

    // 以下计算全是纯函数（`nonisolated`），只依赖传入的序列集合，
    // 因此启动时可以整批放到后台线程跑，不占首帧。

    /// 全量重算：先算全部非 ETF（填充底层结果），再算 ETF。
    nonisolated static func buildAllSnapshots(series: SeriesStore, now: Date, fromCache: Bool)
        -> (snapshots: [TargetSnapshot], context: SnapshotContext) {
        var context = SnapshotContext()
        var out: [TargetSnapshot] = []
        for t in TargetCatalog.all where t.kind == .index {
            if let snap = buildSnapshot(id: t.id, series: series, now: now, fromCache: fromCache, context: &context) {
                out.append(snap)
            }
        }
        for t in TargetCatalog.all where t.kind == .etf {
            if let snap = buildSnapshot(id: t.id, series: series, now: now, fromCache: fromCache, context: &context) {
                out.append(snap)
            }
        }
        return (out, context)
    }

    nonisolated static func buildSnapshot(id: String, series: SeriesStore, now: Date,
                                         fromCache: Bool, context: inout SnapshotContext) -> TargetSnapshot? {
        guard let target = TargetCatalog.target(id: id) else { return nil }
        var snap = TargetSnapshot(id: id)
        snap.status = .ok

        switch target.kind {
        case .index:
            buildIndexSnapshot(target: target, snap: &snap, series: series, context: &context)
        case .etf:
            buildETFSnapshot(target: target, snap: &snap, series: series, context: context)
        }

        // 「抓取于」按 PE → 行情 → 净值 取第一个可用的（与各标的主数据源一致）
        snap.fetchedAt = series.pe[id]?.meta.fetchedAt
            ?? series.price[id]?.meta.fetchedAt
            ?? series.nav[id]?.meta.fetchedAt
        applyFreshness(to: &snap, kind: target.kind, now: now)
        applyCacheStatus(to: &snap, fromCache: fromCache)
        return snap
    }

    /// 按 asOf 日期重算新鲜度与状态。首次计算与摘要缓存恢复共用同一判据，
    /// 两条路径因此不会漂移出「缓存里写着最新、其实已过期」这种偏差。
    nonisolated static func applyFreshness(to snap: inout TargetSnapshot, kind: AssetKind, now: Date) {
        switch kind {
        case .index:
            // 指数只有一个数据源参与判定：法A 看 PE（自然日），法B 或 PE 缺失时看行情（交易日）
            if let asOf = snap.fundamentalAsOf.flatMap(DateUtil.date) {
                snap.freshness = ValuationEngine.fundamentalFreshness(asOf: asOf, now: now)
            } else if let asOf = snap.quoteAsOf.flatMap(DateUtil.date) {
                snap.freshness = ValuationEngine.quoteFreshness(asOf: asOf, now: now)
            }
            if snap.freshness == .stale {
                snap.status = .stale
                snap.statusDetail = "数据已过期"
            }
        case .etf:
            // 行情与净值各判一次，净值放后面：两者都过期时以更该被看见的净值提示为准。
            // 这里有意不写 snap.freshness——ETF 无评分时要落到「暂无数据」，
            // 而 freshness 非空会让它被当成有数据。
            if let asOf = snap.quoteAsOf.flatMap(DateUtil.date),
               ValuationEngine.quoteFreshness(asOf: asOf, now: now) == .stale {
                snap.status = .stale
                snap.statusDetail = "行情已过期"
            }
            if let asOf = snap.fundamentalAsOf.flatMap(DateUtil.date),
               ValuationEngine.fundamentalFreshness(asOf: asOf, now: now) == .stale {
                snap.status = .stale
                snap.statusDetail = "净值已过期"
            }
        }
    }

    /// 无数据与「展示缓存」两种收尾状态。缓存文案会盖掉过期文案，但 status 仍是 .stale。
    nonisolated static func applyCacheStatus(to snap: inout TargetSnapshot, fromCache: Bool) {
        if snap.result == nil && snap.freshness == nil {
            snap.status = .noData
            snap.statusDetail = "暂无数据"
        } else if fromCache {
            snap.statusDetail = "缓存数据，抓取于 \(formatTime(snap.fetchedAt))"
        }
    }

    nonisolated static func buildIndexSnapshot(target: MarketTarget, snap: inout TargetSnapshot,
                                              series: SeriesStore, context: inout SnapshotContext) {
        var result: ValuationResult?

        if target.method == .fundamentals {
            if let peS = series.pe[target.id] {
                result = ValuationEngine.evaluateFundamentals(peSeries: peS)
                if result == nil, let priceS = series.price[target.id] {
                    // PE≤0 回退法B
                    result = ValuationEngine.evaluatePricePosition(priceSeries: priceS)
                    if result != nil {
                        result!.note = ValuationEngine.peNotApplicableNote + "。" + result!.note
                    }
                }
                if let asOf = peS.asOfDate, DateUtil.date(asOf) != nil {
                    snap.fundamentalAsOf = asOf
                    snap.asOfText = "PE 截至 \(asOf)"
                }
            } else if let priceS = series.price[target.id] {
                // PE 序列缺失（获取失败）：只展示行情，不用价格法冒充基本面评分
                if let asOf = priceS.asOfDate, DateUtil.date(asOf) != nil {
                    snap.quoteAsOf = asOf
                    snap.asOfText = "收盘 \(asOf)"
                }
            }
        } else if let priceS = series.price[target.id] {
            result = ValuationEngine.evaluatePricePosition(priceSeries: priceS)
            if let asOf = priceS.asOfDate, DateUtil.date(asOf) != nil {
                snap.quoteAsOf = asOf
                snap.asOfText = "收盘 \(asOf)"
            }
        }

        if let priceS = series.price[target.id], let last = priceS.bars.last {
            // 指数是点位不是货币金额；ETF 市价才带币种
            snap.latestValueText = target.kind == .index
                ? String(format: "%.2f 点", last.close)
                : String(format: "%.2f %@", last.close, target.currency.rawValue)
        } else if let peS = series.pe[target.id], let last = peS.points.last {
            snap.latestValueText = String(format: "PE %.1f", last.pe)
        }
        snap.result = result
        // 记录评分供 ETF 复用（ETF 评分 = 底层指数评分）
        context.underlyingResults[target.id] = result
        // 其他视角：辅助指标（不并入主分数）
        snap.secondaryMetrics = buildSecondaryMetrics(for: target, series: series)
        context.secondaryByTarget[target.id] = snap.secondaryMetrics
    }

    /// 辅助估值指标：法A 标的给 ERP；spx 追加 CAPE 与股息率分位；法B 标的无。
    nonisolated static func buildSecondaryMetrics(for target: MarketTarget, series: SeriesStore) -> [SecondaryMetric] {
        guard target.method == .fundamentals else { return [] }
        var metrics: [SecondaryMetric] = []
        switch target.market {
        case .cn:
            if let peS = series.pe[target.id], let yields = series.yields {
                let erp = ValuationEngine.erpSeriesDaily(pe: peS.points, yields: yields.points, yieldOf: \.cn10y)
                if let m = ValuationEngine.erpMetric(erpSeries: erp) { metrics.append(m) }
            }
        case .us:
            // 标普500：ERP（月度 PE × 月末美债 10Y）+ Shiller CAPE 分位 + 股息率分位
            if let peS = series.pe[target.id], let yields = series.yields {
                let erp = ValuationEngine.erpSeriesMonthly(pe: peS.points, yields: yields.points, yieldOf: \.us10y)
                if let m = ValuationEngine.erpMetric(erpSeries: erp) { metrics.append(m) }
            }
            if let shiller = series.pe[CacheStore.spxShillerPEKey()],
               let m = ValuationEngine.percentileMetric(
                    name: "Shiller CAPE 分位", series: shiller, unit: "",
                    direction: .higherExpensive,
                    note: "CAPE 用 10 年均通胀调整盈利平滑周期；月度数据。分位越高越贵（与主分数同向）。") {
                metrics.append(m)
            }
            if let div = series.pe[CacheStore.spxDividendYieldKey()],
               let m = ValuationEngine.percentileMetric(
                    name: "股息率分位", series: div, unit: "%",
                    direction: .higherCheaper,
                    note: "标普500 股息率（月度）。分位越高越便宜（与主分数方向相反）。") {
                metrics.append(m)
            }
        case .hk:
            break
        }
        return metrics
    }

    nonisolated static func buildETFSnapshot(target: MarketTarget, snap: inout TargetSnapshot,
                                             series: SeriesStore, context: SnapshotContext) {
        // 评分 = 底层指数评分；无底层且法B（黄金ETF）时用自身市价跑价格位置
        snap.result = ValuationEngine.etfScore(
            target: target,
            underlying: target.underlyingTargetID.flatMap { context.underlyingResults[$0] },
            ownPrice: series.price[target.id])
        // 其他视角：跟随底层指数的辅助指标
        if let underlyingID = target.underlyingTargetID {
            snap.secondaryMetrics = context.secondaryByTarget[underlyingID] ?? []
        }
        // 溢折价 = 最新市价 / 最新单位净值 − 1（单位净值，非累计净值）
        if let priceS = series.price[target.id], let lastBar = priceS.bars.last {
            snap.latestValueText = String(format: "%.3f %@", lastBar.close, target.currency.rawValue)
            snap.asOfText = "市价 \(lastBar.date)"
            snap.quoteAsOf = lastBar.date
        }
        if let navS = series.nav[target.id], let lastNav = navS.points.last,
           let lastBar = series.price[target.id]?.bars.last,
           let p = ValuationEngine.premium(price: lastBar.close, unitNav: lastNav.unitNav) {
            snap.premium = p
            snap.premiumText = ValuationEngine.premiumNote(p, isQDII: target.isQDII)
            snap.asOfText += "｜净值 \(lastNav.date)\(target.isQDII ? "（QDII 滞后）" : "")"
            snap.fundamentalAsOf = lastNav.date
        }
    }

    nonisolated static func formatTime(_ fetchedAt: Date?) -> String {
        guard let fetchedAt else { return "未知时间" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: fetchedAt)
    }

    private func update(_ id: String, _ mutate: (inout TargetSnapshot) -> Void) {
        guard let idx = snapshots.firstIndex(where: { $0.id == id }) else { return }
        mutate(&snapshots[idx])
    }
}
