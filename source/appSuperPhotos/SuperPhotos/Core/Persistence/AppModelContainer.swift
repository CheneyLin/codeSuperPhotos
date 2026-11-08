import Foundation
import SwiftData

/// App 的 SwiftData 容器：保险箱清单 + 统计日汇总。
enum AppModelContainer {
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: VaultRecord.self, DayStat.self)
        } catch {
            // 本地存储不可用时退回内存容器，至少保证界面可用且不崩溃。
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            if let container = try? ModelContainer(
                for: VaultRecord.self, DayStat.self,
                configurations: configuration
            ) {
                return container
            }
            fatalError("无法创建 SwiftData 容器：\(error)")
        }
    }()
}
