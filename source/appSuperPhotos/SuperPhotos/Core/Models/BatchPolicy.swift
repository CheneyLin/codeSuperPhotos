import Foundation

/// 批量阈值：销毁与保险箱入库共用同一个数字，改一处即两边同步。
enum BatchPolicy {
    /// 累积到该张数时点亮指示灯并弹出二次确认。
    static let autoConfirmThreshold = 10
}
