import Foundation

enum ParserError: Error, Equatable {
    case emptyData
    case badFormat(String)
    case noRows
}

// MARK: - 腾讯日线行情解析
// 响应：{"code":0,"data":{"{symbol}":{"day":[[日期,开,收,高,低,量],...]}}}
// ETF 请求 qfq 时键为 qfqday；同一 JSON 可能带 qt 字段，忽略。
enum TencentKlineParser {
    static func parse(_ data: Data, symbol: String) throws -> [PriceBar] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let symObj = dataObj[symbol] as? [String: Any] else {
            throw ParserError.badFormat("缺少 data.\(symbol)")
        }
        // 指数返回 day，ETF(qfq) 返回 qfqday
        let rows = (symObj["day"] ?? symObj["qfqday"]) as? [[Any]]
        guard let rows, !rows.isEmpty else { throw ParserError.noRows }
        return rows.compactMap { row in
            guard row.count >= 6,
                  let date = row[0] as? String,
                  let open = Double(row[1] as? String ?? ""),
                  let close = Double(row[2] as? String ?? ""),
                  let high = Double(row[3] as? String ?? ""),
                  let low = Double(row[4] as? String ?? ""),
                  let volume = Double(row[5] as? String ?? "") else { return nil }
            return PriceBar(date: date, open: open, close: close, high: high, low: low, volume: volume)
        }
    }
}

// MARK: - 新浪美股日线解析
// 响应为 JSONP：/*<script>...<\/script>*/\nx([{"d":"2004-01-02","o":..,"c":..},...]);
enum SinaUSParser {
    private struct Row: Decodable {
        let d: String
        let o: String
        let h: String
        let l: String
        let c: String
        let v: String
    }

    static func parse(_ data: Data) throws -> [PriceBar] {
        guard var text = String(data: data, encoding: .utf8) else {
            throw ParserError.badFormat("非 UTF-8")
        }
        // 剥掉 JSONP 包装：取第一个 [ 到最后一个 ]
        guard let l = text.firstIndex(of: "["), let r = text.lastIndex(of: "]"), l < r else {
            throw ParserError.badFormat("JSONP 结构异常")
        }
        text = String(text[l...r])
        guard let jsonData = text.data(using: .utf8) else { throw ParserError.badFormat("编码失败") }
        let rows: [Row]
        do {
            rows = try JSONDecoder().decode([Row].self, from: jsonData)
        } catch {
            throw ParserError.badFormat("JSON 解析失败: \(error.localizedDescription)")
        }
        guard !rows.isEmpty else { throw ParserError.noRows }
        return rows.compactMap { row in
            guard let open = Double(row.o), let close = Double(row.c),
                  let high = Double(row.h), let low = Double(row.l),
                  let volume = Double(row.v) else { return nil }
            return PriceBar(date: row.d, open: open, close: close, high: high, low: low, volume: volume)
        }
    }
}

// MARK: - 中证指数市盈率解析
// 响应：{"code":"200","data":[{"tradeDate":"20250725","close":4127.16,"peg":12.9,...},...]}
// 实测确认 peg 字段数值即官方发布的市盈率（沪深300≈12.9、中证红利≈8.0、科创50≈55.3），
// 每日收盘后发布；模型层命名为 peTTM 口径使用。
enum CSIndexParser {
    private struct Row: Decodable {
        let tradeDate: String
        let peg: Double?
    }
    private struct Response: Decodable {
        let code: String
        let data: [Row]
    }

    static func parse(_ data: Data) throws -> [PEPoint] {
        let resp: Response
        do {
            resp = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ParserError.badFormat("JSON 解析失败: \(error.localizedDescription)")
        }
        let points = resp.data.compactMap { row -> PEPoint? in
            guard let pe = row.peg, row.tradeDate.count == 8 else { return nil }
            let d = row.tradeDate
            let ymd = "\(d.prefix(4))-\(d.dropFirst(4).prefix(2))-\(d.suffix(2))"
            return PEPoint(date: ymd, pe: pe)
        }
        guard !points.isEmpty else { throw ParserError.noRows }
        return points
    }
}

// MARK: - 天天基金净值解析
// 响应为 JS（带 BOM）：含 fS_name = "..."; Data_netWorthTrend = [{x:ms,y:单位净值},...];
// Data_ACWorthTrend = [[ms, 累计净值],...]。溢折价用单位净值。
struct FundNavData: Equatable {
    var fundName: String
    var points: [FundNavPoint]
}

