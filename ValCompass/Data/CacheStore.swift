import Foundation

/// JSON 文件缓存：Caches 目录，逐标的、逐数据类型，带 fetchedAt（在序列 meta 内）。
/// 启动先展示缓存，后台刷新；刷新失败保留缓存；重启后可用。
///
/// 只持有一个目录 URL，因此可以跨线程共享——读盘与写盘都在后台任务里做，不占主线程。
final class CacheStore: Sendable {
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.directory = caches.appendingPathComponent("ValCompassCache", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func fileURL(key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    func save<T: Encodable>(_ value: T, key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: fileURL(key: key), options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL(key: key)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    // MARK: 全量读取

    /// 读出全部标的的原始序列。十几 MB / 九万多个数据点，解码要几百毫秒，
    /// 只能在后台线程调用（`MarketRepository.loadAllFromCache`）。
    func loadAllSeries(targets: [MarketTarget]) -> SeriesStore {
        var store = SeriesStore()
        for target in targets {
            if let s: PriceSeries = load(PriceSeries.self, key: Self.priceKey(target.id)) {
                store.price[target.id] = s
            }
            if let s: PESeries = load(PESeries.self, key: Self.peKey(target.id)) {
                store.pe[target.id] = s
            }
            if let s: FundNavSeries = load(FundNavSeries.self, key: Self.navKey(target.id)) {
                store.nav[target.id] = s
            }
        }
        // 辅助数据：国债收益率与标普500 Shiller PE/股息率
        store.yields = load(YieldSeries.self, key: Self.yieldKey())
        if let s: PESeries = load(PESeries.self, key: Self.spxShillerPEKey()) {
            store.pe[Self.spxShillerPEKey()] = s
        }
        if let s: PESeries = load(PESeries.self, key: Self.spxDividendYieldKey()) {
            store.pe[Self.spxDividendYieldKey()] = s
        }
        return store
    }

    // MARK: 列表摘要（启动首帧用）

    func saveSummary(_ summaries: [SnapshotSummary]) {
        save(summaries, key: Self.summaryKey())
    }

    func loadSummary() -> [SnapshotSummary]? {
        load([SnapshotSummary].self, key: Self.summaryKey())
    }

    // 缓存键约定
    static func priceKey(_ targetID: String) -> String { "\(targetID)-price" }
    static func peKey(_ targetID: String) -> String { "\(targetID)-pe" }
    static func navKey(_ targetID: String) -> String { "\(targetID)-nav" }
    static func yieldKey() -> String { "treasury-10y-yield" }
    // 标普500 辅助数据（挂 spx 名下，非独立标的）
    static func spxShillerPEKey() -> String { "spx-pe-shiller" }
    static func spxDividendYieldKey() -> String { "spx-dividend-yield" }
    // 总览列表摘要（全部标的一个文件）
    static func summaryKey() -> String { "list-summary" }
}
