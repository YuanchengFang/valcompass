import XCTest
@testable import ValCompass

/// 目录校验：新增标的写错字段时应在测试期爆炸，而不是运行时静默无分。
final class CatalogTests: XCTestCase {

    // MARK: 全局约束

    func testIDsAreGloballyUnique() {
        let ids = TargetCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "标的 id 必须全局唯一")
    }

    func testEveryETFUnderlyingResolvesToAnIndex() {
        for etf in TargetCatalog.all where etf.kind == .etf {
            guard let underlyingID = etf.underlyingTargetID else { continue }
            let underlying = TargetCatalog.target(id: underlyingID)
            XCTAssertNotNil(underlying, "\(etf.id) 的底层 \(underlyingID) 必须存在")
            XCTAssertEqual(underlying?.kind, .index, "\(etf.id) 的底层 \(underlyingID) 必须是指数标的")
        }
    }

    func testVisibleETFUnderlyingExists() {
        // 可见 ETF 的底层尤其不能悬空（黄金ETF 这类无底层标的除外）
        for etf in TargetCatalog.visible where etf.kind == .etf {
            if let underlyingID = etf.underlyingTargetID {
                XCTAssertNotNil(TargetCatalog.target(id: underlyingID),
                                "可见 ETF \(etf.id) 的底层 \(underlyingID) 必须存在")
            } else {
                // 无底层的 ETF 只允许法B（黄金ETF 路径：用自身市价评分）
                XCTAssertEqual(etf.method, .pricePosition,
                               "无底层 ETF \(etf.id) 必须用价格位置法（自身市价评分）")
            }
        }
    }

    // MARK: 按 (market, method, kind) 校验必需字段

    func testRequiredFieldsByMarketMethodKind() {
        for t in TargetCatalog.all {
            switch (t.market, t.method, t.kind) {
            case (.cn, .fundamentals, .index):
                XCTAssertNotNil(t.csindexCode, "\(t.id)：法A A股指数必须有中证指数代码")
                // tencentSymbol 允许缺失（如半导体 csiH30184 无腾讯报价）：只取 PE 属预期降级
            case (.cn, .pricePosition, .index):
                XCTAssertNotNil(t.tencentSymbol, "\(t.id)：法B A股指数必须有腾讯 symbol")
            case (.hk, _, .index):
                XCTAssertNotNil(t.tencentSymbol, "\(t.id)：港股指数必须有腾讯 symbol")
            case (.us, _, .index):
                XCTAssertNotNil(t.sinaSymbol, "\(t.id)：美股指数必须有新浪 symbol（spx 的 multpl PE 是叠加项，不替代行情）")
            case (_, _, .etf):
                XCTAssertNotNil(t.tencentSymbol, "\(t.id)：ETF 必须有腾讯 symbol（市价）")
                XCTAssertNotNil(t.fundCode, "\(t.id)：ETF 必须有天天基金代码（净值）")
            }
        }
    }

    func testQDIIFlagOnUSUnderlyingETFs() {
        // 底层是美股的境内 ETF 是 QDII，净值滞后必须标注
        for etf in TargetCatalog.all where etf.kind == .etf {
            guard let underlyingID = etf.underlyingTargetID,
                  let underlying = TargetCatalog.target(id: underlyingID) else { continue }
            if underlying.market == .us {
                XCTAssertTrue(etf.isQDII, "\(etf.id) 跟踪美股标的，必须标 isQDII")
            }
        }
    }

    // MARK: 可见性

    func testHiddenTargetsAreIndicesReferencedByAtLeastOneETF() {
        let referenced = Set(TargetCatalog.all.compactMap(\.underlyingTargetID))
        for t in TargetCatalog.all where !t.isVisible {
            XCTAssertEqual(t.kind, .index, "隐藏标的 \(t.id) 必须是指数（底层）")
            XCTAssertTrue(referenced.contains(t.id), "隐藏指数 \(t.id) 没有被任何 ETF 引用，属于死重")
        }
    }

    func testVisibleExcludesHidden() {
        XCTAssertFalse(TargetCatalog.visible.contains { !$0.isVisible })
        XCTAssertEqual(TargetCatalog.visible.count,
                       TargetCatalog.all.filter(\.isVisible).count)
    }

    // MARK: 规模锚点（防止误删/误加）

    func testCatalogSizeAnchors() {
        XCTAssertEqual(TargetCatalog.all.count, 37)          // 27 可见 + 10 隐藏底层
        XCTAssertEqual(TargetCatalog.visible.count, 27)
        let cnETFs = TargetCatalog.visible.filter { $0.market == .cn && $0.kind == .etf }
        // ETF 组只保留指数组无法提供的敞口（行业/商品/QDII），不含重复宽基
        XCTAssertEqual(cnETFs.count, 13, "总览 A股ETF 组应为 13 个")
    }
}
