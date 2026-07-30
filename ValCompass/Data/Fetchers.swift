import Foundation

enum FetchError: Error {
    case badURL
    case httpStatus(Int)
    case network(Error)
}

/// 极简 HTTP 客户端：统一带 User-Agent（各源均要求）
struct HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func get(_ urlString: String, headers: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: urlString) else { throw FetchError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw FetchError.httpStatus(http.statusCode)
            }
            return data
        } catch let e as FetchError {
            throw e
        } catch {
            throw FetchError.network(error)
        }
    }
}

/// 中证官网请求闸门：全局串行 + 最小间隔，避免并发突发触发 WAF 限流
actor CSIndexGate {
    static let shared = CSIndexGate()
    private var last: Date = .distantPast
    private let minInterval: TimeInterval = 0.6

    func wait() async {
        let elapsed = Date().timeIntervalSince(last)
        if elapsed < minInterval {
            try? await Task.sleep(nanoseconds: UInt64((minInterval - elapsed) * 1_000_000_000))
        }
        last = Date()
    }
}

/// 各数据源抓取器。所有方法返回带元信息的序列。
struct MarketDataFetcher {
    let client: HTTPClient
    var now: () -> Date = Date.init

    // 腾讯单次 count 上限约 640，10 年日线约 2450 条，需按 end 日期向前分页
    private let tencentPageSize = 640
    private let tencentMaxPages = 6

    /// 腾讯日线（A股/港股指数与ETF）。港股 HKD，A股 CNY。
    func fetchTencentDaily(symbol: String, currency: Currency, years: Int = 10) async throws -> PriceSeries {
        var all: [PriceBar] = []
        var end = ""  // 空表示最新
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .year, value: -years, to: now())
        for _ in 0..<tencentMaxPages {
            let url = "https://web.ifzq.gtimg.cn/appstock/app/fqkline/get?param=\(symbol),day,,\(end),\(tencentPageSize),qfq"
            let data = try await client.get(url)
            let page = try TencentKlineParser.parse(data, symbol: symbol)
            guard let first = page.first, let firstDate = DateUtil.date(first.date) else { break }
            // 分页向前拼接，去重（页间边界可能重叠）
            let existing = Set(all.map(\.date))
            all = page.filter { !existing.contains($0.date) } + all
            if firstDate <= cutoff! { break }
            // 下一页：end 取本页最早日期的前一天
            guard let prev = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: firstDate) else { break }
            end = DateUtil.ymd.string(from: prev)
            if page.count < tencentPageSize { break } // 已到头
        }
        guard !all.isEmpty else { throw ParserError.noRows }
        return PriceSeries(meta: SeriesMeta(source: .tencent, fetchedAt: now(), currency: currency,
                                            isMonthly: false, isDelayed: false), bars: all)
    }

    /// 新浪美股日线（一次返回全历史）。USD。
    func fetchSinaDaily(symbol: String) async throws -> PriceSeries {
        let url = "https://stock.finance.sina.com.cn/usstock/api/jsonp.php/x/US_MinKService.getDailyK?symbol=\(symbol)"
        let data = try await client.get(url)
        let bars = try SinaUSParser.parse(data)
        return PriceSeries(meta: SeriesMeta(source: .sina, fetchedAt: now(), currency: .usd,
                                            isMonthly: false, isDelayed: false), bars: bars)
    }

    /// 中证指数 PE 历史（一次请求可返回 10 年全部日度数据）。
    /// 官网有 WAF 限流：串行间隔请求 + 完整浏览器头。
    func fetchCSIndexPE(indexCode: String) async throws -> PESeries {
        await CSIndexGate.shared.wait()
        let url = "https://www.csindex.com.cn/csindex-home/perf/index-perf?indexCode=\(indexCode)&startDate=20150101&endDate=20500101"
        let data = try await client.get(url, headers: [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
            "Referer": "https://www.csindex.com.cn/",
            "Accept": "application/json, text/plain, */*",
        ])
        let points = try CSIndexParser.parse(data)
        return PESeries(meta: SeriesMeta(source: .csindex, fetchedAt: now(), currency: .cny,
                                         isMonthly: false, isDelayed: false), points: points)
    }

    /// 天天基金净值（单位净值 + 累计净值）。isDelayed 标记 QDII 净值滞后。
    func fetchFundNav(fundCode: String, isQDII: Bool) async throws -> FundNavSeries {
        let url = "https://fund.eastmoney.com/pingzhongdata/\(fundCode).js"
        let data = try await client.get(url)
        let parsed = try EastmoneyFundParser.parse(data)
        return FundNavSeries(meta: SeriesMeta(source: .eastmoney, fetchedAt: now(), currency: .cny,
                                              isMonthly: false, isDelayed: isQDII),
                             fundName: parsed.fundName, points: parsed.points)
    }

    /// multpl 标普500 PE（月度，精度有限）。
    func fetchMultplPE(shiller: Bool = false) async throws -> PESeries {
        let path = shiller ? "shiller-pe" : "s-p-500-pe-ratio"
        let url = "https://www.multpl.com/\(path)/table/by-month"
        let data = try await client.get(url)
        let points = try MultplParser.parse(data)
        return PESeries(meta: SeriesMeta(source: .multpl, fetchedAt: now(), currency: .usd,
                                         isMonthly: true, isDelayed: false), points: points)
    }
}
