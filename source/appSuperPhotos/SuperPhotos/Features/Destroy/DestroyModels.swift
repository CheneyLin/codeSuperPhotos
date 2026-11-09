import Foundation

/// 待销毁批量的触发策略；阈值从 `BatchPolicy` 读取，与保险箱入库共用。
enum DestroyPolicy {
    /// 累计到该张数时自动点亮销毁指示灯并弹出确认。
    static let autoConfirmThreshold = BatchPolicy.autoConfirmThreshold
}

/// 销毁流程的显式状态机；只由 DestroyCoordinator 推进。
enum DestroyPhase: Equatable, Sendable {
    case idle
    /// 拖入，等待 200ms 吸附
    case armed
    /// 1.2s 蓄力，唯一的后悔窗口
    case charging
    /// performChanges 已提交，等系统弹窗
    case awaitingSystemConfirm
    /// 系统确认后播放销毁动画
    case destroying
    /// 取消或失败，反向退件
    case ejecting
    /// Toast 已给出
    case finished

    var isBusy: Bool {
        switch self {
        case .idle, .finished: false
        default: true
        }
    }

    var canCancel: Bool {
        self == .armed || self == .charging
    }
}

struct DestroyTicket: Identifiable, Equatable, Sendable {
    let id: String
    let kind: MediaKind
}

/// 整批销毁结果，供统计回写。
struct DestroyOutcome: Equatable, Sendable {
    /// 每次结果唯一，保证相同的取消结果也能触发 onChange。
    let id = UUID()
    let machine: MachineKind
    let succeededIDs: [String]
    let failedIDs: [String]
    let wasCancelled: Bool
}
