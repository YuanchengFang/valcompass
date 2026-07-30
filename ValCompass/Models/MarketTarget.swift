import Foundation

// MARK: - 标的定义

enum AssetKind {
    case index
    case etf
}

enum ValuationMethod {
    case fundamentals   // 法A：基本面（PE）分位
    case pricePosition  // 法B：价格位置分位
}

enum Market {
    case cn, hk, us
}

/// 估值标的定义（静态名单，共 20 个）
struct MarketTarget: Identifiable, Hashable {
    let id: String              // 内部 ID，如 sh000300
    let name: String            // 中文名
    let kind: AssetKind
    let market: Market
    let currency: Currency
    let method: ValuationMethod
    let rationale: String       // 选择理由

    // 数据源标识（按标的类型取用）
    var tencentSymbol: String? = nil  // 腾讯行情 symbol
    var sinaSymbol: String? = nil     // 新浪美股 symbol
    var csindexCode: String? = nil    // 中证指数代码（PE）
    var fundCode: String? = nil       // 天天基金代码（净值）
    var underlyingTargetID: String? = nil // ETF 的底层标的 ID
    var isQDII: Bool = false          // QDII：净值滞后 1-2 个交易日
}

enum TargetCatalog {
    static let all: [MarketTarget] = [
        // A股宽基（法A）
        MarketTarget(id: "sh000300", name: "沪深300", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "A股大盘蓝筹核心宽基，机构配置基准",
                     tencentSymbol: "sh000300", csindexCode: "000300"),
        MarketTarget(id: "sh000905", name: "中证500", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "A股中盘代表，与沪深300互补",
                     tencentSymbol: "sh000905", csindexCode: "000905"),
        MarketTarget(id: "sh000852", name: "中证1000", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "A股小盘代表，成长弹性高",
                     tencentSymbol: "sh000852", csindexCode: "000852"),
        MarketTarget(id: "sh000016", name: "上证50", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "沪市超大盘龙头，防御属性强",
                     tencentSymbol: "sh000016", csindexCode: "000016"),
        MarketTarget(id: "sh000688", name: "科创50", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "科创板核心资产，硬科技方向",
                     tencentSymbol: "sh000688", csindexCode: "000688"),
        MarketTarget(id: "sh000922", name: "中证红利", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "高股息策略代表，类债配置工具",
                     tencentSymbol: "sh000922", csindexCode: "000922"),
        // A股行业（法A）
        MarketTarget(id: "sz399997", name: "中证白酒", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "消费核心赛道，盈利质量高、波动大",
                     tencentSymbol: "sz399997", csindexCode: "399997"),
        MarketTarget(id: "sz399975", name: "证券公司", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "牛市旗手，强周期高弹性",
                     tencentSymbol: "sz399975", csindexCode: "399975"),
        // A股ETF（底层指数评分 + 溢折价）
        MarketTarget(id: "sh510300", name: "沪深300ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪沪深300，规模最大流动性最好",
                     tencentSymbol: "sh510300", fundCode: "510300", underlyingTargetID: "sh000300"),
        MarketTarget(id: "sh510500", name: "中证500ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪中证500，中盘配置工具",
                     tencentSymbol: "sh510500", fundCode: "510500", underlyingTargetID: "sh000905"),
        MarketTarget(id: "sh588000", name: "科创50ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪科创50，个人参与科创板主渠道",
                     tencentSymbol: "sh588000", fundCode: "588000", underlyingTargetID: "sh000688"),
        MarketTarget(id: "sh512880", name: "证券ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪证券公司指数，券商行情工具",
                     tencentSymbol: "sh512880", fundCode: "512880", underlyingTargetID: "sz399975"),
        MarketTarget(id: "sh512690", name: "酒ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪中证白酒，白酒赛道一键配置",
                     tencentSymbol: "sh512690", fundCode: "512690", underlyingTargetID: "sz399997"),
        MarketTarget(id: "sh513100", name: "纳指ETF", kind: .etf, market: .cn, currency: .cny, method: .pricePosition,
                     rationale: "QDII 跟踪纳斯达克100，跨境配置工具；净值滞后1-2个交易日，溢价风险高",
                     tencentSymbol: "sh513100", fundCode: "513100", underlyingTargetID: "ndx", isQDII: true),
        // 港股指数（法B：无公开免费 PE 历史源，用价格位置）
        MarketTarget(id: "hkHSI", name: "恒生指数", kind: .index, market: .hk, currency: .hkd, method: .pricePosition,
                     rationale: "港股大盘基准",
                     tencentSymbol: "hkHSI"),
        MarketTarget(id: "hkHSTECH", name: "恒生科技", kind: .index, market: .hk, currency: .hkd, method: .pricePosition,
                     rationale: "港股科技龙头，高波动",
                     tencentSymbol: "hkHSTECH"),
        MarketTarget(id: "hkHSCEI", name: "恒生中国企业", kind: .index, market: .hk, currency: .hkd, method: .pricePosition,
                     rationale: "H股代表，内地企业港股定价",
                     tencentSymbol: "hkHSCEI"),
        // 美股指数
        MarketTarget(id: "spx", name: "标普500", kind: .index, market: .us, currency: .usd, method: .fundamentals,
                     rationale: "美股大盘基准，全球资产配置锚",
                     sinaSymbol: ".INX"),
        MarketTarget(id: "ndx", name: "纳斯达克100", kind: .index, market: .us, currency: .usd, method: .pricePosition,
                     rationale: "美股科技成长代表；免费 PE 历史源缺失，用价格位置",
                     sinaSymbol: ".NDX"),
        MarketTarget(id: "dji", name: "道琼斯", kind: .index, market: .us, currency: .usd, method: .pricePosition,
                     rationale: "美股传统蓝筹代表；免费 PE 历史源缺失，用价格位置",
                     sinaSymbol: ".DJI"),
    ]

    static func target(id: String) -> MarketTarget? {
        all.first { $0.id == id }
    }
}