enum EastmoneyFundParser {
    static func parse(_ data: Data) throws -> FundNavData {
        guard var text = String(data: data, encoding: .utf8) else {
            throw ParserError.badFormat("非 UTF-8")
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        let name = firstMatch(#"fS_name\s*=\s*"([^"]*)""#, in: text) ?? ""

        guard let netWorthJSON = firstMatch(#"Data_netWorthTrend\s*=\s*(\[.*?\]);"#, in: text) else {
            throw ParserError.badFormat("缺少 Data_netWorthTrend")
        }
        // ACWorthTrend 元素是 [ms, nav] 嵌套数组，非贪婪匹配到 ]; 为止（内层 ] 后跟逗号，不误判）
        let acJSON = firstMatch(#"Data_ACWorthTrend\s*=\s*(\[.*?\]);"#, in: text)

        struct NetWorthRow: Decodable { let x: Double; let y: Double }
        guard let nwData = netWorthJSON.data(using: .utf8),
              let nwRows = try? JSONDecoder().decode([NetWorthRow].self, from: nwData) else {
            throw ParserError.badFormat("Data_netWorthTrend 解析失败")
        }
        // 累计净值：ms -> nav
        var accumulated: [Int: Double] = [:]
        if let acJSON, let acData = acJSON.data(using: .utf8),
           let acRows = try? JSONDecoder().decode([[Double]].self, from: acData) {
            for pair in acRows where pair.count >= 2 {
                accumulated[Int(pair[0] / 1000)] = pair[1]
            }
        }
        let points = nwRows.map { row -> FundNavPoint in
            let sec = Int(row.x / 1000)
            let date = DateUtil.ymd.string(from: Date(timeIntervalSince1970: TimeInterval(sec)))
            return FundNavPoint(date: date, unitNav: row.y, accumulatedNav: accumulated[sec])
        }
        guard !points.isEmpty else { throw ParserError.noRows }
        return FundNavData(fundName: name, points: points)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

// MARK: - 东方财富数据中心：中/美 10 年期国债收益率解析
// 响应：{"result":{"pages":19,"count":9310,"data":[{"SOLAR_DATE":"2026-07-29 00:00:00",
//   "EMM00166466":1.7329,"EMG00001310":4.67},...]},"success":true,...}
// EMM00166466=中国 10Y，EMG00001310=美国 10Y（均可为 null）；按日期倒序。
// 服务端 pageSize 上限 500（请求 3000 也只回 500），需按 pages 翻页。
// 历史锚点已验证：2018-01 CN≈3.9、2020-04 CN≈2.5/US≈0.6-0.8、2024-12 CN≈1.7-2.0/US≈4.2-4.6。
struct TreasuryYieldPage: Equatable {
    var pages: Int          // 总页数（用于翻页终止判断）
    var points: [YieldPoint] // 本页数据，已翻转为升序
}

enum TreasuryYieldParser {
    private struct Row: Decodable {
        let SOLAR_DATE: String
        let EMM00166466: Double?
        let EMG00001310: Double?
    }
    private struct Result: Decodable {
        let pages: Int
        let data: [Row]
    }
    private struct Response: Decodable {
        let success: Bool
        let result: Result?
    }

    static func parse(_ data: Data) throws -> TreasuryYieldPage {
        let resp: Response
        do {
            resp = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ParserError.badFormat("JSON 解析失败: \(error.localizedDescription)")
        }
        guard resp.success, let result = resp.result else {
            throw ParserError.badFormat("success != true 或缺少 result")
        }
        let points = result.data.compactMap { row -> YieldPoint? in
            // "2026-07-29 00:00:00" → "2026-07-29"
            let date = String(row.SOLAR_DATE.prefix(10))
            guard date.count == 10, date.contains("-") else { return nil }
            return YieldPoint(date: date, cn10y: row.EMM00166466, us10y: row.EMG00001310)
        }
        guard !points.isEmpty else { throw ParserError.noRows }
        return TreasuryYieldPage(pages: result.pages, points: points.reversed())
    }
}

// MARK: - multpl 标普500市盈率解析（月度，HTML 表格）
// 真实结构：行形如
//   <tr class="even">
//   <td>Jul 1, 2025</td>
//   <td>
//   &#x2002;
//   27.81
//   </td>
//   </tr>
// 按时间倒序排列。解析器写宽容：只认 日期td + 数值td 的配对。
enum MultplParser {
    static func parse(_ data: Data) throws -> [PEPoint] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParserError.badFormat("非 UTF-8")
        }
        let pattern = #"<td>\s*([A-Z][a-z]{2}\s+\d{1,2},\s*\d{4})\s*</td>\s*<td>(.*?)</td>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw ParserError.badFormat("正则编译失败")
        }
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "America/New_York")
        dateFormatter.dateFormat = "MMM d, yyyy"

        let range = NSRange(text.startIndex..., in: text)
        var points: [PEPoint] = []
        for m in re.matches(in: text, range: range) {
            guard m.numberOfRanges > 2,
                  let dateRange = Range(m.range(at: 1), in: text),
                  let valueRange = Range(m.range(at: 2), in: text) else { continue }
            let dateText = String(text[dateRange])
            // 值单元格可能含 <abbr title="Estimate">†</abbr> 标签、&#x2002; 实体、† 估计标记与换行，全部剔除后取数字
            var valueText = String(text[valueRange])
            valueText = valueText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            valueText = valueText.replacingOccurrences(of: #"&#x[0-9A-Fa-f]+;|&[a-z]+;"#,
                                                       with: "", options: .regularExpression)
            valueText = valueText.replacingOccurrences(of: "†", with: "")
            // 股息率表的值带百分号（如 1.10%），PE 表没有；统一剔除不影响 PE 解析
            valueText = valueText.replacingOccurrences(of: "%", with: "")
            valueText = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
                                   .replacingOccurrences(of: ",", with: "")
            guard let value = Double(valueText),
                  let date = dateFormatter.date(from: dateText) else { continue }
            points.append(PEPoint(date: DateUtil.ymd.string(from: date), pe: value))
        }
        guard !points.isEmpty else { throw ParserError.noRows }
        // 页面按时间倒序，翻转为升序
        return points.reversed()
    }
}
