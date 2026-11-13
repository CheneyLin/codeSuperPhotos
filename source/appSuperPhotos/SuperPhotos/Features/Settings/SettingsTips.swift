import SwiftUI

/// 设置页各模块的使用提示。
/// 原先作为 Section footer 常驻展示，后来收进「更多」弹窗；现在设置页已取消
/// 模块标题与「更多」入口，提示内容统一整理到下面的 `WelcomeSlide`，
/// 供稍后升级的新手欢迎轮播图消费（本文件不实现轮播 UI）。
struct SettingsTip: Identifiable, Sendable {
    let id: String
    let title: String
    let message: String
    /// 可选的权益对比行（目前仅 VIP 使用）；为空时不渲染对比区。
    let comparison: [SettingsTipComparison]
    /// 是否展示内购合规链接（购买入口所在模块需要）。
    let showsLegalLinks: Bool

    init(
        id: String,
        title: String,
        message: String,
        comparison: [SettingsTipComparison] = [],
        showsLegalLinks: Bool = false
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.comparison = comparison
        self.showsLegalLinks = showsLegalLinks
    }
}

/// 权益对比的一行：能力名称 + 免费版 / VIP 两档说明。
/// 只列正式版已兑现的能力，不写规划中或开发期的项目。
struct SettingsTipComparison: Identifiable, Sendable {
    var id: String { title }
    let title: String
    let free: String
    let vip: String
}

extension SettingsTip {
    static let vip = SettingsTip(
        id: "vip",
        title: "VIP 会员".localized,
        message: "VIP 为一次性购买：确认后从 Apple ID 账户扣费一次，即可永久解锁下列权益，不会自动续订，也不会再次扣费。更换设备或重装后，点「恢复购买」即可免费找回，不会重复扣费。价格以 App Store 显示为准；购买与恢复均不影响本机照片与保险箱数据。".localized,
        comparison: [
            .init(title: "保险箱媒体类型".localized, free: "静态图片".localized, vip: "实况照片与视频".localized),
            .init(title: "保险箱容量".localized, free: "1 件".localized, vip: "不限件数与空间".localized),
            .init(title: "销毁道具".localized, free: "仅废纸篓".localized, vip: "五款道具".localized),
            .init(title: "整理批次".localized, free: "固定每批 10 张".localized, vip: "每批 10–200 张可调".localized),
            .init(title: "保险箱 iCloud 同步".localized, free: "不可用".localized, vip: "可选开启（默认关闭）".localized),
            .init(title: "整理统计".localized, free: "今日统计".localized, vip: "增加本周、本月与累计周期".localized)
        ],
        showsLegalLinks: true
    )

    static let appearance = SettingsTip(
        id: "appearance",
        title: "外观与交互".localized,
        message: "显示模式即时生效并保留到下次启动；高对比度会加深文字、加粗描边；降低动效与系统设置取并集。".localized
    )

    static let device = SettingsTip(
        id: "device",
        title: "销毁道具".localized,
        message: "免费版仅可使用默认废纸篓；VIP 可在五款销毁道具间切换。每款道具都有独立的落入动效与音效，统计按当时选中的道具分别计数。".localized
    )

    static let statistics = SettingsTip(
        id: "statistics",
        title: "统计".localized,
        message: "免费版仅可查看今日统计；本周、本月与累计统计属于 VIP 权益。".localized
    )

    static let task = SettingsTip(
        id: "task",
        title: "整理".localized,
        message: "免费版每批固定处理 10 张；VIP 可在设置中调整为每批 10–200 张。只影响之后新建的批次；正在进行的任务按开始时的张数计算进度。相簿不足时按实际张数开始。".localized
    )

    static let snooze = SettingsTip(
        id: "snooze",
        title: "延后".localized,
        message: "延后中的照片到期前不会进入舞台；可在这里逐张恢复或全部恢复。".localized
    )

    static let vault = SettingsTip(
        id: "vault",
        title: "私密保险箱".localized,
        message: "密码盘组合空间 30 × 60 = 1800 种（约 10.8 bit），能挡住随手翻看，挡不住有时间暴力尝试的人；已配合阶梯锁定。密码忘记后无法找回。\n\n保险箱文件以普通格式存放在 App 沙盒，受 iOS 沙盒与系统文件保护；App 密码只保护界面访问，不提供独立的文件加密。旧版加密文件仍可在原设备上读取，但不会参与 iCloud 同步。\n\niCloud 同步为 VIP 功能且默认关闭，只同步标准文件到你的 iCloud 私有数据库；密码与锁定状态始终只留在本机，每台设备各自设置密码。".localized
    )
}

// MARK: - 欢迎轮播图素材（预备，暂不接 UI）

/// 设置页「更多」入口移除后，提示内容按模块整理成可直接消费的轮播页数据。
/// 每页对应 `Assets.xcassets/Config` 里的一枚 3D 图标；`detail` 复用
/// `SettingsTip` 的正式文案，避免轮播图和提示弹窗两处文案走样。
/// 稍后升级欢迎轮播图时只需渲染 `WelcomeSlide.all`，本文件不实现任何 UI。
struct WelcomeSlide: Identifiable, Sendable {
    let id: String
    let iconName: String
    let title: String
    /// 轮播页上的一句话说明（比 detail 短）。
    let summary: String
    /// 完整使用提示；没有对应 SettingsTip 的模块为空串。
    let detail: String
    let showsComparison: Bool
    let showsLegalLinks: Bool
}

