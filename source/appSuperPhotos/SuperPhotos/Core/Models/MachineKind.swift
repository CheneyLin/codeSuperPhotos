import Foundation
import SwiftUI

/// 底部「销毁道具」的五种形态。
///
/// `allCases` 的声明顺序就是点击道具时的循环切换顺序：
/// 废纸篓 → 碎纸机 → 壁炉 → 邮筒 → 任意门 → 废纸篓。
/// `fireplace` / `shredder` 沿用旧 rawValue，保证已落库的选择与
/// `UI_TEST_MACHINE=shredder` 这类入口不失效。
enum MachineKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case wasteBasket = "bin_waste"
    case shredder = "shredder"
    case fireplace = "fireplace"
    case mailbox = "mailbox"
    case anyDoor = "any_door"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wasteBasket: "废纸篓".localized
        case .shredder: "碎纸机".localized
        case .fireplace: "壁炉".localized
        case .mailbox: "邮筒".localized
        case .anyDoor: "任意门".localized
        }
    }

    /// `Assets.xcassets/Devices` 里的素材名。
    var assetName: String {
        switch self {
        case .wasteBasket: "icon_bin_waste"
        case .shredder: "icon_paper_cutter"
        case .fireplace: "icon_fireplace"
        case .mailbox: "icon_mailbox"
        case .anyDoor: "icon_door"
        }
    }

    /// SF Symbol 兜底（设置页小图标 / 无障碍列表用）。
    var symbolName: String {
        switch self {
        case .wasteBasket: "trash"
        case .shredder: "scissors"
        case .fireplace: "flame"
        case .mailbox: "envelope"
        case .anyDoor: "sparkles"
        }
    }

    /// `Resources/Sounds` 中对应的短音效（不含扩展名）。
    var soundName: String {
        switch self {
        case .wasteBasket: "device_bin"
        case .shredder: "device_shredder"
        case .fireplace: "device_fireplace"
        case .mailbox: "device_mailbox"
        case .anyDoor: "device_door"
        }
    }

    /// 统计条 / 指示点的识别色。
    var tint: Color {
        switch self {
        case .wasteBasket: Theme.Device.bin
        case .shredder: Theme.Device.shredder
        case .fireplace: Theme.Device.fireplace
        case .mailbox: Theme.Device.mailbox
        case .anyDoor: Theme.Device.door
        }
    }

    /// 销毁动画时长（秒），由 DestroyCoordinator 使用。
    var destroyDuration: TimeInterval {
        switch self {
        case .wasteBasket: 1.3
        case .shredder: 1.4
        case .fireplace: 1.8
        case .mailbox: 1.5
        case .anyDoor: 1.7
        }
    }

    /// 点击切换时的下一款；末位回到首位。
    var next: MachineKind {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    /// 无障碍 / LCD 提示用的动作描述。
    var dropVerb: String {
        switch self {
        case .wasteBasket: "投进废纸篓".localized
        case .shredder: "送进碎纸机".localized
        case .fireplace: "投入壁炉".localized
        case .mailbox: "寄进邮筒".localized
        case .anyDoor: "送进任意门".localized
        }
    }
}
