import Foundation

/// JSON 文件缓存：Caches 目录，逐标的、逐数据类型，带 fetchedAt（在序列 meta 内）。
/// 启动先展示缓存，后台刷新；刷新失败保留缓存；重启后可用。
final class CacheStore {
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

    // 缓存键约定
    static func priceKey(_ targetID: String) -> String { "\(targetID)-price" }
    static func peKey(_ targetID: String) -> String { "\(targetID)-pe" }
    static func navKey(_ targetID: String) -> String { "\(targetID)-nav" }
    static func yieldKey() -> String { "treasury-10y-yield" }
    // 标普500 辅助数据（挂 spx 名下，非独立标的）
    static func spxShillerPEKey() -> String { "spx-pe-shiller" }
    static func spxDividendYieldKey() -> String { "spx-dividend-yield" }
}
