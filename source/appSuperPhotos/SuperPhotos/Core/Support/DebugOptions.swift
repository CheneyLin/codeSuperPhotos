import Foundation

/// 仅 Debug 构建使用的开发开关；Release 下不参与编译。
#if DEBUG
enum DebugOptions {
    private static let simulateDestroyKey = "debug.simulateDestroy"

    /// 跳过真实 performChanges，只走时序与动画，便于在模拟器里回归销毁流程。
    static var isSimulatingDestroy: Bool {
        UserDefaults.standard.bool(forKey: simulateDestroyKey)
    }

    static func setSimulatingDestroy(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: simulateDestroyKey)
    }

    static func readSimulatingDestroy() -> Bool {
        UserDefaults.standard.bool(forKey: simulateDestroyKey)
    }
}
#endif
