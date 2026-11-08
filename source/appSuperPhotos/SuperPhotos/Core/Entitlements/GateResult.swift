import Foundation

/// 门禁结果：统一给 UI 展示，避免各页面拼提示文案。
enum GateResult: Equatable, Sendable {
    case allowed
    case requiresVIP(String)
    case quotaExceeded(String)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .allowed:
            nil
        case .requiresVIP(let message), .quotaExceeded(let message):
            message
        }
    }
}
