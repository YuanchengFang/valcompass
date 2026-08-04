import Foundation
import SwiftUI

// MARK: - 单个标的的快照（调试 UI 直接消费）

enum SnapshotStatus: Equatable {
    case loading
    case ok
    case stale          // 数据过期（显式状态，不静默沿用）
    case refreshFailed  // 刷新失败，展示缓存
    case noData         // 无缓存且无网络
}

struct TargetSnapshot: Identifiable, Equatable {
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
}

// MARK: - 仓库：缓存优先，后台刷新

@Observable
@MainActor
final class MarketRepository {
    private(set) var snapshots: [TargetSnapshot]
    private(set) var isRefreshing = false

    private let fetcher: MarketDataFetcher
    private let cache: CacheStore

    // 内存中的原始序列（ETF 需要取底层指数评分）
    private var priceSeries: [String: PriceSeries] = [:]
    private var peSeries: [String: PESeries] = [:]
    private var navSeries: [String: FundNavSeries] = [:]
    private var treasuryYields: YieldSeries?   // 中/美 10Y 国债收益率（ERP 用）
    /// 底层标的 id -> 评分结果（供 ETF 复用）
    private var underlyingResults: [String: ValuationResult] = [:]
    /// 标的 id -> 辅助指标（供 ETF 复用底层指数的「其他视角」）
    private var secondaryByTarget: [String: [SecondaryMetric]] = [:]

    init(fetcher: MarketDataFetcher = MarketDataFetcher(client: HTTPClient()), cache: CacheStore = CacheStore()) {
        self.fetcher = fetcher
        self.cache = cache
        self.snapshots = TargetCatalog.all.map { TargetSnapshot(id: $0.id) }
    }

