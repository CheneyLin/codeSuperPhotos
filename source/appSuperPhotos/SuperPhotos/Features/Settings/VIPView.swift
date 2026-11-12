import SwiftUI
import StoreKit

/// VIP 权益页：一次性购买（非消耗型）的完整购买 / 恢复入口。
/// 设置页已提供极简两行快捷操作，本页作为备用完整页保留；
/// 权益对比与欢迎轮播图素材共用 `SettingsTip.vip.comparison`，避免两处文案走样。
struct VIPView: View {
    @Environment(EntitlementStore.self) private var entitlements

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                statusCard
                if !entitlements.isVIP {
                    productCard
                }
                actionArea
                comparisonCard
                legalFooter
            }
            .padding(Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Surface.base.ignoresSafeArea())
        .navigationTitle("VIP 权益".localized)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // App 启动已加载过；此处兜底处理拉取失败后再次进入页面。
            if entitlements.product == nil {
                await entitlements.loadProduct()
            }
        }
        .alert(
            "购买提示".localized,
            isPresented: Binding(
                get: { entitlements.notice != nil },
                set: { presented in
                    if !presented { entitlements.clearNotice() }
                }
            )
        ) {
            Button("好".localized, role: .cancel) { entitlements.clearNotice() }
        } message: {
            Text(entitlements.notice ?? "")
        }
    }

    // MARK: - 当前状态

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: entitlements.isVIP ? "crown.fill" : "person.crop.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(entitlements.isVIP ? Theme.Accent.fire : Theme.Text.secondary)

                Text(entitlements.isVIP ? "VIP 会员".localized : "免费版".localized)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Text.primary)

                Spacer()
            }

            Text(entitlements.isVIP
                 ? "已购买，VIP 永久有效：实况照片与视频、不限容量、本月统计等权益全部可用。".localized
                 : "VIP 为一次性购买，付款一次即可永久解锁实况照片与视频、不限容量与本月统计等权益。".localized)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Text.secondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.raised, cornerRadius: Theme.Radius.card)
    }

    // MARK: - 商品

    private var productCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("购买方案".localized)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Text.primary)

            if let product = entitlements.product {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.displayName)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Text.primary)
                        Text(productTypeText)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(
                                entitlements.isProductTypeMismatch
                                    ? Theme.State.warning
                                    : Theme.Text.secondary
                            )
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                    Text(product.displayPrice)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Text.primary)
                }
            } else if entitlements.isLoadingProduct {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                    Text("正在获取商品信息…".localized)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.secondary)
                }
            } else {
                Button {
                    Task { await entitlements.loadProduct() }
                } label: {
                    Label("重新获取商品信息".localized, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.neuText)
            }

            Text("确认购买后将从你的 Apple ID 账户一次性扣费，购买后永久可用，无自动续订。".localized)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.tertiary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.raised, cornerRadius: Theme.Radius.card)
    }

    /// 非消耗型商品 `product.subscription` 为 nil；若不为 nil 说明 ASC 配成了订阅，
    /// 在页面上明确提示，便于开发期发现配置错误。
    private var productTypeText: String {
        entitlements.isProductTypeMismatch
            ? "商品类型与预期不符（应为一次性购买），请检查 App Store Connect 配置".localized
            : "一次性购买 · 永久解锁，无需续订".localized
    }

    // MARK: - 购买与恢复

    private var actionArea: some View {
        VStack(spacing: Theme.Spacing.md) {
            if !entitlements.isVIP {
                Button {
                    Task { await entitlements.purchase() }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        if entitlements.isPurchasing {
                            ProgressView()
                                .tint(Theme.Text.pillButton)
                        }
                        Text(entitlements.isPurchasing ? "正在购买…".localized : "购买 VIP".localized)
                    }
                }
                .buttonStyle(NeuPillButtonStyle())
                .disabled(
                    entitlements.isPurchasing
                        || entitlements.isRestoring
                        || entitlements.product == nil
                )
                .opacity(
                    entitlements.isPurchasing || entitlements.product == nil ? 0.7 : 1
                )
            }

            Button {
                Task { await entitlements.restore() }
            } label: {
                Label(
                    entitlements.isRestoring ? "正在恢复…".localized : "恢复购买".localized,
                    systemImage: "arrow.clockwise"
                )
                .font(Theme.Typography.body)
            }
            .buttonStyle(NeuTextButtonStyle())
            .disabled(entitlements.isPurchasing || entitlements.isRestoring)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 对比

    private var comparisonCard: some View {
        SettingsTipComparisonView(rows: SettingsTip.vip.comparison)
            .padding(Theme.Spacing.lg)
            .neuSurface(.raised, cornerRadius: Theme.Radius.card)
    }

    // MARK: - 购买说明

    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("VIP 为一次性购买：确认后从 Apple ID 账户扣费一次，购买后永久解锁，不会自动续订，也不会再次扣费。更换设备或重装后，可用「恢复购买」免费找回已购权益。价格以 App Store 显示为准；购买与恢复均不影响本机照片与保险箱数据。".localized)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.tertiary)

            SettingsTipLegalLinks()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        VIPView()
            .environment(EntitlementStore())
    }
}
