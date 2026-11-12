import Foundation
import SwiftData

/// App 的 SwiftData 容器：保险箱清单 + 统计日汇总。
///
/// 关键：必须显式传 `cloudKitDatabase: .none`。`ModelConfiguration` 的默认值是
/// `.automatic`——只要 Target 带 iCloud / CloudKit entitlement，SwiftData 就会自动
/// 把本地 SQLite store 升级为 `NSPersistentCloudKitContainer`。而本项目模型含有
/// 大量非可选属性与 `@Attribute(.unique)` 唯一约束，CloudKit 集成会直接拒绝加载
/// （NSCocoaErrorDomain 134060），容器随即回退到内存态，数据全部丢失。
///
/// 保险箱同步由 `VaultSyncEngine` 通过自建 CKRecord / CKAsset 通道完成，不依赖
/// SwiftData 镜像；统计 `DayStat` 属于纯本机数据，更不能被动同步到 iCloud。
enum AppModelContainer {
    static let shared: ModelContainer = {
        let configuration = ModelConfiguration(cloudKitDatabase: .none)
        do {
            return try ModelContainer(
                for: VaultRecord.self, DayStat.self,
                configurations: configuration
            )
        } catch {
            // 不能静默降级：内存态不会持久化，用户会以为数据已保存。
            print("[SuperPhotos] SwiftData 持久化容器加载失败，已退回内存态，本次数据不会保存：\(error)")
            let fallback = ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            if let container = try? ModelContainer(
                for: VaultRecord.self, DayStat.self,
                configurations: fallback
            ) {
                return container
            }
            fatalError("无法创建 SwiftData 容器：\(error)")
        }
    }()
}
