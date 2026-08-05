import Foundation

// MARK: - 标的定义

enum AssetKind: Sendable {
    case index
    case etf
}

/// 原始值随「列表摘要缓存」落盘（`ValuationResult.method`），改名等于让旧缓存失效
enum ValuationMethod: String, Codable, Sendable {
    case fundamentals   // 法A：基本面（PE）分位
    case pricePosition  // 法B：价格位置分位
}

enum Market: Sendable {
    case cn, hk, us
}

/// 估值标的定义（静态名单，27 个可见 + 10 个隐藏底层指数）
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
    /// 是否在总览/导航中可见。隐藏指数只取数算分，供 ETF 引用，不出现在任何列表。
    var isVisible: Bool = true
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
        // A股ETF（只保留指数组无法提供的敞口或信息：行业/商品/QDII；
        // 底层已在指数组的宽基 ETF 不重复收录——其唯一增量是溢折价，而巨型宽基溢折价常年≈0）
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
        // 隐藏底层指数（isVisible=false）：不在总览出现，只取数算分供 ETF 引用
        MarketTarget(id: "sh000015", name: "红利指数", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "上证红利：沪市高股息代表，红利ETF 底层",
                     tencentSymbol: "sh000015", csindexCode: "000015", isVisible: false),
        MarketTarget(id: "sz399986", name: "中证银行", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "银行板块代表，深度价值，银行ETF 底层",
                     tencentSymbol: "sz399986", csindexCode: "399986", isVisible: false),
        MarketTarget(id: "sz399989", name: "中证医疗", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "医疗器械与服务赛道，医疗ETF 底层",
                     tencentSymbol: "sz399989", csindexCode: "399989", isVisible: false),
        MarketTarget(id: "sh931151", name: "光伏产业", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "光伏产业链代表，强周期成长，光伏ETF 底层",
                     tencentSymbol: "sh931151", csindexCode: "931151", isVisible: false),
        MarketTarget(id: "csiH30184", name: "半导体", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "半导体产业链代表，半导体ETF 底层；腾讯无该指数报价，只取中证 PE",
                     csindexCode: "H30184", isVisible: false),
        MarketTarget(id: "sz399006", name: "创业板指", kind: .index, market: .cn, currency: .cny, method: .pricePosition,
                     rationale: "创业板大盘成长代表，创业板ETF 底层；无免费 PE 历史源，用价格位置",
                     tencentSymbol: "sz399006", isVisible: false),
        MarketTarget(id: "sz399967", name: "中证军工", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "军工板块代表，军工ETF 底层",
                     tencentSymbol: "sz399967", csindexCode: "399967", isVisible: false),
        MarketTarget(id: "sh000932", name: "800消费", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "主要消费板块代表，消费ETF 底层",
                     tencentSymbol: "sh000932", csindexCode: "000932", isVisible: false),
        MarketTarget(id: "sz399976", name: "CS新能车", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "新能源汽车产业链代表，新能源车ETF 底层",
                     tencentSymbol: "sz399976", csindexCode: "399976", isVisible: false),
        MarketTarget(id: "sh000819", name: "有色金属", kind: .index, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "有色金属板块代表，强周期资源品，有色金属ETF 底层",
                     tencentSymbol: "sh000819", csindexCode: "000819", isVisible: false),
        MarketTarget(id: "sh510880", name: "红利ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪上证红利指数，高股息策略工具",
                     tencentSymbol: "sh510880", fundCode: "510880", underlyingTargetID: "sh000015"),
        MarketTarget(id: "sh512800", name: "银行ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪中证银行指数，深度价值板块工具",
                     tencentSymbol: "sh512800", fundCode: "512800", underlyingTargetID: "sz399986"),
        MarketTarget(id: "sh512170", name: "医疗ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪中证医疗指数，医疗赛道配置工具",
                     tencentSymbol: "sh512170", fundCode: "512170", underlyingTargetID: "sz399989"),
        MarketTarget(id: "sh515790", name: "光伏ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪光伏产业指数，新能源赛道工具",
                     tencentSymbol: "sh515790", fundCode: "515790", underlyingTargetID: "sh931151"),
        MarketTarget(id: "sh512480", name: "半导体ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪半导体指数，硬科技赛道工具",
                     tencentSymbol: "sh512480", fundCode: "512480", underlyingTargetID: "csiH30184"),
        MarketTarget(id: "sh518880", name: "黄金ETF", kind: .etf, market: .cn, currency: .cny, method: .pricePosition,
                     rationale: "跟踪 AU99.99 现货黄金，避险与抗通胀配置；黄金无盈利，PE 不适用，用价格位置法评估自身市价",
                     tencentSymbol: "sh518880", fundCode: "518880"),
        MarketTarget(id: "sh513500", name: "标普500ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "QDII 跟踪标普500，美股大盘境内配置工具；净值滞后1-2个交易日，溢价风险高",
                     tencentSymbol: "sh513500", fundCode: "513500", underlyingTargetID: "spx", isQDII: true),
        MarketTarget(id: "sz159915", name: "创业板ETF", kind: .etf, market: .cn, currency: .cny, method: .pricePosition,
                     rationale: "跟踪创业板指，深市成长配置工具；底层无免费 PE 历史源，沿用其价格位置评分",
                     tencentSymbol: "sz159915", fundCode: "159915", underlyingTargetID: "sz399006"),
        MarketTarget(id: "sh512660", name: "军工ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪中证军工指数，国防板块工具",
                     tencentSymbol: "sh512660", fundCode: "512660", underlyingTargetID: "sz399967"),
        MarketTarget(id: "sz159928", name: "消费ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪中证主要消费（800消费）指数，消费板块工具",
                     tencentSymbol: "sz159928", fundCode: "159928", underlyingTargetID: "sh000932"),
        MarketTarget(id: "sh515030", name: "新能源车ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪中证新能源汽车指数，新能源车产业链工具",
                     tencentSymbol: "sh515030", fundCode: "515030", underlyingTargetID: "sz399976"),
        MarketTarget(id: "sh512400", name: "有色金属ETF", kind: .etf, market: .cn, currency: .cny, method: .fundamentals,
                     rationale: "跟踪中证申万有色金属指数，强周期资源品工具",
                     tencentSymbol: "sh512400", fundCode: "512400", underlyingTargetID: "sh000819"),
    ]

    /// 可见标的：总览分组与导航只从这里取
    static let visible: [MarketTarget] = all.filter(\.isVisible)

    static func target(id: String) -> MarketTarget? {
        all.first { $0.id == id }
    }
}
