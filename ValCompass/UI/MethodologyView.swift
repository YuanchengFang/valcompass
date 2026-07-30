import SwiftUI

/// 方法说明：评分口径、五档区间、置信度、两种方法的局限、
/// ETF 溢折价与底层估值的区别、名单选择标准、免责声明。
struct MethodologyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    section("分数是什么", body: """
                    估值分数是一个 0–100 的百分位：它表示当前水平在自身近 10 年历史中所处的位置。分数越高，代表相对历史越贵；分数越低，代表相对历史越便宜。

                    分数只描述「位置」，不构成买卖建议。便宜的可以更便宜，贵的可以更贵；本应用不提供任何择时信号。

                    五档区间：0–20 明显偏低 · 20–40 偏低 · 40–60 合理 · 60–80 偏高 · 80–100 明显偏高。
                    """)

                    section("两种评分方法", body: """
                    法A · 基本面分位（PE）：用当前市盈率在近 10 年 PE 序列中的百分位。适用于有公开 PE 历史数据的标的（A股指数、标普500）。局限：盈利大幅波动时 PE 会失真；成分股整体亏损（PE≤0）时指标不适用，自动回退到法B。标普500 的 PE 来自 multpl.com，为月度数据，精度有限。

                    法B · 价格位置分位：用当前收盘价在近 10 年日线中的百分位。适用于缺少免费 PE 历史源的标的（港股、纳斯达克100、道琼斯）。局限：只看价格、不看盈利或净资产，长期上涨的市场分数会结构性偏高，因此置信度上限为「中」。
                    """)

                    section("置信度", body: """
                    置信度反映历史数据的充分程度：覆盖 8 年以上为「高」，3–8 年为「中」，不足 3 年为「低」。月度数据会进一步降低精度。数据不足时，应用宁可不显示分数，也不会用假设数据填充。
                    """)

                    section("ETF 与溢折价", body: """
                    ETF 的估值分数直接采用其底层指数的评分，因为 ETF 本身没有独立的估值含义。

                    溢折价是另一个维度：溢折价率 = 市价 ÷ 单位净值 − 1，反映交易价格相对基金净值的偏离。QDII 基金（如纳指ETF）净值滞后 1–2 个交易日，此时溢折价仅供参考。即使底层资产估值合理，高溢价买入仍可能承受溢价回落的损失。
                    """)

                    section("名单如何选出", body: """
                    全名单约 20 个标的，选择标准是：流动性与认知度高，方便长期跟踪；横跨 A股、港股、美股三个市场；指数与 ETF 兼顾，既有观察基准也有可交易载体。

                    名单受免费公开数据源覆盖能力约束（腾讯行情、新浪美股、中证指数、天天基金、multpl.com），并非全市场优选，也不代表推荐其中任何标的。
                    """)

                    section("数据与时效", body: """
                    应用采用缓存优先策略：启动时先展示本机缓存（并标注抓取时间），再后台刷新；刷新失败时保留缓存并明确提示；行情超过 5 个交易日、基本面数据超过 10 个自然日未更新时标记为「已过期」。所有数据均可溯源到具体来源、抓取时间与数据所属日期。
                    """)

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("免责声明")
                            .font(AppFont.sectionTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text("本应用仅为信息与研究工具，不构成投资建议，不保证任何收益。估值分数反映当前水平相对自身历史的位置：分数低不代表应当买入，分数高不代表应当卖出。数据来自免费公开源，可能存在延迟、缺失或错误。投资有风险，决策需独立。")
                            .font(AppFont.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Spacing.m)
            }
            .background(Theme.background)
            .navigationTitle("方法说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .tint(Theme.accent)
                }
            }
        }
    }

    private func section(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(AppFont.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(body)
                .font(AppFont.body)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
