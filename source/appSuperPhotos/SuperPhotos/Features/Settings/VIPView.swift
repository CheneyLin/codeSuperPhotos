import SwiftUI

/// VIP 权益页：只做权益对比与模拟开关，不含价格与购买入口。
struct VIPView: View {
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appReduceMotion) private var appReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                statusCard
                comparisonCard
                footer
            }
            .padding(Theme.Spacing.page)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Theme.Surface.base.ignoresSafeArea())
        .navigationTitle("VIP 权益")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 状态

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: entitlements.isVIP ? "crown.fill" : "person.crop.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(entitlements.isVIP ? Theme.Accent.fire : Theme.Text.secondary)

                Text(entitlements.isVIP ? "VIP（模拟）" : "免费版")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Text.primary)

                Spacer()
            }

            Text(entitlements.isVIP
                 ? "模拟 VIP 已开启，下方带 VIP 标记的权益立即生效。"
                 : "当前为免费版。切换下方模拟开关可即时预览 VIP 权益。")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Text.secondary)

            Toggle(
                "模拟 VIP",
                isOn: Binding(
                    get: { entitlements.isVIP },
                    set: { enabled in
                        withAnimation(Theme.Motion.animation(.fast, reduceMotion: reduceMotion)) {
                            entitlements.setVIP(enabled)
                        }
                    }
                )
            )
            .font(Theme.Typography.body)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.raised, cornerRadius: Theme.Radius.card)
    }

    // MARK: - 对比

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("权益对比")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Text.primary)

            ForEach(Feature.allCases) { feature in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(feature.title)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Text.primary)
                        Spacer()
                        Image(systemName: entitlements.isEnabled(feature) ? "checkmark.circle.fill" : "lock.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(entitlements.isEnabled(feature) ? Theme.State.success : Theme.Text.tertiary)
                    }

                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        tierLabel("免费", value: freeValue(for: feature), isActive: !entitlements.isVIP)
                        tierLabel("VIP", value: vipValue(for: feature), isActive: entitlements.isVIP)
                    }
                }

                if feature.id != Feature.allCases.last?.id {
                    Divider()
                        .overlay(Theme.Shadow.insetBorder.opacity(0.35))
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.raised, cornerRadius: Theme.Radius.card)
    }

    private func tierLabel(_ title: String, value: String, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? Theme.Accent.fire : Theme.Text.tertiary)
            Text(value)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .neuSurface(.inset, cornerRadius: Theme.Radius.chip)
    }

    private func freeValue(for feature: Feature) -> String {
        switch feature {
        case .vaultAllMediaTypes: "静态图片"
        case .vaultUnlimitedCapacity: "60 件 · 2GB"
        case .statsAdvanced: "今日 · 本周 · 累计"
        case .extraMachines: "壁炉 · 碎纸机"
        case .dialSkins: "基础外观"
        }
    }

    private func vipValue(for feature: Feature) -> String {
        switch feature {
        case .vaultAllMediaTypes: "全部媒体类型"
        case .vaultUnlimitedCapacity: "不限件数与空间"
        case .statsAdvanced: "增加本月与方式偏好"
        case .extraMachines: "更多玩法（二期）"
        case .dialSkins: "全部皮肤与音效（二期）"
        }
    }

    private var footer: some View {
        Text("一期不接内购：本页没有价格、订阅或购买按钮。二期接入 StoreKit 2 后，真实交易结果会写入同一个 EntitlementStore，门禁调用点无需改动。")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Text.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        VIPView()
            .environment(EntitlementStore())
    }
}