    /// 启动：先展示缓存（标注时间），再后台刷新
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        loadAllFromCache()
        Task { await refreshAll() }
    }

    // MARK: 详情页只读访问（原始序列）

    func priceSeries(for id: String) -> PriceSeries? { priceSeries[id] }
    func peSeries(for id: String) -> PESeries? { peSeries[id] }
    func navSeries(for id: String) -> FundNavSeries? { navSeries[id] }
    func yieldSeries() -> YieldSeries? { treasuryYields }
    /// 标普500 Shiller PE / 股息率（月度，仅 spx 详情页溯源用）
    func spxShillerPE() -> PESeries? { peSeries[CacheStore.spxShillerPEKey()] }
    func spxDividendYield() -> PESeries? { peSeries[CacheStore.spxDividendYieldKey()] }

    /// 全库最近一次抓取时间（取各序列 meta.fetchedAt 的最大值）
    var lastUpdatedAt: Date? {
        var dates = priceSeries.values.map(\.meta.fetchedAt)
        dates += peSeries.values.map(\.meta.fetchedAt)
        dates += navSeries.values.map(\.meta.fetchedAt)
        if let y = treasuryYields { dates.append(y.meta.fetchedAt) }
        return dates.max()
    }

    private var hasStarted = false

    // MARK: 缓存

    private func loadAllFromCache() {
        for target in TargetCatalog.all {
            if let s: PriceSeries = cache.load(PriceSeries.self, key: CacheStore.priceKey(target.id)) {
                priceSeries[target.id] = s
            }
            if let s: PESeries = cache.load(PESeries.self, key: CacheStore.peKey(target.id)) {
                peSeries[target.id] = s
            }
            if let s: FundNavSeries = cache.load(FundNavSeries.self, key: CacheStore.navKey(target.id)) {
                navSeries[target.id] = s
            }
        }
        // 辅助数据：国债收益率与标普500 Shiller PE/股息率
        treasuryYields = cache.load(YieldSeries.self, key: CacheStore.yieldKey())
        if let s: PESeries = cache.load(PESeries.self, key: CacheStore.spxShillerPEKey()) {
            peSeries[CacheStore.spxShillerPEKey()] = s
        }
        if let s: PESeries = cache.load(PESeries.self, key: CacheStore.spxDividendYieldKey()) {
            peSeries[CacheStore.spxDividendYieldKey()] = s
        }
        rebuildSnapshots(fromCache: true)
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
        let coreFailed = (needsPE && peFailed && peSeries[target.id] == nil) || (!needsPE && priceFailed && priceSeries[target.id] == nil)
        let allFailed = (needsPE ? peFailed : true) && priceFailed
        if allFailed || (peS == nil && priceS == nil && peSeries[target.id] == nil && priceSeries[target.id] == nil) {
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
            treasuryYields = yields
            cache.save(yields, key: CacheStore.yieldKey())
        } catch { /* 辅助源失败：沿用缓存或隐藏辅助指标 */ }
        do {
            let shiller = try await fetcher.fetchMultplPE(shiller: true)
            peSeries[CacheStore.spxShillerPEKey()] = shiller
            cache.save(shiller, key: CacheStore.spxShillerPEKey())
        } catch { }
        do {
            let div = try await fetcher.fetchMultplDividendYield()
            peSeries[CacheStore.spxDividendYieldKey()] = div
            cache.save(div, key: CacheStore.spxDividendYieldKey())
        } catch { }
    }

    // MARK: 状态更新（主线程）

    // (类整体 @MainActor)
    private func store(target: MarketTarget, pe: PESeries?, price: PriceSeries?) {
        if let pe { peSeries[target.id] = pe; cache.save(pe, key: CacheStore.peKey(target.id)) }
        if let price { priceSeries[target.id] = price; cache.save(price, key: CacheStore.priceKey(target.id)) }
    }

    // (类整体 @MainActor)
    private func storeETF(target: MarketTarget, price: PriceSeries, nav: FundNavSeries) {
        priceSeries[target.id] = price; cache.save(price, key: CacheStore.priceKey(target.id))
        navSeries[target.id] = nav; cache.save(nav, key: CacheStore.navKey(target.id))
    }

    // (类整体 @MainActor)
    private func markRefreshed(_ id: String) {
        rebuildSnapshot(id: id, fromCache: false)
    }

    // (类整体 @MainActor)
    private func markFailed(_ id: String, error: Error) {
        let hasCache = priceSeries[id] != nil || peSeries[id] != nil || navSeries[id] != nil
        if hasCache {
            rebuildSnapshot(id: id, fromCache: true)
            update(id) { $0.status = .refreshFailed; $0.statusDetail = "刷新失败，展示缓存数据" }
        } else {
            update(id) { $0.status = .noData; $0.statusDetail = "暂无数据：网络请求失败" }
        }
    }

    // MARK: 快照计算

    private func rebuildSnapshots(fromCache: Bool) {
        // 先算全部非 ETF（填充 underlyingResults），再算 ETF
        for t in TargetCatalog.all where t.kind == .index {
            rebuildSnapshot(id: t.id, fromCache: fromCache)
        }
        for t in TargetCatalog.all where t.kind == .etf {
            rebuildSnapshot(id: t.id, fromCache: fromCache)
        }
    }

    private func rebuildSnapshot(id: String, fromCache: Bool) {
        guard let target = TargetCatalog.target(id: id) else { return }
        var snap = TargetSnapshot(id: id)
        snap.status = .ok
        let now = Date()

        switch target.kind {
        case .index:
            buildIndexSnapshot(target: target, snap: &snap, now: now)
        case .etf:
            buildETFSnapshot(target: target, snap: &snap, now: now)
        }

        if snap.result == nil && snap.freshness == nil {
            snap.status = .noData
            snap.statusDetail = "暂无数据"
        } else if fromCache {
            snap.statusDetail = "缓存数据，抓取于 \(formatTime(snap))"
        }
        update(id) { $0 = snap }
    }

    private func buildIndexSnapshot(target: MarketTarget, snap: inout TargetSnapshot, now: Date) {
        var result: ValuationResult?
        var freshness: Freshness?

        if target.method == .fundamentals {
            if let peS = peSeries[target.id] {
                result = ValuationEngine.evaluateFundamentals(peSeries: peS)
                if result == nil, let priceS = priceSeries[target.id] {
                    // PE≤0 回退法B
                    result = ValuationEngine.evaluatePricePosition(priceSeries: priceS)
                    if result != nil {
                        result!.note = ValuationEngine.peNotApplicableNote + "。" + result!.note
                    }
                }
                if let asOf = peS.asOfDate, let d = DateUtil.date(asOf) {
                    freshness = ValuationEngine.fundamentalFreshness(asOf: d, now: now)
                    snap.asOfText = "PE 截至 \(asOf)"
                }
            } else if let priceS = priceSeries[target.id] {
                // PE 序列缺失（获取失败）：只展示行情，不用价格法冒充基本面评分
                if let asOf = priceS.asOfDate, let d = DateUtil.date(asOf) {
                    freshness = ValuationEngine.quoteFreshness(asOf: d, now: now)
                    snap.asOfText = "收盘 \(asOf)"
                }
            }
        } else if let priceS = priceSeries[target.id] {
            result = ValuationEngine.evaluatePricePosition(priceSeries: priceS)
            if let asOf = priceS.asOfDate, let d = DateUtil.date(asOf) {
                freshness = ValuationEngine.quoteFreshness(asOf: d, now: now)
                snap.asOfText = "收盘 \(asOf)"
            }
        }

        if let priceS = priceSeries[target.id], let last = priceS.bars.last {
            // 指数是点位不是货币金额；ETF 市价才带币种
            snap.latestValueText = target.kind == .index
                ? String(format: "%.2f 点", last.close)
                : String(format: "%.2f %@", last.close, target.currency.rawValue)
        } else if let peS = peSeries[target.id], let last = peS.points.last {
            snap.latestValueText = String(format: "PE %.1f", last.pe)
        }
        if freshness == .stale { snap.status = .stale; snap.statusDetail = "数据已过期" }
        snap.result = result
        snap.freshness = freshness
        // 记录评分供 ETF 复用（ETF 评分 = 底层指数评分）
        underlyingResults[target.id] = result
        // 其他视角：辅助指标（不并入主分数）
        snap.secondaryMetrics = buildSecondaryMetrics(for: target)
        secondaryByTarget[target.id] = snap.secondaryMetrics
    }

    /// 辅助估值指标：法A 标的给 ERP；spx 追加 CAPE 与股息率分位；法B 标的无。
    private func buildSecondaryMetrics(for target: MarketTarget) -> [SecondaryMetric] {
        guard target.method == .fundamentals else { return [] }
        var metrics: [SecondaryMetric] = []
        switch target.market {
        case .cn:
            if let peS = peSeries[target.id], let yields = treasuryYields {
                let erp = ValuationEngine.erpSeriesDaily(pe: peS.points, yields: yields.points, yieldOf: \.cn10y)
                if let m = ValuationEngine.erpMetric(erpSeries: erp) { metrics.append(m) }
            }
        case .us:
            // 标普500：ERP（月度 PE × 月末美债 10Y）+ Shiller CAPE 分位 + 股息率分位
            if let peS = peSeries[target.id], let yields = treasuryYields {
                let erp = ValuationEngine.erpSeriesMonthly(pe: peS.points, yields: yields.points, yieldOf: \.us10y)
                if let m = ValuationEngine.erpMetric(erpSeries: erp) { metrics.append(m) }
            }
            if let shiller = peSeries[CacheStore.spxShillerPEKey()],
               let m = ValuationEngine.percentileMetric(
                    name: "Shiller CAPE 分位", series: shiller, unit: "",
                    direction: .higherExpensive,
                    note: "CAPE 用 10 年均通胀调整盈利平滑周期；月度数据。分位越高越贵（与主分数同向）。") {
                metrics.append(m)
            }
            if let div = peSeries[CacheStore.spxDividendYieldKey()],
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

    private func buildETFSnapshot(target: MarketTarget, snap: inout TargetSnapshot, now: Date) {
        // 评分 = 底层指数评分；无底层且法B（黄金ETF）时用自身市价跑价格位置
        snap.result = ValuationEngine.etfScore(
            target: target,
            underlying: target.underlyingTargetID.flatMap { underlyingResults[$0] },
            ownPrice: priceSeries[target.id])
        // 其他视角：跟随底层指数的辅助指标
        if let underlyingID = target.underlyingTargetID {
            snap.secondaryMetrics = secondaryByTarget[underlyingID] ?? []
        }
        // 溢折价 = 最新市价 / 最新单位净值 − 1（单位净值，非累计净值）
        if let priceS = priceSeries[target.id], let lastBar = priceS.bars.last {
            snap.latestValueText = String(format: "%.3f %@", lastBar.close, target.currency.rawValue)
            snap.asOfText = "市价 \(lastBar.date)"
            if let d = DateUtil.date(lastBar.date),
               ValuationEngine.quoteFreshness(asOf: d, now: now) == .stale {
                snap.status = .stale
                snap.statusDetail = "行情已过期"
            }
        }
        if let navS = navSeries[target.id], let lastNav = navS.points.last,
           let lastBar = priceSeries[target.id]?.bars.last,
           let p = ValuationEngine.premium(price: lastBar.close, unitNav: lastNav.unitNav) {
            snap.premium = p
            snap.premiumText = ValuationEngine.premiumNote(p, isQDII: target.isQDII)
            snap.asOfText += "｜净值 \(lastNav.date)\(target.isQDII ? "（QDII 滞后）" : "")"
            if let d = DateUtil.date(lastNav.date),
               ValuationEngine.fundamentalFreshness(asOf: d, now: now) == .stale {
                snap.status = .stale
                snap.statusDetail = "净值已过期"
            }
        }
    }

    private func formatTime(_ snap: TargetSnapshot) -> String {
        let series: SeriesMeta? = peSeries[snap.id]?.meta ?? priceSeries[snap.id]?.meta ?? navSeries[snap.id]?.meta
        guard let fetchedAt = series?.fetchedAt else { return "未知时间" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: fetchedAt)
    }

    private func update(_ id: String, _ mutate: (inout TargetSnapshot) -> Void) {
        guard let idx = snapshots.firstIndex(where: { $0.id == id }) else { return }
        mutate(&snapshots[idx])
    }
}
