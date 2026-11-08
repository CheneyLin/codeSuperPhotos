import Foundation

enum MachineKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case fireplace
    case shredder

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fireplace: "壁炉"
        case .shredder: "碎纸机"
        }
    }

    var symbolName: String {
        switch self {
        case .fireplace: "flame"
        case .shredder: "scissors"
        }
    }

    /// 销毁动画时长（秒）
    var destroyDuration: TimeInterval {
        switch self {
        case .fireplace: 1.8
        case .shredder: 1.4
        }
    }
}
