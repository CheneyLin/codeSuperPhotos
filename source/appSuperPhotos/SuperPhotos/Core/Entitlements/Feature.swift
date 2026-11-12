import Foundation

/// 需要权益判定的能力。页面不得直接判断 tier，一律经由 EntitlementStore。
enum Feature: String, CaseIterable, Sendable, Identifiable {
    case vaultAllMediaTypes
    case vaultUnlimitedCapacity
    case statsAdvanced
    case extraMachines
    case dialSkins

    var id: String { rawValue }

    var minimumTier: EntitlementTier { .vip }

    var title: String {
        switch self {
        case .vaultAllMediaTypes: "保险箱支持实况照片与视频".localized
        case .vaultUnlimitedCapacity: "保险箱容量不限".localized
        case .statsAdvanced: "统计趋势与年度报告".localized
        case .extraMachines: "更多销毁玩法".localized
        case .dialSkins: "密码盘皮肤与音效包".localized
        }
    }

    var detail: String {
        switch self {
        case .vaultAllMediaTypes: "免费版只支持静态图片".localized
        case .vaultUnlimitedCapacity: "免费版上限 60 件 / 2GB".localized
        case .statsAdvanced: "免费版含今日、本周、累计与五款道具分布".localized
        case .extraMachines: "免费版可切换全部五款道具".localized
        case .dialSkins: "免费版含 1 套基础外观与基础音效".localized
        }
    }
}