extension WelcomeSlide {
    static let all: [WelcomeSlide] = [
        .init(id: "vip", iconName: "icon_config_vip", title: "VIP 会员".localized,
              summary: "一次购买，永久解锁全部权益".localized,
              detail: SettingsTip.vip.message, showsComparison: true, showsLegalLinks: true),
        .init(id: "appearance", iconName: "icon_config_ui", title: "外观和交互".localized,
              summary: "浅色 / 深色 / 高对比度，动效与音效随手调".localized,
              detail: SettingsTip.appearance.message, showsComparison: false, showsLegalLinks: false),
        .init(id: "device", iconName: "icon_config_destory", title: "销毁道具".localized,
              summary: "VIP 可切换五款销毁道具".localized,
              detail: SettingsTip.device.message, showsComparison: false, showsLegalLinks: false),
        .init(id: "statistics", iconName: "icon_config_data", title: "统计".localized,
              summary: "今日、本周、本月与累计，整理成果一目了然".localized,
              detail: SettingsTip.statistics.message, showsComparison: false, showsLegalLinks: false),
        .init(id: "task", iconName: "icon_config_batch", title: "整理批次".localized,
              summary: "免费版固定每批 10 张".localized,
              detail: SettingsTip.task.message, showsComparison: false, showsLegalLinks: false),
        .init(id: "snooze", iconName: "icon_config_later", title: "延后".localized,
              summary: "暂时不想处理的照片，先放一放".localized,
              detail: SettingsTip.snooze.message, showsComparison: false, showsLegalLinks: false),
        .init(id: "vault", iconName: "icon_config_vault", title: "私密保险箱".localized,
              summary: "30 × 60 密码盘，标准档可选 iCloud 同步".localized,
              detail: SettingsTip.vault.message, showsComparison: false, showsLegalLinks: false),
        .init(id: "apps", iconName: "icon_config_apps", title: "我们的应用".localized,
              summary: "点开即可前往 App Store 看看其他应用".localized,
              detail: "", showsComparison: false, showsLegalLinks: false),
        .init(id: "about", iconName: "icon_config_about", title: "关于".localized,
              summary: "版本信息与隐私说明".localized,
              detail: "", showsComparison: false, showsLegalLinks: false)
    ]
}

/// 权益对比视图：VIP 页与后续欢迎轮播图共用同一份数据与排版，避免两处文案走样。
struct SettingsTipComparisonView: View {
    let rows: [SettingsTipComparison]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("权益对比".localized)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Text.primary)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.title)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Text.primary)

                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        tierLabel("免费版".localized, value: row.free, isVIP: false)
                        tierLabel("VIP", value: row.vip, isVIP: true)
                    }
                }

                if index != rows.count - 1 {
                    Divider()
                        .overlay(Theme.Shadow.insetBorder.opacity(0.35))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tierLabel(_ title: String, value: String, isVIP: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isVIP ? Theme.Accent.fire : Theme.Text.tertiary)
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
}

/// 内购合规链接：地址从 Info.plist 的 `VIPPrivacyURL` / `VIPTermsURL` 读取，
/// 未配置时不显示。设置页的「更多」提示弹窗入口已移除，链接目前由 `VIPView`
/// 展示；后续欢迎轮播图的 VIP 页也应复用本视图，确保合规链接不遗漏。
struct SettingsTipLegalLinks: View {
    var body: some View {
        let privacy = (Bundle.main.object(forInfoDictionaryKey: "VIPPrivacyURL") as? String)
            .flatMap { URL(string: $0) }
        let terms = (Bundle.main.object(forInfoDictionaryKey: "VIPTermsURL") as? String)
            .flatMap { URL(string: $0) }

        if privacy != nil || terms != nil {
            HStack(spacing: Theme.Spacing.lg) {
                if let privacy {
                    Link("隐私政策".localized, destination: privacy)
                }
                if let terms {
                    Link("使用条款".localized, destination: terms)
                }
            }
            .font(Theme.Typography.caption)
        }
    }
}

/// 备用提示弹窗：半屏卡片，长文案可滚动；风格与 SnoozeListView 的 sheet 一致。
/// 设置页入口已移除，保留供后续欢迎轮播图的「了解更多」复用。
struct SettingsTipSheet: View {
    let tip: SettingsTip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Text.primary)
                    Text("使用提示".localized)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Text.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Text.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭".localized)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text(tip.message)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !tip.comparison.isEmpty {
                        SettingsTipComparisonView(rows: tip.comparison)
                            .padding(Theme.Spacing.lg)
                            .neuSurface(.raised, cornerRadius: Theme.Radius.card)
                    }

                    if tip.showsLegalLinks {
                        SettingsTipLegalLinks()
                    }
                }
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.bottom, Theme.Spacing.page)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Theme.Surface.base)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
