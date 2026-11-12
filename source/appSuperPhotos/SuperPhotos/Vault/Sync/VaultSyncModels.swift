import CloudKit
import Foundation

/// 同步层的纯值类型：SwiftData `@Model` 与 `CKRecord` 都不跨层传递。
/// 本机一条可同步的保险箱条目（已确认是标准档明文文件）。
struct VaultSyncItem: Sendable {
    let id: UUID
    let fileName: String
    let mediaKindRaw: String
    let byteSize: Int64
    let capturedAt: Date?
    let addedAt: Date
    let albumNames: [String]
    let hasPairedVideo: Bool
    let mediaURL: URL
    let pairedVideoURL: URL?
}

/// 云端一条记录的元数据（不含 CKAsset，避免全量查询时下载大文件）。
struct VaultRemoteItem: Sendable {
    let recordName: String
    let id: UUID
    let fileName: String
    let mediaKindRaw: String
    let byteSize: Int64
    let capturedAt: Date?
    let addedAt: Date
    let albumNames: [String]
    let hasPairedVideo: Bool
    let isDeleted: Bool
    let schemaVersion: Int
    let modifiedAt: Date

    init?(record: CKRecord) {
        guard let idString = record[VaultSyncField.itemID] as? String,
              let id = UUID(uuidString: idString) else { return nil }
        self.recordName = record.recordID.recordName
        self.id = id
        self.fileName = record[VaultSyncField.fileName] as? String ?? "photo"
        self.mediaKindRaw = record[VaultSyncField.mediaKindRaw] as? String ?? "photo"
        self.byteSize = (record[VaultSyncField.byteSize] as? NSNumber)?.int64Value ?? 0
        self.capturedAt = record[VaultSyncField.capturedAt] as? Date
        self.addedAt = record[VaultSyncField.addedAt] as? Date ?? Date()
        self.albumNames = record[VaultSyncField.albumNames] as? [String] ?? []
        self.hasPairedVideo = (record[VaultSyncField.hasPairedVideo] as? NSNumber)?.boolValue ?? false
        self.isDeleted = (record[VaultSyncField.isDeleted] as? NSNumber)?.boolValue ?? false
        self.schemaVersion = (record[VaultSyncField.schemaVersionKey] as? NSNumber)?.intValue ?? 0
        self.modifiedAt = record[VaultSyncField.modifiedAt] as? Date ?? Date()
    }
}

/// CloudKit 记录类型与字段名。recordName 用条目 UUID，天然幂等、跨设备一致。
enum VaultSyncField {
    static let containerIdentifier = "iCloud.com.gpwzw.appSuperPhotos"
    static let recordType: CKRecord.RecordType = "VaultItem"
    static let schemaVersion = 1
    /// 单次查询页大小；大照片库按 CKQueryOperation.Cursor 翻页。
    static let pageSize = 100

    static let itemID: CKRecord.FieldKey = "itemID"
    static let fileName: CKRecord.FieldKey = "fileName"
    static let mediaKindRaw: CKRecord.FieldKey = "mediaKindRaw"
    static let byteSize: CKRecord.FieldKey = "byteSize"
    static let capturedAt: CKRecord.FieldKey = "capturedAt"
    static let addedAt: CKRecord.FieldKey = "addedAt"
    static let albumNames: CKRecord.FieldKey = "albumNames"
    static let hasPairedVideo: CKRecord.FieldKey = "hasPairedVideo"
    static let isDeleted: CKRecord.FieldKey = "isDeleted"
    static let schemaVersionKey: CKRecord.FieldKey = "schemaVersion"
    static let modifiedAt: CKRecord.FieldKey = "modifiedAt"
    static let originDevice: CKRecord.FieldKey = "originDevice"
    static let media: CKRecord.FieldKey = "media"
    static let pairedVideo: CKRecord.FieldKey = "pairedVideo"

    /// 全量查询只要元数据；CKAsset 留到确定要下载时才按 recordID 单独取。
    static let metadataKeys: [CKRecord.FieldKey] = [
        itemID, fileName, mediaKindRaw, byteSize, capturedAt, addedAt,
        albumNames, hasPairedVideo, isDeleted, schemaVersionKey, modifiedAt, originDevice
    ]

    static func recordName(for id: UUID) -> String { recordName(forUUIDString: id.uuidString) }

    /// 墓碑里存的是 uuidString，构造 recordName 时不必先转回 UUID。
    static func recordName(forUUIDString string: String) -> String { "vaultitem-\(string)" }
}

/// 开关与同步元数据的持久化 key。开关由设置页 `@AppStorage` 写入，引擎只读。
enum VaultSyncPreference {
    static let enabledKey = "vault.iCloudSyncEnabled"
    static let tombstonesKey = "vault.sync.tombstoneIDs"
    static let lastSyncKey = "vault.sync.lastSyncDate"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

enum VaultSyncPhase: Equatable {
    /// 开关关闭。
    case off
    /// 开关已开但当前不是 VIP。
    case vipRequired
    case ready
    case syncing
    case noAccount
    case restricted
    case failure(String)
}

/// VaultStore 与同步引擎之间的轻量钩子，避免存储层反向依赖引擎类型。
struct VaultSyncHooks {
    /// 本机清单发生任何增删（同步引擎应择机重跑一次）。
    var onRecordsChanged: (() -> Void)?
    /// 本机删除的条目 id：写入墓碑，下一次同步把云端对应记录标记为已删除。
    var onRecordsDeleted: (([UUID]) -> Void)?
}
